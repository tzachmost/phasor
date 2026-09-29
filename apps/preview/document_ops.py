#!/usr/bin/env python3
"""Export Preview images and PDFs without changing their source files."""

from __future__ import annotations

import io
import json
import logging
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from contextlib import ExitStack
from pathlib import Path
from typing import Any

try:
    from .markup_store import _source_path, validate_payload
except ImportError:
    from markup_store import _source_path, validate_payload


MAX_IMAGE_PIXELS = 100_000_000
MAX_IMAGE_DIMENSION = 32_768
SUPPORTED_IMAGE_FORMATS = {
    ".bmp": "BMP",
    ".jpeg": "JPEG",
    ".jpg": "JPEG",
    ".png": "PNG",
    ".tif": "TIFF",
    ".tiff": "TIFF",
    ".webp": "WEBP",
}


def _output_path(source: Path, value: str, expected_suffix: str | None = None) -> Path:
    output = Path(value).expanduser().absolute()
    if output.resolve() == source.resolve():
        raise ValueError("Choose a new file name so the original stays unchanged")
    if expected_suffix and output.suffix.lower() != expected_suffix:
        raise ValueError(f"The output file must use the {expected_suffix} extension")
    output.parent.mkdir(parents=True, exist_ok=True)
    return output


def _atomic_save(output: Path, write) -> None:
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{output.stem}-", suffix=output.suffix, dir=output.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            write(stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _optional_image_stack():
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageOps
    except ImportError as error:
        raise ValueError("Image export needs Pillow. Install the python-pillow package.") from error
    return Image, ImageDraw, ImageFont, ImageOps


def _font_path() -> Path | None:
    configured = os.environ.get("PHASOR_PREVIEW_FONT")
    if configured and Path(configured).is_file():
        return Path(configured)
    candidates = (
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        Path("/usr/share/fonts/TTF/DejaVuSans.ttf"),
        Path("/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"),
        Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"),
        Path("/usr/share/fonts/liberation/LiberationSans-Regular.ttf"),
    )
    return next((path for path in candidates if path.is_file()), None)


def _color(value: str) -> tuple[tuple[int, int, int], float]:
    text = value.removeprefix("#")
    if len(text) == 8:
        alpha = int(text[:2], 16) / 255
        text = text[2:]
    elif len(text) == 6:
        alpha = 1.0
    else:
        raise ValueError("Markup color must contain six or eight hex digits")
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)), alpha


def _rgb01(color: tuple[int, int, int]) -> tuple[float, float, float]:
    return tuple(channel / 255 for channel in color)


def _normalized(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        raise ValueError(f"{name} must be a number")
    result = float(value)
    if not math.isfinite(result) or result < 0 or result > 1:
        raise ValueError(f"{name} must be between zero and one")
    return result


def _draw_image_markup(image, annotations: list[dict[str, Any]]) -> None:
    if not annotations:
        return
    Image, ImageDraw, ImageFont, _ = _optional_image_stack()
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    width, height = image.size
    unit = min(width, height)
    font_path = _font_path()

    for mark in annotations:
        color, opacity = _color(mark["color"])
        rgba = (*color, round(opacity * 255))
        line_width = max(2, round(mark.get("width", 0.006) * unit))
        if mark["type"] in {"stroke", "signature"}:
            points = [(round(x * width), round(y * height)) for x, y in mark["points"]]
            if len(points) == 1:
                radius = line_width / 2
                x, y = points[0]
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=rgba)
            else:
                draw.line(points, fill=rgba, width=line_width, joint="curve")
        elif mark["type"] in {"rectangle", "highlight"}:
            left = min(mark["x1"], mark["x2"]) * width
            top = min(mark["y1"], mark["y2"]) * height
            right = max(mark["x1"], mark["x2"]) * width
            bottom = max(mark["y1"], mark["y2"]) * height
            if mark["type"] == "highlight":
                draw.rectangle((left, top, right, bottom), fill=rgba)
            else:
                draw.rectangle((left, top, right, bottom), outline=rgba, width=line_width)
        elif mark["type"] == "text":
            size = max(8, round(mark.get("size", 0.038) * unit))
            font = ImageFont.truetype(str(font_path), size) if font_path else ImageFont.load_default(size=size)
            text_options: dict[str, Any] = {}
            try:
                from PIL import features

                if features.check_feature("raqm") and any(
                    unicodedata.bidirectional(character) in {"R", "AL"} for character in mark["text"]
                ):
                    text_options["direction"] = "rtl"
            except (ImportError, ValueError):
                pass
            draw.text(
                (round(mark["x"] * width), round(mark["y"] * height)),
                mark["text"],
                fill=rgba,
                font=font,
                **text_options,
            )
    image.alpha_composite(overlay)


def _size_option(value: Any, name: str) -> int | None:
    if value in (None, "", 0, "0"):
        return None
    if isinstance(value, bool):
        raise ValueError(f"{name} must be a whole number")
    try:
        result = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be a whole number") from error
    if result < 1 or result > MAX_IMAGE_DIMENSION:
        raise ValueError(f"{name} must be between 1 and {MAX_IMAGE_DIMENSION}")
    return result


