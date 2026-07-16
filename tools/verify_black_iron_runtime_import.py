#!/usr/bin/env python3
"""Verify that Godot rendered the current Black Iron Helmet PNG, not stale CTEX."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from pixel_template_match import find_masked_template


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet_idle.png"
SCREENSHOT = ROOT / "outputs/visual_acceptance/player_states/idle_s.png"
REPORT = ROOT / "outputs/validation/black_iron_runtime_import_report.json"


def main() -> None:
    imported = list((ROOT / ".godot/imported").glob("black_iron_helmet_idle.png-*.ctex"))
    if len(imported) != 1:
        raise AssertionError(f"Expected one imported idle CTEX, got {len(imported)}")
    cache_fresh = imported[0].stat().st_mtime_ns >= ATLAS.stat().st_mtime_ns
    if not cache_fresh:
        raise AssertionError("Godot CTEX is older than the current helmet PNG; run Godot --headless --import")

    atlas = Image.open(ATLAS).convert("RGBA")
    screenshot = Image.open(SCREENSHOT).convert("RGB")
    cell = atlas.crop((0, 4 * 160, 192, 5 * 160))
    box = cell.getchannel("A").getbbox()
    if box is None:
        raise AssertionError("South idle helmet cell is empty")
    template = cell.crop(box)
    template = template.resize((template.width * 3, template.height * 3), Image.Resampling.NEAREST)
    score, location = find_masked_template(screenshot, template)
    if score < 0.90:
        raise AssertionError(f"Runtime screenshot does not contain the current helmet pixels: score={score:.6f}")
    template_pixels = template.load()
    visible_pixels = [
        template_pixels[x, y][:3]
        for y in range(template.height)
        for x in range(template.width)
        if template_pixels[x, y][3] >= 128
    ]
    mean_rgb = [sum(pixel[channel] for pixel in visible_pixels) / len(visible_pixels) for channel in range(3)]
    if sum(mean_rgb) / 3.0 >= 120 or max(mean_rgb) - min(mean_rgb) >= 18:
        raise AssertionError(f"Runtime helmet is not dark neutral metal: mean_rgb={mean_rgb}")

    payload = {
        "status": "pass",
        "cacheFresh": True,
        "pixelTemplateScore": round(float(score), 6),
        "pixelTemplateLocation": list(location),
        "visibleMeanRgb": [round(value, 1) for value in mean_rgb],
        "atlas": ATLAS.relative_to(ROOT).as_posix(),
        "importedCtex": imported[0].relative_to(ROOT).as_posix(),
        "screenshot": SCREENSHOT.relative_to(ROOT).as_posix(),
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BLACK_IRON_RUNTIME_IMPORT_PASS "
        f"cache_fresh=1 pixel_score={score:.6f} mean_rgb={payload['visibleMeanRgb']}"
    )


if __name__ == "__main__":
    main()
