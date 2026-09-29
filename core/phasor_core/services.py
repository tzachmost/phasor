"""Stable service API assembled over replaceable backends."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
from typing import Any

from .apps import AppsService
from .files import ClipboardService, FileIndexService
from .mango import MangoAdapter, MangoError
from .plugins import PluginManager
from .system import SystemService


METHOD_CAPABILITIES = {
    "launcher.toggle": "apps.read",
    "commands.toggle": "settings.control",
    "settings.toggle": "settings.control",
    "apps.search": "apps.read",
    "apps.launch": "apps.launch",
    "apps.favorite": "apps.favorites",
    "apps.open_store": "apps.store",
    "files.search": "files.search",
    "files.open": "files.open",
    "files.reveal": "files.reveal",
    "files.copy_path": "clipboard.write",
    "files.rename": "files.rename",
    "files.trash": "files.trash",
    "files.copy": "files.copy",
    "files.share": "clipboard.write",
    "spaces.list": "spaces.read",
    "spaces.switch": "spaces.control",
    "spaces.move_window": "spaces.control",
    "spaces.previous": "spaces.control",
    "spaces.next": "spaces.control",
    "windows.list": "windows.read",
    "windows.focus": "windows.control",
    "windows.close": "windows.control",
    "windows.toggle_tiling": "windows.control",
    "windows.toggle_always_on_top": "windows.control",
    "windows.maximize": "windows.control",
    "windows.fullscreen": "windows.control",
    "windows.minimize": "windows.control",
    "windows.restore": "windows.control",
    "clipboard.history": "clipboard.read",
    "clipboard.toggle": "clipboard.read",
    "clipboard.copy": "clipboard.write",
    "clipboard.restore": "clipboard.write",
    "media.status": "media.read",
    "media.command": "media.control",
    "theme.get": "theme.read",
    "settings.get": "settings.read",
    "settings.update": "settings.control",
    "mango.config.get": "settings.read",
    "mango.config.update": "settings.control",
    "mango.config.reset": "settings.control",
    "audio.status": "audio.read",
    "audio.get_volume": "audio.read",
    "audio.set_volume": "audio.control",
    "audio.toggle_mute": "audio.control",
    "network.status": "network.status",
    "network.set_wifi": "network.control",
    "bluetooth.status": "bluetooth.status",
    "bluetooth.set_power": "bluetooth.control",
    "brightness.status": "brightness.read",
    "brightness.set": "brightness.control",
    "notifications.status": "notifications.read",
    "notifications.toggle": "notifications.control",
    "notifications.set_dnd": "notifications.control",
    "screenshots.capture": "screenshots.capture",
}


class Services:
    def __init__(self, publish: Any) -> None:
        self.publish = publish
        self.mango = MangoAdapter()
        self.apps = AppsService()
        self.files = FileIndexService(publish=publish)
        self.clipboard = ClipboardService()
        self.plugins = PluginManager()
        self.system = SystemService()
        self._snapshot: dict[str, Any] = self.mango.snapshot()
        try:
            from .theme_export import apply_universal_theme
            apply_universal_theme(load_theme())
        except (OSError, ValueError) as exc:
            logging.getLogger("phasor.core").warning("Could not apply toolkit theme: %s", exc)

    def refresh(self) -> dict[str, Any]:
        state = self.mango.snapshot()
        if state != self._snapshot:
            previous = self._snapshot
            self._snapshot = state
            old_windows = {row["id"]: row for row in previous.get("windows", [])}
            new_windows = {row["id"]: row for row in state.get("windows", [])}
            for client_id in sorted(new_windows.keys() - old_windows.keys()):
                self.publish({"type": "event", "name": "window.opened", "data": new_windows[client_id]})
            for client_id in sorted(old_windows.keys() - new_windows.keys()):
                self.publish({"type": "event", "name": "window.closed", "data": old_windows[client_id]})
            if previous.get("focusedWindow") != state.get("focusedWindow"):
                self.publish({"type": "event", "name": "window.focused", "data": state.get("focusedWindow")})
            if previous.get("spaces") != state.get("spaces"):
                self.publish({"type": "event", "name": "space.changed", "data": state.get("spaces", [])})
            if previous.get("available") != state.get("available"):
                self.publish({"type": "event", "name": "mango.connectionChanged", "data": {"available": state["available"], "error": state["error"]}})
            self.publish({"type": "snapshot", "data": state})
        return self._snapshot

    def snapshot(self) -> dict[str, Any]:
        return self.refresh()

    def invoke_plugin(self, plugin_id: str, method: str, params: dict[str, Any]) -> Any:
        capability = METHOD_CAPABILITIES.get(method)
        if capability is None:
            raise ValueError(f"Unknown or non-plugin service method: {method}")
        self.plugins.require_capability(plugin_id, capability)
        return self.invoke(method, params)

    def invoke(self, method: str, params: dict[str, Any] | None = None) -> Any:
        params = params or {}
        if method == "health":
            return {"ok": True, "apiVersion": 1}
        if method == "snapshot":
            return self.snapshot()
        if method == "launcher.toggle":
            self.publish({"type": "action", "name": "launcher.toggle", "data": {}})
            return {"toggled": True}
        if method == "settings.toggle":
            section = params.get("section")
            if section not in {None, "appearance", "shell", "system", "shortcuts", "mango", "about"}:
                raise ValueError("Unknown Settings section")
            self.publish({"type": "action", "name": "settings.toggle", "data": {"section": section}})
            return {"toggled": True}
        if method == "commands.toggle":
            self.publish({"type": "action", "name": "commands.toggle", "data": {}})
            return {"toggled": True}
        if method == "clipboard.toggle":
            self.publish({"type": "action", "name": "clipboard.toggle", "data": {}})
            return {"toggled": True}
        if method == "settings.get":
            from .config import load_settings
            return load_settings()
        if method == "settings.update":
            from .config import load_settings, merge, save_settings
            patch = params.get("patch", params)
            if not isinstance(patch, dict):
                raise ValueError("settings patch must be a JSON object")
            previous = load_settings()
            updated = merge(previous, patch)
            save_settings(updated)
            result = load_settings()
            event_data = {"keys": sorted(patch)}
            launcher_patch = patch.get("launcher")
            appearance_patch = patch.get("appearance")
            mango_settings_changed = bool({"spaces", "windows", "commands", "settings"}.intersection(patch)) or (
                isinstance(launcher_patch, dict) and "shortcut" in launcher_patch
            ) or (
                isinstance(appearance_patch, dict)
                and {"theme", "accent", "reducedMotion"}.intersection(appearance_patch)
            )
            managed_mango_config = os.environ.get("PHASOR_MANAGED_MANGO_CONFIG")
            if mango_settings_changed:
                if managed_mango_config:
                    try:
                        from .mango_config import write_mango_config
                        write_mango_config(result, managed_mango_config)
                        self.mango.reload_config()
                        session_config = {"reloaded": True, "restartRequired": False}
                    except (MangoError, OSError, ValueError) as exc:
                        session_config = {"reloaded": False, "restartRequired": True, "error": str(exc)}
                elif os.environ.get("PHASOR_MANGO_CONFIG"):
                    session_config = {
                        "reloaded": False,
                        "restartRequired": False,
                        "customConfig": True,
                        "error": "A custom Mango config is active. These session preferences are saved, but do not override that file.",
                    }
                else:
                    session_config = {"reloaded": False, "restartRequired": True}
                event_data["sessionConfig"] = session_config
                result["sessionConfig"] = session_config
            plugins_patch = patch.get("plugins")
            if isinstance(plugins_patch, dict):
                previous_plugins = previous.get("plugins", {})
                for plugin_id, preference in plugins_patch.items():
                    if not isinstance(preference, dict) or "enabled" not in preference:
                        continue
                    prior = previous_plugins.get(plugin_id, {})
                    was_enabled = prior.get("enabled") if isinstance(prior, dict) else None
                    is_enabled = preference["enabled"]
                    if was_enabled is not None and was_enabled != is_enabled:
                        self.publish({
                            "type": "plugin.enabled" if is_enabled else "plugin.disabled",
                            "name": plugin_id,
                            "data": {"id": plugin_id, "enabled": is_enabled},
                        })
            if isinstance(appearance_patch, dict) and {"theme", "accent"}.intersection(appearance_patch):
                try:
                    from .theme_export import apply_universal_theme
                    apply_universal_theme(load_theme())
                    event_data["toolkitTheme"] = {"applied": True}
                except (OSError, ValueError) as exc:
                    event_data["toolkitTheme"] = {"applied": False, "error": str(exc)}
            if isinstance(appearance_patch, dict) and {"theme", "wallpaper"}.intersection(appearance_patch):
                theme = load_theme()
                try:
                    event_data["wallpaper"] = self.system.apply_wallpaper(theme["wallpaper"], theme["background"])
                except RuntimeError as exc:
                    event_data["wallpaper"] = {"error": str(exc)}
            self.publish({"type": "event", "name": "settings.changed", "data": event_data})
            return result
        if method == "mango.config.get":
            from .config import load_settings
            from .mango_config import editor_config
            external_config = os.environ.get("PHASOR_MANGO_CONFIG")
            if external_config:
                from pathlib import Path
                path = Path(external_config).expanduser()
                content = path.read_text(encoding="utf-8")
                return {"config": content, "source": "external: " + str(path), "editable": False}
            content, source = editor_config(load_settings())
            return {"config": content, "source": source, "editable": True}
        if method in {"mango.config.update", "mango.config.reset"}:
            runtime = os.environ.get("PHASOR_MANAGED_MANGO_CONFIG")
            if not runtime:
                raise ValueError("Mango's active config is externally managed; start Phasor with its managed Mango session to edit it here")
            from .config import load_settings
            from .mango_config import reset_editor_config, save_editor_config
            settings = load_settings()
            if method == "mango.config.update":
                config_text = params.get("config")
                if not isinstance(config_text, str):
                    raise ValueError("config must be text")
                reset = False
                save_editor_config(settings, config_text, runtime)
            else:
                reset = True
                reset_editor_config(settings, runtime)
            result = self.mango.reload_config()
            self.publish({"type": "event", "name": "mango.configChanged", "data": {"reset": reset}})
            return {"saved": True, "reloaded": True, "source": "installed defaults" if reset else "user", **result}
        if method == "plugins.list":
            return self.plugins.list()
        if method == "plugins.enable":
            result = self.plugins.set_enabled(str(params["id"]), True)
            self.publish({"type": "plugin.enabled", "name": str(params["id"]), "data": result})
            return result
        if method == "plugins.disable":
            result = self.plugins.set_enabled(str(params["id"]), False)
            self.publish({"type": "plugin.disabled", "name": str(params["id"]), "data": result})
            return result
        if method == "plugins.report-failure":
            result = self.plugins.report_failure(str(params["id"]), str(params.get("message", "Plugin load failed")))
            if result["disabled"]:
                self.publish({"type": "plugin.disabled", "name": result["id"], "data": result})
            return result
        if method == "plugins.approve":
            result = self.plugins.approve(str(params["id"]), [str(item) for item in params.get("capabilities", [])])
            self.publish({"type": "plugin.enabled", "name": str(params["id"]), "data": result})
            return result
        if method == "plugin.call":
            plugin_params = params.get("params", {})
            if not isinstance(plugin_params, dict):
                raise ValueError("plugin params must be a JSON object")
            return self.invoke_plugin(str(params["id"]), str(params["method"]), plugin_params)
        if method == "apps.search":
            from .config import load_settings
            launcher = load_settings().get("launcher", {})
            favorites = launcher.get("favorites", [])
            show_recents = bool(launcher.get("showRecents", False))
            limit = params.get("limit", 50)
            if isinstance(limit, bool) or not isinstance(limit, int):
                raise ValueError("application search limit must be an integer")
            return self.apps.search(str(params.get("query", "")), limit, list(favorites), show_recents)
        if method == "apps.favorite":
            result = self.apps.favorite(str(params["id"]), params.get("enabled", True))
            self.publish({"type": "app.favoriteChanged", "name": result["id"], "data": result})
            return result
        if method == "apps.open_store":
            return self.apps.open_store(str(params["id"]))
        if method == "apps.launch":
            result = self.apps.launch(str(params["id"]))
            self.publish({"type": "app.launched", "name": result["launched"], "data": result})
            return result
        if method == "files.search":
            limit = params.get("limit", 60)
            if isinstance(limit, bool) or not isinstance(limit, int):
                raise ValueError("file search limit must be an integer")
            return self.files.search(str(params.get("query", "")), limit)
        if method == "files.open":
            result = self.files.open(str(params["path"]))
            self.publish({"type": "file.opened", "name": result["opened"], "data": result})
            return result
        if method == "files.reveal":
            return self.files.reveal(str(params["path"]))
        if method == "files.copy_path":
            return self.clipboard.copy(str(params["path"]))
        if method == "files.rename":
            return self.files.rename(str(params["path"]), str(params.get("name", "")))
        if method == "files.trash":
            return self.files.trash(str(params["path"]))
        if method == "files.copy":
            return self.files.copy_file(str(params["path"]))
        if method == "files.share":
            return self.files.share(str(params["path"]))
        if method == "spaces.list":
            return {"items": self.snapshot().get("spaces", [])}
        if method == "spaces.switch":
            return self.mango.switch_space(str(params["id"]))
        if method == "spaces.move_window":
            return self.mango.move_window(str(params["id"]))
        if method == "spaces.previous":
            return self.mango.adjacent_space("left", move=_boolean(params.get("move", False), "move"))
        if method == "spaces.next":
            return self.mango.adjacent_space("right", move=_boolean(params.get("move", False), "move"))
        if method == "windows.list":
            items = self.snapshot().get("windows", [])
            return {"items": [{**window, "icon": self.apps.icon_for(str(window.get("appId", "")))} for window in items]}
        if method.startswith("windows."):
            action = method.split(".", 1)[1]
            client_id = str(params["id"]) if params.get("id") is not None else None
            if action == "focus" and client_id:
                return self.mango.focus(client_id)
            if action == "close" and client_id:
                return self.mango.close(client_id)
            if action == "toggle_tiling" and client_id:
                return self.mango.toggle_tiling(client_id)
            if action == "toggle_always_on_top" and client_id:
                return self.mango.toggle_always_on_top(client_id)
            if action == "maximize":
                return self.mango.maximize(client_id)
            if action == "fullscreen":
                return self.mango.fullscreen(client_id)
            if action == "minimize":
                return self.mango.minimize(client_id)
            if action == "restore" and client_id:
                return self.mango.restore_minimized(client_id)
        if method == "files.status":
            return self.files.status()
        if method == "clipboard.history":
            limit = params.get("limit", 40)
            if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 200:
                raise ValueError("clipboard history limit must be from 1 to 200")
            return self.clipboard.history(limit)
        if method == "clipboard.copy":
            return self.clipboard.copy(str(params.get("text", "")))
        if method == "clipboard.restore":
            return self.clipboard.restore(str(params.get("id", "")))
        if method == "media.status":
            command = shutil.which("playerctl")
            if not command:
                return {"available": False, "error": "playerctl is not installed"}
            proc = subprocess.run([command, "metadata", "--format", "{{playerName}}\t{{title}}\t{{artist}}\t{{status}}"], capture_output=True, text=True, timeout=2)
            return {"available": proc.returncode == 0, "metadata": proc.stdout.strip().split("\t") if proc.returncode == 0 else [], "error": proc.stderr.strip() or None}
        if method == "media.command":
            action = str(params.get("action", ""))
            commands = {"play": "play", "pause": "pause", "play-pause": "play-pause", "next": "next", "previous": "previous"}
            if action not in commands:
                raise ValueError("Unsupported media action")
            executable = shutil.which("playerctl")
            if not executable:
                raise ValueError("playerctl is not installed")
            subprocess.run([executable, commands[action]], check=True, timeout=2)
            return {"ok": True, "action": action}
        if method == "theme.get":
            return load_theme()
        if method == "wallpaper.apply":
            theme = load_theme()
            return self.system.apply_wallpaper(theme["wallpaper"], theme["background"])
        if method in {"audio.status", "audio.get_volume"}:
            return self.system.audio_status()
        if method == "audio.set_volume":
            return self.system.audio_set_volume(params.get("value"))
        if method == "audio.toggle_mute":
            return self.system.audio_toggle_mute()
        if method == "network.status":
            return self.system.network_status()
        if method == "network.set_wifi":
            return self.system.network_set_wifi(params.get("enabled"))
        if method == "bluetooth.status":
            return self.system.bluetooth_status()
        if method == "bluetooth.set_power":
            return self.system.bluetooth_set_power(params.get("enabled"))
        if method == "brightness.status":
            return self.system.brightness_status()
        if method == "brightness.set":
            return self.system.brightness_set(params.get("percent"))
        if method == "notifications.status":
            return self.system.notifications_status()
        if method == "notifications.toggle":
            return self.system.notifications_toggle()
        if method == "notifications.set_dnd":
            return self.system.notifications_set_dnd(params.get("enabled"))
        if method == "screenshots.capture":
            return self.system.screenshot_capture(params.get("copyToClipboard", False))
        raise ValueError(f"Unknown service method: {method}")

    def close(self) -> None:
        self.system.close()


def load_theme() -> dict[str, Any]:
    from .config import load_settings
    from pathlib import Path
    settings = load_settings().get("appearance", {})
    wallpaper = str(settings.get("wallpaper", "")).strip()
    theme = settings.get("theme", "dark")
    if wallpaper:
        path = Path(wallpaper).expanduser()
        if not path.is_absolute():
            path = Path.home() / path
        wallpaper = str(path)
    return {"theme": theme, "accent": settings.get("accent", "#8bd5ca"), "reducedMotion": bool(settings.get("reducedMotion", False)), "wallpaper": wallpaper, "background": "#f3f5f8" if theme == "light" else "#111318"}


def _boolean(value: Any, name: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{name} must be a boolean")
    return value