def export_image(source_value: str, output_value: str, options: dict[str, Any]) -> dict[str, Any]:
    Image, ImageDraw, ImageFont, ImageOps = _optional_image_stack()
    source = _source_path(source_value)
    suffix = Path(output_value).suffix.lower()
    image_format = SUPPORTED_IMAGE_FORMATS.get(suffix)
    if image_format is None:
        raise ValueError("Choose PNG, JPEG, WebP, TIFF, or BMP for image export")
    output = _output_path(source, output_value)
    if source.suffix.lower() == ".svg":
        raise ValueError("SVG files are view-only for now; open or export a bitmap image instead")

    markup = validate_payload(options.get("markup", {"version": 1, "kind": "image"}))
    if markup["kind"] != "image":
        raise ValueError("Image export requires image markup")

    try:
        with Image.open(source) as source_image:
            if getattr(source_image, "n_frames", 1) > 1:
                source_image.seek(0)
            image = ImageOps.exif_transpose(source_image).copy().convert("RGBA")
    except (OSError, ValueError, Image.DecompressionBombError) as error:
        raise ValueError(f"Could not decode this image for export: {error}") from error

    if image.width * image.height > MAX_IMAGE_PIXELS:
        raise ValueError("This image is too large to export in Preview (limit: 100 megapixels)")

    _draw_image_markup(image, markup["annotations"])

    crop = options.get("crop")
    if crop:
        if not isinstance(crop, dict):
            raise ValueError("Crop selection is invalid")
        x = _normalized(crop.get("x"), "Crop x")
        y = _normalized(crop.get("y"), "Crop y")
        crop_width = _normalized(crop.get("width"), "Crop width")
        crop_height = _normalized(crop.get("height"), "Crop height")
        left = max(0, min(image.width - 1, round(x * image.width)))
        top = max(0, min(image.height - 1, round(y * image.height)))
        right = max(left + 1, min(image.width, round((x + crop_width) * image.width)))
        bottom = max(top + 1, min(image.height, round((y + crop_height) * image.height)))
        image = image.crop((left, top, right, bottom))

    rotation = options.get("rotation", 0)
    if isinstance(rotation, bool) or rotation not in (0, 90, 180, 270):
        raise ValueError("Image rotation must be a multiple of 90 degrees")
    if rotation:
        image = image.rotate(-rotation, expand=True)

    target_width = _size_option(options.get("width"), "Width")
    target_height = _size_option(options.get("height"), "Height")
    if target_width or target_height:
        if options.get("preserve_aspect", True):
            bounds = (target_width or MAX_IMAGE_DIMENSION, target_height or MAX_IMAGE_DIMENSION)
            image.thumbnail(bounds, Image.Resampling.LANCZOS)
        else:
            image = image.resize(
                (target_width or image.width, target_height or image.height),
                Image.Resampling.LANCZOS,
            )
    if image.width * image.height > MAX_IMAGE_PIXELS:
        raise ValueError("The requested output exceeds the 100 megapixel limit")

    quality = options.get("quality", 92)
    if isinstance(quality, bool) or not isinstance(quality, int) or quality < 1 or quality > 100:
        raise ValueError("Image quality must be between 1 and 100")

    if image_format in {"JPEG", "BMP"}:
        if image.mode in {"RGBA", "LA"} or "transparency" in image.info:
            rgba = image.convert("RGBA")
            flattened = Image.new("RGB", rgba.size, "white")
            flattened.paste(rgba, mask=rgba.getchannel("A"))
            image = flattened
        else:
            image = image.convert("RGB")
    elif image_format == "PNG" and image.mode not in {"RGB", "RGBA", "L", "LA", "P"}:
        image = image.convert("RGBA")
    elif image_format == "WEBP" and image.mode not in {"RGB", "RGBA"}:
        image = image.convert("RGBA")

    save_options: dict[str, Any] = {}
    if image_format in {"JPEG", "WEBP"}:
        save_options["quality"] = quality
    if image_format == "JPEG":
        save_options.update(optimize=True, progressive=True)
    elif image_format == "PNG":
        save_options["optimize"] = True
    elif image_format == "WEBP":
        save_options["method"] = 6
    elif image_format == "TIFF":
        save_options["compression"] = "tiff_deflate"

    _atomic_save(output, lambda stream: image.save(stream, format=image_format, **save_options))
    return {"ok": True, "path": str(output), "width": image.width, "height": image.height}


def _reportlab_stack():
    try:
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        from reportlab.pdfgen import canvas
    except ImportError as error:
        raise ValueError("PDF export needs ReportLab. Install the python-reportlab package.") from error
    return pdfmetrics, TTFont, canvas


