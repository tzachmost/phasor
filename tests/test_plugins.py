import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.plugins import PluginError, PluginManager


def write_plugin(root: Path, plugin_id: str, *, builtin=False, surface=None):
    folder = root / "plugins" / plugin_id
    folder.mkdir(parents=True)
    (folder / "Entry.qml").write_text("import QtQuick\nItem {}\n", encoding="utf-8")
    manifest = {
        "id": plugin_id,
        "name": plugin_id,
        "version": "1.0.0",
        "apiVersion": 1,
        "entrypoint": "Entry.qml",
        "categories": ["status-item"],
        "capabilities": ["apps.read"],
        "builtin": builtin,
    }
    if surface:
        manifest["surface"] = surface
    (folder / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
    return folder


class PluginManagerTests(unittest.TestCase):
    def test_user_plugin_needs_bundle_specific_grant(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = write_plugin(root, "org.example.user")
            env = {
                "PHASOR_HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_DATA_HOME": str(root / "data"),
                "XDG_STATE_HOME": str(root / "state"),
            }
            with patch.dict(os.environ, env):
                manager = PluginManager()
                plugin = manager.discover()[0]
                self.assertFalse(plugin["loadable"])
                manager.approve("org.example.user", ["apps.read"])
                manager.require_capability("org.example.user", "apps.read")
                (folder / "Entry.qml").write_text("import QtQuick\nItem { objectName: \"changed\" }\n", encoding="utf-8")
                with self.assertRaisesRegex(PluginError, "needs approval"):
                    manager.require_capability("org.example.user", "apps.read")

    def test_surface_priority_selects_one_reserving_plugin_per_edge(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_plugin(root, "dev.example.high", builtin=True, surface={"anchor": "bottom", "thickness": 48, "reservesWorkArea": True, "overlaysWindows": False, "priority": 100})
            write_plugin(root, "dev.example.low", builtin=True, surface={"anchor": "bottom", "thickness": 32, "reservesWorkArea": True, "overlaysWindows": False, "priority": 10})
            env = {
                "PHASOR_HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_DATA_HOME": str(root / "data"),
                "XDG_STATE_HOME": str(root / "state"),
            }
            with patch.dict(os.environ, env):
                plugins = {plugin["id"]: plugin for plugin in PluginManager().list()["plugins"]}
                self.assertTrue(plugins["dev.example.high"]["loadable"])
                self.assertFalse(plugins["dev.example.low"]["loadable"])

    def test_identical_plugin_copies_are_ignored_without_diagnostic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = write_plugin(root, "dev.example.builtin", builtin=True)
            installed_root = root / "installed" / "plugins"
            installed = installed_root / source.name
            installed.parent.mkdir(parents=True)
            shutil.copytree(source, installed)
            env = {
                "PHASOR_HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_DATA_HOME": str(root / "data"),
                "XDG_STATE_HOME": str(root / "state"),
            }
            with patch.dict(os.environ, env):
                manager = PluginManager()
                manager.dirs = [root / "plugins", installed_root]
                plugins = manager.discover()

            self.assertEqual([plugin["id"] for plugin in plugins], ["dev.example.builtin"])
            self.assertEqual(manager.diagnostics, [])
            self.assertEqual(plugins[0]["manifestPath"], str(source / "plugin.json"))

    def test_conflicting_plugin_copies_keep_first_and_report_diagnostic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = write_plugin(root, "dev.example.builtin", builtin=True)
            installed_root = root / "installed" / "plugins"
            installed = installed_root / source.name
            installed.parent.mkdir(parents=True)
            shutil.copytree(source, installed)
            (installed / "Entry.qml").write_text("import QtQuick\nItem { objectName: \"different\" }\n", encoding="utf-8")
            env = {
                "PHASOR_HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_DATA_HOME": str(root / "data"),
                "XDG_STATE_HOME": str(root / "state"),
            }
            with patch.dict(os.environ, env):
                manager = PluginManager()
                manager.dirs = [root / "plugins", installed_root]
                plugins = manager.discover()

            self.assertEqual(len(plugins), 1)
            self.assertEqual(plugins[0]["manifestPath"], str(source / "plugin.json"))
            self.assertEqual(len(manager.diagnostics), 1)
            self.assertIn("Conflicting plugin id dev.example.builtin", manager.diagnostics[0])

    def test_contribution_must_be_in_declared_slots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = write_plugin(root, "org.example.slot")
            manifest = json.loads((folder / "plugin.json").read_text(encoding="utf-8"))
            manifest["supportedSlots"] = ["launcher.status"]
            manifest["contributions"] = [{"slot": "launcher.actions", "entrypoint": "Entry.qml"}]
            with self.assertRaisesRegex(PluginError, "not declared"):
                PluginManager._validate(manifest, folder)


if __name__ == "__main__":
    unittest.main()
