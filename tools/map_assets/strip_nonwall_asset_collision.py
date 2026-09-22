#!/usr/bin/env python3
"""Strip built-in collision from non-wall project props in the editor catalogs.

Follow-up to strip_user_palette_asset_collision.py. The user reported that
many assets still auto-generate collision when resized. After the user
palette cleanup the remaining offenders are the project props loaded into
the editor palette whose catalog entries still carry collision policies:

  - map_cave_dungeon_asset_catalog.json   (solid_footprint / preset props)
  - map_v15_batch_asset_catalog.json      (profile / line_segment buildings)
  - map_object_asset_catalog.json         (chest / tent / forge)

Placement already forces these policies to manual-collision-only via
maps.new_instance_manual_collision_only_v1, but the resize paths
(build_asset_resize_draft, _resize_instance_collision) and the load-time
refresh_from_asset sync still resurrect collision from the catalog fields
and from stale collision keys in the calibration overrides.

This migration rewrites every non-wall collision-carrying entry in those
catalogs into the same manual-collision-only none-form, and removes the
stale collision keys from map_asset_overrides.json for the affected ids.

Deliberately untouched:
  - wall_cells_generated entries (cave-dungeon walls + wall modules): walls
    are structural room boundaries with dedicated runtime semantics.
  - terrain.palisade_wall_01 (terrain_stamp_generated): intentionally
    non-placeable, never shown in the asset palette.

The script is idempotent: a second run reports zero changes.
"""

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

DATA_DIR = REPO / "assets/data/assets"
TARGET_CATALOGS = [
    DATA_DIR / "map_cave_dungeon_asset_catalog.json",
    DATA_DIR / "map_v15_batch_asset_catalog.json",
    DATA_DIR / "map_object_asset_catalog.json",
]
OVERRIDES = REPO / "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"

WALL_POLICY = "wall_cells_generated"
COLLISION_POLICY_ID = "project_prop_manual_collision_only_v1"

NONE_FORM = {
    "collision_policy": "none",
    "collision_profile_id": "none_visual",
    "collision_footprint_tiles": [0, 0],
    "collision_cells": [],
    "navigation_policy": "ignore",
    "manual_collision_expected": True,
    "collision_authority": "manual_by_user",
    "collision_policy_id": COLLISION_POLICY_ID,
}

OVERRIDE_COLLISION_KEYS = [
    "collision_policy",
    "collision_profile_id",
    "collision_footprint_tiles",
    "collision_cells",
    "navigation_policy",
    "collision_authority",
    "collision_policy_id",
]


def _pair_nonzero(value) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value)
        and (int(value[0]) > 0 or int(value[1]) > 0)
    )


def has_effective_collision(asset: dict) -> bool:
    policy = str(asset.get("collision_policy", ""))
    profile = str(asset.get("collision_profile_id", ""))
    cells = asset.get("collision_cells")
    return (
        policy not in ("", "none")
        or _pair_nonzero(asset.get("collision_footprint_tiles"))
        or (isinstance(cells, list) and len(cells) > 0)
        or profile not in ("", "none_visual")
    )


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: dict) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def clean_catalog(path: Path) -> tuple[list[str], int]:
    """Convert non-wall collision-carrying assets to the none-form.

    Returns (cleaned_ids, wall_entries_skipped).
    """
    payload = load(path)
    assets = payload.get("assets", [])
    cleaned: list[str] = []
    walls_skipped = 0
    for asset in assets:
        policy = str(asset.get("collision_policy", ""))
        if policy == WALL_POLICY:
            if has_effective_collision(asset):
                walls_skipped += 1
            continue
        if not has_effective_collision(asset):
            continue
        asset.update(NONE_FORM)
        cleaned.append(str(asset.get("asset_id", "")))
    if cleaned:
        write(path, payload)
    return cleaned, walls_skipped


def clean_overrides(known_ids: set[str]) -> list[str]:
    payload = load(OVERRIDES)
    overrides = payload.get("overrides", {})
    cleaned: list[str] = []
    for asset_id in sorted(known_ids):
        entry = overrides.get(asset_id)
        if not isinstance(entry, dict):
            continue
        removed = False
        for key in OVERRIDE_COLLISION_KEYS:
            if key in entry:
                del entry[key]
                removed = True
        if removed:
            cleaned.append(asset_id)
    if cleaned:
        write(OVERRIDES, payload)
    return cleaned


def main() -> None:
    known_ids: set[str] = set()
    total_cleaned = 0
    for path in TARGET_CATALOGS:
        cleaned, walls = clean_catalog(path)
        total_cleaned += len(cleaned)
        known_ids |= set(cleaned)
        print(f"{path.name}: cleaned={len(cleaned)} walls_kept={walls}")
        if cleaned:
            print("  sample=" + ",".join(cleaned[:5]))

    override_cleaned = clean_overrides(known_ids)
    print(f"OVERRIDES_CLEANED={len(override_cleaned)}")
    print(f"TOTAL_CATALOG_CLEANED={total_cleaned}")


if __name__ == "__main__":
    main()