def _draw_pdf_markup(
    canvas,
    width: float,
    height: float,
    annotations: list[dict[str, Any]],
    origin_x: float = 0,
    origin_y: float = 0,
) -> None:
    pdfmetrics, TTFont, _ = _reportlab_stack()
    font_path = _font_path()
    font_name = "Helvetica"
    if font_path:
        font_name = "PhasorPreviewUnicode"
        try:
            pdfmetrics.getFont(font_name)
        except KeyError:
            pdfmetrics.registerFont(TTFont(font_name, str(font_path)))
    unit = min(width, height)
    for mark in annotations:
        rgb, alpha = _color(mark["color"])
        red, green, blue = _rgb01(rgb)
        line_width = max(0.75, mark.get("width", 0.006) * unit)
        if mark["type"] in {"stroke", "signature"}:
            points = [
                (origin_x + x * width, origin_y + height - y * height)
                for x, y in mark["points"]
            ]
            canvas.saveState()
            canvas.setStrokeColorRGB(red, green, blue)
            canvas.setLineWidth(line_width)
            canvas.setLineCap(1)
            canvas.setLineJoin(1)
            canvas.setStrokeAlpha(alpha)
            if len(points) == 1:
                canvas.setFillColorRGB(red, green, blue)
                canvas.setFillAlpha(alpha)
                canvas.circle(points[0][0], points[0][1], line_width / 2, stroke=0, fill=1)
            else:
                path = canvas.beginPath()
                path.moveTo(*points[0])
                for point in points[1:]:
                    path.lineTo(*point)
                canvas.drawPath(path, stroke=1, fill=0)
            canvas.restoreState()
        elif mark["type"] in {"rectangle", "highlight"}:
            left = origin_x + min(mark["x1"], mark["x2"]) * width
            bottom = origin_y + height - max(mark["y1"], mark["y2"]) * height
            rect_width = abs(mark["x2"] - mark["x1"]) * width
            rect_height = abs(mark["y2"] - mark["y1"]) * height
            canvas.saveState()
            canvas.setStrokeColorRGB(red, green, blue)
            canvas.setFillColorRGB(red, green, blue)
            canvas.setLineWidth(line_width)
            canvas.setStrokeAlpha(alpha)
            if mark["type"] == "highlight":
                canvas.setFillAlpha(alpha * 0.28)
                canvas.rect(left, bottom, rect_width, rect_height, stroke=0, fill=1)
            else:
                canvas.rect(left, bottom, rect_width, rect_height, stroke=1, fill=0)
            canvas.restoreState()
        elif mark["type"] == "text" and mark["text"]:
            font_size = max(6, mark.get("size", 0.038) * unit)
            canvas.saveState()
            canvas.setFillColorRGB(red, green, blue)
            canvas.setFillAlpha(alpha)
            canvas.setFont(font_name, font_size)
            try:
                canvas.drawString(
                    origin_x + mark["x"] * width,
                    origin_y + height - mark["y"] * height,
                    mark["text"],
                )
            except UnicodeEncodeError as error:
                raise ValueError(
                    "This system has no Unicode font installed. Install DejaVu Sans to export non-Latin text."
                ) from error
            canvas.restoreState()


def _pdf_overlay(page, annotations: list[dict[str, Any]]):
    from pypdf import PdfReader
    from pypdf.generic import RectangleObject

    media_box = page.mediabox
    crop_box = page.cropbox
    width = float(crop_box.width)
    height = float(crop_box.height)
    media_width = float(media_box.width)
    media_height = float(media_box.height)
    if width <= 0 or height <= 0:
        raise ValueError("PDF page has an empty visible area")
    buffer = io.BytesIO()
    pdf_canvas = _reportlab_stack()[2].Canvas(buffer, pagesize=(media_width, media_height), pageCompression=1)
    _draw_pdf_markup(
        pdf_canvas,
        width,
        height,
        annotations,
        origin_x=float(crop_box.left),
        origin_y=float(crop_box.bottom),
    )
    pdf_canvas.save()
    buffer.seek(0)
    overlay_reader = PdfReader(buffer, strict=False)
    overlay_page = overlay_reader.pages[0]
    overlay_page.mediabox = RectangleObject(
        (media_box.left, media_box.bottom, media_box.right, media_box.top)
    )
    overlay_page.cropbox = RectangleObject(
        (crop_box.left, crop_box.bottom, crop_box.right, crop_box.top)
    )
    return overlay_page


def _field_name(annotation: Any) -> str:
    names: list[str] = []
    current = annotation
    seen: set[int] = set()
    while current is not None:
        identity = id(current)
        if identity in seen:
            break
        seen.add(identity)
        name = current.get("/T")
        if name is not None:
            names.append(str(name))
        parent = current.get("/Parent")
        current = parent.get_object() if parent is not None else None
    return ".".join(reversed(names))


def _field_options(field: Any) -> list[dict[str, str]]:
    options: list[dict[str, str]] = []
    for option in field.get("/Opt", []):
        if not isinstance(option, str) and hasattr(option, "__iter__"):
            values = list(option)
            if not values:
                continue
            value = str(values[0])
            label = str(values[1]) if len(values) > 1 else value
        else:
            value = label = str(option)
        options.append({"value": value, "label": label})
    return options


