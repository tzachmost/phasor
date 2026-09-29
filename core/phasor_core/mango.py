"""MangoWM IPC adapter. Mango's tag terminology is exposed as Phasor Spaces."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from typing import Any


class MangoError(RuntimeError):
    pass


class MangoAdapter:
    def __init__(self, executable: str = "mmsg", timeout: float = 1.8) -> None:
        self.executable = executable
        self.timeout = timeout

    @property
    def available(self) -> bool:
        return shutil.which(self.executable) is not None

    def _query(self, *args: str) -> Any:
        if not self.available:
            raise MangoError("mmsg is not installed; install MangoWM and start the Phasor session")
        try:
            proc = subprocess.run(
                [self.executable, "get", *args],
                check=False,
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )
        except subprocess.TimeoutExpired as exc:
            raise MangoError("Mango IPC did not respond before the timeout") from exc
        except OSError as exc:
            raise MangoError(f"Could not run mmsg: {exc}") from exc
        if proc.returncode:
            message = proc.stderr.strip() or proc.stdout.strip() or f"mmsg exited {proc.returncode}"
            raise MangoError(message)
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            raise MangoError("Mango returned a non-JSON IPC response") from exc

    def _dispatch(self, command: str, *args: str, client_id: str | None = None) -> dict[str, Any]:
        if not self.available:
            raise MangoError("mmsg is not installed")
        if client_id is not None and not re.fullmatch(r"(?:[0-9]+|0x[0-9a-fA-F]+)", client_id):
            raise ValueError("invalid Mango client id")
        argv = [self.executable, "dispatch", ",".join([command, *args])]
        if client_id is not None:
            argv.append(f"client,{client_id}")
        try:
            proc = subprocess.run(argv, check=False, capture_output=True, text=True, timeout=self.timeout)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise MangoError(f"Mango dispatch failed: {exc}") from exc
        if proc.returncode:
            raise MangoError(proc.stderr.strip() or proc.stdout.strip() or f"{command} failed")
        return {"ok": True, "command": command}

    @staticmethod
    def _as_list(value: Any, *keys: str) -> list[dict[str, Any]]:
        if isinstance(value, list):
            return [row for row in value if isinstance(row, dict)]
        if isinstance(value, dict):
            for key in keys:
                rows = value.get(key)
                if isinstance(rows, list):
                    return [row for row in rows if isinstance(row, dict)]
        return []

    @staticmethod
    def _id(row: dict[str, Any]) -> str:
        for key in ("id", "client_id", "clientid", "address"):
            if row.get(key) is not None:
                return str(row[key])
        return ""

    def windows(self) -> list[dict[str, Any]]:
        raw = self._query("all-clients")
        clients = self._as_list(raw, "clients", "all-clients", "data")
        focused = self._query("focusing-client")
        focused_id = self._id(focused) if isinstance(focused, dict) else ""
        result = []
        for row in clients:
            client_id = self._id(row)
            result.append({
                "id": client_id,
                "title": str(row.get("title") or row.get("name") or ""),
                "appId": str(row.get("appid") or row.get("app_id") or row.get("class") or ""),
                "focused": bool(row.get("is_focused", row.get("focused", False))) or bool(focused_id and client_id == focused_id),
                "floating": bool(row.get("is_floating", row.get("floating", row.get("isfloating", False)))),
                "fullscreen": bool(row.get("is_fullscreen", row.get("fullscreen", row.get("isfullscreen", False)))),
                "tags": row.get("tags", row.get("tag", [])),
            })
        return result

    def spaces(self) -> list[dict[str, Any]]:
        raw = self._query("all-monitors")
        monitors = self._as_list(raw, "monitors", "outputs", "data")
        spaces: dict[str, dict[str, Any]] = {}
        for monitor in monitors:
            monitor_name = str(monitor.get("name") or monitor.get("monitor") or "")
            tags = monitor.get("tags", [])
            if isinstance(tags, dict):
                tags = tags.get("tags", [])
            if not isinstance(tags, list):
                tags = []
            for tag in tags:
                if not isinstance(tag, dict):
                    continue
                index = tag.get("index", tag.get("id", tag.get("tag")))
                if index is None:
                    continue
                key = str(index)
                item = spaces.setdefault(key, {
                    "id": key,
                    "name": f"Space {key}",
                    "active": False,
                    "urgent": False,
                    "windows": 0,
                    "monitors": [],
                })
                item["active"] = item["active"] or bool(tag.get("is_active", tag.get("active", False)))
                item["urgent"] = item["urgent"] or bool(tag.get("is_urgent", tag.get("urgent", False)))
                item["windows"] += int(tag.get("client_count", tag.get("clients", tag.get("nclients", 0))) or 0) if not isinstance(tag.get("clients"), list) else len(tag["clients"])
                if monitor_name and monitor_name not in item["monitors"]:
                    item["monitors"].append(monitor_name)
        if not spaces:
            # Mango exposes tag masks on all-tags on versions that omit per-monitor tag rows.
            raw_tags = self._query("all-tags")
            monitors2 = self._as_list(raw_tags, "monitors", "outputs", "data")
            for monitor in monitors2:
                tags = monitor.get("tags", [])
                if isinstance(tags, list):
                    for tag in tags:
                        if isinstance(tag, dict) and tag.get("index", tag.get("id")) is not None:
                            index = str(tag.get("index", tag.get("id")))
                            spaces[index] = {"id": index, "name": f"Space {index}", "active": bool(tag.get("is_active", False)), "urgent": bool(tag.get("is_urgent", False)), "windows": int(tag.get("clients", 0) or 0), "monitors": []}
        return sorted(spaces.values(), key=lambda item: (0, int(item["id"])) if item["id"].isdigit() else (1, item["id"]))

    def snapshot(self) -> dict[str, Any]:
        try:
            version = self._query("version")
            windows = self.windows()
            spaces = self.spaces()
            return {"available": True, "version": version, "windows": windows, "spaces": spaces, "focusedWindow": next((row for row in windows if row["focused"]), None), "error": None}
        except MangoError as exc:
            return {"available": False, "version": None, "windows": [], "spaces": [], "focusedWindow": None, "error": str(exc)}

    def focus(self, client_id: str) -> dict[str, Any]:
        return self._dispatch("focusid", client_id=client_id)

    def close(self, client_id: str) -> dict[str, Any]:
        return self._dispatch("killclient", client_id=client_id)

    def toggle_tiling(self, client_id: str) -> dict[str, Any]:
        return self._dispatch("togglefloating", client_id=client_id)

    def toggle_always_on_top(self, client_id: str) -> dict[str, Any]:
        raise MangoError("Mango does not expose an always-on-top action through IPC")

    def maximize(self, client_id: str | None = None) -> dict[str, Any]:
        return self._dispatch("togglemaximizescreen", client_id=client_id)

    def fullscreen(self, client_id: str | None = None) -> dict[str, Any]:
        return self._dispatch("togglefullscreen", client_id=client_id)

    def minimize(self, client_id: str | None = None) -> dict[str, Any]:
        return self._dispatch("minimized", client_id=client_id)

    def reload_config(self) -> dict[str, Any]:
        return self._dispatch("reload_config")

    def switch_space(self, space_id: str) -> dict[str, Any]:
        self._validate_space(space_id)
        return self._dispatch("view", space_id, "0")

    def move_window(self, space_id: str) -> dict[str, Any]:
        self._validate_space(space_id)
        return self._dispatch("tag", space_id, "0")

    def adjacent_space(self, direction: str, *, move: bool = False) -> dict[str, Any]:
        if direction not in {"left", "right"}:
            raise ValueError("direction must be left or right")
        return self._dispatch(("tagto" if move else "viewto") + direction, "0")

    @staticmethod
    def _validate_space(space_id: str) -> None:
        if not space_id.isdigit() or not 1 <= int(space_id) <= 32:
            raise ValueError("Space id must be between 1 and 32")
