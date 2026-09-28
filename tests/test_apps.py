import unittest

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


if __name__ == "__main__":
    unittest.main()