def inspect_pdf_forms(source_value: str) -> dict[str, Any]:
    try:
        from pypdf import PdfReader
    except ImportError as error:
        raise ValueError("PDF forms need pypdf. Install the python-pypdf package.") from error

    source = _source_path(source_value)
    try:
        reader = PdfReader(str(source), strict=False)
        if reader.is_encrypted:
            raise ValueError("Password-protected PDF forms cannot be opened in Preview yet")
        fields = reader.get_fields() or {}
        pages_by_field: dict[str, set[int]] = {}
        widget_states: dict[str, set[str]] = {}
        for page_number, page in enumerate(reader.pages, start=1):
            for reference in page.get("/Annots", []):
                widget = reference.get_object()
                if widget.get("/Subtype") != "/Widget":
                    continue
                name = _field_name(widget)
                if not name:
                    continue
                pages_by_field.setdefault(name, set()).add(page_number)
                appearance = widget.get("/AP", {}).get("/N")
                if appearance is not None:
                    appearance = appearance.get_object()
                    if hasattr(appearance, "keys"):
                        states = widget_states.setdefault(name, set())
                        states.update(str(value) for value in appearance.keys())

        result: list[dict[str, Any]] = []
        for name, field in fields.items():
            field_type = str(field.get("/FT", ""))
            flags = int(field.get("/Ff", 0))
            options = _field_options(field)
            states = field.get("/_States_", [])
            if not states:
                states = sorted(widget_states.get(name, set()))
            states = list(dict.fromkeys(str(value) for value in states))
            if field_type == "/Tx":
                kind = "text"
            elif field_type == "/Ch":
                kind = "multi_choice" if flags & (1 << 21) else "choice"
            elif field_type == "/Btn":
                if flags & (1 << 16):
                    kind = "unsupported"
                elif flags & (1 << 15):
                    kind = "radio"
                    options = [{"value": state, "label": state.removeprefix("/")} for state in states if state != "/Off"]
                else:
                    kind = "checkbox"
                    options = [{"value": state, "label": state.removeprefix("/")} for state in states if state != "/Off"]
            elif field_type == "/Sig":
                kind = "signature"
            else:
                kind = "unsupported"

            raw_value = field.get("/V", "")
            if isinstance(raw_value, (list, tuple)):
                value: str | list[str] = [str(item) for item in raw_value]
            else:
                value = str(raw_value)
            result.append({
                "name": str(name),
                "label": str(field.get("/TU") or name),
                "type": kind,
                "value": value,
                "required": bool(flags & (1 << 1)),
                "read_only": bool(flags & 1),
                "options": options,
                "pages": sorted(pages_by_field.get(name, set())),
            })
        return {"ok": True, "fields": result}
    except ValueError:
        raise
    except Exception as error:
        raise ValueError(f"Could not read PDF form fields: {error}") from error


def _validated_pdf_form_values(reader: Any, values: dict[str, Any]) -> dict[str, Any]:
    if not values:
        return {}
    fields = reader.get_fields() or {}
    unknown = sorted(set(values) - set(fields))
    if unknown:
        raise ValueError(f"The PDF no longer has these form fields: {', '.join(unknown[:5])}")

    normalized: dict[str, Any] = {}
    for name, value in values.items():
        field = fields[name]
        field_type = str(field.get("/FT", ""))
        flags = int(field.get("/Ff", 0))
        if field_type == "/Btn":
            if not isinstance(value, str):
                raise ValueError(f"The value for {name} must be a checkbox or radio option")
            states = field.get("/_States_", [])
            allowed = {str(state) for state in states}
            if not value.startswith("/"):
                value = "/" + value
            if allowed and value not in allowed:
                raise ValueError(f"{value} is not a valid option for {name}")
            normalized[name] = value
        elif field_type == "/Tx":
            if not isinstance(value, str):
                raise ValueError(f"The value for {name} must be text")
            normalized[name] = value
        elif field_type == "/Ch":
            allowed = {option["value"] for option in _field_options(field)}
            if isinstance(value, list):
                if not flags & (1 << 21) or any(not isinstance(item, str) for item in value):
                    raise ValueError(f"The value for {name} must be a single choice")
                if allowed and not set(value).issubset(allowed):
                    raise ValueError(f"The value for {name} contains an unknown choice")
            elif not isinstance(value, str):
                raise ValueError(f"The value for {name} must be a choice")
            elif allowed and value not in allowed:
                raise ValueError(f"{value} is not a valid choice for {name}")
            normalized[name] = value
        else:
            raise ValueError(f"The field {name} cannot be filled by Preview")
    return normalized


def _validated_pdf_order(value: Any, page_count: int) -> list[int]:
    if value is None:
        return list(range(page_count))
    if (
        not isinstance(value, list)
        or not value
        or len(value) > page_count
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
        or any(item < 0 or item >= page_count for item in value)
        or len(set(value)) != len(value)
    ):
        raise ValueError("PDF page order must list one or more unique pages from the source document")
    return value


