"""XDG paths and safe settings loading."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

LAUNCHER_SHORTCUT_CHOICES = (
    "Super+Space",
    "Super+Alt+Space",
    "Super+D",
    "Super+R",
    "Alt+Space",
    "Ctrl+Space",
)
COMMAND_SHORTCUT_CHOICES = (
    "Super+/",
    "Super+Shift+/",
    "Ctrl+Alt+Space",
    "Super+Alt+/",
    "Ctrl+Shift+P",
)
SETTINGS_SHORTCUT_CHOICES = (
    "Super+,",
    "Super+Alt+Comma",
    "Super+Shift+Comma",
    "Ctrl+Alt+S",
)


def _xdg(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


def config_home() -> Path:
    return _xdg("XDG_CONFIG_HOME", "~/.config") / "phasor"


def data_home() -> Path:
    return _xdg("XDG_DATA_HOME", "~/.local/share") / "phasor"


def cache_home() -> Path:
    return _xdg("XDG_CACHE_HOME", "~/.cache") / "phasor"


def state_home() -> Path:
    return _xdg("XDG_STATE_HOME", "~/.local/state") / "phasor"


def runtime_home() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        return Path(runtime) / "phasor"
    return Path("/tmp") / f"phasor-{os.getuid()}"


def settings_path() -> Path:
    return config_home() / "settings.json"


def default_settings_path() -> Path:
    root = Path(os.environ.get("PHASOR_HOME", Path(__file__).resolve().parents[2]))
    return root / "config" / "defaults" / "settings.json"


def default_settings() -> dict[str, Any]:
    try:
        return json.loads(default_settings_path().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {
            "schemaVersion": 1,
            "appearance": {"theme": "dark", "accent": "#8bd5ca", "reducedMotion": False},
            "launcher": {"favorites": [], "showRecents": False},
            "commands": {"shortcut": "Super+/"},
            "settings": {"shortcut": "Super+,"},
            "spaces": {"count": 9, "animationDuration": 200},
            "windows": {"focusMode": "click", "raiseOnFocus": True},
            "dock": {"showCloseButtons": True, "showEmptyState": True},
            "plugins": {},
        }


def load_settings() -> dict[str, Any]:
    defaults = default_settings()
    try:
        loaded = json.loads(settings_path().read_text(encoding="utf-8"))
    except FileNotFoundError:
        return validate_settings(defaults)
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"Cannot read {settings_path()}: {exc}") from exc
    if not isinstance(loaded, dict) or loaded.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported or invalid settings file: {settings_path()}")

    return validate_settings(merge(defaults, loaded))


def validate_settings(merged: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(merged, dict) or merged.get("schemaVersion") != 1:
        raise ValueError("schemaVersion must be 1")
    allowed_sections = {"schemaVersion", "appearance", "launcher", "commands", "settings", "spaces", "windows", "dock", "plugins"}
    unknown_sections = set(merged) - allowed_sections
    if unknown_sections:
        raise ValueError("Unknown settings sections: " + ", ".join(sorted(unknown_sections)))
    for section in ("appearance", "launcher", "commands", "settings", "spaces", "windows", "dock", "plugins"):
        if not isinstance(merged.get(section), dict):
            raise ValueError(f"Settings key '{section}' must be a JSON object")
    appearance = merged["appearance"]
    unknown_appearance = set(appearance) - {"theme", "accent", "reducedMotion", "wallpaper"}
    if unknown_appearance:
        raise ValueError("Unknown appearance settings: " + ", ".join(sorted(unknown_appearance)))
    if appearance.get("theme") not in {"dark", "light", "system"}:
        raise ValueError("appearance.theme must be dark, light, or system")
    accent = appearance.get("accent", "#8bd5ca")
    if not isinstance(accent, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", accent):
        raise ValueError("appearance.accent must be a six-digit hexadecimal color")
    if not isinstance(appearance.get("reducedMotion", False), bool):
        raise ValueError("appearance.reducedMotion must be a boolean")
    if not isinstance(appearance.get("wallpaper", ""), str):
        raise ValueError("appearance.wallpaper must be a path string")
    launcher = merged["launcher"]
    unknown_launcher = set(launcher) - {"shortcut", "showRecents", "favorites"}
    if unknown_launcher:
        raise ValueError("Unknown launcher settings: " + ", ".join(sorted(unknown_launcher)))
    if launcher.get("shortcut", "Super+Space") not in LAUNCHER_SHORTCUT_CHOICES:
        raise ValueError("launcher.shortcut must be one of: " + ", ".join(LAUNCHER_SHORTCUT_CHOICES))
    if not isinstance(launcher.get("showRecents", False), bool):
        raise ValueError("launcher.showRecents must be a boolean")
    if not isinstance(launcher.get("favorites", []), list) or any(not isinstance(item, str) for item in launcher.get("favorites", [])):
        raise ValueError("launcher.favorites must be an array of desktop-entry ids")
    commands = merged["commands"]
    unknown_commands = set(commands) - {"shortcut"}
    if unknown_commands:
        raise ValueError("Unknown command settings: " + ", ".join(sorted(unknown_commands)))
    if commands.get("shortcut", "Super+/") not in COMMAND_SHORTCUT_CHOICES:
        raise ValueError("commands.shortcut must be one of: " + ", ".join(COMMAND_SHORTCUT_CHOICES))
    settings_shortcuts = merged["settings"]
    unknown_settings = set(settings_shortcuts) - {"shortcut"}
    if unknown_settings:
        raise ValueError("Unknown Settings preferences: " + ", ".join(sorted(unknown_settings)))
    if settings_shortcuts.get("shortcut", "Super+,") not in SETTINGS_SHORTCUT_CHOICES:
        raise ValueError("settings.shortcut must be one of: " + ", ".join(SETTINGS_SHORTCUT_CHOICES))
    spaces = merged["spaces"]
    unknown_spaces = set(spaces) - {"count", "animationDuration"}
    if unknown_spaces:
        raise ValueError("Unknown Spaces settings: " + ", ".join(sorted(unknown_spaces)))
    count = spaces.get("count", 9)
    if isinstance(count, bool) or not isinstance(count, int) or count not in range(1, 33):
        raise ValueError("spaces.count must be between 1 and 32")
    duration = spaces.get("animationDuration", 200)
    if isinstance(duration, bool) or not isinstance(duration, int) or not 0 <= duration <= 2000:
        raise ValueError("spaces.animationDuration must be between 0 and 2000")
    windows = merged["windows"]
    unknown_windows = set(windows) - {"focusMode", "raiseOnFocus"}
    if unknown_windows:
        raise ValueError("Unknown window settings: " + ", ".join(sorted(unknown_windows)))
    if windows.get("focusMode", "click") not in {"click", "sloppy"}:
        raise ValueError("windows.focusMode must be click or sloppy")
    if not isinstance(windows.get("raiseOnFocus", True), bool):
        raise ValueError("windows.raiseOnFocus must be a boolean")
    dock = merged["dock"]
    unknown_dock = set(dock) - {"showCloseButtons", "showEmptyState"}
    if unknown_dock:
        raise ValueError("Unknown Dock settings: " + ", ".join(sorted(unknown_dock)))
    for name in ("showCloseButtons", "showEmptyState"):
        if not isinstance(dock.get(name, True), bool):
            raise ValueError(f"dock.{name} must be a boolean")
    if any(not isinstance(plugin_id, str) or not isinstance(value, dict) for plugin_id, value in merged["plugins"].items()):
        raise ValueError("plugins must map plugin ids to JSON objects")
    for plugin_id, preference in merged["plugins"].items():
        if "enabled" in preference and not isinstance(preference["enabled"], bool):
            raise ValueError(f"plugins.{plugin_id}.enabled must be a boolean")
    return merged


def merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = value
    return result


def save_settings(settings: dict[str, Any]) -> None:
    settings = validate_settings(settings)
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
