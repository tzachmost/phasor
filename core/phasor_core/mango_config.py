"""Render Phasor-owned Mango settings into a private runtime config."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path
from typing import Any

from .config import (
    COMMAND_SHORTCUT_CHOICES,
    LAUNCHER_SHORTCUT_CHOICES,
    SETTINGS_SHORTCUT_CHOICES,
    load_settings,
    validate_settings,
)


SHORTCUT_BINDINGS = {
    "Super+Space": ("SUPER", "SPACE"),
    "Super+Alt+Space": ("SUPER+ALT", "SPACE"),
    "Super+D": ("SUPER", "D"),
    "Super+R": ("SUPER", "R"),
    "Alt+Space": ("ALT", "SPACE"),
    "Ctrl+Space": ("CTRL", "SPACE"),
    "Super+/": ("SUPER", "slash"),
    "Super+Shift+/": ("SUPER+SHIFT", "slash"),
    "Ctrl+Alt+Space": ("CTRL+ALT", "SPACE"),
    "Super+Alt+/": ("SUPER+ALT", "slash"),
    "Ctrl+Shift+P": ("CTRL+SHIFT", "P"),
    "Super+,": ("SUPER", "comma"),
    "Super+Alt+Comma": ("SUPER+ALT", "comma"),
    "Super+Shift+Comma": ("SUPER+SHIFT", "comma"),
    "Ctrl+Alt+S": ("CTRL+ALT", "S"),
}

_SPACE_VIEW_BIND = re.compile(r"bind=SUPER\+CTRL,[1-9],view,[1-9],0$")
_SPACE_MOVE_BIND = re.compile(r"bind=SUPER\+SHIFT\+CTRL,[1-9],tag,[1-9],0$")


def project_root() -> Path:
    return Path(os.environ.get("PHASOR_HOME", Path(__file__).resolve().parents[2])).resolve()


def base_config_path() -> Path:
    return project_root() / "config" / "mango" / "config.conf"


def render_mango_config(settings: dict[str, Any], base: str) -> str:
    """Apply validated user settings while preserving other Phasor bindings."""
    settings = validate_settings(settings)
    launcher = settings["launcher"]
    spaces = settings["spaces"]
    windows = settings["windows"]
    shortcut = launcher.get("shortcut", "Super+Space")
    command_shortcut = settings["commands"].get("shortcut", "Super+/")
    settings_shortcut = settings["settings"].get("shortcut", "Super+,")
    if shortcut not in LAUNCHER_SHORTCUT_CHOICES:
        raise ValueError("Unsupported Phasor Launcher shortcut")
    if command_shortcut not in COMMAND_SHORTCUT_CHOICES:
        raise ValueError("Unsupported Phasor command palette shortcut")
    if settings_shortcut not in SETTINGS_SHORTCUT_CHOICES:
        raise ValueError("Unsupported Phasor Settings shortcut")
    launcher_modifiers, launcher_key = SHORTCUT_BINDINGS[shortcut]
    command_modifiers, command_key = SHORTCUT_BINDINGS[command_shortcut]
    settings_modifiers, settings_key = SHORTCUT_BINDINGS[settings_shortcut]

    lines = []
    for line in base.splitlines():
        stripped = line.strip()
        if stripped.startswith("tagrule=id:"):
            continue
        if stripped.startswith(("tag_num=", "animation_duration_tag=", "sloppyfocus=", "focus_on_activate=")):
            continue
        if stripped.startswith("bind=") and any(
            marker in stripped
            for marker in ("phasorctl launcher toggle", "phasorctl settings toggle", "phasorctl commands toggle")
        ):
            continue
        if _SPACE_VIEW_BIND.fullmatch(stripped) or _SPACE_MOVE_BIND.fullmatch(stripped):
            continue
        lines.append(line)

    lines.extend([
        "",
        "# Phasor settings; this file is private to the current session.",
        f"tag_num={spaces.get('count', 9)}",
        f"animation_duration_tag={spaces.get('animationDuration', 200)}",
        f"sloppyfocus={1 if windows.get('focusMode', 'click') == 'sloppy' else 0}",
        f"focus_on_activate={1 if windows.get('raiseOnFocus', True) else 0}",
        "tagrule=id:*,layout_name:grid",
        f"bind={launcher_modifiers},{launcher_key},spawn,phasorctl launcher toggle",
        f"bind={settings_modifiers},{settings_key},spawn,phasorctl settings toggle",
        f"bind={command_modifiers},{command_key},spawn,phasorctl commands toggle",
    ])
    for tag in range(1, min(spaces.get("count", 9), 9) + 1):
        lines.append(f"bind=SUPER+CTRL,{tag},view,{tag},0")
        lines.append(f"bind=SUPER+SHIFT+CTRL,{tag},tag,{tag},0")
    return "\n".join(lines).rstrip() + "\n"


def write_mango_config(
    settings: dict[str, Any],
    output: str | Path,
    *,
    base_config: str | Path | None = None,
) -> Path:
    """Atomically write a mode-0600 runtime config owned by this session."""
    target = Path(output).expanduser()
    source = Path(base_config) if base_config is not None else base_config_path()
    base = source.read_text(encoding="utf-8")
    rendered = render_mango_config(settings, base)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Write the private Mango config for Phasor settings")
    parser.add_argument("--output", required=True, help="Phasor-owned runtime config path")
    args = parser.parse_args()
    write_mango_config(load_settings(), args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
