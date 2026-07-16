#!/usr/bin/env python3
"""Verify that Godot rendered the current Black Iron Helmet PNG, not stale CTEX."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


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

    atlas = np.array(Image.open(ATLAS).convert("RGBA"))
    screenshot = np.array(Image.open(SCREENSHOT).convert("RGB"))
    cell = atlas[4 * 160 : 5 * 160, 0:192]
    alpha = cell[:, :, 3]
    ys, xs = np.where(alpha > 0)
    template = cell[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    template_rgb = cv2.resize(template[:, :, :3], None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
    template_mask = cv2.resize(template[:, :, 3], None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
    match = cv2.matchTemplate(screenshot, template_rgb, cv2.TM_CCORR_NORMED, mask=template_mask)
    _, score, _, location = cv2.minMaxLoc(match)
    if score < 0.90:
        raise AssertionError(f"Runtime screenshot does not contain the current helmet pixels: score={score:.6f}")
    visible_pixels = template[template[:, :, 3] > 0][:, :3]
    mean_rgb = visible_pixels.mean(axis=0)
    if float(mean_rgb.mean()) >= 120 or float(mean_rgb.max() - mean_rgb.min()) >= 18:
        raise AssertionError(f"Runtime helmet is not dark neutral metal: mean_rgb={mean_rgb.tolist()}")

    payload = {
        "status": "pass",
        "cacheFresh": True,
        "pixelTemplateScore": round(float(score), 6),
        "pixelTemplateLocation": list(location),
        "visibleMeanRgb": [round(float(value), 1) for value in mean_rgb],
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
