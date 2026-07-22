#!/usr/bin/env python3
"""Audit every formal monster atlas for slicing and direction anomalies."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFESTS = [
    ROOT / "assets/data/bich_common_client_art_sources.json",
    ROOT / "assets/data/bich_undead_client_art_sources.json",
    ROOT / "assets/data/classic_boss_client_art_sources.json",
    ROOT / "assets/data/complete_monster_client_art_sources.json",
]
CATALOG = ROOT / "assets/data/runtime/monster_animation_catalog.json"
REQUIRED_ACTIONS = {"idle", "walk", "attack", "hit", "death"}
MIN_DIRECTION_OPAQUE_RATIO = 0.35
MAX_DIRECTION_OPAQUE_RATIO = 3.0


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def atlas_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise AssertionError(f"non-project resource path: {resource_path}")
    return ROOT / resource_path.removeprefix("res://")


def row_digest(image: Image.Image, frame_height: int, direction: int) -> str:
    top = direction * frame_height
    payload = image.crop((0, top, image.width, top + frame_height)).tobytes()
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    profiles: dict[str, dict] = {}
    for path in MANIFESTS:
        profiles.update(load_json(path).get("runtimeMappings", {}))

    catalog = load_json(CATALOG)
    rows = catalog.get("monsters", [])
    assert len(rows) == 214, f"catalog contains {len(rows)} rows instead of 214"
    assert all(row.get("status") == "formal" for row in rows), "catalog contains non-formal monster art"
    unresolved = sorted(
        {
            str(row.get("resource_lookup", ""))
            for row in rows
            if str(row.get("resource_lookup", "")) not in profiles
        }
    )
    assert not unresolved, f"catalog resource lookups do not resolve: {unresolved}"

    action_count = 0
    frame_count = 0
    fixed_profiles: set[str] = set()
    geometry_anomalies: list[str] = []
    for name, profile in profiles.items():
        frame_width, frame_height = map(int, profile["frameSize"])
        actions = profile.get("actions", {})
        assert set(actions) == REQUIRED_ACTIONS, f"{name} does not expose the formal five actions"
        fixed_profile = profile.get("directionPolicy") == "fixed_source_direction"
        content_padding = int(profile.get("contentPadding", 0))
        if content_padding:
            assert profile.get("atlasCellIsolation") == "per_frame", (
                f"{name} declares content padding without per-frame atlas isolation"
            )
        for action_name, action in actions.items():
            frames_per_direction = int(action["framesPerDirection"])
            image = Image.open(atlas_path(str(action["path"]))).convert("RGBA")
            assert image.size == (
                frame_width * frames_per_direction,
                frame_height * 8,
            ), f"{name}/{action_name} atlas size is inconsistent with its manifest"

            first_frame_opaque: list[int] = []
            for direction in range(8):
                for frame in range(frames_per_direction):
                    left = frame * frame_width
                    top = direction * frame_height
                    alpha = image.crop(
                        (left, top, left + frame_width, top + frame_height)
                    ).getchannel("A")
                    alpha_bounds = alpha.getbbox()
                    assert alpha_bounds is not None, (
                        f"{name}/{action_name} direction={direction} frame={frame} is empty"
                    )
                    if content_padding:
                        assert (
                            alpha_bounds[0] >= content_padding
                            and alpha_bounds[1] >= content_padding
                            and alpha_bounds[2] <= frame_width - content_padding
                            and alpha_bounds[3] <= frame_height - content_padding
                        ), (
                            f"{name}/{action_name} direction={direction} frame={frame} "
                            f"crosses its isolated cell: bounds={alpha_bounds} "
                            f"cell={(frame_width, frame_height)} padding={content_padding}"
                        )
                    if frame == 0:
                        histogram = alpha.histogram()
                        first_frame_opaque.append(
                            frame_width * frame_height - histogram[0]
                        )
                    frame_count += 1

            source_stride = int(action.get("sourceDirectionStride", -1))
            if fixed_profile or source_stride == 0:
                digests = {
                    row_digest(image, frame_height, direction)
                    for direction in range(8)
                }
                assert len(digests) == 1, (
                    f"{name}/{action_name} declares a fixed source direction "
                    "but its atlas rows differ"
                )
                fixed_profiles.add(name)
            else:
                middle = float(median(first_frame_opaque))
                low = min(first_frame_opaque) / middle
                high = max(first_frame_opaque) / middle
                if low < MIN_DIRECTION_OPAQUE_RATIO or high > MAX_DIRECTION_OPAQUE_RATIO:
                    geometry_anomalies.append(
                        f"{name}/{action_name}: direction opaque ratios "
                        f"{low:.2f}..{high:.2f} counts={first_frame_opaque}"
                    )
            action_count += 1

    assert not geometry_anomalies, "direction slicing anomalies:\n" + "\n".join(geometry_anomalies)
    print(
        "MONSTER_ANIMATION_GEOMETRY_AUDIT_PASS "
        f"catalog=214 profiles={len(profiles)} actions={action_count} "
        f"frames={frame_count} fixed_profiles={len(fixed_profiles)}"
    )


if __name__ == "__main__":
    main()
