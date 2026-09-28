"""Cached, bounded Home index and file actions."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

from .config import cache_home


class FileIndexService:
    def __init__(self, roots: list[Path] | None = None, max_entries: int = 250_000, publish=None) -> None:
        self.roots = roots or [Path.home()]
        self.max_entries = max_entries
        self.publish = publish or (lambda _event: None)
        self.cache_file = cache_home() / "file-index.json"
        self.lock = threading.RLock()
        self.paths: list[str] = []
        self.indexed_at = 0.0
        self.indexing = False
        self.error: str | None = None
        self._load_cache()

    def _load_cache(self) -> None:
        try:
            raw = json.loads(self.cache_file.read_text(encoding="utf-8"))
            if raw.get("version") == 2 and isinstance(raw.get("paths"), list):
                with self.lock:
                    self.paths = [str(path) for path in raw["paths"] if isinstance(path, str)]
                    self.indexed_at = float(raw.get("indexedAt", 0))
        except (OSError, ValueError, AttributeError):
            return

    def _start_scan(self) -> None:
        with self.lock:
            if self.indexing:
                return
            self.indexing = True
            self.error = None
        threading.Thread(target=self._scan, name="phasor-file-index", daemon=True).start()

    def _scan(self) -> None:
        found: list[str] = []
        try:
            for root in self.roots:
                root = root.expanduser().resolve()
                try:
                    root_device = root.stat().st_dev
                except OSError:
                    continue
                for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
                    current_path = Path(current)
                    safe_dirs = []
                    for directory in dirs:
                        if directory.startswith("."):
                            continue
                        candidate = current_path / directory
                        try:
                            if candidate.is_symlink() or candidate.stat().st_dev != root_device or candidate.is_mount():
                                continue
                        except OSError:
                            continue
                        safe_dirs.append(directory)
                        if len(found) < self.max_entries:
                            found.append(str(candidate))
                    dirs[:] = safe_dirs
                    if len(found) >= self.max_entries:
                        dirs[:] = []
                        break
                    for file_name in files:
                        if file_name.startswith("."):
                            continue
                        path = current_path / file_name
                        try:
                            if path.is_symlink() or path.stat().st_dev != root_device:
                                continue
                        except OSError:
                            continue
                        found.append(str(path))
                        if len(found) >= self.max_entries:
                            break
                    if len(found) >= self.max_entries:
                        break
            found.sort(key=str.casefold)
            self.cache_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            tmp = self.cache_file.with_suffix(".json.tmp")
            tmp.write_text(json.dumps({"version": 2, "indexedAt": time.time(), "paths": found}), encoding="utf-8")
            os.chmod(tmp, 0o600)
            tmp.replace(self.cache_file)
            with self.lock:
                self.paths = found
                self.indexed_at = time.time()
            self.publish({"type": "event", "name": "files.indexReady", "data": {"count": len(found)}})
        except Exception as exc:  # Keep the daemon available if an unreadable tree is encountered.
            with self.lock:
                self.error = str(exc)
            self.publish({"type": "event", "name": "files.indexFailed", "data": {"error": str(exc)}})
        finally:
            with self.lock:
                self.indexing = False

    def status(self) -> dict[str, Any]:
        with self.lock:
            state = {"indexed": bool(self.indexed_at), "indexing": self.indexing, "count": len(self.paths), "indexedAt": self.indexed_at or None, "error": self.error}
        if not state["indexed"]:
            self._start_scan()
            state["indexing"] = True
        elif time.time() - float(state["indexedAt"] or 0) > 12 * 60 * 60:
            self._start_scan()
            state["indexing"] = True
        return state

    def search(self, query: str, limit: int = 60) -> dict[str, Any]:
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 200:
            raise ValueError("file search limit must be from 1 to 200")
        needle = query.strip().casefold()
        status = self.status()
        if not needle:
            return {"items": [], "total": 0, "status": status}
        with self.lock:
            paths = tuple(self.paths)
        ranked = []
        for value in paths:
            path = Path(value)
            name = path.name.casefold()
            text = value.casefold()
            if needle in name or needle in text:
                score = (0 if name.startswith(needle) else 1, name.find(needle) if needle in name else 99, len(value), value)
                ranked.append((score, value))
        ranked.sort(key=lambda row: row[0])
        return {"items": [{"path": value, "name": Path(value).name, "directory": Path(value).is_dir()} for _, value in ranked[:limit]], "total": len(ranked), "status": status}

    def open(self, path: str) -> dict[str, Any]:
        target = self._validate(path)
        executable = shutil.which("xdg-open")
        if not executable:
            raise ValueError("xdg-open is not installed")
        subprocess.Popen([executable, str(target)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {"opened": str(target)}

    def reveal(self, path: str) -> dict[str, Any]:
        target = self._validate(path)
        nautilus = shutil.which("nautilus")
        if nautilus:
            subprocess.Popen([nautilus, "--select", str(target)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return {"revealed": str(target), "manager": "nautilus"}
        return self.open(str(target.parent))

    @staticmethod
    def _validate(path: str) -> Path:
        target = Path(path).expanduser().resolve(strict=True)
        home = Path.home().resolve()
        if target != home and home not in target.parents:
            raise ValueError("File action is limited to the user's Home directory")
        if not target.exists():
            raise ValueError("File no longer exists")
        return target


class ClipboardService:
    def copy(self, text: str) -> dict[str, Any]:
        command = shutil.which("wl-copy")
        if not command:
            raise ValueError("wl-copy is not installed")
        proc = subprocess.run([command], input=text, text=True, check=False, capture_output=True, timeout=3)
        if proc.returncode:
            raise ValueError(proc.stderr.strip() or "Clipboard copy failed")
        return {"copied": True}

    def history(self, limit: int = 40) -> dict[str, Any]:
        command = shutil.which("cliphist")
        if not command:
            return {"available": False, "items": [], "error": "cliphist is not installed"}
        proc = subprocess.run([command, "list"], check=False, capture_output=True, text=True, timeout=3)
        if proc.returncode:
            return {"available": False, "items": [], "error": proc.stderr.strip()}
        return {"available": True, "items": proc.stdout.splitlines()[:limit]}
