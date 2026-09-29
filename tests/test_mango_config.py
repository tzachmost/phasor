import tempfile
import unittest
from pathlib import Path

from phasor_core.config import default_settings
from phasor_core.mango_config import render_mango_config, write_mango_config


class MangoConfigTests(unittest.TestCase):
    def test_runtime_config_applies_shortcut_space_and_focus_preferences(self):
        settings = default_settings()
        settings["launcher"]["shortcut"] = "Super+D"
        settings["commands"]["shortcut"] = "Super+Alt+/"
        settings["settings"]["shortcut"] = "Ctrl+Alt+S"
        settings["spaces"]["count"] = 4
        settings["spaces"]["animationDuration"] = 420
        settings["windows"]["focusMode"] = "sloppy"
        settings["windows"]["raiseOnFocus"] = False
        base = (Path(__file__).resolve().parents[1] / "config" / "mango" / "config.conf").read_text(encoding="utf-8")

        config = render_mango_config(settings, base)

        self.assertIn("tag_num=4\n", config)
        self.assertIn("animation_duration_tag=420\n", config)
        self.assertIn("sloppyfocus=1\n", config)
        self.assertIn("focus_on_activate=0\n", config)
        self.assertIn("bind=SUPER,D,spawn,phasorctl launcher toggle\n", config)
        self.assertIn("bind=SUPER+ALT,SLASH,spawn,phasorctl commands toggle\n", config)
        self.assertIn("bind=SUPER+SHIFT,SPACE,togglefloating\n", config)
        self.assertIn("bind=CTRL+ALT,S,spawn,phasorctl settings toggle\n", config)
        self.assertNotIn("bind=SUPER,SPACE,spawn,phasorctl launcher toggle", config)
        self.assertNotIn("bind=SUPER,SLASH,spawn,phasorctl commands toggle", config)
        self.assertIn("bind=SUPER+CTRL,4,view,4,0\n", config)
        self.assertIn("bind=SUPER+SHIFT+CTRL,4,tag,4,0\n", config)
        self.assertNotIn("bind=SUPER+CTRL,5,view,5,0", config)
        self.assertIn("bind=SUPER,W,killclient\n", config)

    def test_runtime_config_is_written_atomically_with_private_permissions(self):
        settings = default_settings()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "runtime" / "mango.conf"
            output = write_mango_config(
                settings,
                target,
                base_config=Path(__file__).resolve().parents[1] / "config" / "mango" / "config.conf",
            )
            self.assertEqual(output, target)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertTrue(target.read_text(encoding="utf-8").endswith("\n"))
            self.assertEqual(list(target.parent.glob("*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
