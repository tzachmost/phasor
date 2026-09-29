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

    def rename(self, path: str, name: str) -> dict[str, Any]:
        target = self._validate(path)
        self._reject_home_root(target)
        if not isinstance(name, str) or not name or name in {".", ".."} or "/" in name or "\0" in name:
            raise ValueError("New name must be a single non-empty path component")
        renamed = target.with_name(name)
        if renamed.exists() or renamed.is_symlink():
            raise ValueError("A file with that name already exists")
        target.rename(renamed)
        self._change_index(target, renamed)
        self.publish({"type": "event", "name": "files.changed", "data": {"action": "renamed", "from": str(target), "to": str(renamed)}})
        return {"renamed": str(renamed)}

    def trash(self, path: str) -> dict[str, Any]:
        target = self._validate(path)
        self._reject_home_root(target)
        gio = shutil.which("gio")
        if not gio:
            raise ValueError("gio is not installed; install glib2 to move files to Trash")
        proc = subprocess.run([gio, "trash", str(target)], check=False, capture_output=True, text=True, timeout=5)
        if proc.returncode:
            raise ValueError(proc.stderr.strip() or "Could not move item to Trash")
        self._change_index(target, None)
        self.publish({"type": "event", "name": "files.changed", "data": {"action": "trashed", "path": str(target)}})
        return {"trashed": str(target)}

    def copy_file(self, path: str) -> dict[str, Any]:
        source = self._validate(path)
        self._reject_home_root(source)
        if not source.is_file():
            raise ValueError("Only files can be copied from the launcher")
        stem, suffix = source.stem, source.suffix
        copy_number = 1
        while True:
            label = "copy" if copy_number == 1 else f"copy {copy_number}"
            destination = source.with_name(f"{stem} ({label}){suffix}")
            if not destination.exists() and not destination.is_symlink():
                break
            copy_number += 1
        try:
            with source.open("rb") as source_stream, destination.open("xb") as destination_stream:
                shutil.copyfileobj(source_stream, destination_stream)
            shutil.copystat(source, destination, follow_symlinks=False)
        except OSError:
            destination.unlink(missing_ok=True)
            raise
        self._change_index(None, destination)
        self.publish({"type": "event", "name": "files.changed", "data": {"action": "copied", "from": str(source), "to": str(destination)}})
        return {"copied": str(destination)}

    def share(self, path: str) -> dict[str, Any]:
        target = self._validate(path)
        uri = target.as_uri()
        ClipboardService().copy(uri)
        return {"shared": uri}

    def reveal(self, path: str) -> dict[str, Any]:
        target = self._validate(path)
        nautilus = shutil.which("nautilus")
        if nautilus:
            subprocess.Popen([nautilus, "--select", str(target)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return {"revealed": str(target), "manager": "nautilus"}
        return self.open(str(target.parent))

    @staticmethod
    def _validate(path: str) -> Path:
        raw = Path(path).expanduser()
        if raw.is_symlink():
            raise ValueError("File actions do not follow symbolic links")
        target = raw.resolve(strict=True)
        home = Path.home().resolve()
        if target != home and home not in target.parents:
            raise ValueError("File action is limited to the user's Home directory")
        if not target.exists():
            raise ValueError("File no longer exists")
        return target

    @staticmethod
    def _reject_home_root(target: Path) -> None:
        if target == Path.home().resolve():
            raise ValueError("This action cannot be applied to the Home directory")

    def _change_index(self, old: Path | None, new: Path | None) -> None:
        with self.lock:
            was_indexed = bool(self.indexed_at)
            old_text = str(old) if old else None
            new_text = str(new) if new else None
            updated: list[str] = []
            for value in self.paths:
                if old_text and (value == old_text or value.startswith(old_text + os.sep)):
                    if new_text:
                        updated.append(new_text + value[len(old_text):])
                    continue
                updated.append(value)
            if new_text:
                updated.append(new_text)
            self.paths = sorted(set(updated), key=str.casefold)
            self.indexed_at = time.time() if was_indexed else 0.0
            self.error = None
            indexed_at = self.indexed_at
            paths = list(self.paths)
        try:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            tmp = self.cache_file.with_suffix(".json.tmp")
            tmp.write_text(json.dumps({"version": 2, "indexedAt": indexed_at, "paths": paths}), encoding="utf-8")
            os.chmod(tmp, 0o600)
            tmp.replace(self.cache_file)
        except OSError:
            with self.lock:
                self.indexed_at = 0.0


class ClipboardService:
    def copy(self, text: str) -> dict[str, Any]:
        command = shutil.which("wl-copy")
        if not command:
            raise ValueError("wl-copy is not installed")
        try:
            # wl-copy forks an owner process that keeps the clipboard selection alive.
            # Capturing stdout/stderr makes subprocess.run wait on the child's inherited pipes.
            proc = subprocess.run(
                [command], input=text, text=True, check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError(f"Clipboard copy failed: {exc}") from exc
        if proc.returncode:
            raise ValueError("wl-copy could not set the clipboard")
        return {"copied": True}

    def history(self, limit: int = 40) -> dict[str, Any]:
        command = shutil.which("cliphist")
        if not command:
            return {"available": False, "items": [], "error": "cliphist is not installed"}
        proc = subprocess.run([command, "list"], check=False, capture_output=True, text=True, timeout=3)
        if proc.returncode:
            return {"available": False, "items": [], "error": proc.stderr.strip()}
        items = proc.stdout.splitlines()[:limit]
        entries = []
        for line in items:
            entry_id, separator, preview = line.partition("\t")
            if separator and entry_id.isdigit():
                entries.append({"id": entry_id, "preview": preview})
        return {"available": True, "items": items, "entries": entries}

    def restore(self, entry_id: str) -> dict[str, Any]:
        if not isinstance(entry_id, str) or not entry_id.isdigit():
            raise ValueError("Clipboard history id must be an integer")
        cliphist = shutil.which("cliphist")
        wl_copy = shutil.which("wl-copy")
        if not cliphist or not wl_copy:
            raise ValueError("cliphist and wl-copy are required to restore clipboard history")
        decoded = subprocess.run([cliphist, "decode", entry_id], check=False, capture_output=True, timeout=3)
        if decoded.returncode:
            message = decoded.stderr.decode("utf-8", errors="replace").strip()
            raise ValueError(message or "Could not decode clipboard history item")
        try:
            copied = subprocess.run(
                [wl_copy], input=decoded.stdout, check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError(f"Clipboard restore failed: {exc}") from exc
        if copied.returncode:
            raise ValueError("wl-copy could not restore the clipboard item")
        return {"restored": entry_id}
