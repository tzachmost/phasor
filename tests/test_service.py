import json
import unittest
import os
import tempfile
from unittest.mock import patch
from pathlib import Path

from phasor_core.events import EventBus
from phasor_core.services import Services


class ServiceTests(unittest.TestCase):
    def test_launcher_action_is_published(self):
        service = Services(lambda event: events.append(event))
        events = []
        result = service.invoke("launcher.toggle")
        self.assertEqual(result, {"toggled": True})
        self.assertEqual(events[0]["name"], "launcher.toggle")

    def test_plugin_calls_are_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            with patch.object(service.system, "audio_status", return_value={"available": True}):
                self.assertEqual(service.invoke_plugin("example.plugin", "audio.status", {}), {"available": True})
            require.assert_called_once_with("example.plugin", "audio.read")

    def test_unknown_methods_are_not_plugin_capabilities(self):
        service = Services(lambda _event: None)
        with self.assertRaisesRegex(ValueError, "Unknown or non-plugin"):
            service.invoke_plugin("example.plugin", "arbitrary.command", {})

    def test_file_mutations_are_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            with patch.object(service.files, "rename", return_value={"renamed": "/home/test/new.txt"}):
                self.assertEqual(service.invoke_plugin("example.plugin", "files.rename", {"path": "/home/test/old.txt", "name": "new.txt"}), {"renamed": "/home/test/new.txt"})
            require.assert_called_once_with("example.plugin", "files.rename")

    def test_clipboard_restore_is_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            with patch.object(service.clipboard, "restore", return_value={"restored": "22"}):
                self.assertEqual(service.invoke_plugin("example.plugin", "clipboard.restore", {"id": "22"}), {"restored": "22"})
            require.assert_called_once_with("example.plugin", "clipboard.write")

    def test_clipboard_toggle_is_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            self.assertEqual(service.invoke_plugin("example.plugin", "clipboard.toggle", {}), {"toggled": True})
            require.assert_called_once_with("example.plugin", "clipboard.read")

    def test_settings_changes_are_saved_and_published(self):
        events = []
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory, "XDG_CONFIG_HOME": directory}):
            service = Services(events.append)
            with patch.object(service.system, "apply_wallpaper", return_value={"started": True}):
                result = service.invoke("settings.update", {"patch": {"appearance": {"theme": "light"}}})
            self.assertEqual(result["appearance"]["theme"], "light")
            self.assertEqual(events[-1]["name"], "settings.changed")
            self.assertEqual(json.loads((Path(directory) / "phasor" / "settings.json").read_text(encoding="utf-8"))["appearance"]["theme"], "light")

    def test_settings_plugin_toggle_publishes_plugin_lifecycle_event(self):
        events = []
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory, "XDG_CONFIG_HOME": directory}):
            service = Services(events.append)
            result = service.invoke("settings.update", {"patch": {"plugins": {"dev.phasor.dock": {"enabled": True}}}})
            self.assertTrue(result["plugins"]["dev.phasor.dock"]["enabled"])
            self.assertEqual(events[0]["type"], "plugin.enabled")
            self.assertEqual(events[0]["name"], "dev.phasor.dock")
            self.assertEqual(events[-1]["name"], "settings.changed")

    def test_launcher_and_settings_toggles_are_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            self.assertEqual(service.invoke_plugin("example.plugin", "settings.toggle", {}), {"toggled": True})
            require.assert_called_once_with("example.plugin", "settings.control")
            require.reset_mock()
            self.assertEqual(service.invoke_plugin("example.plugin", "launcher.toggle", {}), {"toggled": True})
            require.assert_called_once_with("example.plugin", "apps.read")

    def test_settings_api_is_capability_gated(self):
        service = Services(lambda _event: None)
        with patch.object(service.plugins, "require_capability") as require:
            with patch("phasor_core.config.load_settings", return_value={"schemaVersion": 1}):
                service.invoke_plugin("example.plugin", "settings.get", {})
            require.assert_called_once_with("example.plugin", "settings.read")


if __name__ == "__main__":
    unittest.main()
