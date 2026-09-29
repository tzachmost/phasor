"""Render Phasor-owned Mango settings into a private runtime config."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from .config import (
    COMMAND_SHORTCUT_CHOICES,
    LAUNCHER_SHORTCUT_CHOICES,
    SETTINGS_SHORTCUT_CHOICES,
    config_home,
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
_KEY_BIND = re.compile(r"^((?:bind[a-z]*|mousebind|axisbind))\s*=\s*([^,]+),([^,]+),.*$", re.IGNORECASE)


def _binding_signature(line: str) -> tuple[str, tuple[str, ...], str] | None:
    match = _KEY_BIND.match(line.strip())
    if not match:
        return None
    modifiers = tuple(sorted(value.strip().casefold() for value in match.group(2).split("+") if value.strip() not in {"", "none"}))
    return match.group(1).casefold(), modifiers, match.group(3).strip().casefold()


def _keep_effective_bindings(lines: list[str]) -> list[str]:
    seen: set[tuple[str, tuple[str, ...], str]] = set()
    keep: set[int] = set()
    for index in range(len(lines) - 1, -1, -1):
        signature = _binding_signature(lines[index])
        if signature is None:
            keep.add(index)
        elif signature not in seen:
            seen.add(signature)
            keep.add(index)
    return [line for index, line in enumerate(lines) if index in keep]


def project_root() -> Path:
    return Path(os.environ.get("PHASOR_HOME", Path(__file__).resolve().parents[2])).resolve()


def base_config_path() -> Path:
    return project_root() / "config" / "mango" / "config.conf"


def user_config_path() -> Path:
    return config_home() / "mango.conf"


def load_mango_base() -> tuple[str, str]:
    """Return the user's native config or installed Mango defaults plus Phasor profile."""
    custom = user_config_path()
    if custom.is_file():
        return custom.read_text(encoding="utf-8"), "user"

    upstream = Path("/etc/mango/config.conf")
    if not upstream.is_file():
        upstream = base_config_path()
    profile = base_config_path()
    parts = [upstream.read_text(encoding="utf-8")]
    if profile.resolve() != upstream.resolve():
        parts.append(profile.read_text(encoding="utf-8"))
    return "\n".join(parts), "installed defaults"


def render_mango_config(settings: dict[str, Any], base: str) -> str:
    """Apply validated user settings while preserving other Phasor bindings."""
    settings = validate_settings(settings)
    launcher = settings["launcher"]
    spaces = settings["spaces"]
    windows = settings["windows"]
    appearance = settings["appearance"]
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
    # Appearance and motion are owned by the shared Phasor settings page, so
    # they stay coherent across Mango, Quickshell, GTK, and Qt applications.
    theme_keys = {
        "rootcolor", "bordercolor", "splitcolor", "focuscolor",
        "maximizescreencolor", "globalcolor", "overlaycolor",
    }
    animation_keys = {"animations", "layer_animations"}
    for line in base.splitlines():
        stripped = line.strip()
        key, separator, _value = stripped.partition("=")
        key = key.strip().casefold()
        if separator and key in theme_keys:
            continue
        if separator and (key in animation_keys or key.startswith("animation_duration_")):
            continue
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
        "# Colors and reduced motion follow the shared Phasor Appearance page.",
        f"tag_num={spaces.get('count', 9)}",
        f"animations={0 if appearance.get('reducedMotion', False) else 1}",
        f"layer_animations={0 if appearance.get('reducedMotion', False) else 1}",
        f"animation_duration_move={0 if appearance.get('reducedMotion', False) else spaces.get('animationDuration', 200)}",
        f"animation_duration_open={0 if appearance.get('reducedMotion', False) else spaces.get('animationDuration', 200)}",
        f"animation_duration_tag={0 if appearance.get('reducedMotion', False) else spaces.get('animationDuration', 200)}",
        f"animation_duration_close={0 if appearance.get('reducedMotion', False) else spaces.get('animationDuration', 200)}",
        f"sloppyfocus={1 if windows.get('focusMode', 'click') == 'sloppy' else 0}",
        f"focus_on_activate={1 if windows.get('raiseOnFocus', True) else 0}",
        *_theme_config_lines(appearance),
        "tagrule=id:*,layout_name:grid",
        f"bind={launcher_modifiers},{launcher_key},spawn,phasorctl launcher toggle",
        f"bind={settings_modifiers},{settings_key},spawn,phasorctl settings toggle",
        f"bind={command_modifiers},{command_key},spawn,phasorctl commands toggle",
    ])
    for tag in range(1, min(spaces.get("count", 9), 9) + 1):
        lines.append(f"bind=SUPER+CTRL,{tag},view,{tag},0")
        lines.append(f"bind=SUPER+SHIFT+CTRL,{tag},tag,{tag},0")
    return "\n".join(_keep_effective_bindings(lines)).rstrip() + "\n"