def export_pdf(source_value: str, output_value: str, options: dict[str, Any]) -> dict[str, Any]:
    try:
        from pypdf import PdfReader, PdfWriter
    except ImportError as error:
        raise ValueError("PDF editing needs pypdf. Install the python-pypdf package.") from error

    source = _source_path(source_value)
    output = _output_path(source, output_value, ".pdf")
    markup = validate_payload(options.get("markup", {"version": 1, "kind": "pdf"}))
    if markup["kind"] != "pdf":
        raise ValueError("PDF export requires PDF markup")

    try:
        reader = PdfReader(str(source), strict=False)
        if reader.is_encrypted:
            raise ValueError("Password-protected PDFs cannot be edited in Preview yet")
        source_page_count = len(reader.pages)
        if source_page_count < 1:
            raise ValueError("The PDF has no pages to export")
        page_order = _validated_pdf_order(markup.get("page_order"), source_page_count)
        rotations = markup.get("page_rotations", {})
        form_values = _validated_pdf_form_values(reader, markup.get("form_values", {}))
        writer = PdfWriter()
        writer.append(reader, pages=page_order)
        if form_values:
            writer.update_page_form_field_values(None, form_values, auto_regenerate=False)

        source_to_output = {source_index: output_index for output_index, source_index in enumerate(page_order)}
        for source_index, output_index in source_to_output.items():
            page = writer.pages[output_index]
            if page.rotation:
                page.transfer_rotation_to_content()
            annotations = markup["pages"].get(str(source_index), [])
            if annotations:
                page.merge_page(_pdf_overlay(page, annotations), over=True)
            rotation = rotations.get(str(source_index), 0)
            if rotation:
                page.rotate(rotation)

        def write(stream) -> None:
            writer.write(stream)

        _atomic_save(output, write)
    except ValueError:
        raise
    except Exception as error:
        raise ValueError(f"Could not export this PDF: {error}") from error

    return {"ok": True, "path": str(output), "pages": len(page_order)}


def _preview_signing_site_paths() -> list[Path]:
    configured = os.environ.get("PHASOR_PREVIEW_SIGNING_VENV")
    if configured:
        root = Path(configured).expanduser()
    else:
        data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        root = data_home / "phasor-preview" / "signing"
    return sorted((root / "lib").glob("python*/site-packages"), reverse=True)


def _pyhanko_signing_stack():
    try:
        from pyhanko import stamp
        from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
        from pyhanko.sign import fields, signers
    except ImportError:
        for path in _preview_signing_site_paths():
            if path.is_dir() and str(path) not in sys.path:
                sys.path.insert(0, str(path))
        try:
            from pyhanko import stamp
            from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
            from pyhanko.sign import fields, signers
        except ImportError as error:
            raise ValueError(
                "Certificate signing needs pyHanko. Install python-pyhanko, or follow the optional setup in docs/preview.md."
            ) from error
    return stamp, IncrementalPdfFileWriter, fields, signers


def _pdf_has_signatures(reader: Any) -> bool:
    from pypdf.generic import ArrayObject, DictionaryObject

    for field in (reader.get_fields() or {}).values():
        if str(field.get("/FT", "")) != "/Sig":
            continue
        value = field.get("/V")
        if value is None:
            continue
        value = value.get_object() if hasattr(value, "get_object") else value
        if not isinstance(value, DictionaryObject):
            continue
        byte_range = value.get("/ByteRange")
        if isinstance(byte_range, ArrayObject) and len(byte_range) >= 4:
            return True
    return False


def _has_pending_pdf_edits(markup: dict[str, Any], page_count: int) -> bool:
    if any(annotations for annotations in markup.get("pages", {}).values()):
        return True
    if _validated_pdf_order(markup.get("page_order"), page_count) != list(range(page_count)):
        return True
    if any(markup.get("page_rotations", {}).values()):
        return True
    return bool(markup.get("form_values"))


def _signature_box(page: Any, box: Any, viewer_rotation: Any) -> tuple[float, float, float, float]:
    if not isinstance(box, list) or len(box) != 4:
        raise ValueError("Drag on the PDF page to set a signature box")
    left, top, right, bottom = (
        _normalized(value, "Signature box coordinate") for value in box
    )
    if left > right or top > bottom:
        raise ValueError("Signature box corners are invalid")
    if right - left < 0.05 or bottom - top < 0.035:
        raise ValueError("Make the signature box at least 5% of the page width and 3.5% of its height")
    if isinstance(viewer_rotation, bool) or not isinstance(viewer_rotation, int) or viewer_rotation not in {0, 90, 180, 270}:
        raise ValueError("Page rotation must be 0, 90, 180, or 270 degrees")

    crop = page.cropbox
    page_width = float(crop.width)
    page_height = float(crop.height)
    if page_width <= 0 or page_height <= 0:
        raise ValueError("The selected PDF page has no visible area")
    intrinsic_rotation = int(page.get("/Rotate", 0) or 0) % 360
    if intrinsic_rotation not in {0, 90, 180, 270}:
        raise ValueError("This PDF page uses an unsupported rotation")
    rotation = (intrinsic_rotation + viewer_rotation) % 360

    def to_pdf(x: float, y: float) -> tuple[float, float]:
        if rotation == 0:
            normal_x, normal_y = x, 1 - y
        elif rotation == 90:
            normal_x, normal_y = 1 - y, x
        elif rotation == 180:
            normal_x, normal_y = 1 - x, y
        else:
            normal_x, normal_y = y, 1 - x
        return (
            float(crop.left) + normal_x * page_width,
            float(crop.bottom) + normal_y * page_height,
        )

    corners = [
        to_pdf(left, top),
        to_pdf(right, top),
        to_pdf(left, bottom),
        to_pdf(right, bottom),
    ]
    x_values, y_values = zip(*corners)
    result = (min(x_values), min(y_values), max(x_values), max(y_values))
    if result[2] - result[0] < 36 or result[3] - result[1] < 22:
        raise ValueError("Make the signature box at least 36 by 22 PDF points")
    return result


