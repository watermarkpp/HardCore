"""Promote the verified tree calibration review into overrides.

This is intentionally a narrow, fail-closed promotion tool.  It only accepts
the 128 tree assets produced by ``tree_roadblock_explicit_grid_v1`` in the main
catalog and only copies the user's already-verified anchor/footprint values.
The manual review contract permits a foot-tile anchor below the transparent
canvas, so an anchor is required to be a non-negative integer pair but is not
rejected merely for being below the PNG's bottom edge.
``--check`` performs a read-only preflight; ``--write`` adds missing entries
to the existing override document without touching any other entry.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - the repo tool runtime has Pillow
    raise SystemExit("Pillow is required to validate imported asset dimensions") from exc


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets/data/assets/map_asset_catalog.json"
REVIEW_STATE = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
OVERRIDES = ROOT / "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
PROCESSING = "tree_roadblock_explicit_grid_v1"
EXPECTED_COUNT = 128
TARGET_PREFIXES = ("新增树木20260821_",)
TARGET_PATH_MARKERS = ("/trees/新增/",)
REQUIRED_OVERRIDE_FIELDS = (
    "anchor_px",
    "footprint_tiles",
    "visual_footprint_tiles",
    "occupancy_footprint_tiles",
    "base_footprint_tiles",
    "collision_footprint_tiles",
    "placeable",
    "calibration_status",
    "content_layer",
)


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_positive_integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def target_like(review: dict[str, Any]) -> bool:
    display_name = str(review.get("display_name", ""))
    image = str(review.get("image", "")).replace("\\", "/")
    palette = str(review.get("palette_path", ""))
    return (
        display_name.startswith(TARGET_PREFIXES)
        or any(marker in image for marker in TARGET_PATH_MARKERS)
        or "/树木/新增/" in palette
    )


def expected_override(review: dict[str, Any], asset: dict[str, Any]) -> dict[str, Any]:
    footprint = copy.deepcopy(review["footprint_tiles"])
    collision = footprint if str(asset.get("collision_policy", "")) != "none" else [0, 0]
    return {
        "anchor_px": copy.deepcopy(review["anchor_px"]),
        "footprint_tiles": copy.deepcopy(footprint),
        "visual_footprint_tiles": copy.deepcopy(footprint),
        "occupancy_footprint_tiles": copy.deepcopy(footprint),
        "base_footprint_tiles": copy.deepcopy(footprint),
        "collision_footprint_tiles": copy.deepcopy(collision),
        "placeable": True,
        "calibration_status": "placeable",
        "content_layer": "personal_expansion",
    }


def validate(
    catalog: dict[str, Any],
    review_state: dict[str, Any],
    override_payload: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], list[str], int]:
    errors: list[str] = []
    out_of_image_anchor_count = 0
    assets = catalog.get("assets", [])
    reviews = review_state.get("items", {})
    overrides = override_payload.get("overrides", {})
    if not isinstance(assets, list):
        errors.append("catalog.assets_not_array")
        return [], {}, errors, out_of_image_anchor_count
    if not isinstance(reviews, dict):
        errors.append("review.items_not_object")
        return [], {}, errors, out_of_image_anchor_count
    if not isinstance(overrides, dict):
        errors.append("overrides.overrides_not_object")
        return [], {}, errors, out_of_image_anchor_count

    selected = [asset for asset in assets if asset.get("processing") == PROCESSING]
    selected_ids = [str(asset.get("asset_id", "")) for asset in selected]
    if len(selected) != EXPECTED_COUNT:
        errors.append(f"catalog.target_count={len(selected)} expected={EXPECTED_COUNT}")
    if any(not asset_id for asset_id in selected_ids):
        errors.append("catalog.target_missing_asset_id")
    if len(selected_ids) != len(set(selected_ids)):
        errors.append("catalog.target_duplicate_asset_id")
    selected_by_id = {str(asset["asset_id"]): asset for asset in selected if asset.get("asset_id")}

    target_review_ids = {asset_id for asset_id in selected_by_id if asset_id in reviews}
    missing_reviews = sorted(set(selected_by_id) - set(reviews))
    if missing_reviews:
        errors.append(f"review.missing_targets={len(missing_reviews)}")
    extra_target_reviews = sorted(
        asset_id
        for asset_id, review in reviews.items()
        if isinstance(review, dict) and target_like(review) and asset_id not in selected_by_id
    )
    if extra_target_reviews:
        errors.append(f"review.extra_targets={len(extra_target_reviews)}")

    expected_by_id: dict[str, dict[str, Any]] = {}
    for asset_id, asset in selected_by_id.items():
        review = reviews.get(asset_id)
        if not isinstance(review, dict):
            continue
        if review.get("status") != "verified":
            errors.append(f"review.not_verified:{asset_id}")
        for field in ("image", "source_sha256", "output_sha256"):
            if review.get(field) != asset.get(field):
                errors.append(f"review.{field}_mismatch:{asset_id}")
        for field in ("display_name", "palette_path"):
            if review.get(field) != asset.get(field):
                errors.append(f"review.{field}_mismatch:{asset_id}")
        footprint = review.get("footprint_tiles")
        anchor = review.get("anchor_px")
        if not isinstance(footprint, list) or len(footprint) != 2 or not all(is_positive_integer(v) for v in footprint):
            errors.append(f"review.invalid_footprint:{asset_id}")
        if not isinstance(anchor, list) or len(anchor) != 2 or any(
            isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in anchor
        ):
            errors.append(f"review.invalid_anchor:{asset_id}")
        image_rel = str(asset.get("image", ""))
        image_path = ROOT / image_rel
        if not image_path.is_file():
            errors.append(f"asset.image_missing:{asset_id}")
        else:
            try:
                with Image.open(image_path) as image:
                    width, height = image.size
                    if list(image.size) != list(asset.get("image_size", [])):
                        errors.append(f"asset.image_size_mismatch:{asset_id}")
                    if isinstance(anchor, list) and len(anchor) == 2 and all(
                        isinstance(v, int) and not isinstance(v, bool) and v >= 0 for v in anchor
                    ) and not (anchor[0] < width and anchor[1] < height):
                        out_of_image_anchor_count += 1
                    actual_output_sha = sha256_file(image_path)
                    if actual_output_sha != str(asset.get("output_sha256", "")):
                        errors.append(f"asset.output_sha_mismatch:{asset_id}")
            except (OSError, ValueError) as exc:
                errors.append(f"asset.image_unreadable:{asset_id}:{exc}")
        if isinstance(footprint, list) and len(footprint) == 2 and all(is_positive_integer(v) for v in footprint):
            expected_by_id[asset_id] = expected_override(review, asset)

    for asset_id, expected in expected_by_id.items():
        existing = overrides.get(asset_id)
        if existing is None:
            continue
        if not isinstance(existing, dict):
            errors.append(f"override.not_object:{asset_id}")
            continue
        mismatches = [
            field for field in REQUIRED_OVERRIDE_FIELDS
            if existing.get(field) != expected[field]
        ]
        if mismatches:
            errors.append(f"override.inconsistent:{asset_id}:{','.join(mismatches)}")

    return selected, expected_by_id, errors, out_of_image_anchor_count


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        catalog = read_json(CATALOG)
        review_state = read_json(REVIEW_STATE)
        overrides = read_json(OVERRIDES)
        selected, expected_by_id, errors, out_of_image_anchor_count = validate(
            catalog, review_state, overrides
        )
    except ValueError as exc:
        print(f"PROMOTE_FAIL {exc}")
        return 1
    if errors:
        print("PROMOTE_FAIL")
        for error in errors:
            print(error)
        return 1

    current = overrides["overrides"]
    missing = sorted(asset_id for asset_id in expected_by_id if asset_id not in current)
    existing = len(expected_by_id) - len(missing)
    if args.check:
        if missing:
            print(
                "PROMOTE_CHECK_READY "
                f"assets={len(selected)} missing_overrides={len(missing)} "
                f"existing_overrides={existing} "
                f"out_of_image_anchor_count={out_of_image_anchor_count}"
            )
        else:
            print(
                "PROMOTE_CHECK_PASS "
                f"assets={len(selected)} verified=128 overrides={len(expected_by_id)} "
                f"out_of_image_anchor_count={out_of_image_anchor_count}"
            )
        return 0

    if missing:
        updated = copy.deepcopy(overrides)
        updated_overrides = updated["overrides"]
        for asset_id in missing:
            updated_overrides[asset_id] = expected_by_id[asset_id]
        atomic_write(OVERRIDES, updated)
    print(
        "PROMOTE_WRITE_PASS "
        f"assets={len(selected)} added_overrides={len(missing)} "
        f"preserved_overrides={existing} "
        f"out_of_image_anchor_count={out_of_image_anchor_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
