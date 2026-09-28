import tempfile
import time
import unittest
from pathlib import Path

from phasor_core.files import FileIndexService


class FileIndexTests(unittest.TestCase):
    def test_search_ranks_filename_matches_and_reports_index_status(self):
        with tempfile.TemporaryDirectory() as directory:
            service = FileIndexService(roots=[Path(directory)])
            service.cache_file = Path(directory) / "index.json"
            service.paths = [f"{directory}/notes/phasor-roadmap.md", f"{directory}/phasor.md", f"{directory}/archive/old-phasor.txt"]
            service.indexed_at = time.time()
            result = service.search("phasor")
            self.assertEqual(result["total"], 3)
            self.assertEqual(Path(result["items"][0]["path"]).name, "phasor.md")
            self.assertTrue(result["status"]["indexed"])

    def test_scan_indexes_directories_and_skips_hidden_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "home"
            (root / "Projects").mkdir(parents=True)
            (root / ".private").mkdir()
            (root / "Projects" / "readme.md").write_text("hello", encoding="utf-8")
            (root / ".private" / "secret.txt").write_text("hidden", encoding="utf-8")
            service = FileIndexService(roots=[root])
            service.cache_file = Path(directory) / "cache" / "index.json"
            service._scan()
            self.assertIn(str(root / "Projects"), service.paths)
            self.assertIn(str(root / "Projects" / "readme.md"), service.paths)
            self.assertNotIn(str(root / ".private" / "secret.txt"), service.paths)


if __name__ == "__main__":
    unittest.main()
