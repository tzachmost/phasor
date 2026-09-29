import io
import tempfile
import unittest
from pathlib import Path

try:
    from PIL import Image
    from pypdf import PdfReader
    from reportlab.pdfgen import canvas
except ImportError as error:
    raise unittest.SkipTest(f"Preview export dependencies are not installed: {error}")

from apps.preview.document_ops import export_image, export_pdf


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


if __name__ == "__main__":
    unittest.main()
