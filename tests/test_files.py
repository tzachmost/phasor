import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.files import ClipboardService, FileIndexService


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

    def test_rename_updates_the_file_index(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory, "XDG_CACHE_HOME": str(Path(directory) / "cache")}):
            home = Path(directory)
            source = home / "old.txt"
            source.write_text("content", encoding="utf-8")
            service = FileIndexService(roots=[home])
            service.paths = [str(source)]
            service.indexed_at = time.time()
            result = service.rename(str(source), "new.txt")
            destination = home / "new.txt"
            self.assertEqual(result["renamed"], str(destination))
            self.assertFalse(source.exists())
            self.assertIn(str(destination), service.paths)
            self.assertNotIn(str(source), service.paths)

    def test_copy_file_creates_unique_copy_in_same_directory(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory, "XDG_CACHE_HOME": str(Path(directory) / "cache")}):
            home = Path(directory)
            source = home / "notes.txt"
            source.write_text("content", encoding="utf-8")
            service = FileIndexService(roots=[home])
            service.paths = [str(source)]
            service.indexed_at = time.time()
            first = service.copy_file(str(source))["copied"]
            second = service.copy_file(str(source))["copied"]
            self.assertEqual(Path(first).name, "notes (copy).txt")
            self.assertEqual(Path(second).name, "notes (copy 2).txt")
            self.assertEqual(Path(second).read_text(encoding="utf-8"), "content")
            self.assertIn(first, service.paths)
            self.assertIn(second, service.paths)

    def test_home_root_cannot_be_renamed_or_trashed(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}):
            service = FileIndexService(roots=[Path(directory)])
            with self.assertRaisesRegex(ValueError, "Home directory"):
                service.rename(directory, "renamed-home")
            with self.assertRaisesRegex(ValueError, "Home directory"):
                service.trash(directory)

    def test_file_link_is_copied_to_clipboard(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}):
            target = Path(directory) / "notes.txt"
            target.write_text("content", encoding="utf-8")
            with patch("phasor_core.files.ClipboardService.copy") as copy:
                result = FileIndexService(roots=[Path(directory)]).share(str(target))
            self.assertEqual(result["shared"], target.as_uri())
            copy.assert_called_once_with(target.as_uri())

    def test_actions_reject_symbolic_links(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}):
            target = Path(directory) / "target.txt"
            alias = Path(directory) / "alias.txt"
            target.write_text("content", encoding="utf-8")
            alias.symlink_to(target)
            with self.assertRaisesRegex(ValueError, "symbolic links"):
                FileIndexService(roots=[Path(directory)]).rename(str(alias), "renamed.txt")

    def test_clipboard_history_parses_restore_ids(self):
        completed = subprocess.CompletedProcess(["cliphist", "list"], 0, "22\tPlain text\n21\tAnother value\n", "")
        with patch("phasor_core.files.shutil.which", return_value="/usr/bin/cliphist"), patch("phasor_core.files.subprocess.run", return_value=completed):
            result = ClipboardService().history()
        self.assertEqual(result["entries"], [
            {"id": "22", "preview": "Plain text"},
            {"id": "21", "preview": "Another value"},
        ])

    def test_clipboard_copy_does_not_capture_background_owner_pipes(self):
        completed = subprocess.CompletedProcess(["wl-copy"], 0)
        with patch("phasor_core.files.shutil.which", return_value="/usr/bin/wl-copy"), patch(
            "phasor_core.files.subprocess.run", return_value=completed
        ) as run:
            result = ClipboardService().copy("hello")
        self.assertEqual(result, {"copied": True})
        self.assertEqual(run.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["stderr"], subprocess.DEVNULL)

    def test_clipboard_restore_decodes_bytes_before_copying(self):
        decoded = subprocess.CompletedProcess(["cliphist", "decode", "22"], 0, b"raw clipboard bytes", b"")
        copied = subprocess.CompletedProcess(["wl-copy"], 0, b"", b"")
        with patch("phasor_core.files.shutil.which", side_effect=lambda command: f"/usr/bin/{command}"), patch(
            "phasor_core.files.subprocess.run", side_effect=[decoded, copied]
        ) as run:
            result = ClipboardService().restore("22")
        self.assertEqual(result, {"restored": "22"})
        self.assertEqual(run.call_args_list[0].args[0], ["/usr/bin/cliphist", "decode", "22"])
        self.assertEqual(run.call_args_list[1].kwargs["input"], b"raw clipboard bytes")
        self.assertEqual(run.call_args_list[1].kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(run.call_args_list[1].kwargs["stderr"], subprocess.DEVNULL)

    def test_clipboard_restore_rejects_non_numeric_ids(self):
        with patch("phasor_core.files.subprocess.run") as run:
            with self.assertRaisesRegex(ValueError, "integer"):
                ClipboardService().restore("22;rm -rf")
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
