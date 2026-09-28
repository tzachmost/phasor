"""Manifest discovery, lifecycle metadata, and per-call capability policy."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from . import API_VERSION
from .config import data_home, load_settings, save_settings, state_home


class PluginError(RuntimeError):
    pass


class PluginManager:
    def __init__(self) -> None:
        self.root = Path(os.environ.get("PHASOR_HOME", Path(__file__).resolve().parents[2])).resolve()
        self.dirs = [
            self.root / "plugins",
            Path("/usr/share/phasor/plugins"),
            data_home() / "plugins",
        ]
        self.dirs = list(dict.fromkeys(directory.resolve() for directory in self.dirs))
        self.diagnostics: list[str] = []

    @staticmethod
    def _bundle_hash(directory: Path) -> str:
        digest = hashlib.sha256()
        for path in sorted(p for p in directory.rglob("*") if p.is_file() and not p.is_symlink()):
            relative = path.relative_to(directory).as_posix().encode()
            digest.update(len(relative).to_bytes(4, "big"))
            digest.update(relative)
            digest.update(path.read_bytes())
        return digest.hexdigest()

    def discover(self) -> list[dict[str, Any]]:
        self.diagnostics = []
        settings = load_settings()
        configured = settings.setdefault("plugins", {})
        if not isinstance(configured, dict):
            raise PluginError("settings.plugins must be an object")
        discovered: dict[str, dict[str, Any]] = {}
        for directory in self.dirs:
            if not directory.is_dir():
                continue
            for manifest_path in sorted(directory.glob("*/plugin.json")):
                plugin_dir = manifest_path.parent.resolve()
                try:
                    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                    plugin = self._validate(manifest, plugin_dir)
                    plugin_id = plugin["id"]
                    if plugin_id in discovered:
                        self.diagnostics.append(f"Duplicate plugin id {plugin_id} at {manifest_path}; ignored")
                        continue
                    plugin["manifestPath"] = str(manifest_path)
                    plugin["bundleHash"] = self._bundle_hash(plugin_dir)
                    plugin["builtin"] = self._is_builtin(plugin_dir, bool(manifest.get("builtin")))
                    plugin["contributions"] = [
                        {**item, "entrypoint": (plugin_dir / item["entrypoint"]).as_uri()}
                        for item in plugin.get("contributions", [])
                    ]
                    pref = configured.get(plugin_id, {})
                    if not isinstance(pref, dict):
                        pref = {}
                    approved = bool(plugin["builtin"])
                    grant = pref.get("grant", {}) if isinstance(pref, dict) else {}
                    if not approved and isinstance(grant, dict):
                        approved = grant.get("bundleHash") == plugin["bundleHash"] and set(grant.get("capabilities", [])) <= set(plugin["capabilities"])
                    plugin["enabled"] = bool(pref.get("enabled", plugin["builtin"])) and approved
                    plugin["needsApproval"] = not approved
                    plugin["surfaceCompatible"] = True
                    plugin["entrypoint"] = (plugin_dir / plugin["entrypoint"]).as_uri()
                    discovered[plugin_id] = plugin
                except (OSError, json.JSONDecodeError, PluginError, TypeError, ValueError) as exc:
                    self.diagnostics.append(f"Could not load {manifest_path}: {exc}")
        plugins = list(discovered.values())
        reserved: dict[str, dict[str, Any]] = {}
        for plugin in sorted(plugins, key=lambda item: int(item.get("surface", {}).get("priority", 0)), reverse=True):
            surface = plugin.get("surface")
            if not plugin["enabled"] or not isinstance(surface, dict) or not surface.get("reservesWorkArea"):
                continue
            anchor = surface.get("anchor")
            if anchor in reserved:
                plugin["surfaceCompatible"] = False
                self.diagnostics.append(f"Surface {plugin['id']} conflicts with {reserved[anchor]['id']} at {anchor}")
            else:
                reserved[str(anchor)] = plugin
        for plugin in plugins:
            plugin["loadable"] = plugin["enabled"] and plugin["surfaceCompatible"]
        return plugins

    @staticmethod
    def _is_builtin(plugin_dir: Path, declared: bool) -> bool:
        if not declared:
            return False
        roots = [Path(os.environ.get("PHASOR_HOME", Path(__file__).resolve().parents[2])).resolve() / "plugins", Path("/usr/share/phasor/plugins")]
        return any(plugin_dir == root or root in plugin_dir.parents for root in roots)

    @staticmethod
    def _validate(manifest: Any, plugin_dir: Path) -> dict[str, Any]:
        if not isinstance(manifest, dict):
            raise PluginError("manifest root must be an object")
        required = ("id", "name", "version", "apiVersion", "entrypoint", "categories", "capabilities")
        missing = [key for key in required if key not in manifest]
        if missing:
            raise PluginError("missing fields: " + ", ".join(missing))
        if (
            not isinstance(manifest["id"], str)
            or not manifest["id"].strip()
            or any(char.isspace() for char in manifest["id"])
            or not isinstance(manifest["name"], str)
            or not manifest["name"].strip()
            or not isinstance(manifest["version"], str)
            or not manifest["version"].strip()
            or isinstance(manifest["apiVersion"], bool)
            or not isinstance(manifest["apiVersion"], int)
        ):
            raise PluginError("invalid id or apiVersion")
        if manifest["apiVersion"] != API_VERSION:
            raise PluginError(f"plugin API {manifest['apiVersion']} is incompatible with host API {API_VERSION}")
        if not isinstance(manifest["categories"], list) or not isinstance(manifest["capabilities"], list):
            raise PluginError("categories and capabilities must be arrays")
        if any(not isinstance(value, str) for value in manifest["categories"] + manifest["capabilities"]):
            raise PluginError("categories and capabilities must contain strings")
        entrypoint = Path(str(manifest["entrypoint"]))
        if entrypoint.is_absolute() or ".." in entrypoint.parts:
            raise PluginError("entrypoint must stay inside the plugin directory")
        resolved = (plugin_dir / entrypoint).resolve()
        if plugin_dir not in resolved.parents or not resolved.is_file():
            raise PluginError("entrypoint is missing or escapes the plugin directory")
        allowed_caps = {
            "windows.read", "windows.control", "spaces.read", "spaces.control",
            "apps.read", "apps.launch", "apps.favorites", "apps.store", "files.search", "files.open", "files.reveal",
            "clipboard.read", "clipboard.write", "notifications.read", "tray.read",
            "notifications.control", "media.read", "media.control", "system.read",
            "audio.read", "audio.control", "brightness.read", "brightness.control",
            "bluetooth.status", "bluetooth.control", "screenshots.capture",
            "agent.context", "agent.actions", "network.status", "network.control", "theme.read",
        }
        unknown = set(manifest["capabilities"]) - allowed_caps
        if unknown:
            raise PluginError("unknown capabilities: " + ", ".join(sorted(unknown)))
        plugin = dict(manifest)
        supported_slots = manifest.get("supportedSlots", [])
        if not isinstance(supported_slots, list) or any(not isinstance(slot, str) or not slot for slot in supported_slots):
            raise PluginError("supportedSlots must be an array of non-empty strings")
        plugin["supportedSlots"] = supported_slots
        contributions = manifest.get("contributions", [])
        if not isinstance(contributions, list):
            raise PluginError("contributions must be an array")
        for contribution in contributions:
            if not isinstance(contribution, dict) or not isinstance(contribution.get("slot"), str) or not isinstance(contribution.get("entrypoint"), str):
                raise PluginError("each contribution requires slot and entrypoint")
            if contribution["slot"] not in supported_slots:
                raise PluginError(f"contribution slot is not declared in supportedSlots: {contribution['slot']}")
            component = Path(contribution["entrypoint"])
            if component.is_absolute() or ".." in component.parts or not (plugin_dir / component).resolve().is_file():
                raise PluginError(f"invalid contribution entrypoint: {component}")
        plugin["contributions"] = contributions
        surface = manifest.get("surface")
        if surface is not None:
            if not isinstance(surface, dict) or surface.get("anchor") not in {"top", "bottom", "left", "right", "overlay", "desktop"}:
                raise PluginError("surface anchor must be top, bottom, left, right, overlay, or desktop")
            thickness = surface.get("thickness", 0)
            if not isinstance(thickness, int) or not 0 <= thickness <= 512:
                raise PluginError("surface thickness must be an integer from 0 to 512")
            if not isinstance(surface.get("reservesWorkArea", False), bool) or not isinstance(surface.get("overlaysWindows", False), bool):
                raise PluginError("surface reservation and overlay flags must be booleans")
            if not isinstance(surface.get("priority", 0), int) or not isinstance(surface.get("autoHide", False), bool):
                raise PluginError("surface priority must be an integer and autoHide must be a boolean")
        for path in plugin_dir.rglob("*"):
            if path.is_symlink():
                raise PluginError("plugin bundles may not contain symlinks")
        return plugin

    def list(self) -> dict[str, Any]:
        plugins = self.discover()
        failures = self._load_failures()
        for plugin_id, failure in failures.items():
            if failure.get("count", 0):
                self.diagnostics.append(f"{plugin_id}: {failure['count']} load failure(s); last error: {failure.get('message', 'unknown')}")
        slots: dict[str, list[str]] = {}
        regions: dict[str, list[dict[str, Any]]] = {}
        for plugin in plugins:
            if plugin["loadable"]:
                for contribution in plugin.get("contributions", []):
                    slots.setdefault(contribution["slot"], []).append(plugin["id"])
                surface = plugin.get("surface")
                if isinstance(surface, dict):
                    anchor = surface["anchor"]
                    regions.setdefault(anchor, []).append({
                        "plugin": plugin["id"],
                        "thickness": surface.get("thickness", 0),
                        "reservesWorkArea": surface.get("reservesWorkArea", False),
                        "overlaysWindows": surface.get("overlaysWindows", False),
                        "autoHide": surface.get("autoHide", False),
                        "priority": surface.get("priority", 0),
                        "slots": surface.get("slots", []),
                    })
        return {"apiVersion": API_VERSION, "plugins": plugins, "slots": slots, "regions": regions, "diagnostics": list(self.diagnostics)}

    @staticmethod
    def _load_failures() -> dict[str, Any]:
        try:
            value = json.loads((state_home() / "plugin-failures.json").read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def report_failure(self, plugin_id: str, message: str) -> dict[str, Any]:
        plugin = next((item for item in self.discover() if item["id"] == plugin_id), None)
        if plugin is None:
            raise PluginError(f"Unknown plugin: {plugin_id}")
        failures = self._load_failures()
        record = failures.get(plugin_id, {})
        if record.get("bundleHash") != plugin["bundleHash"]:
            record = {"bundleHash": plugin["bundleHash"], "count": 0}
        record["count"] = int(record.get("count", 0)) + 1
        record["message"] = message[:500]
        failures[plugin_id] = record
        path = state_home() / "plugin-failures.json"
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(failures, indent=2) + "\n", encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(path)
        disabled = False
        if record["count"] >= 3:
            settings = load_settings()
            settings.setdefault("plugins", {}).setdefault(plugin_id, {})["enabled"] = False
            save_settings(settings)
            disabled = True
        return {"id": plugin_id, "failures": record["count"], "disabled": disabled, "message": record["message"]}

    def set_enabled(self, plugin_id: str, enabled: bool) -> dict[str, Any]:
        plugins = {item["id"]: item for item in self.discover()}
        if plugin_id not in plugins:
            raise PluginError(f"Unknown plugin: {plugin_id}")
        settings = load_settings()
        pref = settings.setdefault("plugins", {}).setdefault(plugin_id, {})
        pref["enabled"] = enabled
        save_settings(settings)
        return {"id": plugin_id, "enabled": enabled, "needsApproval": plugins[plugin_id]["needsApproval"]}

    def approve(self, plugin_id: str, capabilities: list[str]) -> dict[str, Any]:
        plugins = {item["id"]: item for item in self.discover()}
        plugin = plugins.get(plugin_id)
        if plugin is None:
            raise PluginError(f"Unknown plugin: {plugin_id}")
        if plugin["builtin"]:
            raise PluginError("First-party plugins are already approved")
        requested = set(plugin["capabilities"])
        grants = set(capabilities)
        if not grants <= requested:
            raise PluginError("Can only grant capabilities declared in the manifest")
        settings = load_settings()
        pref = settings.setdefault("plugins", {}).setdefault(plugin_id, {})
        pref["grant"] = {"bundleHash": plugin["bundleHash"], "capabilities": sorted(grants)}
        pref["enabled"] = True
        save_settings(settings)
        return {"id": plugin_id, "enabled": True, "capabilities": sorted(grants), "bundleHash": plugin["bundleHash"]}

    def require_capability(self, plugin_id: str, capability: str) -> None:
        plugin = next((item for item in self.discover() if item["id"] == plugin_id), None)
        if plugin is None:
            raise PluginError(f"Unknown plugin: {plugin_id}")
        if not plugin["enabled"]:
            if plugin["needsApproval"]:
                raise PluginError(f"Plugin {plugin_id} is disabled or needs approval for this bundle")
            raise PluginError(f"Plugin {plugin_id} is disabled")
        if capability not in plugin["capabilities"]:
            raise PluginError(f"Plugin {plugin_id} did not declare {capability}")
        if not plugin["builtin"]:
            settings = load_settings()
            grant = settings.get("plugins", {}).get(plugin_id, {}).get("grant", {})
            if grant.get("bundleHash") != plugin["bundleHash"] or capability not in grant.get("capabilities", []):
                raise PluginError(f"Plugin {plugin_id} has not been granted {capability} for this bundle")
