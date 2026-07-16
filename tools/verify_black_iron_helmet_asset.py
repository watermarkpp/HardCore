#!/usr/bin/env python3
"""Verify Black Iron Helmet direction, action, alpha and body alignment."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
HELMET_ROOT = ROOT / "assets/art/characters/warrior/wear/helmet"
DRESS_ROOT = ROOT / "assets/art/characters/warrior/wear/dress"
SOURCE = HELMET_ROOT / "black_iron_helmet.source.json"
CANONICAL_MANIFEST = ROOT / "dev_art_sources/reference/generated/black_iron_helmet/canonical_directions/manifest.json"
REPORT = ROOT / "outputs/validation/black_iron_helmet_asset_report.json"
ACTIONS = {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "death": 4}
CELL = (192, 160)


def cell_box(frame: int, direction: int) -> tuple[int, int, int, int]:
    return (frame * CELL[0], direction * CELL[1], (frame + 1) * CELL[0], (direction + 1) * CELL[1])


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    if source.get("schemaVersion") != 6:
        raise AssertionError("Black Iron Helmet provenance schema is not version 6")
    if source.get("generation", {}).get("aiPixelsLimitedTo") != ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]:
        raise AssertionError("Runtime atlas does not use the complete newly generated direction family")
    if source.get("generation", {}).get("oldDerivedStateItemWorldPixelsUsed", True):
        raise AssertionError("Runtime atlas still claims old StateItem-derived world pixels")
    if abs(float(source.get("generation", {}).get("runtimeEnvelopeScale", 0.0)) - 0.7225) > 0.0001:
        raise AssertionError("Runtime helmet is not scaled to 72.25% of the real-client p75 envelope")
    canonical = json.loads(CANONICAL_MANIFEST.read_text(encoding="utf-8"))
    records = {record.get("direction"): record for record in canonical.get("records", [])}
    if not records.get("W", {}).get("horizontalFlipApplied", False):
        raise AssertionError("W is not mirrored to match the runtime W-facing body")
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
                opaque_counts.append(sum(alpha_histogram[1:]))
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
        if action == "death":
            south_late = [
                frame for frame in provenance_frames
                if int(frame["direction"]) == 4 and int(frame["frame"]) >= 2
            ]
            if len(south_late) != 2 or any(
                frame.get("poseVariant") != "south-death-foreshortened-crown" for frame in south_late
            ):
                raise AssertionError("South death frames 2/3 still reuse the standing front helmet")
        for frame in provenance_frames:
            direction_name = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(frame["direction"])]
            envelope = source["clientHelmetParameterBaseline"]["directionRuntimeMaxSize"][direction_name]
            generated = frame["generatedSize"]
            if generated[0] > round(envelope[0] * 0.7225) or generated[1] > round(envelope[1] * 0.7225):
                raise AssertionError(f"{action} {direction_name} exceeds the 72.25% client envelope: {generated}")
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
            "W applies the runtime-confirmed horizontal mirror",
            "every generated helmet fits within 72.25% of its real-client p75 direction envelope",
        ],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BLACK_IRON_HELMET_ASSET_VERIFY_PASS frames={total_frames} report={REPORT.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
