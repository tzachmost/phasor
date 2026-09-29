import io
import importlib.util
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

try:
    from PIL import Image
    from pypdf import PdfReader
    from reportlab.pdfgen import canvas
except ImportError as error:
    raise unittest.SkipTest(f"Preview export dependencies are not installed: {error}")

from apps.preview.document_ops import available_ocr_languages, embed_pdf_text, export_image, export_pdf, extract_image_selection, inspect_document, inspect_pdf_forms, insert_pdf_pages, merge_pdfs, print_document, recognize_image_text, remove_image_background, sign_pdf


SIGNING_AVAILABLE = all(importlib.util.find_spec(name) for name in ("pyhanko", "cryptography"))


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

    def make_animated_image(self, name="animated.gif"):
        source = self.root / name
        frames = [Image.new("RGB", (8, 6), color) for color in ("red", "blue")]
        frames[0].save(source, save_all=True, append_images=frames[1:], duration=100, loop=0)
        return source

    def make_pdf(self, name="source.pdf", pages=("PHASOR PAGE",)):
        source = self.root / name
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        for text in pages:
            page_canvas.drawString(20, 50, text)
            page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        return source

    def fake_ocr_tools(self):
        def locate(command):
            return f"/fake/bin/{command}" if command in {"tesseract", "ocrmypdf"} else None

        def run(command, **_options):
            if "--list-langs" in command:
                return SimpleNamespace(returncode=0, stdout="List of available languages (1):\neng\n", stderr="")
            self.assertIn("--output-type", command)
            self.assertIn("pdf", command)
            self.assertIn("--redo-ocr", command)
            Path(command[-1]).write_bytes(Path(command[-2]).read_bytes())
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        return locate, run

    def make_form_pdf(self, name="form.pdf"):
        source = self.root / name
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.acroForm.textfield(
            name="full_name", tooltip="Full name", x=40, y=140, width=180, height=24, value=""
        )
        page_canvas.acroForm.textfield(
            name="issued_by",
            tooltip="Issued by",
            x=40,
            y=110,
            width=180,
            height=20,
            value="Phasor Office",
            fieldFlags="readOnly",
        )
        page_canvas.acroForm.textfield(
            name="notes",
            tooltip="Notes",
            x=40,
            y=15,
            width=130,
            height=30,
            value="Initial note",
            fieldFlags="multiline",
        )
        page_canvas.acroForm.textfield(
            name="access_code",
            tooltip="Access code",
            x=190,
            y=110,
            width=95,
            height=20,
            value="existing secret",
            fieldFlags="password",
        )
        page_canvas.acroForm.checkbox(
            name="accept_terms", tooltip="Accept terms", x=40, y=100, size=14, checked=False
        )
        page_canvas.acroForm.choice(
            name="country", tooltip="Country", x=40, y=55, width=120, height=22,
            options=["Poland", "Canada"], value="Poland",
        )
        page_canvas.acroForm.choice(
            name="editable_region", tooltip="Region", x=185, y=65, width=100, height=22,
            options=["Poland", "Canada"], value="Poland", fieldFlags="combo edit",
        )
        page_canvas.acroForm.listbox(
            name="favorite_drinks",
            tooltip="Favorite drinks",
            x=185,
            y=12,
            width=100,
            height=48,
            options=["Tea", "Coffee", "Water"],
            value="Tea",
            fieldFlags="multiSelect",
        )
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        return source

    def test_image_inspection_reports_dimensions_format_and_file_details(self):
        source = self.make_image("inspection.png")

        result = inspect_document(str(source))

        self.assertEqual(result["kind"], "image")
        self.assertEqual(result["format"], "PNG")
        self.assertEqual((result["width"], result["height"]), (20, 10))
        self.assertEqual(result["frames"], 1)
        self.assertFalse(result["animated"])
        self.assertGreater(result["size_bytes"], 0)
        self.assertEqual(result["name"], "inspection.png")
        self.assertIsNotNone(datetime.fromisoformat(result["modified"]).tzinfo)

    def test_svg_inspection_keeps_basic_details_when_pillow_cannot_read_the_format(self):
        source = self.root / "vector.svg"
        source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"/>', encoding="utf-8")

        result = inspect_document(str(source))

        self.assertEqual(result["kind"], "image")
        self.assertEqual(result["format"], "SVG")
        self.assertIn("metadata_error", result)
        self.assertGreater(result["size_bytes"], 0)

    def test_pdf_inspection_reports_page_count_and_common_metadata(self):
        source = self.root / "inspection.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.setTitle("Preview inspection fixture")
        page_canvas.setAuthor("Phasor tests")
        page_canvas.setSubject("PDF metadata")
        page_canvas.drawString(40, 100, "Inspection")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())

        result = inspect_document(str(source))

        self.assertEqual(result["kind"], "pdf")
        self.assertEqual(result["page_count"], 1)
        self.assertEqual(result["title"], "Preview inspection fixture")
        self.assertEqual(result["author"], "Phasor tests")
        self.assertEqual(result["subject"], "PDF metadata")
        self.assertFalse(result["encrypted"])

    def test_pdf_inspection_reports_encryption_and_reads_metadata_after_unlocking(self):
        from pypdf import PdfWriter

        source = self.root / "encrypted-inspection.pdf"
        writer = PdfWriter()
        writer.add_blank_page(width=200, height=100)
        writer.encrypt("test password", algorithm="AES-256-R5")
        with source.open("wb") as stream:
            writer.write(stream)

        result = inspect_document(str(source))

        self.assertEqual(result["kind"], "pdf")
        self.assertTrue(result["encrypted"])
        self.assertNotIn("page_count", result)

        unlocked = inspect_document(str(source), "test password")
        self.assertTrue(unlocked["encrypted"])
        self.assertEqual(unlocked["page_count"], 1)
        with self.assertRaisesRegex(ValueError, "password is incorrect"):
            inspect_document(str(source), "wrong password")

    def test_pdf_forms_can_be_inspected_after_unlocking(self):
        from pypdf import PdfReader, PdfWriter

        source = self.make_form_pdf("password-forms-source.pdf")
        writer = PdfWriter()
        writer.append(PdfReader(source))
        writer.encrypt("forms secret", algorithm="AES-256-R5")
        encrypted = self.root / "password-forms.pdf"
        with encrypted.open("wb") as stream:
            writer.write(stream)

        locked = inspect_pdf_forms(str(encrypted))
        self.assertTrue(locked["encrypted"])
        self.assertEqual(locked["fields"], [])
        unlocked = inspect_pdf_forms(str(encrypted), "forms secret")
        self.assertTrue(unlocked["encrypted"])
        self.assertIn("full_name", {field["name"] for field in unlocked["fields"]})
        with self.assertRaisesRegex(ValueError, "password is incorrect"):
            inspect_pdf_forms(str(encrypted), "wrong")

    def test_pdf_form_inspection_hides_parent_groups_without_widgets(self):
        from pypdf import PdfWriter
        from pypdf.generic import ArrayObject, DictionaryObject, NameObject, NumberObject, TextStringObject

        writer = PdfWriter()
        page = writer.add_blank_page(width=200, height=100)
        parent = DictionaryObject({
            NameObject("/FT"): NameObject("/Tx"),
            NameObject("/T"): TextStringObject("person"),
        })
        parent_reference = writer._add_object(parent)
        widget = DictionaryObject({
            NameObject("/Subtype"): NameObject("/Widget"),
            NameObject("/T"): TextStringObject("name"),
            NameObject("/Parent"): parent_reference,
            NameObject("/Rect"): ArrayObject([NumberObject(10), NumberObject(10), NumberObject(110), NumberObject(30)]),
        })
        widget_reference = writer._add_object(widget)
        parent[NameObject("/Kids")] = ArrayObject([widget_reference])
        page[NameObject("/Annots")] = ArrayObject([widget_reference])
        writer._root_object.update({
            NameObject("/AcroForm"): DictionaryObject({
                NameObject("/Fields"): ArrayObject([parent_reference]),
            }),
        })
        source = self.root / "nested-form.pdf"
        with source.open("wb") as stream:
            writer.write(stream)

        fields = inspect_pdf_forms(str(source))["fields"]

        self.assertEqual([field["name"] for field in fields], ["person.name"])

    def make_signature_fixture(self, name="signed.pdf"):
        """Make a compact structural fixture for signature detection."""
        from pypdf import PdfWriter
        from pypdf.generic import (
            ArrayObject,
            ByteStringObject,
            DictionaryObject,
            NameObject,
            NumberObject,
            TextStringObject,
        )

        writer = PdfWriter()
        writer.add_blank_page(width=200, height=100)
        signature = DictionaryObject({
            NameObject("/Type"): NameObject("/Sig"),
            NameObject("/ByteRange"): ArrayObject(
                [NumberObject(0), NumberObject(10), NumberObject(20), NumberObject(30)]
            ),
            NameObject("/Contents"): ByteStringObject(b"signature fixture"),
        })
        signature_reference = writer._add_object(signature)
        field = DictionaryObject({
            NameObject("/FT"): NameObject("/Sig"),
            NameObject("/T"): TextStringObject("ExistingSignature"),
            NameObject("/V"): signature_reference,
        })
        writer._root_object.update({
            NameObject("/AcroForm"): DictionaryObject({
                NameObject("/Fields"): ArrayObject([writer._add_object(field)]),
                NameObject("/SigFlags"): NumberObject(3),
            })
        })
        source = self.root / name
        with source.open("wb") as stream:
            writer.write(stream)
        return source

    def make_certificate(self, password="test password"):
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives.serialization import pkcs12
        from cryptography.x509.oid import NameOID

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Phasor Preview Test")])
        now = datetime.now(timezone.utc)
        certificate = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=1))
            .not_valid_after(now + timedelta(days=1))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .sign(key, hashes.SHA256())
        )
        encoded = pkcs12.serialize_key_and_certificates(
            b"phasor-test",
            key,
            certificate,
            None,
            serialization.BestAvailableEncryption(password.encode("utf-8")),
        )
        path = self.root / "signing-test.p12"
        path.write_bytes(encoded)
        return path, certificate

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

    def test_image_export_flips_the_selected_pixels(self):
        source = self.root / "quadrants.png"
        image = Image.new("RGB", (2, 2))
        image.putdata([(255, 0, 0), (0, 0, 255), (0, 255, 0), (255, 255, 0)])
        image.save(source)

        horizontal = self.root / "horizontal.png"
        export_image(
            str(source), str(horizontal),
            {"flip_horizontal": True, "markup": {"version": 1, "kind": "image", "annotations": []}},
        )
        with Image.open(horizontal) as flipped:
            self.assertEqual(flipped.convert("RGB").getpixel((0, 0)), (0, 0, 255))
            self.assertEqual(flipped.convert("RGB").getpixel((0, 1)), (255, 255, 0))

        vertical = self.root / "vertical.png"
        export_image(
            str(source), str(vertical),
            {"flip_vertical": True, "markup": {"version": 1, "kind": "image", "annotations": []}},
        )
        with Image.open(vertical) as flipped:
            self.assertEqual(flipped.convert("RGB").getpixel((0, 0)), (0, 255, 0))
            self.assertEqual(flipped.convert("RGB").getpixel((0, 1)), (255, 0, 0))

        rotated = self.root / "rotated-and-flipped.png"
        export_image(
            str(source), str(rotated),
            {"rotation": 90, "flip_horizontal": True,
             "markup": {"version": 1, "kind": "image", "annotations": []}},
        )
        with Image.open(rotated) as flipped:
            self.assertEqual(flipped.convert("RGB").getpixel((0, 0)), (255, 0, 0))
            self.assertEqual(flipped.convert("RGB").getpixel((1, 0)), (0, 255, 0))

    def test_image_export_rejects_non_boolean_flip_options(self):
        source = self.make_image()
        output = self.root / "invalid-flip.png"
        with self.assertRaisesRegex(ValueError, "flip options must be boolean"):
            export_image(
                str(source), str(output),
                {"flip_horizontal": "yes", "markup": {"version": 1, "kind": "image", "annotations": []}},
            )
        self.assertFalse(output.exists())

    def test_freeform_selection_exports_a_transparent_bounded_png_copy(self):
        source = self.root / "selection-source.png"
        image = Image.new("RGBA", (12, 8), (40, 100, 180, 128))
        image.save(source)
        original = source.read_bytes()
        output = self.root / "selection.png"

        result = extract_image_selection(
            str(source), str(output),
            {"points": [[0, 0], [1, 0], [0, 1]]},
        )

        self.assertEqual((result["width"], result["height"]), (12, 8))
        with Image.open(output) as extracted:
            self.assertEqual(extracted.mode, "RGBA")
            self.assertEqual(extracted.getpixel((1, 1)), (40, 100, 180, 128))
            self.assertEqual(extracted.getpixel((10, 6))[3], 0)
        self.assertEqual(source.read_bytes(), original)

    def test_freeform_selection_applies_crop_rotation_flips_and_selected_frame(self):
        source = self.make_animated_image("lasso-animation.gif")
        output = self.root / "lasso-frame.png"

        result = extract_image_selection(
            str(source), str(output),
            {
                "points": [[0, 0], [1, 0], [1, 1], [0, 1]],
                "crop": {"x": 0.25, "y": 0.25, "width": 0.5, "height": 0.5},
                "rotation": 90,
                "flip_horizontal": True,
                "frame_index": 1,
            },
        )

        self.assertEqual((result["width"], result["height"]), (2, 4))
        with Image.open(output) as extracted:
            self.assertEqual(extracted.convert("RGB").getpixel((1, 1)), (0, 0, 255))
            self.assertEqual(extracted.getchannel("A").getextrema(), (255, 255))

    def test_freeform_selection_rejects_invalid_points_and_source_overwrite(self):
        source = self.make_image("lasso-invalid.png")
        output = self.root / "lasso-invalid-output.png"
        for points in ([], [[0, 0], [0.5, 0.5]], [[0, 0], [0, 0], [1, 1]], [[0, 0], [float("nan"), 1], [1, 0]]):
            with self.subTest(points=points):
                with self.assertRaises(ValueError):
                    extract_image_selection(str(source), str(output), {"points": points})
                self.assertFalse(output.exists())
        with self.assertRaisesRegex(ValueError, "original stays unchanged"):
            extract_image_selection(str(source), str(source), {"points": [[0, 0], [1, 0], [0, 1]]})

    def test_freeform_selection_cli_reads_geometry_from_stdin(self):
        from apps.preview import document_ops

        source = self.make_image("lasso-stdin.png")
        output = self.root / "lasso-stdin-output.png"
        command = ["document_ops.py", "extract-selection", str(source), str(output), "-"]
        payload = {"points": [[0, 0], [1, 0], [0, 1]]}
        result_json = io.StringIO()

        with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(payload) + "\n")):
            with redirect_stdout(result_json):
                exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(result_json.getvalue())["path"], str(output))
        self.assertTrue(output.exists())

    def test_animated_image_export_writes_the_selected_frame(self):
        source = self.make_animated_image()
        output = self.root / "second-frame.png"

        result = export_image(
            str(source), str(output),
            {"frame_index": 1, "markup": {"version": 1, "kind": "image", "annotations": []}},
        )

        self.assertEqual((result["width"], result["height"]), (8, 6))
        with Image.open(output) as exported:
            self.assertEqual(exported.convert("RGB").getpixel((0, 0)), (0, 0, 255))

    def test_animated_image_export_rejects_invalid_frame_indexes(self):
        source = self.make_animated_image()
        output = self.root / "invalid-frame.png"
        for frame_index in (-1, 2, True, "next"):
            with self.subTest(frame_index=frame_index):
                with self.assertRaisesRegex(ValueError, "Image frame"):
                    export_image(
                        str(source), str(output),
                        {"frame_index": frame_index, "markup": {"version": 1, "kind": "image", "annotations": []}},
                    )
                self.assertFalse(output.exists())

    def test_image_text_recognition_uses_current_crop_rotation_flip_and_selected_frame(self):
        source = self.make_image("ocr-image.png")
        observed = {}

        def run(command, **_options):
            if "--list-langs" in command:
                return SimpleNamespace(returncode=0, stdout="List of available languages (1):\neng\n", stderr="")
            with Image.open(command[1]) as prepared:
                observed["size"] = prepared.size
                observed["pixel"] = prepared.convert("RGB").getpixel((0, 0))
            self.assertEqual(command[-4:], ["-l", "eng", "--psm", "3"])
            return SimpleNamespace(returncode=0, stdout="PHASOR OCR SAMPLE\n", stderr="")

        original = source.read_bytes()
        with patch("apps.preview.document_ops.shutil.which", return_value="/fake/tesseract"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=run):
                result = recognize_image_text(
                    str(source),
                    {
                        "language": "eng",
                        "crop": {"x": 0.2, "y": 0.1, "width": 0.5, "height": 0.8},
                        "rotation": 90,
                        "flip_horizontal": True,
                    },
                )

        self.assertEqual(result["text"], "PHASOR OCR SAMPLE")
        self.assertEqual(observed["size"], (8, 10))
        self.assertEqual(observed["pixel"], (255, 255, 255))
        self.assertEqual(source.read_bytes(), original)

    def test_image_text_recognition_rejects_uninstalled_or_malformed_languages(self):
        source = self.make_image("ocr-language.png")

        with patch("apps.preview.document_ops.shutil.which", return_value=None):
            with self.assertRaisesRegex(ValueError, "needs Tesseract"):
                available_ocr_languages()

        def run(_command, **_options):
            return SimpleNamespace(returncode=0, stdout="List of available languages (1):\neng\n", stderr="")

        with patch("apps.preview.document_ops.shutil.which", return_value="/fake/tesseract"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=run):
                with self.assertRaisesRegex(ValueError, "language codes"):
                    recognize_image_text(str(source), {"language": "eng;bad"})

    def test_ocr_language_list_omits_orientation_only_data(self):
        def run(_command, **_options):
            return SimpleNamespace(
                returncode=0,
                stdout="List of available languages (3):\neng\nosd\npol\n",
                stderr="",
            )

        with patch("apps.preview.document_ops.shutil.which", return_value="/fake/tesseract"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=run):
                self.assertEqual(available_ocr_languages()["languages"], ["eng", "pol"])

    def test_image_recognition_cli_reads_options_from_stdin(self):
        from apps.preview import document_ops

        source = self.make_image("ocr-cli.png")
        command = ["document_ops.py", "recognize-image", str(source), "-"]
        output = io.StringIO()
        with patch("apps.preview.document_ops.recognize_image_text", return_value={"ok": True, "text": "local"}) as recognize:
            with patch("apps.preview.document_ops.sys.stdin", io.StringIO('{"language":"eng"}\n')):
                with redirect_stdout(output):
                    exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(output.getvalue())["text"], "local")
        recognize.assert_called_once_with(str(source), {"language": "eng"})

    def test_background_removal_writes_a_transparent_transformed_png_copy(self):
        source = self.root / "background-source.png"
        Image.new("RGB", (6, 4), "white").save(source)
        original = source.read_bytes()
        output = self.root / "background-removed.png"
        session_value = object()
        session_models = []
        removal_options = []

        def new_session(model):
            session_models.append(model)
            return session_value

        def remove(image, session, decontaminate):
            removal_options.append((session, decontaminate, image.mode, image.size))
            result = image.copy().convert("RGBA")
            alpha = Image.new("L", result.size, 255)
            for x in range(3, result.width):
                for y in range(result.height):
                    alpha.putpixel((x, y), 0)
            result.putalpha(alpha)
            return result

        with patch("apps.preview.document_ops._background_removal_stack", return_value=(new_session, remove)):
            result = remove_image_background(
                str(source),
                str(output),
                {
                    "crop": {"x": 1 / 3, "y": 0, "width": 0.5, "height": 1},
                    "rotation": 90,
                    "flip_horizontal": True,
                    "markup": {"version": 1, "kind": "image", "annotations": []},
                },
            )

        with Image.open(output) as exported:
            exported.load()
            self.assertEqual(exported.format, "PNG")
            self.assertEqual(exported.size, (4, 3))
            self.assertEqual(exported.mode, "RGBA")
            self.assertEqual(exported.getchannel("A").getextrema(), (0, 255))
        self.assertEqual(session_models, ["u2net"])
        self.assertEqual(removal_options, [(session_value, True, "RGBA", (6, 4))])
        self.assertEqual(source.read_bytes(), original)
        self.assertTrue(result["transparent"])

    def test_background_removal_cli_reads_options_from_stdin(self):
        source = self.make_image("background-cli-source.png")
        output = self.root / "background-cli-output.png"
        options = {"markup": {"version": 1, "kind": "image", "annotations": []}}
        command = ["document_ops.py", "background", str(source), str(output), "-"]
        output_json = io.StringIO()
        fake_stack = (lambda model: object(), lambda image, **kwargs: image)

        with patch("apps.preview.document_ops._background_removal_stack", return_value=fake_stack):
            with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(options) + "\n")):
                with redirect_stdout(output_json):
                    status = importlib.import_module("apps.preview.document_ops").main(command)

        self.assertEqual(status, 0)
        self.assertTrue(json.loads(output_json.getvalue())["transparent"])

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

    def test_searchable_pdf_copy_applies_pending_page_operations_and_keeps_source(self):
        source = self.make_pdf(pages=("FIRST OCR PAGE", "SECOND OCR PAGE"))
        original = source.read_bytes()
        output = self.root / "searchable-copy.pdf"
        locate, run = self.fake_ocr_tools()

        with patch("apps.preview.document_ops.shutil.which", side_effect=locate):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=run):
                result = embed_pdf_text(
                    str(source),
                    str(output),
                    {"language": "eng", "markup": {"version": 1, "kind": "pdf", "pages": {}, "page_order": [1, 0]}},
                )

        reader = PdfReader(output)
        self.assertEqual(result["pages"], 2)
        self.assertIn("SECOND OCR PAGE", reader.pages[0].extract_text())
        self.assertIn("FIRST OCR PAGE", reader.pages[1].extract_text())
        self.assertEqual(source.read_bytes(), original)

    def test_searchable_pdf_copy_unlocks_with_stdin_password_and_never_passes_it_to_ocr(self):
        from pypdf import PdfWriter

        source = self.make_pdf("protected-ocr.pdf", pages=("PROTECTED PAGE",))
        writer = PdfWriter(clone_from=source)
        writer.encrypt("secret OCR password", algorithm="AES-256")
        with source.open("wb") as stream:
            writer.write(stream)
        original = source.read_bytes()
        output = self.root / "unlocked-searchable.pdf"
        locate, base_run = self.fake_ocr_tools()
        observed_command = {}

        def run(command, **options):
            if "--list-langs" not in command:
                observed_command["args"] = list(command)
                observed_command["encrypted"] = PdfReader(command[-2]).is_encrypted
            return base_run(command, **options)

        with patch("apps.preview.document_ops.shutil.which", side_effect=locate):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=run):
                result = embed_pdf_text(
                    str(source), str(output), {"language": "eng", "source_password": "secret OCR password"}
                )

        self.assertTrue(result["ok"])
        self.assertFalse(observed_command["encrypted"])
        self.assertNotIn("secret OCR password", observed_command["args"])
        self.assertEqual(PdfReader(output).pages[0].extract_text().strip(), "PROTECTED PAGE")
        self.assertEqual(source.read_bytes(), original)

    def test_searchable_pdf_cli_reads_password_and_markup_from_stdin(self):
        from apps.preview import document_ops

        source = self.make_pdf("ocr-stdin.pdf")
        output = self.root / "ocr-stdin-output.pdf"
        command = ["document_ops.py", "searchable-pdf", str(source), str(output), "-"]
        options = {"source_password": "stdin secret", "markup": {"version": 1, "kind": "pdf", "pages": {}}}
        result_json = io.StringIO()
        with patch("apps.preview.document_ops.embed_pdf_text", return_value={"ok": True, "pages": 1}) as embed:
            with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(options) + "\n")):
                with redirect_stdout(result_json):
                    exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(result_json.getvalue())["pages"], 1)
        self.assertNotIn("stdin secret", command)
        embed.assert_called_once_with(str(source), str(output), options)

    def test_searchable_pdf_copy_requires_optional_backend_and_rejects_overwrite(self):
        source = self.make_pdf("ocr-guard.pdf")
        with patch("apps.preview.document_ops.shutil.which", return_value=None):
            with self.assertRaisesRegex(ValueError, "needs Tesseract"):
                embed_pdf_text(str(source), str(self.root / "result.pdf"), {})

        with self.assertRaisesRegex(ValueError, "original stays unchanged"):
            embed_pdf_text(str(source), str(source), {})

    def test_pdf_export_draws_text_anchors_and_keeps_note_as_pdf_annotation(self):
        source = self.root / "text-anchors.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(240, 160))
        page_canvas.drawString(24, 112, "Anchored source text")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        output = self.root / "text-anchors-export.pdf"
        selection_rect = [0.1, 0.25, 0.76, 0.34]
        markup = {
            "version": 1,
            "kind": "pdf",
            "pages": {
                "0": [
                    {"type": "text_highlight", "quote": "Anchored source text", "rects": [selection_rect], "color": "#f3c969"},
                    {"type": "underline", "quote": "Anchored source text", "rects": [selection_rect], "color": "#8bd5ca"},
                    {"type": "strike", "quote": "Anchored source text", "rects": [selection_rect], "color": "#ed8796"},
                    {"type": "note", "quote": "Anchored source text", "rects": [selection_rect], "note": "Verify the source citation.", "color": "#f3c969"},
                ]
            },
        }

        export_pdf(str(source), str(output), {"markup": markup})

        page = PdfReader(output).pages[0]
        self.assertIn("Anchored source text", page.extract_text())
        self.assertTrue(page.get_contents().get_data())
        notes = [annotation.get_object() for annotation in page.get("/Annots", [])]
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0].get("/Subtype"), "/Text")
        self.assertEqual(notes[0].get("/Contents"), "Verify the source citation.")
        self.assertEqual(int(notes[0].get("/F")), 4)
        self.assertGreater(float(notes[0]["/Rect"][2]), float(notes[0]["/Rect"][0]))

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

    def test_pdf_page_insertion_adds_a_blank_to_a_prepared_copy(self):
        source = self.root / "insert-blank-source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "FIRST PAGE")
        page_canvas.showPage()
        page_canvas.drawString(20, 50, "SECOND PAGE")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        original = source.read_bytes()
        output = self.root / "insert-blank-copy.pdf"
        markup = {
            "version": 1,
            "kind": "pdf",
            "pages": {
                "1": [{"type": "text", "x": 0.1, "y": 0.5, "text": "Editable work is preserved visually", "color": "#102030"}]
            },
            "page_order": [1, 0],
            "page_rotations": {"1": 90},
        }

        result = insert_pdf_pages(
            str(source),
            "",
            str(output),
            {"markup": markup, "insert_at": 1},
        )

        reader = PdfReader(output)
        self.assertEqual(result["pages"], 3)
        self.assertEqual(result["blank_pages"], 1)
        self.assertEqual(len(reader.pages), 3)
        self.assertIn("SECOND PAGE", reader.pages[0].extract_text())
        self.assertIn("Editable work is preserved visually", reader.pages[0].extract_text())
        self.assertEqual(reader.pages[0].rotation, 90)
        self.assertEqual(reader.pages[1].extract_text().strip(), "")
        self.assertIn("FIRST PAGE", reader.pages[2].extract_text())
        self.assertEqual(source.read_bytes(), original)

    def test_pdf_page_insertion_imports_selected_pages_and_namespaces_forms(self):
        current = self.make_form_pdf("current-pages.pdf")
        imported = self.make_form_pdf("imported-pages.pdf")
        current_bytes = current.read_bytes()
        imported_bytes = imported.read_bytes()
        output = self.root / "inserted-pages.pdf"

        result = insert_pdf_pages(
            str(current),
            str(imported),
            str(output),
            {
                "markup": {
                    "version": 1,
                    "kind": "pdf",
                    "pages": {},
                    "form_values": {"full_name": "Ada Lovelace"},
                },
                "pages": "1",
                "insert_at": 1,
            },
        )

        reader = PdfReader(output)
        fields = reader.get_fields()
        self.assertEqual(result["pages"], 2)
        self.assertEqual(result["imported_pages"], 1)
        self.assertEqual(len(reader.pages), 2)
        self.assertEqual(fields["full_name"]["/V"], "Ada Lovelace")
        self.assertTrue(any(name.endswith(".full_name") for name in fields))
        self.assertEqual(current.read_bytes(), current_bytes)
        self.assertEqual(imported.read_bytes(), imported_bytes)

    def test_pdf_page_insertion_requires_new_password_for_protected_imports(self):
        from pypdf import PdfWriter

        current = self.root / "current.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "CURRENT")
        page_canvas.save()
        current.write_bytes(buffer.getvalue())
        imported = self.root / "protected-import.pdf"
        encrypted_writer = PdfWriter()
        encrypted_writer.add_page(PdfReader(io.BytesIO(buffer.getvalue())).pages[0])
        encrypted_writer.encrypt("import password", algorithm="AES-256")
        with imported.open("wb") as stream:
            encrypted_writer.write(stream)
        imported_bytes = imported.read_bytes()
        output = self.root / "protected-inserted.pdf"
        base_options = {
            "markup": {"version": 1, "kind": "pdf", "pages": {}},
            "pages": "1",
            "insert_at": 1,
            "import_password": "import password",
        }

        with self.assertRaisesRegex(ValueError, "Set a password"):
            insert_pdf_pages(str(current), str(imported), str(output), base_options)

        result = insert_pdf_pages(
            str(current), str(imported), str(output), {**base_options, "protect_password": "output password"}
        )
        reader = PdfReader(output)
        self.assertTrue(result["encrypted"])
        self.assertEqual(int(reader.decrypt("output password")), 2)
        self.assertIn("CURRENT", reader.pages[0].extract_text())
        self.assertEqual(len(reader.pages), 2)
        self.assertEqual(imported.read_bytes(), imported_bytes)

    def test_pdf_page_insertion_cli_reads_passwords_from_stdin(self):
        from apps.preview import document_ops

        source = self.make_form_pdf("stdin-insert-current.pdf")
        imported = self.make_form_pdf("stdin-insert-import.pdf")
        output = self.root / "stdin-insert-output.pdf"
        secret = "stdin output secret"
        command = ["document_ops.py", "insert", str(source), str(imported), str(output), "-"]
        options = {
            "markup": {"version": 1, "kind": "pdf", "pages": {}},
            "pages": "1",
            "insert_at": 1,
            "protect_password": secret,
        }
        result_json = io.StringIO()
        with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(options) + "\n")):
            with redirect_stdout(result_json):
                exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertNotIn(secret, command)
        self.assertTrue(json.loads(result_json.getvalue())["ok"])
        self.assertTrue(PdfReader(output).is_encrypted)

    def test_pdf_export_unlocks_protects_and_optimizes_only_a_new_copy(self):
        from pypdf import PdfReader, PdfWriter

        original = self.make_form_pdf("protected-source.pdf")
        original_bytes = original.read_bytes()
        reader = PdfReader(original)
        encrypted_writer = PdfWriter()
        encrypted_writer.append(reader)
        encrypted_writer.encrypt("source secret", algorithm="AES-256-R5")
        source = self.root / "encrypted-source.pdf"
        with source.open("wb") as stream:
            encrypted_writer.write(stream)
        source_bytes = source.read_bytes()
        output = self.root / "protected-output.pdf"
        markup = {
            "version": 1,
            "kind": "pdf",
            "pages": {},
            "form_values": {"full_name": "Ada Lovelace"},
        }

        result = export_pdf(
            str(source),
            str(output),
            {
                "markup": markup,
                "source_password": "source secret",
                "protect_password": "output secret",
                "reduce_file_size": True,
            },
        )

        exported = PdfReader(output)
        self.assertTrue(exported.is_encrypted)
        self.assertEqual(int(exported.decrypt("output secret")), 2)
        self.assertEqual(exported.get_fields()["full_name"]["/V"], "Ada Lovelace")
        self.assertTrue(result["encrypted"])
        self.assertEqual(result["input_size_bytes"], len(source_bytes))
        self.assertEqual(result["output_size_bytes"], output.stat().st_size)
        self.assertEqual(original.read_bytes(), original_bytes)
        self.assertEqual(source.read_bytes(), source_bytes)
        with self.assertRaisesRegex(ValueError, "password is incorrect"):
            export_pdf(str(source), str(self.root / "wrong.pdf"), {"source_password": "wrong"})
        self.assertFalse((self.root / "wrong.pdf").exists())

    def test_pdf_lossless_size_reduction_compresses_content_and_preserves_text(self):
        source = self.root / "verbose-source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(400, 400), pageCompression=0)
        for index in range(1200):
            page_canvas.drawString(24, 380 - (index % 360), f"Repeated searchable line {index % 8}")
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        output = self.root / "optimized.pdf"

        result = export_pdf(str(source), str(output), {"reduce_file_size": True})

        self.assertLess(result["output_size_bytes"], result["input_size_bytes"])
        text = PdfReader(output).pages[0].extract_text()
        self.assertIn("Repeated searchable line", text)
        self.assertEqual(PdfReader(source).pages[0].extract_text(), text)

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
        self.assertFalse(fields["full_name"]["multiline"])
        self.assertTrue(fields["issued_by"]["read_only"])
        self.assertTrue(fields["notes"]["multiline"])
        self.assertTrue(fields["access_code"]["password"])
        self.assertEqual(fields["access_code"]["value"], "")
        self.assertEqual(fields["accept_terms"]["type"], "checkbox")
        self.assertEqual(fields["country"]["type"], "choice")
        self.assertFalse(fields["country"]["editable"])
        self.assertTrue(fields["editable_region"]["editable"])
        self.assertEqual(fields["favorite_drinks"]["type"], "multi_choice")
        self.assertEqual(fields["favorite_drinks"]["value"], ["Tea"])
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
                        "editable_region": "Iceland",
                        "favorite_drinks": ["Coffee", "Water"],
                        "notes": "First line\nSecond line",
                        "access_code": "new secret",
                    },
                }
            },
        )

        values = PdfReader(output).get_fields()
        self.assertEqual(values["full_name"]["/V"], "Ada Lovelace")
        self.assertEqual(str(values["accept_terms"]["/V"]), "/Yes")
        self.assertEqual(values["country"]["/V"], "Canada")
        self.assertEqual(values["editable_region"]["/V"], "Iceland")
        self.assertEqual(values["favorite_drinks"]["/V"], ["Coffee", "Water"])
        self.assertEqual(values["notes"]["/V"], "First line\nSecond line")
        self.assertEqual(values["access_code"]["/V"], "new secret")
        output_page = PdfReader(output).pages[0]
        widgets = {
            str(reference.get_object().get("/T")): reference.get_object()
            for reference in output_page.get("/Annots", [])
        }
        name_appearance = widgets["full_name"]["/AP"]["/N"].get_object()
        self.assertIn(b"(Ada Lovelace) Tj", name_appearance.get_data())
        self.assertEqual(str(widgets["accept_terms"].get("/AS")), "/Yes")
        self.assertEqual(PdfReader(source).get_fields()["full_name"]["/V"], "")
        self.assertEqual(PdfReader(source).get_fields()["issued_by"]["/V"], "Phasor Office")

    def test_pdf_export_rejects_changes_to_read_only_form_fields(self):
        source = self.make_form_pdf()
        output = self.root / "changed-read-only.pdf"

        with self.assertRaisesRegex(ValueError, "issued_by is read-only"):
            export_pdf(
                str(source),
                str(output),
                {
                    "markup": {
                        "version": 1,
                        "kind": "pdf",
                        "pages": {},
                        "form_values": {"issued_by": "Changed"},
                    }
                },
            )

        self.assertFalse(output.exists())

    def test_pdf_export_rejects_custom_values_for_fixed_choice_fields(self):
        source = self.make_form_pdf()
        output = self.root / "invalid-fixed-choice.pdf"

        with self.assertRaisesRegex(ValueError, "Iceland is not a valid choice for country"):
            export_pdf(
                str(source),
                str(output),
                {
                    "markup": {
                        "version": 1,
                        "kind": "pdf",
                        "pages": {},
                        "form_values": {"country": "Iceland"},
                    }
                },
            )

        self.assertFalse(output.exists())

    def test_pdf_export_cli_reads_field_values_from_stdin(self):
        from apps.preview import document_ops

        source = self.make_form_pdf()
        output = self.root / "stdin-form.pdf"
        secret = "stdin secret"
        command = ["document_ops.py", "pdf", str(source), str(output), "-"]
        options = {
            "markup": {
                "version": 1,
                "kind": "pdf",
                "pages": {},
                "form_values": {"access_code": secret},
            }
        }
        result_json = io.StringIO()
        with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(options) + "\n")):
            with redirect_stdout(result_json):
                exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(result_json.getvalue())["ok"])
        self.assertNotIn(secret, command)
        self.assertEqual(PdfReader(output).get_fields()["access_code"]["/V"], secret)

    def test_pdf_inspection_cli_reads_password_from_stdin(self):
        from pypdf import PdfWriter
        from apps.preview import document_ops

        source = self.root / "stdin-password.pdf"
        writer = PdfWriter()
        writer.add_blank_page(width=200, height=100)
        writer.encrypt("stdin PDF secret", algorithm="AES-256-R5")
        with source.open("wb") as stream:
            writer.write(stream)
        command = ["document_ops.py", "inspect", str(source), "-"]
        output = io.StringIO()
        payload = {"password": "stdin PDF secret"}
        with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps(payload) + "\n")):
            with redirect_stdout(output):
                exit_code = document_ops.main(command)

        self.assertEqual(exit_code, 0)
        self.assertNotIn("stdin PDF secret", command)
        self.assertEqual(json.loads(output.getvalue())["page_count"], 1)

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

    @unittest.skipUnless(SIGNING_AVAILABLE, "Optional pyHanko signing dependency is not installed")
    def test_certificate_signing_creates_visible_incremental_copy_and_valid_signature(self):
        from asn1crypto import x509 as asn1_x509
        from cryptography.hazmat.primitives.serialization import Encoding
        from pypdf import PdfWriter
        from pyhanko.pdf_utils.reader import PdfFileReader
        from pyhanko.sign.validation import validate_pdf_signature
        from pyhanko_certvalidator import ValidationContext

        source = self.root / "source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.drawString(20, 170, "Keep the original document content")
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        original_bytes = source.read_bytes()
        certificate_path, certificate = self.make_certificate()
        output = self.root / "signed.pdf"

        result = sign_pdf(
            str(source),
            str(output),
            str(certificate_path),
            {
                "page_index": 0,
                "box": [0.1, 0.1, 0.55, 0.35],
                "rotation": 0,
                "reason": "Approved",
                "location": "Warsaw",
                "markup": {"version": 1, "kind": "pdf", "pages": {}},
            },
            "test password",
        )

        self.assertEqual(result["page"], 1)
        self.assertEqual(source.read_bytes(), original_bytes)
        self.assertTrue(output.read_bytes().startswith(original_bytes))
        with output.open("rb") as stream:
            signed_pdf = PdfFileReader(stream)
            self.assertEqual(len(signed_pdf.embedded_signatures), 1)
            signature = signed_pdf.embedded_signatures[0]
            status = validate_pdf_signature(
                signature,
                signer_validation_context=ValidationContext(
                    trust_roots=[asn1_x509.Certificate.load(certificate.public_bytes(Encoding.DER))]
                ),
            )
            self.assertTrue(status.intact)
            self.assertTrue(status.valid)
            self.assertTrue(status.trusted)
            self.assertEqual(signature.field_name, "PhasorSignature")

        signed_page = PdfReader(output).pages[0]
        signature_widget = next(
            reference.get_object()
            for reference in signed_page.get("/Annots", [])
            if reference.get_object().get("/T") == "PhasorSignature"
        )
        self.assertEqual(tuple(round(float(value)) for value in signature_widget["/Rect"]), (30, 130, 165, 180))
        self.assertIsNotNone(signature_widget.get("/AP"))

        signed_reader = PdfReader(output)
        self.assertIn("Keep the original document content", signed_reader.pages[0].extract_text())

        encrypted_writer = PdfWriter()
        encrypted_writer.append(PdfReader(source))
        encrypted_writer.encrypt("source PDF password", algorithm="AES-256-R5")
        encrypted_source = self.root / "encrypted-signing-source.pdf"
        with encrypted_source.open("wb") as stream:
            encrypted_writer.write(stream)
        encrypted_output = self.root / "encrypted-signed.pdf"
        encrypted_result = sign_pdf(
            str(encrypted_source),
            str(encrypted_output),
            str(certificate_path),
            {
                "page_index": 0,
                "box": [0.1, 0.1, 0.55, 0.35],
                "rotation": 0,
                "reason": "Approved",
                "location": "Warsaw",
                "markup": {"version": 1, "kind": "pdf", "pages": {}},
            },
            "test password",
            "source PDF password",
        )
        self.assertTrue(encrypted_result["encrypted"])
        encrypted_reader = PdfReader(encrypted_output)
        self.assertTrue(encrypted_reader.is_encrypted)
        encrypted_reader.decrypt("source PDF password")
        self.assertIn("Keep the original document content", encrypted_reader.pages[0].extract_text())
        with encrypted_output.open("rb") as stream:
            signed_encrypted_pdf = PdfFileReader(stream)
            self.assertNotEqual(signed_encrypted_pdf.decrypt("source PDF password").status.value, 0)
            self.assertEqual(len(signed_encrypted_pdf.embedded_signatures), 1)
            encrypted_signature_status = validate_pdf_signature(
                signed_encrypted_pdf.embedded_signatures[0],
                signer_validation_context=ValidationContext(
                    trust_roots=[asn1_x509.Certificate.load(certificate.public_bytes(Encoding.DER))]
                ),
            )
            self.assertTrue(encrypted_signature_status.intact)
            self.assertTrue(encrypted_signature_status.valid)

    @unittest.skipUnless(SIGNING_AVAILABLE, "Optional pyHanko signing dependency is not installed")
    def test_certificate_signing_applies_pending_edits_before_signing(self):
        from pypdf import PdfWriter

        source = self.root / "prepared-source.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.drawString(20, 170, "Before markup")
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        certificate_path, _ = self.make_certificate()
        output = self.root / "prepared-signed.pdf"
        options = {
            "page_index": 0,
            "box": [0.1, 0.1, 0.55, 0.35],
            "rotation": 0,
            "markup": {
                "version": 1,
                "kind": "pdf",
                "pages": {"0": [{"type": "text", "x": 0.1, "y": 0.5, "text": "Prepared note", "color": "#102030"}]},
                "page_order": [0],
                "form_values": {},
            },
        }

        from apps.preview import document_ops

        output_json = io.StringIO()
        command = ["document_ops.py", "sign", str(source), str(output), str(certificate_path)]
        with patch("apps.preview.document_ops.sys.stdin", io.StringIO(json.dumps({"password": "test password", "options": options}) + "\n")):
            with redirect_stdout(output_json):
                exit_code = document_ops.main(command)
        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(output_json.getvalue())["ok"])
        self.assertNotIn("test password", command)

        output_reader = PdfReader(output)
        self.assertIn("Before markup", output_reader.pages[0].extract_text())
        self.assertIn("Prepared note", output_reader.pages[0].extract_text())
        self.assertEqual(len(output_reader.get_fields()), 1)
        self.assertEqual(len(PdfReader(source).get_fields() or {}), 0)

        encrypted_writer = PdfWriter()
        encrypted_writer.append(PdfReader(source))
        encrypted_writer.encrypt("source PDF password", algorithm="AES-256-R5")
        encrypted_source = self.root / "encrypted-prepared-source.pdf"
        with encrypted_source.open("wb") as stream:
            encrypted_writer.write(stream)
        encrypted_output = self.root / "encrypted-prepared-signed.pdf"
        sign_pdf(
            str(encrypted_source),
            str(encrypted_output),
            str(certificate_path),
            options,
            "test password",
            "source PDF password",
        )
        encrypted_result = PdfReader(encrypted_output)
        self.assertTrue(encrypted_result.is_encrypted)
        encrypted_result.decrypt("source PDF password")
        self.assertIn("Before markup", encrypted_result.pages[0].extract_text())
        self.assertIn("Prepared note", encrypted_result.pages[0].extract_text())
        from pyhanko.pdf_utils.reader import PdfFileReader
        with encrypted_output.open("rb") as stream:
            signed_pdf = PdfFileReader(stream)
            self.assertNotEqual(signed_pdf.decrypt("source PDF password").status.value, 0)
            self.assertEqual(len(signed_pdf.embedded_signatures), 1)

    @unittest.skipUnless(SIGNING_AVAILABLE, "Optional pyHanko signing dependency is not installed")
    def test_certificate_signing_rejects_wrong_password_and_preserves_existing_signatures(self):
        source = self.root / "unsigned.pdf"
        from asn1crypto import x509 as asn1_x509
        from cryptography.hazmat.primitives.serialization import Encoding
        from pyhanko_certvalidator import ValidationContext
        from pyhanko.sign.validation import validate_pdf_signature

        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.showPage()
        page_canvas.save()
        source.write_bytes(buffer.getvalue())
        certificate_path, certificate = self.make_certificate()
        base_options = {
            "page_index": 0,
            "box": [0.1, 0.1, 0.55, 0.35],
            "rotation": 0,
            "markup": {"version": 1, "kind": "pdf", "pages": {}},
        }
        failed_output = self.root / "failed.pdf"
        with self.assertRaisesRegex(ValueError, "Check the file and password"):
            sign_pdf(str(source), str(failed_output), str(certificate_path), base_options, "wrong")
        self.assertFalse(failed_output.exists())

        signed = self.root / "already-signed.pdf"
        sign_pdf(str(source), str(signed), str(certificate_path), base_options, "test password")
        validation_context = ValidationContext(
            trust_roots=[asn1_x509.Certificate.load(certificate.public_bytes(Encoding.DER))]
        )
        signature_count = len(PdfReader(signed).get_fields() or {})
        edited_options = dict(base_options)
        edited_options["markup"] = {
            "version": 1,
            "kind": "pdf",
            "pages": {"0": [{"type": "text", "x": 0.1, "y": 0.3, "text": "Would break signature", "color": "#102030"}]},
        }
        with self.assertRaisesRegex(ValueError, "already has a digital signature"):
            sign_pdf(str(signed), str(self.root / "invalidated.pdf"), str(certificate_path), edited_options, "test password")
        self.assertEqual(len(PdfReader(signed).get_fields() or {}), signature_count)

        countersigned = self.root / "countersigned.pdf"
        sign_pdf(str(signed), str(countersigned), str(certificate_path), base_options, "test password")
        from pyhanko.pdf_utils.reader import PdfFileReader
        with countersigned.open("rb") as stream:
            signed_pdf = PdfFileReader(stream)
            self.assertEqual(len(signed_pdf.embedded_signatures), 2)
            self.assertTrue(validate_pdf_signature(signed_pdf.embedded_signatures[0], signer_validation_context=validation_context).intact)
            self.assertTrue(validate_pdf_signature(signed_pdf.embedded_signatures[1], signer_validation_context=validation_context).intact)

    def test_signature_box_maps_rotated_offset_cropbox_coordinates(self):
        from pypdf import PdfReader, PdfWriter
        from apps.preview.document_ops import _signature_box

        writer = PdfWriter()
        page = writer.add_blank_page(width=300, height=200)
        page.cropbox.lower_left = (25, 35)
        page.cropbox.upper_right = (275, 185)
        page.rotate(90)
        buffer = io.BytesIO()
        writer.write(buffer)
        buffer.seek(0)
        rotated_page = PdfReader(buffer).pages[0]

        self.assertEqual(_signature_box(rotated_page, [0.1, 0.1, 0.5, 0.5], 0), (150.0, 50.0, 250.0, 110.0))

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

    def test_pdf_merge_unlocks_the_current_document_for_a_new_copy(self):
        from pypdf import PdfWriter

        first = self.root / "encrypted-first.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "UNLOCKED FIRST PAGE")
        page_canvas.save()
        buffer.seek(0)
        writer = PdfWriter()
        writer.append(PdfReader(buffer))
        writer.encrypt("merge secret", algorithm="AES-256-R5")
        with first.open("wb") as stream:
            writer.write(stream)
        original = first.read_bytes()
        second = self.root / "second.pdf"
        second_canvas = canvas.Canvas(str(second), pagesize=(200, 100))
        second_canvas.drawString(20, 50, "SECOND PAGE")
        second_canvas.save()
        output = self.root / "encrypted-merged.pdf"

        result = merge_pdfs(
            [str(first), str(second)],
            str(output),
            {
                "source_password": "merge secret",
                "markup": {"version": 1, "kind": "pdf", "pages": {}},
            },
        )

        merged = PdfReader(output)
        self.assertEqual(result["pages"], 2)
        self.assertIn("UNLOCKED FIRST PAGE", merged.pages[0].extract_text())
        self.assertIn("SECOND PAGE", merged.pages[1].extract_text())
        self.assertEqual(first.read_bytes(), original)

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

    def test_pdf_merge_rejects_signed_inputs_before_invalidating_them(self):
        unsigned = self.make_form_pdf("unsigned.pdf")
        signed = self.make_signature_fixture()
        original_signed_pdf = signed.read_bytes()

        for sources, output_name in (
            ([signed, unsigned], "signed-first-merge.pdf"),
            ([unsigned, signed], "signed-appended-merge.pdf"),
        ):
            output = self.root / output_name
            with self.subTest(signed_position=sources.index(signed)):
                with self.assertRaisesRegex(
                    ValueError, "contains a digital signature.*merging would invalidate"
                ):
                    merge_pdfs([str(path) for path in sources], str(output), {})
                self.assertFalse(output.exists())
        self.assertEqual(signed.read_bytes(), original_signed_pdf)

    def test_print_submits_a_prepared_copy_with_printer_options(self):
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

    def test_print_unlocks_protected_pdf_only_in_the_temporary_copy(self):
        from pypdf import PdfWriter

        source = self.root / "encrypted-print.pdf"
        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(200, 100))
        page_canvas.drawString(20, 50, "PRINT PROTECTED CONTENT")
        page_canvas.save()
        buffer.seek(0)
        writer = PdfWriter()
        writer.append(PdfReader(buffer))
        writer.encrypt("print secret", algorithm="AES-256-R5")
        with source.open("wb") as stream:
            writer.write(stream)
        original = source.read_bytes()

        def submit(command, **kwargs):
            prepared = PdfReader(command[-1])
            self.assertFalse(prepared.is_encrypted)
            self.assertIn("PRINT PROTECTED CONTENT", prepared.pages[0].extract_text())
            return SimpleNamespace(returncode=0, stdout="job-locked", stderr="")

        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=submit):
                result = print_document(
                    str(source),
                    {
                        "source_password": "print secret",
                        "markup": {"version": 1, "kind": "pdf", "pages": {}},
                    },
                )

        self.assertTrue(result["ok"])
        self.assertEqual(result["job"], "job-locked")
        self.assertEqual(source.read_bytes(), original)

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

    def test_print_uses_the_selected_animated_frame(self):
        source = self.make_animated_image()
        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch(
                "apps.preview.document_ops.subprocess.run",
                return_value=SimpleNamespace(returncode=0, stdout="job-1", stderr=""),
            ):
                with patch("apps.preview.document_ops.export_image", wraps=export_image) as image_export:
                    result = print_document(
                        str(source),
                        {"frame_index": 1, "flip_horizontal": True,
                         "markup": {"version": 1, "kind": "image", "annotations": []}},
                    )

        self.assertTrue(result["ok"])
        self.assertEqual(image_export.call_args.args[2]["frame_index"], 1)
        self.assertTrue(image_export.call_args.args[2]["flip_horizontal"])

    def test_print_preserves_cropped_rotated_pdf_content_in_prepared_copy(self):
        from pypdf import PdfWriter

        buffer = io.BytesIO()
        page_canvas = canvas.Canvas(buffer, pagesize=(300, 200))
        page_canvas.drawString(40, 50, "CROPPED ROTATED PRINT PAGE")
        page_canvas.showPage()
        page_canvas.save()
        buffer.seek(0)
        page = PdfReader(buffer).pages[0]
        page.cropbox.lower_left = (20, 15)
        page.cropbox.upper_right = (280, 185)
        page.rotate(90)
        writer = PdfWriter()
        writer.add_page(page)
        source = self.root / "cropped-rotated.pdf"
        with source.open("wb") as stream:
            writer.write(stream)
        original = source.read_bytes()

        def submit(command, **kwargs):
            printed = PdfReader(command[-1])
            self.assertEqual(len(printed.pages), 1)
            self.assertEqual(printed.pages[0].rotation, 180)
            self.assertEqual(tuple(map(float, printed.pages[0].cropbox)), (15.0, 20.0, 185.0, 280.0))
            self.assertIn("CROPPED ROTATED PRINT PAGE", printed.pages[0].extract_text())
            return SimpleNamespace(returncode=0, stdout="job-2", stderr="")

        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch("apps.preview.document_ops.subprocess.run", side_effect=submit):
                result = print_document(
                    str(source),
                    {
                        "markup": {
                            "version": 1,
                            "kind": "pdf",
                            "pages": {},
                            "page_order": [0],
                            "page_rotations": {"0": 180},
                        },
                        "pages": "1",
                    },
                )

        self.assertTrue(result["ok"])
        self.assertEqual(source.read_bytes(), original)

    def test_print_options_reject_command_injection_and_invalid_ranges(self):
        from apps.preview.document_ops import _validated_print_options

        with self.assertRaisesRegex(ValueError, "printer name"):
            _validated_print_options({"printer": "Office; touch /tmp/unsafe"})
        with self.assertRaisesRegex(ValueError, "ascending"):
            _validated_print_options({"pages": "5-2"})

    def test_print_rejects_page_ranges_outside_the_prepared_document(self):
        source = self.make_form_pdf()
        submissions = []

        with patch("apps.preview.document_ops.shutil.which", return_value="/usr/bin/lp"):
            with patch(
                "apps.preview.document_ops.subprocess.run",
                side_effect=lambda *args, **kwargs: submissions.append(args),
            ):
                with self.assertRaisesRegex(ValueError, "exceeds the 1-page prepared document"):
                    print_document(str(source), {"pages": "1-2"})

        self.assertEqual(submissions, [])


if __name__ == "__main__":
    unittest.main()
