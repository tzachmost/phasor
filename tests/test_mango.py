import unittest
from unittest.mock import patch

from phasor_core.mango import MangoAdapter, MangoError


class MangoAdapterTests(unittest.TestCase):
    def test_windows_and_spaces_normalize_documented_json(self):
        adapter = MangoAdapter()
        values = {
            "all-clients": [{"id": 37, "title": "Editor", "appid": "zed", "is_floating": True}],
            "focusing-client": {"id": 37, "title": "Editor"},
            "all-monitors": [{"name": "DP-1", "tags": [{"index": 1, "is_active": True, "clients": 1}, {"index": 2, "clients": 0}]}],
            "version": "0.16.0",
        }
        adapter._query = lambda *args: values[args[0]]
        snapshot = adapter.snapshot()
        self.assertTrue(snapshot["available"])
        self.assertEqual(snapshot["windows"][0]["appId"], "zed")
        self.assertTrue(snapshot["windows"][0]["focused"])
        self.assertEqual([row["id"] for row in snapshot["spaces"]], ["1", "2"])
        self.assertTrue(snapshot["spaces"][0]["active"])

    def test_dispatch_uses_argument_array_and_client_selector(self):
        adapter = MangoAdapter()
        with patch("phasor_core.mango.shutil.which", return_value="/usr/bin/mmsg"), patch("phasor_core.mango.subprocess.run") as run:
            run.return_value.returncode = 0
            adapter.focus("48")
            args = run.call_args.args[0]
        self.assertEqual(args, ["mmsg", "dispatch", "focusid", "client,48"])
        with patch("phasor_core.mango.shutil.which", return_value="/usr/bin/mmsg"), patch("phasor_core.mango.subprocess.run") as run:
            with self.assertRaisesRegex(ValueError, "invalid Mango client id"):
                adapter.focus("48,unsafe")
            run.assert_not_called()

    def test_space_id_validation(self):
        adapter = MangoAdapter()
        with self.assertRaises(ValueError):
            adapter.switch_space("0")
        with self.assertRaises(ValueError):
            adapter.switch_space("1; touch /tmp/nope")

    def test_always_on_top_is_reported_as_unsupported(self):
        with self.assertRaisesRegex(MangoError, "does not expose an always-on-top"):
            MangoAdapter().toggle_always_on_top("1")


if __name__ == "__main__":
    unittest.main()
