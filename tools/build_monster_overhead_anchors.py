#!/usr/bin/env python3
"""Build stable per-monster overhead anchors from final atlas alpha pixels.

The runtime anchor must not follow the current animation frame because that
would make names and health bars bounce.  The neutral idle silhouette is the
semantic body-height reference: attack weapons, jumps, and collapsed death
poses must neither pull the overhead upward nor push it into the chest.  This
builder measures every atlas for audit evidence, then records the topmost idle
body pixel across all eight directions and all idle frames as one immutable
cell-local Y coordinate for each monsterId.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets/data/runtime/monster_animation_catalog.json"
OUTPUT_PATH = ROOT / "assets/data/runtime/monster_overhead_anchors.json"
MANIFEST_PATHS = [
    ROOT / "assets/data/complete_monster_client_art_sources.json",
    ROOT / "assets/data/classic_boss_client_art_sources.json",
    ROOT / "assets/data/bich_common_client_art_sources.json",
    ROOT / "assets/data/bich_undead_client_art_sources.json",
]
REQUIRED_ACTIONS = ("idle", "walk", "attack", "hit", "death")
CONTRACT = "monster.overhead_anchor.v4"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def atlas_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ValueError(f"non-project atlas path: {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


def resolve_profile(
    monster_id: int,
    resource_lookup: str,
    manifests: list[dict[str, Any]],
) -> tuple[dict[str, Any], str]:
    # Match MonsterVisual's precedence: complete ID, boss ID, then the named
    # compatibility mappings.  Some older manifests store an ID -> name alias.
    for manifest in manifests:
        by_id = manifest.get("runtimeMappingsByMonsterId", {})
        candidate = by_id.get(str(monster_id))
        if isinstance(candidate, dict) and candidate:
            return candidate, str(candidate.get("name", resource_lookup))
        if isinstance(candidate, str):
            profile = manifest.get("runtimeMappings", {}).get(candidate)
            if isinstance(profile, dict) and profile:
                return profile, candidate
    for manifest in manifests:
        profile = manifest.get("runtimeMappings", {}).get(resource_lookup)
        if isinstance(profile, dict) and profile:
            return profile, resource_lookup
    raise KeyError(
        f"monsterId={monster_id} resource_lookup={resource_lookup!r} has no profile"
    )


def profile_signature(profile: dict[str, Any]) -> tuple[Any, ...]:
    frame_size = tuple(map(int, profile["frameSize"]))
    actions = profile["actions"]
    return (
        frame_size,
        *(
            (
                action,
                str(actions[action]["path"]),
                int(actions[action]["framesPerDirection"]),
            )
            for action in REQUIRED_ACTIONS
        ),
    )


def measure_profile(profile: dict[str, Any]) -> dict[str, Any]:
    frame_width, frame_height = map(int, profile["frameSize"])
    topmost = frame_height
    sampled_frames = 0
    action_tops: dict[str, int] = {}
    for action_name in REQUIRED_ACTIONS:
        action = profile.get("actions", {}).get(action_name)
        if not isinstance(action, dict):
            raise ValueError(f"profile has no {action_name} action")
        frame_count = int(action["framesPerDirection"])
        image = Image.open(atlas_path(str(action["path"]))).convert("RGBA")
        expected_size = (frame_width * frame_count, frame_height * 8)
        if image.size != expected_size:
            raise ValueError(
                f"{action['path']} size={image.size} expected={expected_size}"
            )
        action_top = frame_height
        alpha = image.getchannel("A")
        for direction in range(8):
            row_y = direction * frame_height
            for frame in range(frame_count):
                frame_x = frame * frame_width
                bounds = alpha.crop(
                    (frame_x, row_y, frame_x + frame_width, row_y + frame_height)
                ).getbbox()
                if bounds is None:
                    raise ValueError(
                        f"{action['path']} direction={direction} frame={frame} is empty"
                    )
                action_top = min(action_top, int(bounds[1]))
                sampled_frames += 1
        action_tops[action_name] = action_top
        topmost = min(topmost, action_top)
    if topmost >= frame_height:
        raise ValueError("profile contains no visible pixels")
    return {
        "allActionVisibleTop": topmost,
        "actionVisibleTops": action_tops,
        "sampledFrames": sampled_frames,
    }


def build() -> dict[str, Any]:
    catalog = load_json(CATALOG_PATH)
    manifests = [load_json(path) for path in MANIFEST_PATHS]
    measured_profiles: dict[tuple[Any, ...], dict[str, Any]] = {}
    anchors: dict[str, Any] = {}
    for row in catalog.get("monsters", []):
        monster_id = int(row["monster_id"])
        resource_lookup = str(row["resource_lookup"])
        profile, profile_name = resolve_profile(monster_id, resource_lookup, manifests)
        signature = profile_signature(profile)
        if signature not in measured_profiles:
            measured_profiles[signature] = measure_profile(profile)
        measured = measured_profiles[signature]
        frame_width, frame_height = map(int, profile["frameSize"])
        anchors[str(monster_id)] = {
            "profile": profile_name,
            "frameSize": [frame_width, frame_height],
            "stableBodyTop": int(measured["actionVisibleTops"]["idle"]),
            "allActionVisibleTop": int(measured["allActionVisibleTop"]),
            "actionVisibleTops": measured["actionVisibleTops"],
            "sampledFrames": int(measured["sampledFrames"]),
        }
    expected_count = int(catalog.get("summary", {}).get("total", 0))
    if len(anchors) != expected_count or expected_count != 214:
        raise ValueError(
            f"anchor count={len(anchors)} catalog total={expected_count}, expected 214"
        )
    return {
        "schemaVersion": 1,
        "contract": CONTRACT,
        "identityKey": "monsterId",
        "measurementPolicy": (
            "stableBodyTop is the minimum non-transparent cell-local Y across "
            "all neutral idle frames and all eight directions; every formal "
            "action is also measured and retained as audit evidence"
        ),
        "runtimePolicy": (
            "one immutable stableBodyTop per monsterId; health bar bottom "
            "remains a fixed gap above it, so direction/action/frame changes "
            "never move the overhead"
        ),
        "summary": {
            "monsterCount": len(anchors),
            "uniqueVisualProfileCount": len(measured_profiles),
            "requiredActions": list(REQUIRED_ACTIONS),
            "requiredDirections": 8,
        },
        "anchorsByMonsterId": anchors,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the checked-in output matches the current final atlases",
    )
    args = parser.parse_args()
    generated = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        current = OUTPUT_PATH.read_text(encoding="utf-8")
        if current != generated:
            raise SystemExit(
                "monster overhead anchor data is stale; run "
                "tools/build_monster_overhead_anchors.py"
            )
        print(
            "MONSTER_OVERHEAD_ANCHOR_DATA_PASS "
            "monsters=214 actions=5 directions=8"
        )
        return
    OUTPUT_PATH.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
