#!/usr/bin/env python3
"""Strip built-in collision from user palette (sucai) map editor assets.

The user palette assets imported from the desktop sucai folder were written
with collision_policy solid_footprint / preset and non-zero
collision_footprint_tiles. Every editor path (placement, asset resize,
instance resize, load-time profile refresh, runtime build) derives collision
from these catalog fields, so erased instance collision came back whenever
the asset or the instance was resized.

This migration rewrites every user.* asset that carries effective collision
into the same manual-collision-only form the editor's whole-erase tool and
the visual-only wall policy (map_asset_manual_collision_policy.gd) already
produce:

    collision_policy        = "none"
    collision_profile_id    = "none_visual"
    collision_footprint_tiles = [0, 0]
    collision_cells         = []
    navigation_policy       = "ignore"
    manual_collision_expected = true
    collision_authority     = "manual_by_user"
    collision_policy_id     = "user_palette_manual_collision_only_v1"

Scope is strictly limited to asset_id prefixed with "user.". Project-authored
assets keep their intentional collision (wall_cells_generated,
terrain_stamp_generated, solid_footprint on buildings/obstacles in the
cave-dungeon / v1_5 / wall-module catalogs are untouched).

Files touched:
  - assets/data/assets/map_asset_catalog.json          (editor authority)
  - assets/data/assets/map_direct_folder_asset_catalog.json (byte-identical
    mirror written by the import tools and re-consumed by audit tools)
  - assets/data/expansions/personal_expansion_001/map_asset_overrides.json
    (per-asset calibration overlay; shallow-merged over the base catalog, so
    stale collision keys there would resurrect collision)

The script is idempotent: a second run reports zero changes.
"""

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

MAIN_CATALOG = REPO / "assets/data/assets/map_asset_catalog.json"
DIRECT_CATALOG = REPO / "assets/data/assets/map_direct_folder_asset_catalog.json"
OVERRIDES = REPO / "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"

USER_PREFIX = "user."
COLLISION_POLICY_ID = "user_palette_manual_collision_only_v1"

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

# Keys a calibration override may carry that would resurrect collision over
# the cleaned base catalog (save_override allowed-key superset, collision part).
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


def clean_catalog(path: Path) -> tuple[list[str], list[str]]:
    """Apply the none-form to user.* assets carrying collision.

    Returns (cleaned_ids, skipped_ids) where skipped_ids are user.* assets
    whose collision fields deviated from the standard form in shape only
    (already none) and therefore only received missing none-form keys.
    """
    payload = load(path)
    assets = payload.get("assets", [])
    cleaned: list[str] = []
    for asset in assets:
        asset_id = str(asset.get("asset_id", ""))
        if not asset_id.startswith(USER_PREFIX):
            continue
        if not has_effective_collision(asset):
            continue
        asset.update(NONE_FORM)
        cleaned.append(asset_id)
    if cleaned:
        write(path, payload)
    return cleaned, []


def clean_overrides(path: Path, known_ids: set[str]) -> list[str]:
    payload = load(path)
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
        write(path, payload)
    return cleaned


def leftover_scan() -> list[str]:
    """Report user.* assets still carrying collision in any editor-loaded catalog."""
    leftovers: list[str] = []
    data_dir = REPO / "assets/data/assets"
    catalog_paths = [MAIN_CATALOG] + sorted(
        p for p in data_dir.glob("map_*_asset_catalog.json") if p not in (MAIN_CATALOG, DIRECT_CATALOG)
    )
    catalog_paths.append(DIRECT_CATALOG)
    for path in catalog_paths:
        try:
            payload = load(path)
        except (OSError, json.JSONDecodeError):
            continue
        for asset in payload.get("assets", []):
            asset_id = str(asset.get("asset_id", ""))
            if asset_id.startswith(USER_PREFIX) and has_effective_collision(asset):
                leftovers.append(f"{path.name}:{asset_id}")
    return leftovers


def main() -> None:
    main_cleaned, _ = clean_catalog(MAIN_CATALOG)
    direct_cleaned, _ = clean_catalog(DIRECT_CATALOG)

    known_ids = set(main_cleaned) | set(direct_cleaned)
    # Overrides must also be cleaned for user assets that were already
    # collision-free in the base catalog but may carry stale keys.
    main_assets = load(MAIN_CATALOG).get("assets", [])
    known_ids |= {
        str(asset.get("asset_id", ""))
        for asset in main_assets
        if str(asset.get("asset_id", "")).startswith(USER_PREFIX)
    }
    override_cleaned = clean_overrides(OVERRIDES, known_ids)

    leftovers = leftover_scan()

    print(f"MAIN_CATALOG_CLEANED={len(main_cleaned)}")
    print(f"DIRECT_CATALOG_CLEANED={len(direct_cleaned)}")
    print(f"OVERRIDES_CLEANED={len(override_cleaned)}")
    print(f"LEFTOVER_USER_COLLISION={len(leftovers)}")
    for item in leftovers[:10]:
        print(f"  LEFTOVER {item}")
    if main_cleaned:
        print("MAIN_SAMPLE=" + ",".join(main_cleaned[:5]))


if __name__ == "__main__":
    main()
