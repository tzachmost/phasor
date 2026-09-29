"""Human-readable diagnostics with explicit pass/warning/failure status."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from .client import request
from .config import config_home, default_settings_path, load_settings, runtime_home, state_home
from .mango import MangoAdapter
from .plugins import PluginError, PluginManager


class Report:
    def __init__(self) -> None:
        self.failures = 0

    def add(self, status: str, name: str, detail: str) -> None:
        print(f"{status:4} {name}: {detail}")
        if status == "FAIL":
            self.failures += 1


def _quickshell_version() -> str:
    command = shutil.which("quickshell")
    if not command:
        raise RuntimeError("quickshell is not installed")
    proc = subprocess.run([command, "--version"], check=False, capture_output=True, text=True, timeout=4)
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "version check failed")
    return proc.stdout.strip() or proc.stderr.strip()


def main() -> int:
    report = Report()
    checks = {
        "MangoWM": "mango",
        "Mango IPC": "mmsg",
        "Quickshell": "quickshell",
        "Python 3": "python3",
        "File opener": "xdg-open",
        "Wayland clipboard": "wl-copy",
        "Notification backend": "swaync",
        "Clipboard history": "cliphist",
        "Screenshot tool": "flameshot",
        "Background service": "swaybg",
        "Media controls": "playerctl",
        "Brightness controls": "brightnessctl",
        "Audio controls": "wpctl",
        "Network controls": "nmcli",
        "Bluetooth controls": "bluetoothctl",
        "Notification controls": "swaync-client",
    }
    for label, executable in checks.items():
        path = shutil.which(executable)
        mandatory = label in {
            "MangoWM", "Mango IPC", "Quickshell", "Python 3", "Wayland clipboard",
            "Notification backend", "Clipboard history", "Screenshot tool", "Background service",
            "Notification controls",
        }
        report.add("PASS" if path else ("FAIL" if mandatory else "WARN"), label, path or f"{executable} is not installed")

    try:
        version = _quickshell_version()
        report.add("PASS", "Quickshell version", version)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        report.add("FAIL", "Quickshell version", str(exc))

    if default_settings_path().is_file():
        try:
            load_settings()
            report.add("PASS", "Phasor settings", f"valid schemaVersion 1 settings at {config_home() / 'settings.json'}")
        except (ValueError, OSError) as exc:
            report.add("FAIL", "Phasor settings", str(exc))
    else:
        report.add("FAIL", "Default settings", f"missing {default_settings_path()}")

    session_candidates = [
        Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "wayland-sessions/phasor.desktop",
        Path("/usr/share/wayland-sessions/phasor.desktop"),
    ]
    entry = next((path for path in session_candidates if path.is_file()), None)
    report.add("PASS" if entry else "WARN", "Wayland session", str(entry) if entry else "Phasor session entry has not been installed")

    try:
        plugin_state = PluginManager().list()
        enabled = [plugin["id"] for plugin in plugin_state["plugins"] if plugin.get("loadable")]
        report.add("PASS" if enabled else "WARN", "Plugin manifests", f"{len(enabled)} loadable: {', '.join(enabled) or 'none'}")
        for diagnostic in plugin_state["diagnostics"]:
            report.add("WARN", "Plugin diagnostic", diagnostic)
    except (ValueError, OSError, json.JSONDecodeError, PluginError) as exc:
        report.add("FAIL", "Plugin manifests", str(exc))

    try:
        core = request("health", timeout=0.5)
        report.add("PASS", "Phasor core", f"API {core.get('apiVersion')} at {runtime_home()}")
    except RuntimeError as exc:
        report.add("WARN", "Phasor core", str(exc))

    mango = MangoAdapter().snapshot()
    if mango["available"]:
        report.add("PASS", "Mango IPC", f"connected; {len(mango['windows'])} window(s), {len(mango['spaces'])} Space(s)")
    elif shutil.which("mmsg"):
        report.add("WARN", "Mango IPC", mango["error"] or "not connected; run diagnostics inside a Phasor session")
    else:
        report.add("FAIL", "Mango IPC", mango["error"] or "mmsg unavailable")

    report.add("INFO", "Logs", str(state_home()))
    if report.failures:
        print(f"\nDoctor found {report.failures} required issue(s).")
        return 1
    print("\nDoctor checks complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