def sign_pdf(
    source_value: str,
    output_value: str,
    certificate_value: str,
    options: dict[str, Any],
    password: str,
) -> dict[str, Any]:
    try:
        from pypdf import PdfReader
    except ImportError as error:
        raise ValueError("PDF signing needs pypdf. Install the python-pypdf package.") from error
    if not isinstance(options, dict):
        raise ValueError("Signature options must be an object")
    if not isinstance(password, str) or len(password) > 4096:
        raise ValueError("The certificate password is invalid or too long")
    source = _source_path(source_value)
    certificate = _source_path(certificate_value)
    output = _output_path(source, output_value, ".pdf")
    if output.resolve() == certificate.resolve():
        raise ValueError("Choose an output file separate from the certificate")
    markup = validate_payload(options.get("markup", {"version": 1, "kind": "pdf"}))
    if markup["kind"] != "pdf":
        raise ValueError("Certificate signing requires a PDF document")

    try:
        source_reader = PdfReader(str(source), strict=False)
        if source_reader.is_encrypted:
            raise ValueError("Password-protected PDFs cannot be signed in Preview yet")
        page_count = len(source_reader.pages)
        if page_count < 1:
            raise ValueError("This PDF has no pages to sign")
        page_index = options.get("page_index")
        if isinstance(page_index, bool) or not isinstance(page_index, int) or not 0 <= page_index < page_count:
            raise ValueError("The selected signature page is no longer available")
        already_signed = _pdf_has_signatures(source_reader)
        pending_edits = _has_pending_pdf_edits(markup, page_count)
        if already_signed and pending_edits:
            raise ValueError(
                "This PDF already has a digital signature. Exporting pending edits would invalidate it; sign an unchanged copy or export the edits separately first."
            )
        box = options.get("box")
        if not isinstance(box, list) or len(box) != 4:
            raise ValueError("Drag on the PDF page to set a signature box")
        normalized_box = [_normalized(value, "Signature box coordinate") for value in box]
        if (
            normalized_box[0] > normalized_box[2]
            or normalized_box[1] > normalized_box[3]
            or normalized_box[2] - normalized_box[0] < 0.05
            or normalized_box[3] - normalized_box[1] < 0.035
        ):
            raise ValueError("Make the signature box large enough to display a certificate signature")
        viewer_rotation = options.get("rotation", 0)
        if isinstance(viewer_rotation, bool) or not isinstance(viewer_rotation, int) or viewer_rotation not in {0, 90, 180, 270}:
            raise ValueError("Page rotation must be 0, 90, 180, or 270 degrees")
    except ValueError:
        raise
    except Exception as error:
        raise ValueError(f"Could not inspect this PDF for signing: {error}") from error

    stamp, IncrementalPdfFileWriter, fields, signers = _pyhanko_signing_stack()
    previous_logging_disable = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    try:
        signer = signers.SimpleSigner.load_pkcs12(
            str(certificate), passphrase=password.encode("utf-8") if password else None
        )
    except Exception as error:
        raise ValueError("Could not open the PKCS#12 certificate. Check the file and password.") from error
    finally:
        logging.disable(previous_logging_disable)
    if signer is None:
        raise ValueError("Could not open the PKCS#12 certificate. Check the file and password.")

    reason = options.get("reason", "")
    location = options.get("location", "")
    if not isinstance(reason, str) or len(reason) > 256:
        raise ValueError("The signing reason must be 256 characters or fewer")
    if not isinstance(location, str) or len(location) > 256:
        raise ValueError("The signing location must be 256 characters or fewer")

    def prepare_and_sign(signature_source: Path, selected_page: int) -> None:
        signature_reader = PdfReader(str(signature_source), strict=False)
        pdf_box = _signature_box(
            signature_reader.pages[selected_page], normalized_box, viewer_rotation
        )
        existing_names = set((signature_reader.get_fields() or {}).keys())
        with signature_source.open("rb") as source_stream:
            writer = IncrementalPdfFileWriter(source_stream)
            field_name = "PhasorSignature"
            suffix = 2
            while field_name in existing_names:
                field_name = f"PhasorSignature{suffix}"
                suffix += 1
            metadata = signers.PdfSignatureMetadata(
                field_name=field_name,
                md_algorithm="sha256",
                reason=reason or None,
                location=location or None,
            )
            signature_writer = signers.PdfSigner(
                metadata,
                signer=signer,
                stamp_style=stamp.TextStampStyle(
                    stamp_text="Digitally signed by %(signer)s\n%(ts)s"
                ),
                new_field_spec=fields.SigFieldSpec(
                    sig_field_name=field_name,
                    on_page=selected_page,
                    box=tuple(round(value) for value in pdf_box),
                ),
            )
            _atomic_save(
                output,
                lambda stream: signature_writer.sign_pdf(writer, output=stream),
            )

    try:
        if pending_edits:
            with tempfile.TemporaryDirectory(prefix="phasor-preview-sign-") as directory:
                prepared = Path(directory) / "prepared.pdf"
                export_pdf(str(source), str(prepared), {"markup": markup})
                prepare_and_sign(prepared, page_index)
        else:
            prepare_and_sign(source, page_index)
    except ValueError:
        raise
    except Exception as error:
        raise ValueError(f"Could not digitally sign this PDF: {error}") from error
    return {"ok": True, "path": str(output), "page": page_index + 1}


