import unittest
from unittest.mock import patch

from phasor_core.system import SystemService


class SystemServiceTests(unittest.TestCase):
    def test_audio_status_parses_volume_and_mute(self):
        with patch("phasor_core.system.shutil.which", return_value="/usr/bin/wpctl"), patch.object(
            SystemService, "_checked", return_value="Volume: 0.72 [MUTED]"
        ):
            self.assertEqual(SystemService.audio_status(), {"available": True, "volume": 0.72, "muted": True})

    def test_brightness_status_parses_machine_output(self):
        with patch("phasor_core.system.shutil.which", return_value="/usr/bin/brightnessctl"), patch.object(
            SystemService, "_checked", return_value="intel_backlight,backlight,4800,9600,50%"
        ):
            result = SystemService.brightness_status()
        self.assertEqual(result["device"], "intel_backlight")
        self.assertEqual(result["percent"], 50)

    def test_setters_reject_unbounded_values_without_running_commands(self):
        with patch.object(SystemService, "_checked") as run:
            with self.assertRaisesRegex(ValueError, "volume"):
                SystemService.audio_set_volume(2)
            with self.assertRaisesRegex(ValueError, "brightness"):
                SystemService.brightness_set(-1)
            with self.assertRaisesRegex(ValueError, "boolean"):
                SystemService.network_set_wifi("on")
            run.assert_not_called()

    def test_missing_status_backend_is_reported(self):
        with patch("phasor_core.system.shutil.which", return_value=None):
            self.assertFalse(SystemService.audio_status()["available"])
            self.assertFalse(SystemService.network_status()["available"])


if __name__ == "__main__":
    unittest.main()
