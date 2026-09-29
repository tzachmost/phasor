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

    def test_appearance_settings_are_validated(self):
        invalid_appearance = [
            {"theme": "sepia"},
            {"accent": "not-a-color"},
            {"reducedMotion": "yes"},
        ]
        for appearance in invalid_appearance:
            with self.subTest(appearance=appearance), tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
                config_dir = Path(directory) / "phasor"
                config_dir.mkdir()
                (config_dir / "settings.json").write_text(json.dumps({"schemaVersion": 1, "appearance": appearance}), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "appearance"):
                    load_settings()

    def test_saving_settings_rejects_schema_drift(self):
        from phasor_core.config import save_settings
        settings = load_settings()
        settings["appearance"]["unexpected"] = True
        with self.assertRaisesRegex(ValueError, "Unknown appearance settings"):
            save_settings(settings)

    def test_plugin_enable_preference_must_be_boolean(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
            config_dir = Path(directory) / "phasor"
            config_dir.mkdir()
            (config_dir / "settings.json").write_text(json.dumps({
                "schemaVersion": 1,
                "plugins": {"dev.phasor.dock": {"enabled": "yes"}},
            }), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "plugins.dev.phasor.dock.enabled"):
                load_settings()


if __name__ == "__main__":
    unittest.main()
