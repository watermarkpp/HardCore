#!/usr/bin/env python3
"""Prove that fresh Godot captures contain every current idle helmet row."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from pixel_template_match import find_masked_template


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet_idle.png"
SOURCE = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet.source.json"
CAPTURE_ROOT = ROOT / "outputs/visual_acceptance/player_states"
REPORT = ROOT / "outputs/validation/black_iron_runtime_directions_v100_godot3d.json"
VERSION = "v100_godot3d_20260717"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
CELL = (192, 160)


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    accepted_rows = source.get("approvedDirectionReferences", {}).get("acceptedRowMapping", [])
    if accepted_rows != DIRECTIONS:
        raise AssertionError("Godot direction rows are not canonical N..NW order")

    source_frames = source["actions"]["idle"]["frames"]
    results = []
    for direction_index, direction in enumerate(DIRECTIONS):
        capture = CAPTURE_ROOT / f"{VERSION}_idle_{direction.lower()}.png"
        if not capture.exists():
            raise FileNotFoundError(capture)
        if capture.stat().st_mtime_ns <= ATLAS.stat().st_mtime_ns:
            raise AssertionError(f"{direction} capture predates the current atlas")

        cell = atlas.crop((0, direction_index * CELL[1], CELL[0], (direction_index + 1) * CELL[1]))
        box = cell.getchannel("A").getbbox()
        if box is None:
            raise AssertionError(f"{direction} idle row is empty")
        template = cell.crop(box)
        template = template.resize((template.width * 3, template.height * 3), Image.Resampling.NEAREST)
        screenshot = Image.open(capture).convert("RGB")
        score, location = find_masked_template(screenshot, template)
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
                "canonicalYawExplicit": True,
            }
        )

    payload = {
        "status": "pass",
        "version": VERSION,
        "runtimeEnvelopeScale": source["generation"]["runtimeEnvelopeScale"],
        "allCanonicalYawsExplicit": True,
        "allCapturesNewerThanAtlas": True,
        "directions": results,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    scores = [record["pixelTemplateScore"] for record in results]
    print(
        "BLACK_IRON_RUNTIME_DIRECTIONS_PASS "
        f"fresh_unique_captures=8 scale={payload['runtimeEnvelopeScale']:.4f} "
        f"min_score={min(scores):.6f} godot_canonical_yaws=8"
    )


if __name__ == "__main__":
    main()
