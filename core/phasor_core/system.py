"""Small system-control adapters backed by standard Wayland utilities."""

from __future__ import annotations

import re
import shutil
import subprocess
from typing import Any


class SystemService:
    """Stable Phasor methods over replaceable desktop utilities.

    Every external command is invoked with an argv array. Status methods report
    missing backends as unavailable; control methods return actionable errors.
    """

    @staticmethod
    def _run(executable: str, *args: str, timeout: float = 3.0) -> subprocess.CompletedProcess[str]:
        path = shutil.which(executable)
        if not path:
            raise RuntimeError(f"{executable} is not installed")
        try:
            return subprocess.run([path, *args], capture_output=True, text=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise RuntimeError(f"{executable} failed: {exc}") from exc

    @classmethod
    def _checked(cls, executable: str, *args: str, timeout: float = 3.0) -> str:
        proc = cls._run(executable, *args, timeout=timeout)
        if proc.returncode:
            raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"{executable} exited {proc.returncode}")
        return proc.stdout.strip()

    @classmethod
    def audio_status(cls) -> dict[str, Any]:
        if not shutil.which("wpctl"):
            return {"available": False, "error": "wpctl is not installed"}
        try:
            output = cls._checked("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
        except RuntimeError as exc:
            return {"available": False, "error": str(exc)}
        match = re.search(r"Volume:\s*([0-9]+(?:\.[0-9]+)?)", output)
        if not match:
            return {"available": False, "error": "wpctl returned an unrecognized volume"}
        return {"available": True, "volume": float(match.group(1)), "muted": "[MUTED]" in output.upper()}

    @classmethod
    def audio_set_volume(cls, value: Any) -> dict[str, Any]:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 1.5:
            raise ValueError("audio volume must be a number from 0 to 1.5")
        cls._checked("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{float(value):.3f}")
        return cls.audio_status()

    @classmethod
    def audio_toggle_mute(cls) -> dict[str, Any]:
        cls._checked("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle")
        return cls.audio_status()

    @classmethod
    def network_status(cls) -> dict[str, Any]:
        if not shutil.which("nmcli"):
            return {"available": False, "error": "NetworkManager (nmcli) is not installed"}
        try:
            connection = cls._checked("nmcli", "-t", "-f", "STATE,CONNECTIVITY", "general")
            wifi = cls._checked("nmcli", "radio", "wifi")
            state, _, connectivity = connection.partition(":")
            return {"available": True, "state": state, "connectivity": connectivity, "wifiEnabled": wifi.lower() == "enabled"}
        except RuntimeError as exc:
            return {"available": False, "error": str(exc)}

    @classmethod
    def network_set_wifi(cls, enabled: Any) -> dict[str, Any]:
        if not isinstance(enabled, bool):
            raise ValueError("wifi enabled must be a boolean")
        cls._checked("nmcli", "radio", "wifi", "on" if enabled else "off")
        return cls.network_status()

    @classmethod
    def bluetooth_status(cls) -> dict[str, Any]:
        if not shutil.which("bluetoothctl"):
            return {"available": False, "error": "bluetoothctl is not installed"}
        try:
            output = cls._checked("bluetoothctl", "show")
        except RuntimeError as exc:
            return {"available": False, "error": str(exc)}
        match = re.search(r"^\s*Powered:\s*(yes|no)\s*$", output, re.MULTILINE | re.IGNORECASE)
        if not match:
            return {"available": False, "error": "bluetoothctl returned no adapter power state"}
        return {"available": True, "powered": match.group(1).lower() == "yes"}

    @classmethod
    def bluetooth_set_power(cls, enabled: Any) -> dict[str, Any]:
        if not isinstance(enabled, bool):
            raise ValueError("Bluetooth enabled must be a boolean")
        cls._checked("bluetoothctl", "power", "on" if enabled else "off")
        return cls.bluetooth_status()

    @classmethod
    def brightness_status(cls) -> dict[str, Any]:
        if not shutil.which("brightnessctl"):
            return {"available": False, "error": "brightnessctl is not installed"}
        try:
            output = cls._checked("brightnessctl", "-m")
        except RuntimeError as exc:
            return {"available": False, "error": str(exc)}
        row = output.splitlines()[0].split(",") if output else []
        if len(row) < 5 or not row[2].isdigit() or not row[3].isdigit():
            return {"available": False, "error": "brightnessctl returned an unrecognized device state"}
        current, maximum = int(row[2]), int(row[3])
        return {"available": True, "device": row[0], "current": current, "maximum": maximum, "percent": (current * 100 / maximum) if maximum else 0}

    @classmethod
    def brightness_set(cls, percent: Any) -> dict[str, Any]:
        if isinstance(percent, bool) or not isinstance(percent, (int, float)) or not 0 <= percent <= 100:
            raise ValueError("brightness must be a number from 0 to 100")
        cls._checked("brightnessctl", "set", f"{float(percent):.0f}%")
        return cls.brightness_status()

    @classmethod
    def notifications_status(cls) -> dict[str, Any]:
        executable = shutil.which("swaync-client")
        if not executable:
            return {"available": False, "error": "swaync-client is not installed"}
        try:
            dnd = cls._checked("swaync-client", "-D", "-sw", timeout=1.5)
            count = cls._checked("swaync-client", "-c", "-sw", timeout=1.5)
            return {"available": True, "backend": "SwayNotificationCenter", "doNotDisturb": dnd.lower() == "true", "count": int(count)}
        except (RuntimeError, ValueError) as exc:
            return {"available": False, "error": str(exc)}

    @classmethod
    def notifications_toggle(cls) -> dict[str, Any]:
        cls._checked("swaync-client", "-t", "-sw")
        return {"ok": True, "action": "toggle"}

    @classmethod
    def notifications_set_dnd(cls, enabled: Any) -> dict[str, Any]:
        if not isinstance(enabled, bool):
            raise ValueError("do-not-disturb enabled must be a boolean")
        cls._checked("swaync-client", "-dn" if enabled else "-df", "-sw")
        return {"ok": True, "doNotDisturb": enabled}

    @classmethod
    def screenshot_capture(cls, copy_to_clipboard: Any = False) -> dict[str, Any]:
        if not isinstance(copy_to_clipboard, bool):
            raise ValueError("copyToClipboard must be a boolean")
        args = ["gui"]
        if copy_to_clipboard:
            args.append("-c")
        executable = shutil.which("flameshot")
        if not executable:
            raise RuntimeError("flameshot is not installed")
        try:
            proc = subprocess.Popen([executable, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as exc:
            raise RuntimeError(f"Could not start flameshot: {exc}") from exc
        return {"started": True, "pid": proc.pid, "copyToClipboard": copy_to_clipboard}
