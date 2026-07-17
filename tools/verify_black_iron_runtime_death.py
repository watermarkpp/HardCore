#!/usr/bin/env python3
"""Verify all 32 runtime death captures against the matching atlas cells."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from pixel_template_match import find_masked_template


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet_death.png"
SOURCE = ROOT / "assets/art/characters/warrior/wear/helmet/black_iron_helmet.source.json"
POSE_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
CAPTURE_ROOT = ROOT / "outputs/visual_acceptance/player_states"
REPORT = ROOT / "outputs/validation/black_iron_runtime_death_32.json"
VERSION = "v108_death_anchor_20260717"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
EXPECTED_YAWS = [180.0, 135.0, 90.0, 45.0, 0.0, -45.0, -90.0, -135.0]
CELL = (192, 160)


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    baseline = json.loads(POSE_BASELINE.read_text(encoding="utf-8"))
    source_frames = {
        (int(record["direction"]), int(record["frame"])): record
        for record in source["actions"]["death"]["frames"]
    }
    pose_records = {
        (int(record["directionRow"]), int(record["frame"])): record
        for record in baseline["records"]
    }
    if len(source_frames) != 32 or len(pose_records) != 32:
        raise AssertionError("Death provenance is not a complete 8x4 mapping")

    results: list[dict] = []
    for direction, direction_name in enumerate(DIRECTIONS):
        for frame in range(4):
            capture = CAPTURE_ROOT / f"{VERSION}_death_{direction_name.lower()}_f{frame}.png"
            if not capture.exists() or capture.stat().st_mtime_ns <= ATLAS.stat().st_mtime_ns:
                raise AssertionError(f"Missing fresh runtime capture: {direction_name} F{frame}")
            cell = atlas.crop(
                (
                    frame * CELL[0],
                    direction * CELL[1],
                    (frame + 1) * CELL[0],
                    (direction + 1) * CELL[1],
                )
            )
            box = cell.getchannel("A").getbbox()
            if box is None:
                raise AssertionError(f"Death atlas cell is empty: {direction_name} F{frame}")
            template = cell.crop(box)
            template = template.resize((template.width * 3, template.height * 3), Image.Resampling.NEAREST)
            score, location = find_masked_template(Image.open(capture).convert("RGB"), template)
            if score < 0.90:
                raise AssertionError(
                    f"Runtime capture does not contain matching death cell {direction_name} F{frame}: {score:.6f}"
                )
            provenance = source_frames[(direction, frame)]
            pose = pose_records[(direction, frame)]
            godot_pose = pose["recommendedGodotPose"]
            if provenance.get("poseVariant") != "godot-orthographic-complete-helmet":
                raise AssertionError(f"Death pose does not use complete geometry: {direction_name} F{frame}")
            if abs(float(godot_pose["yawDegrees"]) - EXPECTED_YAWS[direction]) > 0.001:
                raise AssertionError(f"Death yaw does not match direction row: {direction_name} F{frame}")
            results.append(
                {
                    "direction": direction_name,
                    "directionRow": direction,
                    "frame": frame,
                    "capture": capture.relative_to(ROOT).as_posix(),
                    "pixelTemplateScore": round(score, 6),
                    "pixelTemplateLocation": list(location),
                    "yawDegrees": godot_pose["yawDegrees"],
                    "fallDegrees": godot_pose["fallDegrees"],
                    "targetScreenDegrees": godot_pose["targetScreenDegrees"],
                }
            )

    payload = {
        "status": "pass",
        "version": VERSION,
        "records": results,
        "mappingRule": baseline["mappingRule"],
        "allCapturesNewerThanAtlas": True,
        "minimumPixelTemplateScore": min(record["pixelTemplateScore"] for record in results),
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BLACK_IRON_RUNTIME_DEATH_PASS "
        f"captures={len(results)} min_score={payload['minimumPixelTemplateScore']:.6f} same_row_same_frame=32"
    )


if __name__ == "__main__":
    main()