def merge_pdfs(source_values: list[str], output_value: str, options: dict[str, Any]) -> dict[str, Any]:
    try:
        from pypdf import PdfReader, PdfWriter
    except ImportError as error:
        raise ValueError("PDF merging needs pypdf. Install the python-pypdf package.") from error

    if not isinstance(source_values, list) or not 2 <= len(source_values) <= 64:
        raise ValueError("Choose between 2 and 64 PDF documents to merge")
    if any(not isinstance(value, str) for value in source_values) or not isinstance(options, dict):
        raise ValueError("Merge paths and options have an invalid format")
    sources = [_source_path(value) for value in source_values]
    if any(source.suffix.lower() != ".pdf" for source in sources):
        raise ValueError("Every merge input must be a PDF document")
    output = _output_path(sources[0], output_value, ".pdf")
    if output.resolve() in {source.resolve() for source in sources}:
        raise ValueError("Choose a new file name so none of the original PDFs are overwritten")

    markup = options.get("markup", {"version": 1, "kind": "pdf"})
    total_pages = 0
    writer = PdfWriter()
    try:
        with tempfile.TemporaryDirectory(prefix="phasor-preview-merge-") as temporary:
            prepared_first = Path(temporary) / "phasor-merge-first.pdf"
            export_pdf(str(sources[0]), str(prepared_first), {"markup": markup})
            with ExitStack() as stack:
                seen_form_names: set[str] = set()
                for document_index, path in enumerate([prepared_first, *sources[1:]], start=1):
                    stream = stack.enter_context(path.open("rb"))
                    reader = PdfReader(stream, strict=False)
                    if reader.is_encrypted:
                        raise ValueError(f"Password-protected PDFs cannot be merged ({path.name})")
                    page_count = len(reader.pages)
                    if page_count < 1:
                        raise ValueError(f"The PDF has no pages to merge ({path.name})")
                    total_pages += page_count
                    if total_pages > 20_000:
                        raise ValueError("Merged PDFs may contain up to 20,000 pages")
                    fields = reader.get_fields() or {}
                    if document_index == 1:
                        seen_form_names.update(str(name) for name in fields)
                    elif fields:
                        stem = re.sub(r"[^A-Za-z0-9_-]+", "_", path.stem).strip("_-")[:64] or "document"
                        prefix = f"{stem}_{document_index}"
                        suffix = 2
                        while prefix in seen_form_names or any(
                            f"{prefix}.{name}" in seen_form_names for name in fields
                        ):
                            prefix = f"{stem}_{document_index}_{suffix}"
                            suffix += 1
                        reader.add_form_topname(prefix)
                        seen_form_names.update(f"{prefix}.{name}" for name in fields)
                    writer.append(reader)

                def write(stream) -> None:
                    writer.write(stream)

                _atomic_save(output, write)
    except ValueError:
        raise
    except Exception as error:
        raise ValueError(f"Could not merge these PDFs: {error}") from error

    return {"ok": True, "path": str(output), "pages": total_pages, "documents": len(sources)}


def list_printers() -> dict[str, Any]:
    if not shutil.which("lp"):
        return {"ok": False, "printers": [], "error": "Printing needs CUPS command-line tools (lp)."}
    lpstat = shutil.which("lpstat")
    if not lpstat:
        return {"ok": True, "printers": [], "default": "", "message": "No printer list command is available."}
    try:
        result = subprocess.run([lpstat, "-p", "-d"], capture_output=True, text=True, timeout=8, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "printers": [], "error": f"Could not query printers: {error}"}
    output = result.stdout + "\n" + result.stderr
    printers = sorted(set(re.findall(r"(?m)^printer\s+(\S+)\s+is\b", output)))
    default_match = re.search(r"(?m)^system default destination:\s*(\S+)\s*$", output)
    default = default_match.group(1) if default_match and default_match.group(1) != "none" else ""
    if result.returncode and not printers:
        return {"ok": False, "printers": [], "default": default, "error": output.strip() or "No printers are configured."}
    return {"ok": True, "printers": printers, "default": default}


def _validated_print_options(options: dict[str, Any]) -> tuple[str, int, str]:
    printer = options.get("printer", "")
    if not isinstance(printer, str) or len(printer) > 256 or (
        printer and not re.fullmatch(r"[A-Za-z0-9_.:-]+(?:/[A-Za-z0-9_.:-]+)?", printer)
    ):
        raise ValueError("The selected printer name is invalid")
    copies = options.get("copies", 1)
    if isinstance(copies, bool) or not isinstance(copies, int) or copies < 1 or copies > 99:
        raise ValueError("Copies must be between 1 and 99")
    page_range = options.get("pages", "")
    if not isinstance(page_range, str) or len(page_range) > 256:
        raise ValueError("The page range is invalid")
    if page_range:
        if not re.fullmatch(r"[0-9]+(?:-[0-9]+)?(?:,[0-9]+(?:-[0-9]+)?)*", page_range):
            raise ValueError("Use page numbers or ranges such as 1-3,5")
        for part in page_range.split(","):
            ends = [int(item) for item in part.split("-")]
            if min(ends) < 1 or max(ends) > 20_000 or (len(ends) == 2 and ends[0] > ends[1]):
                raise ValueError("Page numbers must be valid and ranges must be in ascending order")
    return printer, copies, page_range


