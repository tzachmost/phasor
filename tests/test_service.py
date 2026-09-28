import unittest
from unittest.mock import patch

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


if __name__ == "__main__":
    unittest.main()
