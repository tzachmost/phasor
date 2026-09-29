import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.apps import AppsService, desktop_exec_argv


class DesktopExecTests(unittest.TestCase):
    def test_desktop_field_codes_are_expanded_without_shell_interpolation(self):
        argv = desktop_exec_argv('viewer "%c" "%k" %% %U', "Photo Viewer", "/tmp/viewer.desktop", "viewer-icon")
        self.assertEqual(argv, ["viewer", "Photo Viewer", "/tmp/viewer.desktop", "%"])

    def test_icon_code_expands_to_two_arguments(self):
        argv = desktop_exec_argv("viewer %i %f", "Viewer", "/tmp/viewer.desktop", "viewer-icon")
        self.assertEqual(argv, ["viewer", "--icon", "viewer-icon"])

    def test_favorites_rank_before_other_apps(self):
        service = AppsService()
        service._cache = [
            {"id": "alpha", "name": "Alpha", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "alpha", "terminal": False},
            {"id": "pinned", "name": "Pinned App", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "pinned", "terminal": False},
        ]
        result = service.search("", favorites=["pinned"])
        self.assertEqual(result["items"][0]["id"], "pinned")
        self.assertTrue(result["items"][0]["favorite"])

    def test_recent_apps_rank_after_favorites_when_enabled(self):
        service = AppsService()
        service._cache = [
            {"id": "alpha", "name": "Alpha", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "alpha", "terminal": False},
            {"id": "beta", "name": "Beta", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "beta", "terminal": False},
            {"id": "pinned", "name": "Pinned", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "pinned", "terminal": False},
        ]
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_STATE_HOME": directory}):
            AppsService._record_recent("beta")
            result = service.search("", favorites=["pinned"], show_recents=True)

        self.assertEqual([item["id"] for item in result["items"]], ["pinned", "beta", "alpha"])
        self.assertTrue(result["items"][1]["recent"])

    def test_launch_records_a_bounded_recent_app_list(self):
        service = AppsService()
        service._cache = [
            {"id": "viewer", "name": "Viewer", "genericName": "", "comment": "", "icon": "", "desktopFile": "", "exec": "viewer", "terminal": False},
        ]
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_STATE_HOME": directory}), patch("phasor_core.apps.subprocess.Popen") as launch:
            result = service.launch("viewer")
            history = json.loads((Path(directory) / "phasor" / "recent-apps.json").read_text(encoding="utf-8"))

        self.assertEqual(result["launched"], "viewer")
        self.assertEqual(history, ["viewer"])
        launch.assert_called_once()


if __name__ == "__main__":
    unittest.main()
