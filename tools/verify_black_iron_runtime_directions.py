#!/usr/bin/env python3
"""Prove that fresh Godot captures contain every current idle helmet row."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet_idle.png"
SOURCE = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet.source.json"
MANIFEST = ROOT / "dev_art_sources/reference/generated/black_iron_helmet/canonical_directions/manifest.json"
CAPTURE_ROOT = ROOT / "outputs/visual_acceptance/player_states"
REPORT = ROOT / "outputs/validation/black_iron_runtime_directions_v07225_w_flipped.json"
VERSION = "v07225_w_flipped_20260715b"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
CELL = (192, 160)


def main() -> None:
    atlas = np.array(Image.open(ATLAS).convert("RGBA"))
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    records = {record["direction"]: record for record in manifest["records"]}
    if not records["W"]["horizontalFlipApplied"]:
        raise AssertionError("W is missing the runtime-confirmed horizontal flip")

    source_frames = source["actions"]["idle"]["frames"]
    results = []
    for direction_index, direction in enumerate(DIRECTIONS):
        capture = CAPTURE_ROOT / f"{VERSION}_idle_{direction.lower()}.png"
        if not capture.exists():
            raise FileNotFoundError(capture)
        if capture.stat().st_mtime_ns <= ATLAS.stat().st_mtime_ns:
            raise AssertionError(f"{direction} capture predates the current atlas")

        cell = atlas[direction_index * CELL[1] : (direction_index + 1) * CELL[1], : CELL[0]]
        ys, xs = np.where(cell[:, :, 3] > 0)
        if not len(xs):
            raise AssertionError(f"{direction} idle row is empty")
        template = cell[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
        template_rgb = cv2.resize(template[:, :, :3], None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
        template_mask = cv2.resize(template[:, :, 3], None, fx=3, fy=3, interpolation=cv2.INTER_NEAREST)
        screenshot = np.array(Image.open(capture).convert("RGB"))
        match = cv2.matchTemplate(screenshot, template_rgb, cv2.TM_CCORR_NORMED, mask=template_mask)
        _, score, _, location = cv2.minMaxLoc(match)
        if score < 0.90:
            raise AssertionError(f"{direction} fresh Godot capture does not contain the current row: {score:.6f}")

        provenance = next(frame for frame in source_frames if frame["direction"] == direction_index and frame["frame"] == 0)
        results.append(
            {
                "direction": direction,
                "capture": capture.relative_to(ROOT).as_posix(),
                "captureMtimeNs": capture.stat().st_mtime_ns,
                "currentAtlasTemplateSize": provenance["generatedSize"],
                "pixelTemplateScore": round(float(score), 6),
                "pixelTemplateLocation": list(location),
                "horizontalFlipApplied": bool(records[direction]["horizontalFlipApplied"]),
            }
        )

    payload = {
        "status": "pass",
        "version": VERSION,
        "runtimeEnvelopeScale": source["generation"]["runtimeEnvelopeScale"],
        "wRuntimeMirrorApplied": records["W"]["horizontalFlipApplied"],
        "allCapturesNewerThanAtlas": True,
        "directions": results,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    scores = [record["pixelTemplateScore"] for record in results]
    print(
        "BLACK_IRON_RUNTIME_DIRECTIONS_PASS "
        f"fresh_unique_captures=8 scale={payload['runtimeEnvelopeScale']:.4f} "
        f"min_score={min(scores):.6f} w_runtime_flip=1"
    )


if __name__ == "__main__":
    main()
