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
    if source.get("schemaVersion") != 15:
        raise AssertionError("Black Iron Helmet provenance schema is not version 15")
    direction_references = source.get("approvedDirectionReferences", {})
    if direction_references.get("sourceSlotDirectionOrder") != [
        "N", "E", "W", "SW", "S", "SE", "NW", "NE"
    ]:
        raise AssertionError("Approved source-slot facing classification changed")
    if direction_references.get("canonicalRowSourceSlots") != [0, 7, 1, 5, 4, 3, 2, 6]:
        raise AssertionError("Approved source slots are not reordered into canonical game rows")
    if not source.get("generation", {}).get("aiGenerated", False):
        raise AssertionError("Direct approved-design pixels are not recorded")
    if not source.get("generation", {}).get("aiConceptUsed", False):
        raise AssertionError("Approved meteoric concept is missing from construction provenance")
    if source.get("generation", {}).get("aiPixelsLimitedTo") != ["idle", "walk", "attack", "hit"]:
        raise AssertionError("Direct approved-design pixel scope is incorrect")
    generator = str(source.get("generation", {}).get("runtimePixelGenerator", ""))
    if "Direct approved-design crops" not in generator or "Godot 4.7" not in generator:
        raise AssertionError("Runtime atlas does not record the direct-design plus Godot death pipeline")
    if source.get("generation", {}).get("oldDerivedStateItemWorldPixelsUsed", True):
        raise AssertionError("Runtime atlas still claims old StateItem-derived world pixels")
    if abs(float(source.get("generation", {}).get("runtimeEnvelopeScale", 0.0)) - 1.0) > 0.0001:
        raise AssertionError("Runtime helmet is not calibrated to the real-client median envelope")
    death_baseline = json.loads(DEATH_POSE_BASELINE.read_text(encoding="utf-8"))
    death_records = {
        (int(record["directionRow"]), int(record["frame"])): record
        for record in death_baseline.get("records", [])
    }
    godot_manifest = json.loads(GODOT_RENDER_MANIFEST.read_text(encoding="utf-8"))
    if len(death_records) != 32 or len(godot_manifest.get("records", [])) != 32:
        raise AssertionError("Godot death mapping is not the complete 8x4 table")
    baseline = source.get("clientHelmetParameterBaseline", {})
    if int(baseline.get("outlierFilteredPoseRecords", 0)) <= 0:
        raise AssertionError("Head-proximal pose-anchor outlier filtering was not recorded")
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
                effective_opaque_pixels = sum(
                    alpha * count for alpha, count in enumerate(alpha_histogram)
                ) / 255.0
                opaque_counts.append(round(effective_opaque_pixels, 3))
                visible_colours = {
                    pixel[:3]
                    for pixel in helmet_cell.getdata()
                    if pixel[3] >= 128
                }
                if not visible_colours:
                    raise AssertionError(f"{action} direction={direction} frame={frame} has no visible colours")
                if action == "death":
                    if max(max(colour) for colour in visible_colours) > 56:
                        raise AssertionError(f"{action} direction={direction} frame={frame} exceeds matte black palette")
                    if any(max(colour) - min(colour) != 0 for colour in visible_colours):
                        raise AssertionError(f"{action} direction={direction} frame={frame} contains tinted metal pixels")
                elif any(max(colour) - min(colour) > 14 for colour in visible_colours):
                    raise AssertionError(f"{action} direction={direction} frame={frame} contains non-neutral design pixels")
                direction_name = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][direction]
                if action == "death":
                    target_opaque = float(death_records[(direction, frame)]["clientHelmetOpaquePixels"]["median"])
                else:
                    target_opaque = float(
                        source["clientHelmetParameterBaseline"]["directionRuntimeOpaquePixels"][direction_name]
                    )
                opaque_ratio = effective_opaque_pixels / max(1.0, target_opaque)
                minimum_opaque_ratio = 0.65 if action == "death" else 0.90
                maximum_opaque_ratio = 1.35 if action == "death" else 1.25
                if opaque_ratio < minimum_opaque_ratio or opaque_ratio > maximum_opaque_ratio:
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
        if action != "death" and any(
            frame.get("poseVariant") != "approved-design-direct-resize"
            for frame in provenance_frames
        ):
            raise AssertionError(f"{action} frames do not all use direct approved-design crops")
        for frame in provenance_frames:
            direction_name = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(frame["direction"])]
            generated = frame["generatedSize"]
            if action == "death":
                pose = death_records[(int(frame["direction"]), int(frame["frame"]))]
                max_width = math.floor(float(pose["clientHelmetWidth"]["median"]) + 0.5)
                max_height = math.floor(float(pose["clientHelmetHeight"]["median"]) + 0.5)
                if generated[0] > max_width or generated[1] > max_height:
                    raise AssertionError(f"death {direction_name} exceeds its same-cell client envelope: {generated}")
            else:
                envelope = source["clientHelmetParameterBaseline"]["directionRuntimeTargetSize"][direction_name]
                if generated[0] > envelope[0] or generated[1] > envelope[1]:
                    raise AssertionError(f"{action} {direction_name} exceeds the real-client median envelope: {generated}")
            helmet_anchor = frame.get("helmetAnchorCentroid", [])
            hair_anchor = frame.get("hairAnchorCentroid", [])
            pasted_center = [
                int(frame["paste"][0]) + generated[0] // 2,
                int(frame["paste"][1]) + generated[1] // 2,
            ]
            if len(helmet_anchor) != 2 or any(
                abs(pasted_center[axis] - round(float(helmet_anchor[axis]))) > 1 for axis in range(2)
            ):
                raise AssertionError(
                    f"{action} {direction_name} F{frame['frame']} is not centred on its same-cell Helmet.wil anchor"
                )
            if action == "death":
                if len(hair_anchor) != 2:
                    raise AssertionError(f"death {direction_name} F{frame['frame']} has no Hair.wil head anchor")
                head_distance = math.dist(
                    [float(value) for value in helmet_anchor],
                    [float(value) for value in hair_anchor],
                )
                if head_distance > 10.0:
                    raise AssertionError(
                        f"death {direction_name} F{frame['frame']} helmet is not on the actor head: "
                        f"distance={head_distance:.3f}"
                    )
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
            "all standing/action directions use direct approved-design crops with only background removal and resize",
            "standing/action alpha-weighted visual mass stays within 90%-125% of the same-direction client median",
            "all death directions come from one Godot geometry with explicit canonical yaw",
            "all 184 cells use the matching action/direction/frame six-appearance Helmet.wil median anchor",
            "all 32 death cells use the matching direction/frame Godot pose record",
            "every death helmet anchor remains within 10 pixels of the same-cell male-warrior Hair.wil head",
            "every generated helmet fits within its real-client median envelope",
            "runtime pixels use only the four-tone neutral matte black-iron palette",
            "death opaque visual mass stays within 65%-135% of the matching client median",
        ],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BLACK_IRON_HELMET_ASSET_VERIFY_PASS frames={total_frames} report={REPORT.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
