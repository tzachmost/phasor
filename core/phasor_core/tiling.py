"""Validated, compositor-independent preferences for window arrangement."""

from __future__ import annotations

import math
from typing import Any

LAYOUTS = ("grid", "tile", "center_tile", "vertical_tile", "scroller", "vertical_scroller", "monocle", "deck")
# preference: (native key, default, minimum, maximum); booleans have no range.
FIELDS = {
    "innerHorizontal": ("gappih", 8, 0, 100),
    "innerVertical": ("gappiv", 8, 0, 100),
    "outerHorizontal": ("gappoh", 10, 0, 100),
    "outerVertical": ("gappov", 10, 0, 100),
    "smartGaps": ("smartgaps", False, None, None),
    "borderWidth": ("borderpx", 2, 0, 12),
    "hideSingleBorder": ("no_border_when_single", False, None, None),
    "masterCount": ("default_nmaster", 1, 1, 10),
    "masterRatio": ("default_mfact", 0.55, 0.1, 0.9),
    "newIsMaster": ("new_is_master", True, None, None),
    "scrollerWidth": ("scroller_default_proportion", 0.8, 0.1, 1.0),
    "centerScroller": ("scroller_focus_center", False, None, None),
    "preferCenter": ("scroller_prefer_center", False, None, None),
    "smartSplit": ("dwindle_smart_split", False, None, None),
    "preserveSplit": ("dwindle_preserve_split", False, None, None),
}


def defaults() -> dict[str, Any]:
    return {"layout": "grid", **{name: spec[1] for name, spec in FIELDS.items()}}


def validate(value: Any) -> None:
    if not isinstance(value, dict):
        raise ValueError("tiling must be a JSON object")
    unknown = set(value) - {"layout", *FIELDS}
    if unknown:
        raise ValueError("Unknown tiling settings: " + ", ".join(sorted(unknown)))
    if value.get("layout", "grid") not in LAYOUTS:
        raise ValueError("tiling.layout must be one of: " + ", ".join(LAYOUTS))
    for name, (_, default, low, high) in FIELDS.items():
        actual = value.get(name, default)
        if isinstance(default, bool):
            valid = isinstance(actual, bool)
        elif isinstance(default, int):
            valid = type(actual) is int and low <= actual <= high
        else:
            valid = type(actual) in (int, float) and math.isfinite(actual) and low <= actual <= high
        if not valid:
            raise ValueError(f"tiling.{name} must be " + ("a boolean" if low is None else f"between {low} and {high}"))


def config_lines(value: dict[str, Any]) -> list[str]:
    validate(value)
    settings = {**defaults(), **value}
    lines = []
    for name, (key, default, _, _) in FIELDS.items():
        native = int(settings[name]) if isinstance(default, bool) else settings[name]
        lines.append(f"{key}={native}")
    lines.append(f"tagrule=id:*,layout_name:{settings['layout']},nmaster:{settings['masterCount']},mfact:{settings['masterRatio']}")
    return lines
