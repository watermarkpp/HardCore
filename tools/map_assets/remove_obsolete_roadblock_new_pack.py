"""Remove the retired 2026-08-21 ``路障/新增`` metadata pack.

The old pack is selected fail-closed by its exact palette path plus the
``tree_roadblock_explicit_grid_v1`` processing/tag.  The tool removes only
those IDs from the main catalog, footprint review state, and expansion
overrides.  It never deletes PNGs; the write report lists the exact files so a
caller can move or remove them separately after the metadata cleanup.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CATALOG_REL = Path("assets/data/assets/map_asset_catalog.json")
REVIEW_REL = Path("assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json")
OVERRIDES_REL = Path("assets/data/expansions/personal_expansion_001/map_asset_overrides.json")
WORKSPACE_REL = Path("map_editor_workspace")
TARGET_PALETTE = "装饰物1/路障/新增"
TARGET_TAG = "tree_roadblock_explicit_grid_v1"
EXPECTED_COUNT = 16
IMAGE_PREFIX = "assets/art/maps/_shared/user_palette/decorations_1/barricades/新增/"

# These IDs are a residual-reference guard after the main catalog entries have
# been removed.  They are not used to select a main-catalog asset; selection
# remains governed by TARGET_PALETTE + TARGET_TAG.
KNOWN_LEGACY_IDS = {
    "user.cdb4723a9c62ec77",
    "user.106a7ef48783c39c",
    "user.69da6325a585a3e0",
    "user.db9da430f78824ce",
    "user.d13b5d379a608d11",
    "user.1440243e9c564a2c",
    "user.3b48b3e78b5788ca",
    "user.ca658345cec84700",
    "user.1d7b8837430a143d",
    "user.39806a640e9d78ac",
    "user.e84e9a0084dd7443",
    "user.1f6f6db0df32911f",
    "user.3819e1bac3f136bc",
    "user.4013bce08dc0b07e",
    "user.37e2f534312b82a9",
    "user.5ff97372f9668ca5",
}


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def processing_tag_matches(asset: dict[str, Any]) -> bool:
    processing = asset.get("processing")
    processing_match = processing == TARGET_TAG or (
        isinstance(processing, dict)
        and str(processing.get("pipeline", "")) == TARGET_TAG
    )
    tags = asset.get("tags", [])
    return processing_match and isinstance(tags, list) and TARGET_TAG in tags


def is_target_asset(asset: Any) -> bool:
    return (
        isinstance(asset, dict)
        and str(asset.get("palette_path", "")) == TARGET_PALETTE
        and processing_tag_matches(asset)
    )


def normalize_path(value: Any) -> str:
    return str(value).replace("\\", "/")


def workspace_references(root: Path, ids: set[str], image_paths: set[str]) -> list[str]:
    workspace = root / WORKSPACE_REL
    if not workspace.is_dir():
        return []
    tokens = sorted(ids | {path for path in image_paths if path})
    hits: list[str] = []
    for path in workspace.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        normalized_text = text.replace("\\", "/")
        for token in tokens:
            if token and token in normalized_text:
                hits.append(f"{path.relative_to(root).as_posix()}::{token}")
    return sorted(set(hits))


def record_references(payload: dict[str, Any], ids: set[str], image_paths: set[str]) -> set[str]:
    references: set[str] = set()
    for key, value in payload.get("items", payload.get("overrides", {})).items():
        key_text = str(key)
        if key_text in ids or key_text in KNOWN_LEGACY_IDS:
            references.add(key_text)
            continue
        if not isinstance(value, dict):
            continue
        encoded = json.dumps(value, ensure_ascii=False)
        normalized = encoded.replace("\\", "/")
        if any(path in normalized for path in image_paths):
            references.add(key_text)
    return references


def selected_assets(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    assets = catalog.get("assets", [])
    if not isinstance(assets, list):
        raise ValueError("catalog.assets must be an array")
    return [asset for asset in assets if is_target_asset(asset)]


def print_image_report(paths: list[str]) -> None:
    print("obsolete_image_directory=" + IMAGE_PREFIX)
    print("obsolete_image_paths=" + json.dumps(sorted(paths), ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    catalog_path = root / CATALOG_REL
    review_path = root / REVIEW_REL
    overrides_path = root / OVERRIDES_REL
    try:
        catalog = read_json(catalog_path)
        review_state = read_json(review_path)
        overrides = read_json(overrides_path)
        targets = selected_assets(catalog)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"OBSOLETE_ROADBLOCK_CLEANUP_FAIL {exc}")
        return 1

    target_ids = {str(asset.get("asset_id", "")) for asset in targets}
    if any(not asset_id for asset_id in target_ids):
        print("OBSOLETE_ROADBLOCK_CLEANUP_FAIL target_missing_asset_id")
        return 1
    if len(targets) not in (0, EXPECTED_COUNT):
        print(
            "OBSOLETE_ROADBLOCK_CLEANUP_FAIL "
            f"target_count={len(targets)} expected=0_or_{EXPECTED_COUNT}"
        )
        return 1
    if len(target_ids) != len(targets):
        print("OBSOLETE_ROADBLOCK_CLEANUP_FAIL duplicate_target_id")
        return 1

    image_paths = {
        normalize_path(asset.get("image", ""))
        for asset in targets
        if normalize_path(asset.get("image", "")).startswith(IMAGE_PREFIX)
    }
    workspace_hits = workspace_references(root, target_ids, image_paths)
    residual_review = record_references(review_state, target_ids, image_paths)
    residual_overrides = record_references(overrides, target_ids, image_paths)
    if workspace_hits:
        print("OBSOLETE_ROADBLOCK_CLEANUP_FAIL map_editor_workspace_references")
        print("\n".join(workspace_hits))
        return 1

    if args.check:
        if targets or residual_review or residual_overrides:
            print(
                "OBSOLETE_ROADBLOCK_CHECK_PENDING "
                f"catalog_matches={len(targets)} review_matches={len(residual_review)} "
                f"override_matches={len(residual_overrides)}"
            )
            print_image_report(sorted(image_paths))
            return 1
        print("OBSOLETE_ROADBLOCK_CHECK_PASS catalog_matches=0 review_matches=0 override_matches=0")
        return 0

    if targets:
        catalog["assets"] = [
            asset for asset in catalog.get("assets", [])
            if str(asset.get("asset_id", "")) not in target_ids
        ]
    review_items = review_state.get("items", {})
    if not isinstance(review_items, dict):
        print("OBSOLETE_ROADBLOCK_CLEANUP_FAIL review.items must be an object")
        return 1
    review_state["items"] = {
        key: value for key, value in review_items.items() if str(key) not in target_ids
    }
    override_items = overrides.get("overrides", {})
    if not isinstance(override_items, dict):
        print("OBSOLETE_ROADBLOCK_CLEANUP_FAIL overrides.overrides must be an object")
        return 1
    overrides["overrides"] = {
        key: value for key, value in override_items.items() if str(key) not in target_ids
    }
    write_json(catalog_path, catalog)
    write_json(review_path, review_state)
    write_json(overrides_path, overrides)
    print(
        "OBSOLETE_ROADBLOCK_WRITE_PASS "
        f"removed_catalog={len(targets)} removed_review={len(target_ids & set(review_items))} "
        f"removed_overrides={len(target_ids & set(override_items))}"
    )
    print_image_report(sorted(image_paths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
