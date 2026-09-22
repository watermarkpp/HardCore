"""Promote the dirty manual review for the 48 small decorations.

The clean worktree owns the catalog, review state, and overrides.  The
authority review is read from a separate worktree so that this tool can copy
only the exact ``mse.small_decor.001`` through ``.048`` records.  All other
review items and overrides are preserved byte-for-byte in the in-memory
merge, and the write path is deliberately limited to those 48 IDs.

``--check`` validates the authority and reports whether promotion is ready or
complete.  ``--write`` promotes the 48 review records and writes exactly the
48 corresponding overrides.  Both modes fail closed on catalog selection,
fingerprint, image, geometry, or schema errors.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import re
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_AUTHORITY_ROOT = ROOT.parent / "maps"
CATALOG_REL = Path("assets/data/assets/map_small_decoration_asset_catalog.json")
REVIEW_REL = Path("assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json")
OVERRIDES_REL = Path("assets/data/expansions/personal_expansion_001/map_asset_overrides.json")
PACKAGE_ID = "mse_small_decoration_pack_20260822_v1"
EXPECTED_IDS = tuple(f"mse.small_decor.{index:03d}" for index in range(1, 49))
EXPECTED_ID_SET = frozenset(EXPECTED_IDS)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
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


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def integer_pair(value: Any, *, positive: bool) -> list[int] | None:
    if not isinstance(value, list) or len(value) != 2:
        return None
    result: list[int] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, (int, float)):
            return None
        if not math.isfinite(float(item)) or int(item) != item:
            return None
        number = int(item)
        if (positive and number <= 0) or (not positive and number < 0):
            return None
        result.append(number)
    return result


def resolve_image(root: Path, relative_path: Any) -> Path | None:
    if not isinstance(relative_path, str) or not relative_path or relative_path.startswith(("/", "\\")):
        return None
    normalized = relative_path.replace("\\", "/")
    path = (root / Path(normalized)).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        return None
    return path


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


def select_catalog_assets(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if catalog.get("package_id") != PACKAGE_ID:
        raise ValueError("catalog.package_id_mismatch")
    assets = catalog.get("assets")
    if not isinstance(assets, list) or len(assets) != len(EXPECTED_IDS):
        raise ValueError(f"catalog.asset_count={len(assets) if isinstance(assets, list) else 'invalid'} expected=48")
    selected: dict[str, dict[str, Any]] = {}
    for asset in assets:
        if not isinstance(asset, dict):
            raise ValueError("catalog.asset_not_object")
        asset_id = str(asset.get("asset_id", ""))
        if asset_id in selected:
            raise ValueError(f"catalog.duplicate_id:{asset_id}")
        if asset_id not in EXPECTED_ID_SET:
            raise ValueError(f"catalog.unexpected_id:{asset_id}")
        if asset.get("package_id") != PACKAGE_ID:
            raise ValueError(f"catalog.asset_package_mismatch:{asset_id}")
        selected[asset_id] = asset
    if set(selected) != EXPECTED_ID_SET:
        raise ValueError("catalog.exact_id_set_mismatch")
    return {asset_id: selected[asset_id] for asset_id in EXPECTED_IDS}


def validate_authority(
    root: Path,
    authority_root: Path,
    catalog: dict[str, Any],
    authority_review: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    assets = select_catalog_assets(catalog)
    items = authority_review.get("items")
    if not isinstance(items, dict):
        raise ValueError("authority.review.items_not_object")
    authority_ids = {asset_id for asset_id in items if asset_id.startswith("mse.small_decor.")}
    if authority_ids != EXPECTED_ID_SET:
        missing = sorted(EXPECTED_ID_SET - authority_ids)
        extra = sorted(authority_ids - EXPECTED_ID_SET)
        raise ValueError(f"authority.review.exact_small_id_set_mismatch missing={missing} extra={extra}")

    expected_overrides: dict[str, dict[str, Any]] = {}
    validated_items: dict[str, dict[str, Any]] = {}
    for asset_id in EXPECTED_IDS:
        asset = assets[asset_id]
        review = items.get(asset_id)
        if not isinstance(review, dict):
            raise ValueError(f"authority.review.not_object:{asset_id}")
        if review.get("status") != "verified":
            raise ValueError(f"authority.review.not_verified:{asset_id}")
        for field in ("display_name", "palette_path", "image", "source_sha256", "output_sha256"):
            if review.get(field) != asset.get(field):
                raise ValueError(f"authority.review.{field}_mismatch:{asset_id}")
        if not is_sha256(review.get("source_sha256")) or not is_sha256(review.get("output_sha256")):
            raise ValueError(f"authority.review.fingerprint_invalid:{asset_id}")
        anchor = integer_pair(review.get("anchor_px"), positive=False)
        footprint = integer_pair(review.get("footprint_tiles"), positive=True)
        if anchor is None:
            raise ValueError(f"authority.review.invalid_anchor:{asset_id}")
        if footprint is None:
            raise ValueError(f"authority.review.invalid_footprint:{asset_id}")
        image_path = resolve_image(root, asset.get("image"))
        if image_path is None or not image_path.is_file():
            raise ValueError(f"catalog.image_missing_or_unsafe:{asset_id}")
        if sha256_file(image_path) != str(asset.get("output_sha256", "")):
            raise ValueError(f"catalog.image_sha_mismatch:{asset_id}")
        if sha256_file(image_path) != str(review.get("output_sha256", "")):
            raise ValueError(f"authority.review.image_sha_mismatch:{asset_id}")
        validated_items[asset_id] = copy.deepcopy(review)
        expected_overrides[asset_id] = {
            "anchor_px": copy.deepcopy(review["anchor_px"]),
            "footprint_tiles": copy.deepcopy(review["footprint_tiles"]),
            "visual_footprint_tiles": copy.deepcopy(review["footprint_tiles"]),
            "occupancy_footprint_tiles": copy.deepcopy(review["footprint_tiles"]),
            "base_footprint_tiles": copy.deepcopy(review["footprint_tiles"]),
            "collision_footprint_tiles": [0, 0],
            "collision_policy": "none",
            "collision_profile_id": "none_visual",
            "navigation_policy": "ignore",
            "placeable": True,
            "calibration_status": "placeable",
            "content_layer": "personal_expansion",
        }
    return validated_items, expected_overrides


def merge_target_items(
    current: dict[str, Any], target_items: dict[str, dict[str, Any]], *, label: str
) -> tuple[dict[str, Any], int]:
    items = current.get("items")
    if not isinstance(items, dict):
        raise ValueError(f"{label}.items_not_object")
    unexpected = sorted(
        asset_id for asset_id in items
        if asset_id.startswith("mse.small_decor.") and asset_id not in EXPECTED_ID_SET
    )
    if unexpected:
        raise ValueError(f"{label}.unexpected_small_ids:{unexpected}")
    merged = copy.deepcopy(current)
    merged_items = merged["items"]
    before_non_target = {
        asset_id: canonical(value)
        for asset_id, value in items.items()
        if asset_id not in EXPECTED_ID_SET
    }
    for asset_id in EXPECTED_IDS:
        merged_items[asset_id] = copy.deepcopy(target_items[asset_id])
    after_non_target = {
        asset_id: canonical(value)
        for asset_id, value in merged_items.items()
        if asset_id not in EXPECTED_ID_SET
    }
    if before_non_target != after_non_target:
        raise ValueError(f"{label}.non_target_mutation")
    changed = sum(
        canonical(items.get(asset_id)) != canonical(target_items[asset_id])
        for asset_id in EXPECTED_IDS
    )
    return merged, changed


def merge_target_overrides(
    current: dict[str, Any], target_overrides: dict[str, dict[str, Any]]
) -> tuple[dict[str, Any], int]:
    overrides = current.get("overrides")
    if not isinstance(overrides, dict):
        raise ValueError("overrides.overrides_not_object")
    unexpected = sorted(
        asset_id for asset_id in overrides
        if asset_id.startswith("mse.small_decor.") and asset_id not in EXPECTED_ID_SET
    )
    if unexpected:
        raise ValueError(f"overrides.unexpected_small_ids:{unexpected}")
    merged = copy.deepcopy(current)
    merged_overrides = merged["overrides"]
    before_non_target = {
        asset_id: canonical(value)
        for asset_id, value in overrides.items()
        if asset_id not in EXPECTED_ID_SET
    }
    for asset_id in EXPECTED_IDS:
        merged_overrides[asset_id] = copy.deepcopy(target_overrides[asset_id])
    after_non_target = {
        asset_id: canonical(value)
        for asset_id, value in merged_overrides.items()
        if asset_id not in EXPECTED_ID_SET
    }
    if before_non_target != after_non_target:
        raise ValueError("overrides.non_target_mutation")
    changed = sum(
        canonical(overrides.get(asset_id)) != canonical(target_overrides[asset_id])
        for asset_id in EXPECTED_IDS
    )
    return merged, changed


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--authority-root", type=Path, default=DEFAULT_AUTHORITY_ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    authority_root = args.authority_root.resolve()
    if root == authority_root:
        print("SMALL_DECOR_PROMOTION_FAIL authority_root_must_differ_from_root")
        return 1
    try:
        catalog = read_json(root / CATALOG_REL)
        clean_review = read_json(root / REVIEW_REL)
        clean_overrides = read_json(root / OVERRIDES_REL)
        authority_review = read_json(authority_root / REVIEW_REL)
        target_items, target_overrides = validate_authority(root, authority_root, catalog, authority_review)
        merged_review, changed_review = merge_target_items(clean_review, target_items, label="review")
        merged_overrides, changed_overrides = merge_target_overrides(clean_overrides, target_overrides)
    except ValueError as exc:
        print(f"SMALL_DECOR_PROMOTION_FAIL {exc}")
        return 1

    if args.check:
        if changed_review or changed_overrides:
            print(
                "SMALL_DECOR_PROMOTION_CHECK_READY "
                f"assets=48 review_updates={changed_review} override_updates={changed_overrides}"
            )
        else:
            print("SMALL_DECOR_PROMOTION_CHECK_PASS assets=48 review=48 overrides=48 non_target_preserved=true")
        return 0

    try:
        if changed_review:
            atomic_write(root / REVIEW_REL, merged_review)
        if changed_overrides:
            atomic_write(root / OVERRIDES_REL, merged_overrides)
    except OSError as exc:
        print(f"SMALL_DECOR_PROMOTION_FAIL write_error:{exc}")
        return 1
    print(
        "SMALL_DECOR_PROMOTION_WRITE_PASS "
        f"assets=48 review_updates={changed_review} override_updates={changed_overrides} "
        "non_target_preserved=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
