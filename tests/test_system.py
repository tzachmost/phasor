import unittest
from unittest.mock import MagicMock, patch

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

    def test_notification_status_reports_count_and_do_not_disturb(self):
        with patch("phasor_core.system.shutil.which", return_value="/usr/bin/swaync-client"), patch.object(
            SystemService, "_checked", side_effect=["true", "3"]
        ):
            result = SystemService.notifications_status()
        self.assertEqual(result, {"available": True, "backend": "SwayNotificationCenter", "doNotDisturb": True, "count": 3})

    def test_notification_dnd_requires_boolean_and_uses_swaync(self):
        with patch.object(SystemService, "_checked") as run:
            with self.assertRaisesRegex(ValueError, "boolean"):
                SystemService.notifications_set_dnd("on")
            run.assert_not_called()
            result = SystemService.notifications_set_dnd(False)
            self.assertEqual(result, {"ok": True, "doNotDisturb": False})
            run.assert_called_once_with("swaync-client", "-df", "-sw")

    def test_screenshot_starts_configured_gui_backend(self):
        process = MagicMock()
        process.pid = 456
        with patch("phasor_core.system.shutil.which", return_value="/usr/bin/flameshot"), patch(
            "phasor_core.system.subprocess.Popen", return_value=process
        ) as popen:
            result = SystemService.screenshot_capture(copy_to_clipboard=True)
        self.assertEqual(result, {"started": True, "pid": 456, "copyToClipboard": True})
        self.assertEqual(popen.call_args.args[0], ["/usr/bin/flameshot", "gui", "-c"])

    def test_wallpaper_uses_configured_background_and_stops_cleanly(self):
        process = MagicMock()
        process.pid = 123
        process.poll.return_value = None
        with patch("phasor_core.system.shutil.which", return_value="/usr/bin/swaybg"), patch("phasor_core.system.subprocess.Popen", return_value=process) as popen:
            service = SystemService()
            result = service.apply_wallpaper("", "#f3f5f8")
            self.assertEqual(result["pid"], 123)
            self.assertEqual(popen.call_args.args[0], ["/usr/bin/swaybg", "-c", "#f3f5f8"])
            service.close()
            process.terminate.assert_called_once()


if __name__ == "__main__":
    unittest.main()
