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

    def test_text_anchored_annotations_round_trip_on_pdf_pages(self) -> None:
        payload = {
            "version": 1,
            "kind": "pdf",
            "pages": {
                "0": [
                    {"type": "text_highlight", "quote": "Review this line", "rects": [[0.1, 0.2, 0.8, 0.25]], "color": "#f3c969"},
                    {"type": "underline", "quote": "Review this line", "rects": [[0.1, 0.2, 0.8, 0.25]], "color": "#8bd5ca"},
                    {"type": "strike", "quote": "Review this line", "rects": [[0.1, 0.2, 0.8, 0.25]], "color": "#ed8796"},
                    {"type": "note", "quote": "Review this line", "rects": [[0.1, 0.2, 0.8, 0.25]], "note": "Check this against the source.", "color": "#f3c969"},
                ]
            },
        }

        save_markup(str(self.document), json.dumps(payload))

        self.assertEqual(load_markup(str(self.document)), payload)

    def test_text_anchored_annotations_reject_empty_anchors_bad_rectangles_and_image_use(self) -> None:
        base = {"version": 1, "kind": "pdf", "pages": {"0": []}}
        with self.assertRaisesRegex(ValueError, "selected quote"):
            validate_payload({**base, "pages": {"0": [{"type": "underline", "quote": " ", "rects": [[0.1, 0.2, 0.8, 0.25]]}]}})
        with self.assertRaisesRegex(ValueError, "positive width and height"):
            validate_payload({**base, "pages": {"0": [{"type": "strike", "quote": "Text", "rects": [[0.8, 0.2, 0.1, 0.25]]}]}})
        with self.assertRaisesRegex(ValueError, "only for PDF"):
            validate_payload({"version": 1, "kind": "image", "annotations": [{"type": "note", "quote": "Text", "rects": [[0.1, 0.2, 0.8, 0.25]], "note": "Review"}]})

    def test_pdf_page_operations_round_trip_through_sidecar(self) -> None:
        payload = {
            "version": 1,
            "kind": "pdf",
            "pages": {},
            "page_order": [2, 0],
            "page_rotations": {"2": 90, "0": 270},
        }

        save_markup(str(self.document), json.dumps(payload))

        self.assertEqual(load_markup(str(self.document)), payload)

    def test_pdf_form_values_round_trip_through_sidecar(self) -> None:
        payload = {
            "version": 1,
            "kind": "pdf",
            "pages": {},
            "form_values": {"full_name": "Ada Lovelace", "accept_terms": "/Yes", "foods": ["tea", "cake"]},
        }

        save_markup(str(self.document), json.dumps(payload))

        self.assertEqual(load_markup(str(self.document)), payload)

    def test_signature_strokes_are_preserved_as_markup(self) -> None:
        payload = {
            "version": 1,
            "kind": "image",
            "annotations": [
                {"type": "signature", "points": [[0.1, 0.2], [0.4, 0.5]], "color": "#111111", "width": 0.01}
            ],
        }

        save_markup(str(self.document), json.dumps(payload))

        self.assertEqual(load_markup(str(self.document)), payload)

    def test_pdf_form_values_reject_bad_names_and_values(self) -> None:
        base = {"version": 1, "kind": "pdf", "pages": {}}
        with self.assertRaisesRegex(ValueError, "field map"):
            validate_payload({**base, "form_values": []})
        with self.assertRaisesRegex(ValueError, "strings"):
            validate_payload({**base, "form_values": {"name": True}})

    def test_pdf_page_operations_reject_duplicates_and_invalid_rotations(self) -> None:
        with self.assertRaisesRegex(ValueError, "unique"):
            validate_payload({
                "version": 1,
                "kind": "pdf",
                "pages": {},
                "page_order": [1, 1],
            })
        with self.assertRaisesRegex(ValueError, "0, 90, 180, or 270"):
            validate_payload({
                "version": 1,
                "kind": "pdf",
                "pages": {},
                "page_rotations": {"0": 45},
            })

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
