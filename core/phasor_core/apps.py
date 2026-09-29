"""Desktop application discovery and safe launch support."""

from __future__ import annotations

import configparser
import json
import os
import shlex
import shutil
import subprocess
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Any

from .config import state_home


def application_dirs() -> list[Path]:
    dirs = [Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser() / "applications"]
    dirs.extend(Path(path).expanduser() / "applications" for path in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"))
    return dirs


def _truth(value: str | None) -> bool:
    return (value or "").strip().lower() == "true"


@lru_cache(maxsize=1)
def _icon_index() -> dict[str, str]:
    """Index installed icon files as a fallback for incomplete icon themes."""
    data_dirs = [Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()]
    data_dirs.extend(Path(path).expanduser() for path in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"))
    icons: dict[str, str] = {}
    for data_dir in data_dirs:
        for root in (data_dir / "icons", data_dir / "pixmaps"):
            if not root.is_dir():
                continue
            for directory, _subdirs, files in os.walk(root):
                for filename in files:
                    if filename.endswith((".svg", ".svgz", ".png", ".xpm")):
                        path = Path(directory) / filename
                        if path.is_file():
                            icons.setdefault(path.stem, str(path))
    return icons


def resolve_icon(icon: str) -> str:
    """Resolve desktop icon names to installed files when possible."""
    icon = icon.strip()
    if not icon:
        return ""
    candidate = Path(icon).expanduser()
    if candidate.is_absolute() and candidate.is_file():
        return str(candidate)
    name = candidate.name
    if name.endswith((".svgz", ".svg", ".png", ".xpm")):
        name = name.rsplit(".", 1)[0]
    data_dirs = [Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()]
    data_dirs.extend(Path(path).expanduser() for path in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"))
    themes = ("hicolor", "Adwaita", "AdwaitaLegacy", "breeze", "breeze-dark")
    locations = (
        "scalable/apps", "symbolic/apps", "apps/scalable", "apps/48",
        "16x16/apps", "22x22/apps", "24x24/apps", "32x32/apps",
        "48x48/apps", "64x64/apps", "96x96/apps", "128x128/apps",
        "48x48/legacy", "48x48/legacy/apps",
    )
    extensions = (".svg", ".svgz", ".png", ".xpm")
    for data_dir in data_dirs:
        for theme in themes:
            for location in locations:
                for extension in extensions:
                    path = data_dir / "icons" / theme / location / (name + extension)
                    if path.is_file():
                        return str(path)
        for extension in extensions:
            path = data_dir / "pixmaps" / (name + extension)
            if path.is_file():
                return str(path)
    return _icon_index().get(name, "")


class AppsService:
    def __init__(self) -> None:
        self._cache: list[dict[str, Any]] | None = None

    def list(self) -> list[dict[str, Any]]:
        if self._cache is not None:
            return self._cache
        entries: dict[str, dict[str, Any]] = {}
        for directory in application_dirs():
            if not directory.is_dir():
                continue
            for path in directory.rglob("*.desktop"):
                if any(part.startswith(".") for part in path.relative_to(directory).parts):
                    continue
                config = configparser.ConfigParser(interpolation=None, strict=False)
                config.optionxform = str
                try:
                    config.read(path, encoding="utf-8")
                    item = config["Desktop Entry"]
                except (OSError, KeyError, configparser.Error):
                    continue
                if item.get("Type", "Application") != "Application" or _truth(item.get("NoDisplay")) or _truth(item.get("Hidden")):
                    continue
                name = item.get("Name", "").strip()
                command = item.get("Exec", "").strip()
                if not name or not command:
                    continue
                try_exec = item.get("TryExec", "").strip()
                if try_exec and shutil.which(try_exec) is None and not Path(try_exec).is_file():
                    continue
                app_id = path.name[:-8]
                entries.setdefault(app_id, {
                    "id": app_id,
                    "name": name,
                    "genericName": item.get("GenericName", ""),
                    "comment": item.get("Comment", ""),
                    "icon": resolve_icon(item.get("Icon", "")),
                    "desktopFile": str(path),
                    "exec": command,
                    "terminal": _truth(item.get("Terminal")),
                })
        entries.setdefault("phasor-settings", {
            "id": "phasor-settings",
            "name": "Settings",
            "genericName": "Desktop Settings",
            "comment": "Personalize appearance, workspaces, and window layout",
            "icon": resolve_icon("preferences-system"),
            "desktopFile": "phasor-settings.desktop",
            "exec": "phasorctl settings toggle",
            "terminal": False,
        })
        self._cache = sorted(entries.values(), key=lambda row: row["name"].casefold())
        return self._cache

    def search(
        self,
        query: str,
        limit: int = 50,
        favorites: list[str] | None = None,
        show_recents: bool = False,
    ) -> dict[str, Any]:
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 200:
            raise ValueError("application search limit must be from 1 to 200")
        if not isinstance(show_recents, bool):
            raise ValueError("show_recents must be a boolean")
        needle = query.strip().casefold()
        entries = self.list()
        favorite_ids = set(favorites or [])
        recent_ids = self._recent_apps() if show_recents else []
        recent_rank = {app_id: index for index, app_id in enumerate(recent_ids)}
        if not needle:
            items = [
                {**app, "favorite": app["id"] in favorite_ids, "recent": app["id"] in recent_rank}
                for app in entries
            ]
            items.sort(key=lambda app: (
                not app["favorite"],
                not app["recent"],
                recent_rank.get(app["id"], len(recent_rank)),
                app["name"].casefold(),
            ))
            return {"items": items[:limit], "total": len(items)}
        ranked = []
        for app in entries:
            name = app["name"].casefold()
            generic = app["genericName"].casefold()
            comment = app["comment"].casefold()
            app_id = app["id"].casefold()
            if needle in name or needle in generic or needle in comment or needle in app_id:
                is_recent = app["id"] in recent_rank
                score = (
                    not (app["id"] in favorite_ids),
                    not is_recent,
                    0 if name.startswith(needle) else 1,
                    name.find(needle) if needle in name else 99,
                    name,
                )
                ranked.append((score, {**app, "favorite": app["id"] in favorite_ids, "recent": is_recent}))
        ranked.sort(key=lambda item: item[0])
        return {"items": [app for _, app in ranked[:limit]], "total": len(ranked)}

    def icon_for(self, app_id: str) -> str:
        """Resolve Mango's app id to the icon declared by its desktop entry."""
        needle = app_id.casefold().removesuffix(".desktop")
        for app in self.list():
            desktop_id = str(app["id"]).casefold().removesuffix(".desktop")
            if needle in {desktop_id, Path(desktop_id).name}:
                return str(app.get("icon", ""))
        return ""

    def favorite(self, app_id: str, enabled: bool) -> dict[str, Any]:
        if not isinstance(enabled, bool):
            raise ValueError("favorite enabled must be a boolean")
        if not any(row["id"] == app_id for row in self.list()):
            raise ValueError(f"Unknown application id: {app_id}")
        from .config import load_settings, save_settings
        settings = load_settings()
        launcher = settings.setdefault("launcher", {})
        favorites = list(launcher.get("favorites", []))
        if enabled and app_id not in favorites:
            favorites.append(app_id)
        if not enabled:
            favorites = [item for item in favorites if item != app_id]
        launcher["favorites"] = favorites
        save_settings(settings)
        return {"id": app_id, "favorite": enabled}

    @staticmethod
    def _recent_apps() -> list[str]:
        path = state_home() / "recent-apps.json"
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return []
        if not isinstance(value, list):
            return []
        return list(dict.fromkeys(item for item in value if isinstance(item, str)))[:20]

    @staticmethod
    def _record_recent(app_id: str) -> None:
        recent = [app_id, *(item for item in AppsService._recent_apps() if item != app_id)][:20]
        path = state_home() / "recent-apps.json"
        temporary = None
        try:
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            fd, temporary = tempfile.mkstemp(prefix=".recent-apps-", suffix=".tmp", dir=path.parent)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(recent, stream, ensure_ascii=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        except OSError:
            if temporary:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass

    def open_store(self, app_id: str) -> dict[str, Any]:
        if not any(row["id"] == app_id for row in self.list()):
            raise ValueError(f"Unknown application id: {app_id}")
        executable = shutil.which("xdg-open")
        if not executable:
            raise ValueError("xdg-open is not installed")
        import urllib.parse
        url = "appstream://" + urllib.parse.quote(app_id, safe=".-_")
        subprocess.Popen([executable, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {"openedStore": app_id}

    def launch(self, app_id: str) -> dict[str, Any]:
        app = next((row for row in self.list() if row["id"] == app_id), None)
        if app is None:
            raise ValueError(f"Unknown application id: {app_id}")
        if app["terminal"]:
            raise ValueError("Terminal desktop entries are not launched until a terminal integration is configured")
        argv = desktop_exec_argv(app["exec"], app["name"], app["desktopFile"], app["icon"])
        if not argv:
            raise ValueError(f"Desktop entry has no runnable command: {app_id}")
        try:
            subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as exc:
            raise ValueError(f"Could not launch {app['name']}: {exc}") from exc
        self._record_recent(app_id)
        return {"launched": app_id, "name": app["name"]}


def desktop_exec_argv(command: str, name: str, desktop_file: str, icon: str) -> list[str]:
    """Expand the safe subset of the Desktop Entry Exec field codes."""
    tokens = shlex.split(command, posix=True)
    argv: list[str] = []
    for token in tokens:
        if token == "%i":
            if icon:
                argv.extend(["--icon", icon])
            continue
        if token in {"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%v", "%m"}:
            continue
        token = token.replace("%%", "\0")
        token = token.replace("%c", name).replace("%k", desktop_file)
        token = token.replace("\0", "%")
        # Field codes may also appear inside an argument. File/URI codes have no
        # input in the launcher and are removed, as required for this use case.
        for code in ("%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%v", "%m", "%i"):
            token = token.replace(code, "")
        if token:
            argv.append(token)
    return argv
