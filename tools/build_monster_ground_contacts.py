#!/usr/bin/env python3
"""Build stable per-monster ground contacts from final atlas alpha pixels."""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any

from PIL import Image

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
CONTRACT = "monster.ground_contact.v2"
CLIENT_ACTOR_GROUND_OFFSET = (32, 28)
ALPHA_THRESHOLD = 16


def rounded_median(values: list[float]) -> int:
    return int(round(statistics.median(values)))


def frame_contact(alpha: Image.Image, bounds: tuple[int, int, int, int]) -> tuple[float, int]:
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
    return contact_x, bounds[3] - 1


def measure_profile(profile: dict[str, Any]) -> dict[str, Any]:
    frame_width, frame_height = map(int, profile["frameSize"])
    foot_x, foot_y = map(int, profile["footAnchor"])
    offsets: dict[str, list[list[int]]] = {}
    maximum_frame_deviation = [0, 0]
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
        action_offsets: list[list[int]] = []
        for direction in range(8):
            frame_offsets: list[tuple[float, int]] = []
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
                contact_x, contact_y = frame_contact(frame_alpha, bounds)
                frame_offsets.append(
                    (
                        contact_x - foot_x - CLIENT_ACTOR_GROUND_OFFSET[0],
                        contact_y - foot_y - CLIENT_ACTOR_GROUND_OFFSET[1],
                    )
                )
                sampled_frames += 1
            stable_x = rounded_median([row[0] for row in frame_offsets])
            stable_y = rounded_median([row[1] for row in frame_offsets])
            maximum_frame_deviation[0] = max(
                maximum_frame_deviation[0],
                max(abs(round(row[0] - stable_x)) for row in frame_offsets),
            )
            maximum_frame_deviation[1] = max(
                maximum_frame_deviation[1],
                max(abs(row[1] - stable_y) for row in frame_offsets),
            )
            action_offsets.append([stable_x, stable_y])
        offsets[action_name] = action_offsets
    return {
        "actorLocalOffsetsByActionDirection": offsets,
        "maximumFrameDeviation": maximum_frame_deviation,
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


def build() -> dict[str, Any]:
    catalog = load_json(CATALOG_PATH)
    manifests = [load_json(path) for path in MANIFEST_PATHS]
    profiles: dict[str, Any] = {}
    profile_ids_by_signature: dict[str, str] = {}
    profile_by_monster_id: dict[str, str] = {}
    legacy_name_to_monster_id: dict[str, int] = {}
    for row in catalog.get("monsters", []):
        monster_id = int(row["monster_id"])
        lookup = str(row["resource_lookup"])
        profile, profile_name = resolve_profile(monster_id, lookup, manifests)
        signature = profile_signature(profile)
        if signature not in profile_ids_by_signature:
            profile_id = f"profile_{len(profile_ids_by_signature):03d}"
            profile_ids_by_signature[signature] = profile_id
            profiles[profile_id] = {
                "sourceLookup": profile_name,
                "frameSize": profile["frameSize"],
                "footAnchor": profile["footAnchor"],
                **measure_profile(profile),
            }
        profile_by_monster_id[str(monster_id)] = profile_ids_by_signature[signature]
        for field in ("name", "base_name", "resource_lookup"):
            legacy_name = str(row.get(field, ""))
            if legacy_name and legacy_name not in legacy_name_to_monster_id:
                legacy_name_to_monster_id[legacy_name] = monster_id
    if len(profile_by_monster_id) != 214:
        raise ValueError(
            f"ground contact count={len(profile_by_monster_id)}, expected 214"
        )
    return {
        "schemaVersion": 2,
        "contract": CONTRACT,
        "identityKey": "monsterId",
        "coordinateSpace": (
            "actor-local offset added to MonsterVisual.position; derived from "
            "the median visible ground-contact band after subtracting "
            "footAnchor and CLIENT_ACTOR_GROUND_OFFSET"
        ),
        "clientActorGroundOffset": list(CLIENT_ACTOR_GROUND_OFFSET),
        "measurementPolicy": (
            "one immutable median contact per action and direction across all "
            "frames; frame animation never moves the target ring"
        ),
        "summary": {
            "monsterCount": len(profile_by_monster_id),
            "uniqueVisualProfileCount": len(profiles),
            "requiredActions": list(REQUIRED_ACTIONS),
            "requiredDirections": 8,
        },
        "profileByMonsterId": profile_by_monster_id,
        "legacyNameToMonsterId": legacy_name_to_monster_id,
        "profiles": profiles,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generated = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != generated:
            raise SystemExit(
                "monster ground contacts are stale; run "
                "tools/build_monster_ground_contacts.py"
            )
        print("MONSTER_GROUND_CONTACT_DATA_PASS monsters=214 actions=5 directions=8")
        return
    OUTPUT_PATH.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
