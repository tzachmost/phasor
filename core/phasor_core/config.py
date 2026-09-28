"""XDG paths and safe settings loading."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


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
            "spaces": {"count": 9, "animationDuration": 200},
            "windows": {"focusMode": "click", "raiseOnFocus": True},
            "plugins": {},
        }


def load_settings() -> dict[str, Any]:
    defaults = default_settings()
    try:
        loaded = json.loads(settings_path().read_text(encoding="utf-8"))
    except FileNotFoundError:
        return defaults
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"Cannot read {settings_path()}: {exc}") from exc
    if not isinstance(loaded, dict) or loaded.get("schemaVersion") != 1:
        raise ValueError(f"Unsupported or invalid settings file: {settings_path()}")
    merged = merge(defaults, loaded)
    for section in ("appearance", "launcher", "spaces", "windows", "plugins"):
        if not isinstance(merged.get(section), dict):
            raise ValueError(f"Settings key '{section}' must be a JSON object")
    count = merged["spaces"].get("count", 9)
    if isinstance(count, bool) or not isinstance(count, int) or count not in range(1, 33):
        raise ValueError("spaces.count must be between 1 and 32")
    duration = merged["spaces"].get("animationDuration", 200)
    if isinstance(duration, bool) or not isinstance(duration, int) or not 0 <= duration <= 2000:
        raise ValueError("spaces.animationDuration must be between 0 and 2000")
    favorites = merged["launcher"].get("favorites", [])
    if not isinstance(favorites, list) or any(not isinstance(item, str) for item in favorites):
        raise ValueError("launcher.favorites must be an array of desktop-entry ids")
    if not isinstance(merged["appearance"].get("wallpaper", ""), str):
        raise ValueError("appearance.wallpaper must be a path string")
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
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
