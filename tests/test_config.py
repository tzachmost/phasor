import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.config import load_settings
from phasor_core.services import load_theme


class ConfigTests(unittest.TestCase):
    def test_defaults_include_wallpaper_setting(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
            settings = load_settings()
            self.assertEqual(settings["appearance"]["wallpaper"], "")
            self.assertEqual(load_theme()["wallpaper"], "")

    def test_boolean_is_not_accepted_as_space_count(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
            config_dir = Path(directory) / "phasor"
            config_dir.mkdir()
            (config_dir / "settings.json").write_text(json.dumps({"schemaVersion": 1, "spaces": {"count": True}}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "spaces.count"):
                load_settings()

    def test_relative_wallpaper_resolves_from_home(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_CONFIG_HOME": directory, "HOME": directory}):
            config_dir = Path(directory) / "phasor"
            config_dir.mkdir()
            (config_dir / "settings.json").write_text(json.dumps({"schemaVersion": 1, "appearance": {"wallpaper": "Pictures/wall.jpg"}}), encoding="utf-8")
            self.assertEqual(load_theme()["wallpaper"], str(Path(directory) / "Pictures/wall.jpg"))


if __name__ == "__main__":
    unittest.main()
