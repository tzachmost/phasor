#!/usr/bin/env python3
"""Export Preview images and PDFs without changing their source files."""

from __future__ import annotations

import io
import json
import math
import os
import sys
import tempfile
import unicodedata
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
        if mark["type"] == "stroke":
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
        if mark["type"] == "stroke":
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
        writer = PdfWriter()
        writer.append(reader, pages=page_order)

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


def main(argv: list[str]) -> int:
    if len(argv) != 5 or argv[1] not in {"image", "pdf"}:
        print(json.dumps({"error": "Usage: document_ops.py image|pdf SOURCE OUTPUT OPTIONS_JSON"}))
        return 2
    try:
        options = json.loads(argv[4])
        if not isinstance(options, dict):
            raise ValueError("Export options must be an object")
        result = export_image(argv[2], argv[3], options) if argv[1] == "image" else export_pdf(argv[2], argv[3], options)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
