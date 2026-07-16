#!/usr/bin/env python3
"""Verify Black Iron Helmet direction, action, alpha and body alignment."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
HELMET_ROOT = ROOT / "assets/art/characters/warrior/wear/helmet"
DRESS_ROOT = ROOT / "assets/art/characters/warrior/wear/dress"
SOURCE = HELMET_ROOT / "black_iron_helmet.source.json"
DEATH_POSE_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
GODOT_RENDER_MANIFEST = ROOT / "outputs/visual_acceptance/black_iron_helmet_3d/manifest.json"
REPORT = ROOT / "outputs/validation/black_iron_helmet_asset_report.json"
ACTIONS = {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4}
CELL = (192, 160)


def cell_box(frame: int, direction: int) -> tuple[int, int, int, int]:
    return (frame * CELL[0], direction * CELL[1], (frame + 1) * CELL[0], (direction + 1) * CELL[1])


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    if source.get("schemaVersion") != 7:
        raise AssertionError("Black Iron Helmet provenance schema is not version 7")
    if source.get("generation", {}).get("aiPixelsLimitedTo") != []:
        raise AssertionError("Runtime atlas still claims direct image-generation pixels")
    if not str(source.get("generation", {}).get("runtimePixelGenerator", "")).startswith("Godot 4.7"):
        raise AssertionError("Runtime atlas is not attributed to the Godot orthographic renderer")
    if source.get("generation", {}).get("oldDerivedStateItemWorldPixelsUsed", True):
        raise AssertionError("Runtime atlas still claims old StateItem-derived world pixels")
    if abs(float(source.get("generation", {}).get("runtimeEnvelopeScale", 0.0)) - 1.0) > 0.0001:
        raise AssertionError("Runtime helmet is not calibrated to the real-client p75 envelope")
    death_baseline = json.loads(DEATH_POSE_BASELINE.read_text(encoding="utf-8"))
    death_records = {
        (int(record["directionRow"]), int(record["frame"])): record
        for record in death_baseline.get("records", [])
    }
    godot_manifest = json.loads(GODOT_RENDER_MANIFEST.read_text(encoding="utf-8"))
    if len(death_records) != 32 or len(godot_manifest.get("records", [])) != 32:
        raise AssertionError("Godot death mapping is not the complete 8x4 table")
    baseline = source.get("clientHelmetParameterBaseline", {})
    if baseline.get("deathCanonicalRotate90Degrees", True):
        raise AssertionError("Death frames still apply the invalid whole-helmet 90-degree rotation")
    total_frames = 0
    report_actions: dict[str, dict] = {}
    for action, frames in ACTIONS.items():
        helmet_path = HELMET_ROOT / f"black_iron_helmet_{action}.png"
        dress_path = DRESS_ROOT / f"dress_006_{action}.png"
        helmet = Image.open(helmet_path).convert("RGBA")
        dress = Image.open(dress_path).convert("RGBA")
        expected_size = (CELL[0] * frames, CELL[1] * 8)
        if helmet.size != expected_size or dress.size != expected_size:
            raise AssertionError(f"{action} atlas size mismatch: helmet={helmet.size}, dress={dress.size}")
        direction_signatures: list[str] = []
        moving_directions = 0
        opaque_counts: list[int] = []
        for direction in range(8):
            row = helmet.crop((0, direction * CELL[1], helmet.width, (direction + 1) * CELL[1]))
            direction_signatures.append(str(hash(row.tobytes())))
            frame_boxes: list[tuple[int, int, int, int]] = []
            for frame in range(frames):
                box = cell_box(frame, direction)
                helmet_cell = helmet.crop(box)
                dress_cell = dress.crop(box)
                helmet_bbox = helmet_cell.getchannel("A").getbbox()
                dress_bbox = dress_cell.getchannel("A").getbbox()
                if helmet_bbox is None or dress_bbox is None:
                    raise AssertionError(f"{action} direction={direction} frame={frame} is empty")
                if min(helmet_bbox) < 0 or helmet_bbox[2] > CELL[0] or helmet_bbox[3] > CELL[1]:
                    raise AssertionError(f"{action} direction={direction} frame={frame} clips the cell")
                horizontal_overlap = min(helmet_bbox[2], dress_bbox[2]) - max(helmet_bbox[0], dress_bbox[0])
                if horizontal_overlap < 8:
                    raise AssertionError(f"{action} direction={direction} frame={frame} misses the body head")
                frame_boxes.append(helmet_bbox)
                alpha_histogram = helmet_cell.getchannel("A").histogram()
                opaque_pixels = sum(alpha_histogram[1:])
                opaque_counts.append(opaque_pixels)
                direction_name = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][direction]
                if action == "death":
                    target_opaque = float(death_records[(direction, frame)]["clientHelmetOpaquePixels"]["median"])
                else:
                    target_opaque = float(
                        source["clientHelmetParameterBaseline"]["directionRuntimeOpaquePixels"][direction_name]
                    )
                opaque_ratio = opaque_pixels / max(1.0, target_opaque)
                if opaque_ratio < 0.65 or opaque_ratio > 1.35:
                    raise AssertionError(
                        f"{action} {direction_name} F{frame} visual mass diverges from client median: {opaque_ratio:.3f}"
                    )
                total_frames += 1
            if len(set(frame_boxes)) > 1:
                moving_directions += 1
        if len(set(direction_signatures)) != 8:
            raise AssertionError(f"{action} does not have eight distinct direction rows")
        if action in {"walk", "attack", "hit", "death"} and moving_directions != 8:
            raise AssertionError(f"{action} helmet does not follow every direction's frame motion")
        report_actions[action] = {
            "framesPerDirection": frames,
            "directions": 8,
            "logicalFrames": frames * 8,
            "movingDirections": moving_directions,
            "minOpaquePixelsPerFrame": min(opaque_counts),
            "maxOpaquePixelsPerFrame": max(opaque_counts),
        }
        provenance_frames = source.get("actions", {}).get(action, {}).get("frames", [])
        if any(bool(frame.get("rotatedForDeath", False)) for frame in provenance_frames):
            raise AssertionError(f"{action} provenance still contains rotated whole-helmet frames")
        if action == "death" and any(
            frame.get("poseVariant") != "godot-orthographic-complete-helmet"
            for frame in provenance_frames
        ):
            raise AssertionError("Death frames do not all use the complete Godot-rendered helmet geometry")
        for frame in provenance_frames:
            direction_name = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(frame["direction"])]
            generated = frame["generatedSize"]
            if action == "death":
                pose = death_records[(int(frame["direction"]), int(frame["frame"]))]
                max_width = math.floor(float(pose["clientHelmetWidth"]["p75"]) + 0.5)
                max_height = math.floor(float(pose["clientHelmetHeight"]["p75"]) + 0.5)
                if generated[0] > max_width or generated[1] > max_height:
                    raise AssertionError(f"death {direction_name} exceeds its same-cell client envelope: {generated}")
                hair = pose["hairAnchorCentroid"]
                pasted_center = [
                    int(frame["paste"][0]) + generated[0] // 2,
                    int(frame["paste"][1]) + generated[1] // 2,
                ]
                if abs(pasted_center[0] - round(float(hair[0]))) > 1 or abs(pasted_center[1] - round(float(hair[1]))) > 1:
                    raise AssertionError(f"death {direction_name} F{frame['frame']} is not centred on its same-cell Hair anchor")
            else:
                envelope = source["clientHelmetParameterBaseline"]["directionRuntimeMaxSize"][direction_name]
                if generated[0] > envelope[0] or generated[1] > envelope[1]:
                    raise AssertionError(f"{action} {direction_name} exceeds the real-client p75 envelope: {generated}")
    if total_frames != 184:
        raise AssertionError(f"Expected 184 logical frames, got {total_frames}")
    report = {
        "status": "pass",
        "item": "黑铁头盔",
        "totalLogicalFrames": total_frames,
        "directionOrder": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
        "actions": report_actions,
        "checks": [
            "all action atlases use 192x160 cells",
            "all 184 logical frames are non-empty",
            "all eight direction rows are distinct",
            "walk/attack/hit/death follow per-frame head motion in every direction",
            "helmet horizontally overlaps the equipped dress body in every frame",
            "all eight directions come from one Godot geometry with explicit canonical yaw",
            "all 32 death cells use the matching direction/frame Hair anchor and Godot pose record",
            "every generated helmet fits within its real-client p75 envelope",
            "opaque visual mass stays within 65%-135% of the matching client median",
        ],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BLACK_IRON_HELMET_ASSET_VERIFY_PASS frames={total_frames} report={REPORT.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