def _image_pdf(image_path: Path, output_path: Path) -> None:
    Image, _, _, _ = _optional_image_stack()
    from reportlab.lib.utils import ImageReader

    with Image.open(image_path) as image:
        width, height = image.size
        page_width, page_height = (841.89, 595.28) if width > height else (595.28, 841.89)
        margin = 36
        scale = min((page_width - margin * 2) / width, (page_height - margin * 2) / height)
        draw_width = width * scale
        draw_height = height * scale
        pdf_canvas = _reportlab_stack()[2].Canvas(
            str(output_path), pagesize=(page_width, page_height), pageCompression=1
        )
        pdf_canvas.drawImage(
            ImageReader(image.copy()),
            (page_width - draw_width) / 2,
            (page_height - draw_height) / 2,
            width=draw_width,
            height=draw_height,
            mask="auto",
        )
        pdf_canvas.showPage()
        pdf_canvas.save()


def print_document(source_value: str, options: dict[str, Any]) -> dict[str, Any]:
    source = _source_path(source_value)
    printer, copies, page_range = _validated_print_options(options)
    lp = shutil.which("lp")
    if not lp:
        raise ValueError("Printing needs CUPS command-line tools (lp). Install cups on Arch or cups-client on Fedora.")

    markup = validate_payload(options.get("markup", {"version": 1, "kind": "pdf" if source.suffix.lower() == ".pdf" else "image"}))
    with tempfile.TemporaryDirectory(prefix="phasor-preview-print-") as temporary:
        temporary_root = Path(temporary)
        pdf_path = temporary_root / "phasor-print.pdf"
        if source.suffix.lower() == ".pdf":
            export_pdf(str(source), str(pdf_path), {"markup": markup})
        else:
            if markup["kind"] != "image":
                raise ValueError("Image printing requires image markup")
            image_path = temporary_root / "phasor-print.png"
            export_image(
                str(source),
                str(image_path),
                {
                    "markup": markup,
                    "crop": options.get("crop"),
                    "rotation": options.get("rotation", 0),
                    "quality": 100,
                },
            )
            _image_pdf(image_path, pdf_path)

        command = [lp, "-n", str(copies)]
        if printer:
            command.extend(["-d", printer])
        if page_range:
            command.extend(["-P", page_range])
        command.append(str(pdf_path))
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=60, check=False)
        except subprocess.TimeoutExpired as error:
            raise ValueError("The print service did not respond within 60 seconds") from error
        except OSError as error:
            raise ValueError(f"Could not start the print service: {error}") from error
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "The print service rejected the job"
            raise ValueError(message)
        return {"ok": True, "job": result.stdout.strip(), "printer": printer, "copies": copies}


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 2 and argv[1] == "printers":
            result = list_printers()
        elif len(argv) == 3 and argv[1] == "forms":
            result = inspect_pdf_forms(argv[2])
        elif len(argv) == 4 and argv[1] == "print":
            options = json.loads(argv[3])
            if not isinstance(options, dict):
                raise ValueError("Print options must be an object")
            result = print_document(argv[2], options)
        elif len(argv) == 5 and argv[1] == "merge":
            sources = json.loads(argv[3])
            options = json.loads(argv[4])
            if not isinstance(sources, list) or any(not isinstance(path, str) for path in sources):
                raise ValueError("Merge input paths must be a list of strings")
            if not isinstance(options, dict):
                raise ValueError("Merge options must be an object")
            result = merge_pdfs(sources, argv[2], options)
        elif len(argv) == 5 and argv[1] in {"image", "pdf"}:
            options = json.loads(argv[4])
            if not isinstance(options, dict):
                raise ValueError("Export options must be an object")
            result = export_image(argv[2], argv[3], options) if argv[1] == "image" else export_pdf(argv[2], argv[3], options)
        elif len(argv) == 5 and argv[1] == "sign":
            signing_input = sys.stdin.readline(5 * 1024 * 1024 + 1)
            if not signing_input.endswith("\n") or len(signing_input) > 5 * 1024 * 1024:
                raise ValueError("The signing input is missing or too large")
            payload = json.loads(signing_input)
            if (
                not isinstance(payload, dict)
                or not isinstance(payload.get("password"), str)
                or not isinstance(payload.get("options"), dict)
            ):
                raise ValueError("The signing input is invalid")
            password = payload["password"]
            if len(password) > 4096:
                raise ValueError("The certificate password is too long")
            result = sign_pdf(argv[2], argv[3], argv[4], payload["options"], password)
        else:
            raise ValueError("Usage: document_ops.py printers | forms PDF | print DOCUMENT OPTIONS_JSON | merge OUTPUT SOURCES_JSON OPTIONS_JSON | image|pdf SOURCE OUTPUT OPTIONS_JSON | sign SOURCE OUTPUT CERTIFICATE (signing JSON on stdin)")
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get("ok", True) else 1
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
