"""Promote the verified manual review for the 64 new map entrances/exits.

The catalog and the user's review are deliberately separate concerns.  The
catalog describes the imported PNGs; this tool copies only the verified
``anchor_px`` and ``footprint_tiles`` values into the effective override
document.  It is intentionally fail-closed: the catalog must be exactly the
2026-08-22 64-asset package, every authority review must be verified and must
match its catalog fingerprint, and every output PNG must hash to the catalog.

``--check`` performs the complete read-only preflight.  ``--write`` merges
the 64 target review records and overrides atomically while preserving every
non-target record.  The same directory may be supplied for ``--root`` and
``--authority-root``; in that case the review merge is a no-op and only the
override promotion remains.
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
CATALOG_REL = Path("assets/data/assets/map_exit_asset_catalog.json")
REVIEW_REL = Path(
    "assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
)
OVERRIDES_REL = Path(
    "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
)
PACKAGE_ID = "user_map_exit_pack_20260822_v1"
EXPECTED_IDS = tuple(
    f"user.map_exit.20260822.s{sheet:02d}_r{row}_c{column}"
    for sheet in range(1, 9)
    for row in range(1, 3)
    for column in range(1, 5)
)
EXPECTED_ID_SET = frozenset(EXPECTED_IDS)
TARGET_PREFIX = "user.map_exit.20260822."
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot_read_json:{path}:{exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"json_root_not_object:{path}")
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
    """Return a strict JSON integer pair, rejecting bools and float values."""

    if not isinstance(value, list) or len(value) != 2:
        return None
    result: list[int] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, int):
            return None
        if (positive and item <= 0) or (not positive and item < 0):
            return None
        result.append(item)
    return result


def resolve_image(root: Path, relative_path: Any) -> Path | None:
    if not isinstance(relative_path, str) or not relative_path:
        return None
    if relative_path.startswith(("/", "\\")):
        return None
    normalized = relative_path.replace("\\", "/")
    path = (root / Path(normalized)).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        return None
    return path


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    """Replace one JSON document atomically in its original directory."""

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=path.name + ".", suffix=".tmp", dir=path.parent
    )
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
        raise ValueError(f"catalog.package_id_mismatch:{catalog.get('package_id')!r}")
    assets = catalog.get("assets")
    if not isinstance(assets, list) or len(assets) != len(EXPECTED_IDS):
        count = len(assets) if isinstance(assets, list) else "invalid"
        raise ValueError(f"catalog.asset_count:{count}:expected={len(EXPECTED_IDS)}")

    selected: dict[str, dict[str, Any]] = {}
    for asset in assets:
        if not isinstance(asset, dict):
            raise ValueError("catalog.asset_not_object")
        asset_id = asset.get("asset_id")
        if not isinstance(asset_id, str) or asset_id in selected:
            raise ValueError(f"catalog.duplicate_or_invalid_id:{asset_id!r}")
        if asset_id not in EXPECTED_ID_SET:
            raise ValueError(f"catalog.unexpected_id:{asset_id}")
        if asset.get("package_id") != PACKAGE_ID:
            raise ValueError(f"catalog.asset_package_mismatch:{asset_id}")
        selected[asset_id] = asset

    if set(selected) != EXPECTED_ID_SET:
        missing = sorted(EXPECTED_ID_SET - set(selected))
        extra = sorted(set(selected) - EXPECTED_ID_SET)
        raise ValueError(f"catalog.exact_id_set_mismatch:missing={missing}:extra={extra}")
    return {asset_id: selected[asset_id] for asset_id in EXPECTED_IDS}


def target_ids(items: dict[str, Any], label: str) -> set[str]:
    ids = {asset_id for asset_id in items if asset_id.startswith(TARGET_PREFIX)}
    extra = sorted(ids - EXPECTED_ID_SET)
    if extra:
        raise ValueError(f"{label}.unexpected_target_ids:{extra}")
    return ids


def expected_override(review: dict[str, Any]) -> dict[str, Any]:
    footprint = copy.deepcopy(review["footprint_tiles"])
    return {
        "anchor_px": copy.deepcopy(review["anchor_px"]),
        "footprint_tiles": copy.deepcopy(footprint),
        "visual_footprint_tiles": copy.deepcopy(footprint),
        "occupancy_footprint_tiles": copy.deepcopy(footprint),
        "base_footprint_tiles": copy.deepcopy(footprint),
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": False,
        "placeable": True,
        "calibration_status": "placeable",
        "content_layer": "personal_expansion",
    }


def validate_authority(
    root: Path,
    catalog: dict[str, Any],
    authority_review: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    assets = select_catalog_assets(catalog)
    items = authority_review.get("items")
    if not isinstance(items, dict):
        raise ValueError("authority.review.items_not_object")
    authority_ids = target_ids(items, "authority.review")
    if authority_ids != EXPECTED_ID_SET:
        missing = sorted(EXPECTED_ID_SET - authority_ids)
        raise ValueError(f"authority.review.exact_id_set_mismatch:missing={missing}")

    validated_items: dict[str, dict[str, Any]] = {}
    target_overrides: dict[str, dict[str, Any]] = {}
    for asset_id in EXPECTED_IDS:
        asset = assets[asset_id]
        review = items.get(asset_id)
        if not isinstance(review, dict):
            raise ValueError(f"authority.review.not_object:{asset_id}")
        if review.get("status") != "verified":
            raise ValueError(f"authority.review.not_verified:{asset_id}")
        for field in (
            "display_name",
            "palette_path",
            "image",
            "source_sha256",
            "output_sha256",
        ):
            if review.get(field) != asset.get(field):
                raise ValueError(f"authority.review.{field}_mismatch:{asset_id}")
        if not is_sha256(review.get("source_sha256")) or not is_sha256(
            review.get("output_sha256")
        ):
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
        actual_sha = sha256_file(image_path)
        if actual_sha != asset.get("output_sha256"):
            raise ValueError(f"catalog.image_sha_mismatch:{asset_id}")
        if actual_sha != review.get("output_sha256"):
            raise ValueError(f"authority.review.image_sha_mismatch:{asset_id}")

        validated_items[asset_id] = copy.deepcopy(review)
        target_overrides[asset_id] = expected_override(review)
    return validated_items, target_overrides


def merge_target_items(
    current: dict[str, Any],
    target_items: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], int]:
    items = current.get("items")
    if not isinstance(items, dict):
        raise ValueError("review.items_not_object")
    target_ids(items, "review")
    merged = copy.deepcopy(current)
    merged_items = merged["items"]
    for asset_id in EXPECTED_IDS:
        merged_items[asset_id] = copy.deepcopy(target_items[asset_id])
    changed = sum(
        canonical(items.get(asset_id)) != canonical(target_items[asset_id])
        for asset_id in EXPECTED_IDS
    )
    return merged, changed


def merge_target_overrides(
    current: dict[str, Any],
    target_overrides: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], int]:
    overrides = current.get("overrides")
    if not isinstance(overrides, dict):
        raise ValueError("overrides.overrides_not_object")
    target_ids(overrides, "overrides")
    merged = copy.deepcopy(current)
    merged_overrides = merged["overrides"]
    for asset_id in EXPECTED_IDS:
        merged_overrides[asset_id] = copy.deepcopy(target_overrides[asset_id])
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
    parser.add_argument("--authority-root", type=Path, default=None)
    args = parser.parse_args()

    root = args.root.resolve()
    authority_root = (args.authority_root or args.root).resolve()
    try:
        catalog = read_json(root / CATALOG_REL)
        current_review = read_json(root / REVIEW_REL)
        current_overrides = read_json(root / OVERRIDES_REL)
        authority_review = read_json(authority_root / REVIEW_REL)
        target_items, target_overrides = validate_authority(
            root, catalog, authority_review
        )
        merged_review, changed_review = merge_target_items(current_review, target_items)
        merged_overrides, changed_overrides = merge_target_overrides(
            current_overrides, target_overrides
        )
    except ValueError as exc:
        print(f"MAP_EXIT_PROMOTION_FAIL {exc}")
        return 1

    if args.check:
        if changed_review or changed_overrides:
            print(
                "MAP_EXIT_PROMOTION_CHECK_READY "
                f"assets=64 review_updates={changed_review} "
                f"override_updates={changed_overrides} non_target_preserved=true"
            )
        else:
            print(
                "MAP_EXIT_PROMOTION_CHECK_PASS "
                "assets=64 review=64 overrides=64 non_target_preserved=true"
            )
        return 0

    try:
        if changed_review:
            atomic_write(root / REVIEW_REL, merged_review)
        if changed_overrides:
            atomic_write(root / OVERRIDES_REL, merged_overrides)
    except OSError as exc:
        print(f"MAP_EXIT_PROMOTION_FAIL write_error:{exc}")
        return 1

    print(
        "MAP_EXIT_PROMOTION_WRITE_PASS "
        f"assets=64 review_updates={changed_review} "
        f"override_updates={changed_overrides} non_target_preserved=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
