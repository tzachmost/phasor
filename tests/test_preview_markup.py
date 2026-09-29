from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from apps.preview.markup_store import load_markup, save_markup, validate_payload


class PreviewMarkupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.document = Path(self.temporary.name) / "notes.pdf"
        self.document.write_bytes(b"preview test fixture")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_image_markup_is_written_atomically_as_private_sidecar(self) -> None:
        payload = {
            "version": 1,
            "kind": "image",
            "annotations": [
                {"type": "stroke", "color": "#8bd5ca", "width": 0.006, "points": [[0.1, 0.2], [0.8, 0.9]]},
                {"type": "text", "color": "#f3c969", "x": 0.3, "y": 0.4, "text": "Review", "size": 0.038},
            ],
        }

        result = save_markup(str(self.document), json.dumps(payload))
        sidecar = Path(result["sidecar"])

        self.assertTrue(result["ok"])
        self.assertEqual(sidecar.name, "notes.pdf.phasor-markup.json")
        self.assertEqual(load_markup(str(self.document)), payload)
        self.assertEqual(sidecar.stat().st_mode & 0o777, 0o600)

    def test_pdf_markup_is_kept_separate_for_each_page(self) -> None:
        payload = {
            "version": 1,
            "kind": "pdf",
            "pages": {
                "0": [{"type": "highlight", "color": "#f3c969", "width": 0.006, "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.3}],
                "4": [{"type": "rectangle", "color": "#8bd5ca", "width": 0.006, "x1": 0.2, "y1": 0.3, "x2": 0.9, "y2": 0.8}],
            },
        }

        save_markup(str(self.document), json.dumps(payload))

        self.assertEqual(load_markup(str(self.document)), payload)

    def test_markup_rejects_out_of_range_coordinates_and_invalid_colors(self) -> None:
        base = {"version": 1, "kind": "image", "annotations": []}
        with self.assertRaisesRegex(ValueError, "between zero and one"):
            validate_payload({**base, "annotations": [{"type": "text", "x": 1.1, "y": 0.5, "text": "bad"}]})
        with self.assertRaisesRegex(ValueError, "hex color"):
            validate_payload({**base, "annotations": [{"type": "text", "x": 0.5, "y": 0.5, "text": "bad", "color": "red"}]})

    def test_loading_without_a_sidecar_returns_empty_markup(self) -> None:
        self.assertEqual(
            load_markup(str(self.document)),
            {"version": 1, "kind": "image", "annotations": []},
        )


if __name__ == "__main__":
    unittest.main()
