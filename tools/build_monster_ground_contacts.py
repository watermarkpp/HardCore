#!/usr/bin/env python3
"""Build independently calibrated monster ground projections.

Alpha measurement is evidence, not the runtime authority.  Shadows, weapons,
tails, wings and spell pixels make the lowest visible pixel unreliable.  This
builder therefore creates a neutral-pose initial estimate, then requires one
explicit checked-in calibration per stable monsterId.  Runtime consumes only
the calibrated immutable center/radii and never follows the current frame.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

from build_monster_overhead_anchors import (
    CATALOG_PATH,
    MANIFEST_PATHS,
    REQUIRED_ACTIONS,
    ROOT,
    atlas_path,
    load_json,
    resolve_profile,
)


OUTPUT_PATH = ROOT / "assets/data/runtime/monster_ground_contacts.json"
CALIBRATION_PATH = (
    ROOT / "assets/data/runtime/monster_ground_contact_calibrations.json"
)
DEFAULT_REVIEW_OUTPUT = (
    ROOT / "outputs/test_visuals/monster_ground_contact_calibration_v3.png"
)
CONTRACT = "monster.ground_contact.v3"
CALIBRATION_CONTRACT = "monster.ground_contact.calibration.v3"
CLIENT_ACTOR_GROUND_OFFSET = (32, 28)
ALPHA_THRESHOLD = 16
NEUTRAL_ACTIONS = ("idle", "walk")
PROJECTION_STRATEGIES = ("grounded", "flying", "hover")

# These are semantic movement classes, not alpha-derived guesses.  The exact
# values are written into the data calibration catalog by --seed-calibrations;
# runtime and normal builds never depend on this Python set.
FLYING_MONSTER_IDS = {
    43, 44,       # cave bats
    97, 98,       # falcons
    114, 115,     # flying bees
    127,          # bats
    128,          # wedge moth
    144,          # bee
}
HOVER_MONSTER_IDS = {
    168, 169,     # moon-devil spider
    241,          # flying fire meteor
}
REVIEWED_RING_RADII_BY_MONSTER_ID = {
    56: [24, 7],
    57: [24, 7],
    59: [24, 7],
    76: [32, 10],
    77: [32, 10],
    78: [32, 10],
    89: [28, 8],
    90: [28, 8],
    91: [28, 8],
    124: [44, 13],
    141: [26, 8],
    142: [26, 8],
    146: [24, 7],
    147: [24, 7],
    160: [36, 11],
    161: [36, 11],
    180: [46, 14],
    193: [30, 9],
    224: [40, 12],
    225: [40, 12],
    239: [32, 10],
    240: [30, 9],
}


def rounded_median(values: list[float]) -> int:
    return int(round(statistics.median(values)))


def clamp_int(value: float, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, int(round(value))))


def frame_contact(
    alpha: Image.Image,
    bounds: tuple[int, int, int, int],
) -> tuple[float, int, int]:
    """Measure a review-only visible foot candidate.

    The narrow lower band is intentionally retained as diagnostic evidence.
    The final runtime projection does not consume it without an explicit
    monsterId calibration.
    """
    body_height = bounds[3] - bounds[1]
    band_height = max(3, min(10, body_height // 10))
    band_top = max(bounds[1], bounds[3] - band_height)
    pixels = alpha.load()
    contact_xs: list[int] = []
    for y in range(band_top, bounds[3]):
        for x in range(bounds[0], bounds[2]):
            if pixels[x, y] > ALPHA_THRESHOLD:
                contact_xs.append(x)
    contact_x = (
        statistics.median(contact_xs)
        if contact_xs
        else (bounds[0] + bounds[2] - 1) * 0.5
    )
    contact_width = (
        max(contact_xs) - min(contact_xs) + 1 if contact_xs else bounds[2] - bounds[0]
    )
    return contact_x, bounds[3] - 1, contact_width


def measure_profile(profile: dict[str, Any]) -> dict[str, Any]:
    frame_width, frame_height = map(int, profile["frameSize"])
    foot_x, foot_y = map(int, profile["footAnchor"])
    neutral_offsets: list[tuple[float, int]] = []
    neutral_widths: list[int] = []
    action_direction_ranges: dict[str, list[list[int]]] = {}
    sampled_frames = 0
    for action_name in REQUIRED_ACTIONS:
        action = profile["actions"][action_name]
        frame_count = int(action["framesPerDirection"])
        atlas = Image.open(atlas_path(str(action["path"]))).convert("RGBA")
        expected_size = (frame_width * frame_count, frame_height * 8)
        if atlas.size != expected_size:
            raise ValueError(
                f"{action['path']} size={atlas.size} expected={expected_size}"
            )
        alpha = atlas.getchannel("A")
        action_ranges: list[list[int]] = []
        for direction in range(8):
            direction_offsets: list[tuple[float, int]] = []
            row_y = direction * frame_height
            for frame in range(frame_count):
                frame_x = frame * frame_width
                frame_alpha = alpha.crop(
                    (frame_x, row_y, frame_x + frame_width, row_y + frame_height)
                )
                bounds = frame_alpha.getbbox()
                if bounds is None:
                    raise ValueError(
                        f"{action['path']} direction={direction} frame={frame} empty"
                    )
                contact_x, contact_y, contact_width = frame_contact(
                    frame_alpha,
                    bounds,
                )
                offset = (
                    contact_x - foot_x - CLIENT_ACTOR_GROUND_OFFSET[0],
                    contact_y - foot_y - CLIENT_ACTOR_GROUND_OFFSET[1],
                )
                direction_offsets.append(offset)
                if action_name in NEUTRAL_ACTIONS:
                    neutral_offsets.append(offset)
                    neutral_widths.append(contact_width)
                sampled_frames += 1
            xs = [value[0] for value in direction_offsets]
            ys = [value[1] for value in direction_offsets]
            action_ranges.append(
                [round(min(xs)), round(max(xs)), min(ys), max(ys)]
            )
        action_direction_ranges[action_name] = action_ranges
    if not neutral_offsets:
        raise ValueError("profile contains no neutral-pose contact samples")
    stable_x = rounded_median([value[0] for value in neutral_offsets])
    stable_y = rounded_median([value[1] for value in neutral_offsets])
    median_contact_width = rounded_median([float(value) for value in neutral_widths])
    radius_x = clamp_int(max(16.0, median_contact_width * 0.42), 16, 52)
    radius_y = clamp_int(radius_x * 0.30, 5, 17)
    return {
        "visualFootOffset": [stable_x, stable_y],
        "ringEllipseRadii": [radius_x, radius_y],
        "neutralSampleSpread": [
            round(max(value[0] for value in neutral_offsets) - min(value[0] for value in neutral_offsets)),
            max(value[1] for value in neutral_offsets) - min(value[1] for value in neutral_offsets),
        ],
        "actionDirectionVisibleContactRanges": action_direction_ranges,
        "sampledFrames": sampled_frames,
    }


def profile_signature(profile: dict[str, Any]) -> str:
    return json.dumps(
        {
            "frameSize": profile["frameSize"],
            "footAnchor": profile["footAnchor"],
            "actions": {
                action_name: {
                    "path": profile["actions"][action_name]["path"],
                    "framesPerDirection": profile["actions"][action_name][
                        "framesPerDirection"
                    ],
                }
                for action_name in REQUIRED_ACTIONS
            },
        },
        sort_keys=True,
        ensure_ascii=False,
    )


def automatic_initials() -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    catalog = load_json(CATALOG_PATH)
    manifests = [load_json(path) for path in MANIFEST_PATHS]
    measured_by_signature: dict[str, dict[str, Any]] = {}
    rows: list[dict[str, Any]] = []
    initials: dict[str, dict[str, Any]] = {}
    for row in catalog.get("monsters", []):
        monster_id = int(row["monster_id"])
        lookup = str(row["resource_lookup"])
        profile, profile_name = resolve_profile(monster_id, lookup, manifests)
        signature = profile_signature(profile)
        if signature not in measured_by_signature:
            measured_by_signature[signature] = measure_profile(profile)
        measured = measured_by_signature[signature]
        strategy = (
            "flying"
            if monster_id in FLYING_MONSTER_IDS
            else "hover"
            if monster_id in HOVER_MONSTER_IDS
            else "grounded"
        )
        visual_foot = list(measured["visualFootOffset"])
        # Airborne bodies retain their measured horizontal center while their
        # vertical projection lands on the authored actor ground plane.
        ring_center = (
            list(visual_foot)
            if strategy == "grounded"
            else [int(visual_foot[0]), 0]
        )
        ring_radii = list(
            REVIEWED_RING_RADII_BY_MONSTER_ID.get(
                monster_id,
                measured["ringEllipseRadii"],
            )
        )
        initials[str(monster_id)] = {
            "monsterId": monster_id,
            "name": str(row["name"]),
            "sourceLookup": profile_name,
            "projectionStrategy": strategy,
            "visualFootOffset": visual_foot,
            "ringCenterOffset": ring_center,
            "ringEllipseRadii": ring_radii,
            "neutralSampleSpread": list(measured["neutralSampleSpread"]),
            "actionDirectionVisibleContactRanges": measured[
                "actionDirectionVisibleContactRanges"
            ],
            "sampledFrames": int(measured["sampledFrames"]),
            "_profile": profile,
        }
        rows.append(row)
    if len(initials) != 214:
        raise ValueError(f"ground projection count={len(initials)}, expected 214")
    return rows, initials


def seed_calibrations(initials: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entries: dict[str, Any] = {}
    for monster_id, initial in initials.items():
        entries[monster_id] = {
            "projectionStrategy": initial["projectionStrategy"],
            "visualFootOffset": initial["visualFootOffset"],
            "ringCenterOffset": initial["ringCenterOffset"],
            "ringEllipseRadii": initial["ringEllipseRadii"],
            "calibrationSource": "neutral_pose_seed_reviewed_v3",
        }
    return {
        "schemaVersion": 3,
        "contract": CALIBRATION_CONTRACT,
        "identityKey": "monsterId",
        "policy": (
            "Every formal monsterId owns an explicit absolute calibration. "
            "Automatic alpha measurement may seed this file but never bypasses it."
        ),
        "entriesByMonsterId": entries,
    }


def load_calibrations(initials: dict[str, dict[str, Any]]) -> dict[str, Any]:
    calibrations = load_json(CALIBRATION_PATH)
    if calibrations.get("contract") != CALIBRATION_CONTRACT:
        raise ValueError("monster ground calibration contract mismatch")
    entries = calibrations.get("entriesByMonsterId", {})
    if not isinstance(entries, dict) or set(entries) != set(initials):
        raise ValueError(
            "monster ground calibrations must explicitly cover exactly 214 monsterIds"
        )
    for monster_id, entry in entries.items():
        if entry.get("projectionStrategy") not in PROJECTION_STRATEGIES:
            raise ValueError(f"monsterId={monster_id} projection strategy invalid")
        for field in ("visualFootOffset", "ringCenterOffset", "ringEllipseRadii"):
            values = entry.get(field)
            if not isinstance(values, list) or len(values) != 2:
                raise ValueError(f"monsterId={monster_id} {field} invalid")
        radii = entry["ringEllipseRadii"]
        if not (8 <= float(radii[0]) <= 80 and 3 <= float(radii[1]) <= 32):
            raise ValueError(f"monsterId={monster_id} ringEllipseRadii invalid")
    return entries


def build() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    rows, initials = automatic_initials()
    calibrations = load_calibrations(initials)
    entries: dict[str, Any] = {}
    legacy_name_to_monster_id: dict[str, int] = {}
    strategy_counts = {strategy: 0 for strategy in PROJECTION_STRATEGIES}
    for row in rows:
        monster_id = int(row["monster_id"])
        key = str(monster_id)
        initial = initials[key]
        calibration = calibrations[key]
        strategy = str(calibration["projectionStrategy"])
        strategy_counts[strategy] += 1
        visual_foot = [int(round(value)) for value in calibration["visualFootOffset"]]
        ring_center = [int(round(value)) for value in calibration["ringCenterOffset"]]
        ring_radii = [int(round(value)) for value in calibration["ringEllipseRadii"]]
        entries[key] = {
            "monsterId": monster_id,
            "name": str(row["name"]),
            "sourceLookup": initial["sourceLookup"],
            "projectionStrategy": strategy,
            "visualFootOffset": visual_foot,
            "ringCenterOffset": ring_center,
            "ringEllipseRadii": ring_radii,
            "hoverHeightPx": max(0, ring_center[1] - visual_foot[1]),
            "stableAcrossActions": list(REQUIRED_ACTIONS),
            "stableAcrossDirections": 8,
            "calibrationSource": str(calibration["calibrationSource"]),
            "automaticInitial": {
                "visualFootOffset": initial["visualFootOffset"],
                "ringCenterOffset": initial["ringCenterOffset"],
                "ringEllipseRadii": initial["ringEllipseRadii"],
                "neutralSampleSpread": initial["neutralSampleSpread"],
                "sampledFrames": initial["sampledFrames"],
            },
        }
        for field in ("name", "base_name", "resource_lookup"):
            legacy_name = str(row.get(field, ""))
            if legacy_name and legacy_name not in legacy_name_to_monster_id:
                legacy_name_to_monster_id[legacy_name] = monster_id
    output = {
        "schemaVersion": 3,
        "contract": CONTRACT,
        "calibrationContract": CALIBRATION_CONTRACT,
        "identityKey": "monsterId",
        "coordinateSpace": (
            "MonsterVisual-local offsets; runtime adds MonsterVisual.position "
            "exactly once. Ellipse radii are unscaled screen pixels."
        ),
        "clientActorGroundOffset": list(CLIENT_ACTOR_GROUND_OFFSET),
        "measurementPolicy": (
            "idle/walk alpha contacts are review evidence only; explicit per-ID "
            "calibrations separate visual feet from grounded/flying/hover projection"
        ),
        "runtimeStabilityPolicy": (
            "one immutable center and ellipse per monsterId across every action, "
            "direction and frame; no animation-pose target-ring drift"
        ),
        "summary": {
            "monsterCount": len(entries),
            "explicitCalibrationCount": len(calibrations),
            "requiredActions": list(REQUIRED_ACTIONS),
            "requiredDirections": 8,
            "projectionStrategyCounts": strategy_counts,
        },
        "entriesByMonsterId": entries,
        "legacyNameToMonsterId": legacy_name_to_monster_id,
    }
    return output, initials


def render_review_atlas(
    output_path: Path,
    entries: dict[str, Any],
    initials: dict[str, dict[str, Any]],
) -> None:
    columns = 12
    cell_width = 208
    cell_height = 172
    rows = math.ceil(len(entries) / columns)
    sheet = Image.new(
        "RGBA",
        (columns * cell_width, rows * cell_height),
        (18, 22, 28, 255),
    )
    draw = ImageDraw.Draw(sheet)
    for index, monster_id in enumerate(
        sorted(entries, key=lambda value: int(value))
    ):
        entry = entries[monster_id]
        initial = initials[monster_id]
        profile = initial["_profile"]
        frame_width, frame_height = map(int, profile["frameSize"])
        foot_x, foot_y = map(int, profile["footAnchor"])
        action = profile["actions"]["idle"]
        atlas = Image.open(atlas_path(str(action["path"]))).convert("RGBA")
        direction = 4
        frame = atlas.crop(
            (
                0,
                direction * frame_height,
                frame_width,
                (direction + 1) * frame_height,
            )
        )
        frame_draw = ImageDraw.Draw(frame)
        ring_center = entry["ringCenterOffset"]
        visual_foot = entry["visualFootOffset"]
        radii = entry["ringEllipseRadii"]
        origin_x = foot_x + CLIENT_ACTOR_GROUND_OFFSET[0]
        origin_y = foot_y + CLIENT_ACTOR_GROUND_OFFSET[1]
        ring_box = (
            origin_x + ring_center[0] - radii[0],
            origin_y + ring_center[1] - radii[1],
            origin_x + ring_center[0] + radii[0],
            origin_y + ring_center[1] + radii[1],
        )
        frame_draw.ellipse(ring_box, outline=(255, 202, 45, 255), width=2)
        foot_point = (
            origin_x + visual_foot[0],
            origin_y + visual_foot[1],
        )
        frame_draw.line(
            (
                foot_point[0] - 5,
                foot_point[1],
                foot_point[0] + 5,
                foot_point[1],
            ),
            fill=(64, 220, 255, 255),
            width=2,
        )
        frame_draw.line(
            (
                foot_point[0],
                foot_point[1] - 5,
                foot_point[0],
                foot_point[1] + 5,
            ),
            fill=(64, 220, 255, 255),
            width=2,
        )
        frame.thumbnail((cell_width - 12, cell_height - 30), Image.Resampling.LANCZOS)
        cell_x = (index % columns) * cell_width
        cell_y = (index // columns) * cell_height
        paste_x = cell_x + (cell_width - frame.width) // 2
        paste_y = cell_y + 22 + (cell_height - 28 - frame.height) // 2
        sheet.alpha_composite(frame, (paste_x, paste_y))
        strategy_short = str(entry["projectionStrategy"])[0].upper()
        draw.text(
            (cell_x + 5, cell_y + 4),
            f"#{monster_id} {strategy_short} "
            f"C{entry['ringCenterOffset']} R{entry['ringEllipseRadii']}",
            fill=(235, 239, 244, 255),
        )
        draw.rectangle(
            (cell_x, cell_y, cell_x + cell_width - 1, cell_y + cell_height - 1),
            outline=(54, 63, 74, 255),
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(output_path, quality=92)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--seed-calibrations", action="store_true")
    parser.add_argument(
        "--review-output",
        type=Path,
        default=None,
        help="write the 214-monster review atlas outside Git",
    )
    args = parser.parse_args()
    _, initials = automatic_initials()
    if args.seed_calibrations:
        CALIBRATION_PATH.write_text(
            json.dumps(seed_calibrations(initials), ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )
        print(f"wrote {CALIBRATION_PATH.relative_to(ROOT)}")
    generated_data, initials = build()
    generated = json.dumps(generated_data, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != generated:
            raise SystemExit(
                "monster ground contacts are stale; run "
                "tools/build_monster_ground_contacts.py"
            )
        print(
            "MONSTER_GROUND_CONTACT_DATA_PASS "
            "contract=v3 monsters=214 explicit_calibrations=214"
        )
    else:
        OUTPUT_PATH.write_text(generated, encoding="utf-8")
        print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")
    review_output = args.review_output
    if review_output is not None:
        resolved_review = (
            review_output
            if review_output.is_absolute()
            else ROOT / review_output
        )
        render_review_atlas(
            resolved_review,
            generated_data["entriesByMonsterId"],
            initials,
        )
        print(f"wrote review atlas {resolved_review}")


if __name__ == "__main__":
    main()
