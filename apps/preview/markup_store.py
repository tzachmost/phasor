#!/usr/bin/env python3
"""Load and save editable Phasor Preview markup sidecars."""

from __future__ import annotations

import json
import math
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


MAX_SIDECAR_BYTES = 4 * 1024 * 1024
MAX_ANNOTATIONS = 2000
MAX_POINTS_PER_STROKE = 6000
COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$")


def _source_path(value: str) -> Path:
    path = Path(value).expanduser().absolute()
    if not path.is_file():
        raise ValueError("The document file does not exist or is not a regular file")
    return path


def _sidecar_path(source: Path) -> Path:
    return source.with_name(source.name + ".phasor-markup.json")


def _coordinate(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Markup coordinates must be numbers")
    result = float(value)
    if not math.isfinite(result) or result < 0 or result > 1:
        raise ValueError("Markup coordinates must be between zero and one")
    return result


def _validate_annotation(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("Each markup item must be an object")
    kind = value.get("type")
    color = value.get("color", "#8bd5ca")
    if kind not in {
        "stroke", "signature", "rectangle", "highlight", "text",
        "text_highlight", "underline", "strike", "note",
    }:
        raise ValueError("Unsupported markup type")
    if not isinstance(color, str) or not COLOR_RE.fullmatch(color):
        raise ValueError("Markup color must be a hex color")

    result: dict[str, Any] = {"type": kind, "color": color}
    if kind in {"stroke", "signature"}:
        points = value.get("points")
        if not isinstance(points, list) or not points or len(points) > MAX_POINTS_PER_STROKE:
            raise ValueError("A pen stroke must contain between one and 6000 points")
        normalized_points: list[list[float]] = []
        for point in points:
            if not isinstance(point, list) or len(point) != 2:
                raise ValueError("A pen point must contain two coordinates")
            normalized_points.append([_coordinate(point[0]), _coordinate(point[1])])
        result["points"] = normalized_points
        result["width"] = _width(value.get("width", 0.006))
    elif kind in {"rectangle", "highlight"}:
        result.update({
            "x1": _coordinate(value.get("x1")),
            "y1": _coordinate(value.get("y1")),
            "x2": _coordinate(value.get("x2")),
            "y2": _coordinate(value.get("y2")),
            "width": _width(value.get("width", 0.006)),
        })
    elif kind == "text":
        text = value.get("text")
        if not isinstance(text, str) or len(text) > 4096:
            raise ValueError("Markup text must be a string up to 4096 characters")
        result.update({
            "x": _coordinate(value.get("x")),
            "y": _coordinate(value.get("y")),
            "text": text,
            "size": _width(value.get("size", 0.038), maximum=0.2),
        })
    else:
        quote = value.get("quote")
        if not isinstance(quote, str) or not quote.strip() or len(quote) > 4096:
            raise ValueError("A text annotation must include a selected quote up to 4096 characters")
        rects = value.get("rects")
        if not isinstance(rects, list) or not rects or len(rects) > 256:
            raise ValueError("A text annotation must include between one and 256 selection rectangles")
        normalized_rects: list[list[float]] = []
        for rect in rects:
            if not isinstance(rect, list) or len(rect) != 4:
                raise ValueError("A selection rectangle must contain four coordinates")
            x1, y1, x2, y2 = (_coordinate(coordinate) for coordinate in rect)
            if x2 <= x1 or y2 <= y1:
                raise ValueError("A selection rectangle must have a positive width and height")
            normalized_rects.append([x1, y1, x2, y2])
        result.update({"quote": quote, "rects": normalized_rects})
        if kind == "note":
            note = value.get("note")
            if not isinstance(note, str) or not note.strip() or len(note) > 4096:
                raise ValueError("A note annotation must contain text up to 4096 characters")
            result["note"] = note
    return result


def _width(value: Any, maximum: float = 0.05) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Markup size must be a number")
    result = float(value)
    if not math.isfinite(result) or result <= 0 or result > maximum:
        raise ValueError("Markup size is outside the supported range")
    return result


def validate_payload(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("version") != 1:
        raise ValueError("Unsupported Preview markup file")
    kind = value.get("kind")
    if kind == "image":
        annotations = value.get("annotations", [])
        if not isinstance(annotations, list) or len(annotations) > MAX_ANNOTATIONS:
            raise ValueError("Image markup has too many annotations")
        validated = [_validate_annotation(item) for item in annotations]
        if any(item["type"] in {"text_highlight", "underline", "strike", "note"} for item in validated):
            raise ValueError("Text-anchored annotations are supported only for PDF markup")
        return {"version": 1, "kind": "image", "annotations": validated}
    if kind == "pdf":
        pages = value.get("pages", {})
        if not isinstance(pages, dict) or len(pages) > 20000:
            raise ValueError("PDF markup has an invalid page map")
        normalized: dict[str, list[dict[str, Any]]] = {}
        total = 0
        for page, annotations in pages.items():
            if not isinstance(page, str) or not page.isdigit():
                raise ValueError("PDF markup page ids must be non-negative integers")
            if not isinstance(annotations, list):
                raise ValueError("PDF page markup must be a list")
            total += len(annotations)
            if total > MAX_ANNOTATIONS:
                raise ValueError("PDF markup has too many annotations")
            normalized[str(int(page))] = [_validate_annotation(item) for item in annotations]
        result: dict[str, Any] = {"version": 1, "kind": "pdf", "pages": normalized}
        page_order = value.get("page_order")
        if page_order is not None:
            if (
                not isinstance(page_order, list)
                or not page_order
                or len(page_order) > 20000
                or any(isinstance(page, bool) or not isinstance(page, int) for page in page_order)
                or any(page < 0 or page >= 20000 for page in page_order)
                or len(set(page_order)) != len(page_order)
            ):
                raise ValueError("PDF page order must contain unique non-negative page ids")
            result["page_order"] = page_order

        page_rotations = value.get("page_rotations")
        if page_rotations is not None:
            if not isinstance(page_rotations, dict) or len(page_rotations) > 20000:
                raise ValueError("PDF page rotations must be a page map")
            rotations: dict[str, int] = {}
            for page, rotation in page_rotations.items():
                if not isinstance(page, str) or not page.isdigit():
                    raise ValueError("PDF rotation page ids must be non-negative integers")
                if isinstance(rotation, bool) or not isinstance(rotation, int) or rotation not in {0, 90, 180, 270}:
                    raise ValueError("PDF page rotations must be 0, 90, 180, or 270 degrees")
                rotations[str(int(page))] = rotation
            result["page_rotations"] = rotations
        form_values = value.get("form_values")
        if form_values is not None:
            if not isinstance(form_values, dict) or len(form_values) > MAX_ANNOTATIONS:
                raise ValueError("PDF form values must be a field map")
            normalized_values: dict[str, str | list[str]] = {}
            for name, field_value in form_values.items():
                if not isinstance(name, str) or not name or len(name) > 512:
                    raise ValueError("PDF form field names must be non-empty strings up to 512 characters")
                if isinstance(field_value, str) and len(field_value) <= 4096:
                    normalized_values[name] = field_value
                elif (
                    isinstance(field_value, list)
                    and len(field_value) <= 256
                    and all(isinstance(item, str) and len(item) <= 4096 for item in field_value)
                ):
                    normalized_values[name] = field_value
                else:
                    raise ValueError("PDF form values must be strings or lists of strings up to 4096 characters")
            result["form_values"] = normalized_values
        return result
    raise ValueError("Markup kind must be image or pdf")


def load_markup(path: str) -> dict[str, Any]:
    sidecar = _sidecar_path(_source_path(path))
    if not sidecar.exists():
        return {"version": 1, "kind": "image", "annotations": []}
    if sidecar.stat().st_size > MAX_SIDECAR_BYTES:
        raise ValueError("The Preview markup file exceeds the 4 MiB limit")
    try:
        payload = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not read the Preview markup file: {error}") from error
    return validate_payload(payload)


def save_markup(path: str, payload_text: str) -> dict[str, Any]:
    source = _source_path(path)
    if len(payload_text.encode("utf-8")) > MAX_SIDECAR_BYTES:
        raise ValueError("The Preview markup data exceeds the 4 MiB limit")
    try:
        payload = validate_payload(json.loads(payload_text))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Invalid Preview markup data: {error}") from error

    sidecar = _sidecar_path(source)
    encoded = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    file_descriptor, temporary = tempfile.mkstemp(prefix=".phasor-preview-", suffix=".tmp", dir=sidecar.parent)
    try:
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, sidecar)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    return {"ok": True, "sidecar": str(sidecar)}


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"load", "save"}:
        print(json.dumps({"error": "Usage: markup_store.py load|save DOCUMENT [JSON]"}))
        return 2
    try:
        if argv[1] == "load":
            result = load_markup(argv[2])
        else:
            if len(argv) != 4:
                raise ValueError("Save requires one JSON markup argument")
            result = save_markup(argv[2], argv[3])
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
