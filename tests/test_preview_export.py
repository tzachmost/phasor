import io
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

try:
    from PIL import Image
    from pypdf import PdfReader
    from reportlab.pdfgen import canvas
except ImportError as error:
    raise unittest.SkipTest(f"Preview export dependencies are not installed: {error}")

from apps.preview.document_ops import export_image, export_pdf, inspect_pdf_forms, merge_pdfs, print_document


class PreviewExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def make_image(self, name="source.png"):
        source = self.root / name
        Image.new("RGB", (20, 10), "white").save(source)
        return source

    def make_form_pdf(self, name="form.pdf"):
        source = self.root / name
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.acroForm.textfield(
            name="full_name", tooltip="Full name", x=40, y=140, width=180, height=24, value=""
        )
        page_canvas.acroForm.checkbox(
            name="accept_terms", tooltip="Accept terms", x=40, y=100, size=14, checked=False
        )
        page_canvas.acroForm.choice(
            name="country", tooltip="Country", x=40, y=55, width=120, height=22,
            options=["Poland", "Canada"], value="Poland",
        )
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        return source

    def test_image_export_crops_rotates_resizes_and_flattens_markup(self):
        source = self.make_image()
        output = self.root / "result.png"
        result = export_image(
            str(source),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "image",
                    "annotations": [
                        {
                            "type": "rectangle",
                            "x1": 0.1,
                            "y1": 0.1,
                            "x2": 0.3,
                            "y2": 0.3,
                            "width": 0.01,
                            "color": "#ff0000",
                        }
                    ],
                },
                "crop": {"x": 0, "y": 0, "width": 0.5, "height": 1},
                "rotation": 90,
                "width": 5,
                "height": 5,
                "preserve_aspect": True,
                "quality": 92,
            },
        )

        with Image.open(output) as exported:
            self.assertEqual(exported.size, (5, 5))
            self.assertGreater(exported.getpixel((1, 1))[0], 200)
        self.assertEqual(result["width"], 5)
        self.assertEqual(result["height"], 5)
        with Image.open(source) as original:
            self.assertEqual(original.size, (20, 10))

    def test_image_export_rejects_overwriting_source(self):
        source = self.make_image()
        with self.assertRaisesRegex(ValueError, "original stays unchanged"):
            export_image(str(source), str(source), {"markup": {"version": 1, "kind": "image"}})

    def test_image_highlights_blend_without_making_pixels_transparent(self):
        source = self.root / "transparent.png"
        Image.new("RGBA", (20, 10), "white").save(source)
        output = self.root / "highlight.png"
        export_image(
            str(source),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "image",
                    "annotations": [
                        {
                            "type": "highlight",
                            "x1": 0.1,
                            "y1": 0.1,
                            "x2": 0.9,
                            "y2": 0.9,
                            "width": 0.01,
                            "color": "#80ff0000",
                        }
                    ],
                }
            },
        )

        with Image.open(output) as exported:
            red, green, blue, alpha = exported.getpixel((10, 5))
        self.assertEqual(alpha, 255)
        self.assertGreater(red, green)

    def test_image_export_converts_supported_formats(self):
        source = self.make_image()
        expected_formats = {
            ".png": "PNG",
            ".jpg": "JPEG",
            ".webp": "WEBP",
            ".tiff": "TIFF",
            ".bmp": "BMP",
        }
        for suffix, expected in expected_formats.items():
            with self.subTest(format=expected):
                output = self.root / f"converted{suffix}"
                export_image(
                    str(source),
                    str(output),
                    {"markup": {"version": 1, "kind": "image"}, "quality": 82},
                )
                with Image.open(output) as exported:
                    self.assertEqual(exported.format, expected)

    def test_pdf_export_reorders_pages_rotates_and_keeps_text_searchable(self):
        source = self.root / "source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "FIRST PAGE")
        page_canvas.showPage()
        page_canvas.drawString(20, 50, "SECOND PAGE")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        output = self.root / "result.pdf"
        markup = {
            "version": 1,
            "kind": "pdf",
            "pages": {
                "1": [
                    {
                        "type": "rectangle",
                        "x1": 0.1,
                        "y1": 0.1,
                        "x2": 0.4,
                        "y2": 0.3,
                        "width": 0.01,
                        "color": "#8bd5ca",
                    },
                    {
                        "type": "text",
                        "x": 0.1,
                        "y": 0.5,
                        "text": "Review ✓",
                        "size": 0.04,
                        "color": "#ff0000",
                    },
                ]
            },
            "page_order": [1, 0],
            "page_rotations": {"1": 90},
        }

        result = export_pdf(str(source), str(output), {"markup": markup})

        reader = PdfReader(output)
        self.assertEqual(len(reader.pages), 2)
        self.assertEqual(reader.pages[0].rotation, 90)
        self.assertIn("SECOND PAGE", reader.pages[0].extract_text())
        self.assertIn("Review ✓", reader.pages[0].extract_text())
        self.assertIn("FIRST PAGE", reader.pages[1].extract_text())
        self.assertIn(b" RG", reader.pages[0].get_contents().get_data())
        self.assertEqual(result["pages"], 2)
        self.assertEqual(PdfReader(source).pages[0].rotation, 0)

    def test_pdf_export_can_exclude_pages(self):
        source = self.root / "source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "KEEP THIS PAGE")
        page_canvas.showPage()
        page_canvas.drawString(20, 50, "DROP THIS PAGE")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        output = self.root / "kept.pdf"

        export_pdf(
            str(source),
            str(output),
            {"markup": {"version": 1, "kind": "pdf", "pages": {}, "page_order": [0]}},
        )

        reader = PdfReader(output)
        self.assertEqual(len(reader.pages), 1)
        self.assertIn("KEEP THIS PAGE", reader.pages[0].extract_text())

    def test_pdf_markup_respects_offset_crop_box(self):
        from pypdf import PdfWriter
        from pypdf.generic import RectangleObject

        source = self.root / "offset-page.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(40, 60, "Visible page area")
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())

        reader = PdfReader(source)
        page = reader.pages[0]
        page.mediabox = RectangleObject((10, 20, 210, 120))
        page.cropbox = RectangleObject((30, 35, 170, 105))
        writer = PdfWriter()
        writer.add_page(page)
        offset_pdf = io.BytesIO()
        writer.write(offset_pdf)
        source.write_bytes(offset_pdf.getvalue())

        output = self.root / "offset-page-export.pdf"
        export_pdf(
            str(source),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {
                        "0": [
                            {
                                "type": "rectangle",
                                "x1": 0.1,
                                "y1": 0.1,
                                "x2": 0.4,
                                "y2": 0.3,
                                "width": 0.01,
                                "color": "#ff0000",
                            }
                        ]
                    },
                }
            },
        )

        exported_page = PdfReader(output).pages[0]
        self.assertEqual(tuple(map(float, exported_page.mediabox)), (10, 20, 210, 120))
        self.assertEqual(tuple(map(float, exported_page.cropbox)), (30, 35, 170, 105))
        self.assertIn(b"44 84 42 14 re", exported_page.get_contents().get_data())

    def test_pdf_forms_can_be_discovered_filled_and_saved_as_a_copy(self):
        source = self.make_form_pdf()
        output = self.root / "filled-form.pdf"

        form_info = inspect_pdf_forms(str(source))
        fields = {field["name"]: field for field in form_info["fields"]}
        self.assertEqual(fields["full_name"]["type"], "text")
        self.assertEqual(fields["accept_terms"]["type"], "checkbox")
        self.assertEqual(fields["country"]["type"], "choice")
        self.assertEqual(fields["full_name"]["pages"], [1])

        export_pdf(
            str(source),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {},
                    "form_values": {
                        "full_name": "Ada Lovelace",
                        "accept_terms": "/Yes",
                        "country": "Canada",
                    },
                }
            },
        )

        values = PdfReader(output).get_fields()
        self.assertEqual(values["full_name"]["/V"], "Ada Lovelace")
        self.assertEqual(str(values["accept_terms"]["/V"]), "/Yes")
        self.assertEqual(values["country"]["/V"], "Canada")
        output_page = PdfReader(output).pages[0]
        widgets = {
            str(reference.get_object().get("/T")): reference.get_object()
            for reference in output_page.get("/Annots", [])
        }
        name_appearance = widgets["full_name"]["/AP"]["/N"].get_object()
        self.assertIn(b"(Ada Lovelace) Tj", name_appearance.get_data())
        self.assertEqual(str(widgets["accept_terms"].get("/AS")), "/Yes")
        self.assertEqual(PdfReader(source).get_fields()["full_name"]["/V"], "")

    def test_pdf_signature_markup_exports_as_vector_strokes(self):
        source = self.root / "signature.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        output = self.root / "signed-visually.pdf"

        export_pdf(
            str(source),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {
                        "0": [
                            {
                                "type": "signature",
                                "points": [[0.1, 0.2], [0.5, 0.5], [0.9, 0.2]],
                                "width": 0.02,
                                "color": "#112233",
                            }
                        ]
                    },
                }
            },
        )

        content = PdfReader(output).pages[0].get_contents().get_data()
        self.assertIn(b"20 80 m", content)
        self.assertIn(b"180 80 l", content)
        self.assertIn(b"S", content)

    def test_pdf_merge_appends_documents_after_the_prepared_current_pdf(self):
        first = self.root / "first.pdf"
        second = self.root / "second.pdf"
        first_buffer = io.BytesIO()
        first_canvas = canvas.Canvas(first_buffer, pagesize=(200, 100))
        first_canvas.drawString(20, 50, "KEEP THIS PAGE")
        first_canvas.showPage()
        first_canvas.drawString(20, 50, "PREPARED PAGE")
        first_canvas.showPage()
        first_canvas.save()
        first.write_bytes(first_buffer.getvalue())
        second_buffer = io.BytesIO()
        second_canvas = canvas.Canvas(second_buffer, pagesize=(200, 100))
        second_canvas.drawString(20, 50, "APPENDED PAGE")
        second_canvas.save()
        second.write_bytes(second_buffer.getvalue())
        output = self.root / "merged.pdf"

        result = merge_pdfs(
            [str(first), str(second)],
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {
                        "1": [
                            {
                                "type": "text",
                                "x": 0.1,
                                "y": 0.5,
                                "text": "Merged note",
                                "size": 0.04,
                                "color": "#ff0000",
                            }
                        ]
                    },
                    "page_order": [1],
                }
            },
        )

        merged = PdfReader(output)
        self.assertEqual(result["documents"], 2)
        self.assertEqual(result["pages"], 2)
        self.assertEqual(len(merged.pages), 2)
        self.assertIn("PREPARED PAGE", merged.pages[0].extract_text())
        self.assertIn("Merged note", merged.pages[0].extract_text())
        self.assertIn("APPENDED PAGE", merged.pages[1].extract_text())
        self.assertEqual(len(PdfReader(first).pages), 2)

    def test_pdf_merge_namespaces_imported_form_fields_and_preserves_values(self):
        first = self.make_form_pdf("form-one.pdf")
        second = self.make_form_pdf("form-two.pdf")
        output = self.root / "forms-merged.pdf"

        merge_pdfs(
            [str(first), str(second)],
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {},
                    "form_values": {"full_name": "Ada Lovelace"},
                }
            },
        )

        fields = PdfReader(output).get_fields()
        self.assertEqual(fields["full_name"]["/V"], "Ada Lovelace")
        self.assertEqual(fields["form-two_2.full_name"]["/V"], "")
        self.assertEqual(len(PdfReader(output).pages), 2)

    def test_pdf_merge_rejects_overwriting_any_source(self):
        first = self.make_form_pdf("first.pdf")
        second = self.make_form_pdf("second.pdf")

        with self.assertRaisesRegex(ValueError, "original PDFs are overwritten"):
            merge_pdfs([str(first), str(second)], str(second), {})

    def test_print_submits_a_flattened_copy_with_printer_options(self):
        source = self.root / "print-source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "FIRST PRINT PAGE")
        page_canvas.showPage()
        page_canvas.drawString(20, 50, "SECOND PRINT PAGE")
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        commands = []

        def submit(command, **kwargs):
            commands.append(command)
            printed = PdfReader(command[-1])
            self.assertEqual(len(printed.pages), 1)
            self.assertIn("SECOND PRINT PAGE", printed.pages[0].extract_text())
            return SimpleNamespace(returncode=0, stdout="request id is Office-42", stderr="")

        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=submit):
                result = print_document(
                    str(source),
                    {
                        "markup": {
                            "version": 1,
                            "kind": "pdf",
                            "pages": {},
                            "page_order": [1],
                        },
                        "printer": "Office",
                        "copies": 2,
                        "pages": "1",
                    },
                )

        self.assertIn(["-d", "Office"], [commands[0][i:i + 2] for i in range(len(commands[0]) - 1)])
        self.assertIn(["-n", "2"], [commands[0][i:i + 2] for i in range(len(commands[0]) - 1)])
        self.assertIn(["-P", "1"], [commands[0][i:i + 2] for i in range(len(commands[0]) - 1)])
        self.assertTrue(result["ok"])
        self.assertEqual(result["printer"], "Office")

    def test_print_converts_marked_up_image_to_single_page_pdf(self):
        source = self.make_image()

        def submit(command, **kwargs):
            printed = PdfReader(command[-1])
            self.assertEqual(len(printed.pages), 1)
            self.assertGreater(float(printed.pages[0].mediabox.width), 20)
            return SimpleNamespace(returncode=0, stdout="job-1", stderr="")

        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=submit):
                result = print_document(
                    str(source),
                    {"markup": {"version": 1, "kind": "image", "annotations": []}},
                )
        self.assertTrue(result["ok"])

    def test_print_options_reject_command_injection_and_invalid_ranges(self):
        from apps.preview.document_ops import _validated_print_options

        with self.assertRaisesRegex(ValueError, "printer name"):
            _validated_print_options({"printer": "Office; touch /tmp/unsafe"})
        with self.assertRaisesRegex(ValueError, "ascending"):
            _validated_print_options({"pages": "5-2"})


if __name__ == "__main__":
    unittest.main()