def _theme_config_lines(appearance: dict[str, Any]) -> list[str]:
    requested = str(appearance.get("theme", "dark"))
    dark = requested != "light"
    if requested == "system":
        settings = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser() / "gtk-3.0" / "settings.ini"
        try:
            value = next(
                line.partition("=")[2].strip().casefold()
                for line in settings.read_text(encoding="utf-8").splitlines()
                if line.startswith("gtk-application-prefer-dark-theme=")
            )
            dark = value == "true"
        except (OSError, StopIteration):
            pass
    accent = str(appearance.get("accent", "#8bd5ca")).lstrip("#").lower()
    background = "111318" if dark else "f3f5f8"
    border = "3e4654" if dark else "b6c0cd"
    return [
        f"rootcolor=0x{background}ff",
        f"bordercolor=0x{border}ff",
        f"splitcolor=0x{accent}ff",
        f"focuscolor=0x{accent}ff",
        f"maximizescreencolor=0x{accent}ff",
        f"globalcolor=0x{accent}ff",
        f"overlaycolor=0x{accent}66",
    ]


def editor_config(settings: dict[str, Any]) -> tuple[str, str]:
    base, source = load_mango_base()
    return render_mango_config(settings, base), source


def _atomic_write(target: Path, content: str) -> Path:
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
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


def validate_config_text(content: str) -> None:
    executable = shutil.which("mango")
    if not executable:
        raise RuntimeError("Mango is not installed, so the configuration cannot be checked")
    check_dir = config_home()
    check_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".mango-check-", suffix=".conf", dir=check_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.chmod(temporary, 0o600)
        try:
            proc = subprocess.run([executable, "-c", temporary, "-p"], capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired as exc:
            raise ValueError("Mango configuration check timed out") from exc
        if proc.returncode:
            message = proc.stderr.strip() or proc.stdout.strip() or f"Mango rejected the config (exit {proc.returncode})"
            raise ValueError(message)
    finally:
        try:
            os.unlink(temporary)
        except OSError:
            pass


def save_editor_config(settings: dict[str, Any], content: str, runtime: str | Path) -> Path:
    if not isinstance(content, str) or not content.strip():
        raise ValueError("Mango config must be non-empty text")
    if len(content.encode("utf-8")) > 1_048_576:
        raise ValueError("Mango config is limited to 1 MiB")
    if "\0" in content:
        raise ValueError("Mango config cannot contain NUL bytes")
    effective = render_mango_config(settings, content)
    validate_config_text(content)
    validate_config_text(effective)
    _atomic_write(user_config_path(), content.rstrip() + "\n")
    return _atomic_write(Path(runtime).expanduser(), effective)


def reset_editor_config(settings: dict[str, Any], runtime: str | Path) -> Path:
    try:
        user_config_path().unlink()
    except FileNotFoundError:
        pass
    base, _source = load_mango_base()
    effective = render_mango_config(settings, base)
    validate_config_text(effective)
    return _atomic_write(Path(runtime).expanduser(), effective)


def write_mango_config(
    settings: dict[str, Any],
    output: str | Path,
    *,
    base_config: str | Path | None = None,
) -> Path:
    """Atomically write a mode-0600 runtime config owned by this session."""
    target = Path(output).expanduser()
    source = Path(base_config) if base_config is not None else None
    base = source.read_text(encoding="utf-8") if source is not None else load_mango_base()[0]
    rendered = render_mango_config(settings, base)
    return _atomic_write(target, rendered)


def main() -> int:
    parser = argparse.ArgumentParser(description="Write the private Mango config for Phasor settings")
    parser.add_argument("--output", required=True, help="Phasor-owned runtime config path")
    args = parser.parse_args()
    write_mango_config(load_settings(), args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
