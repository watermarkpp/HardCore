"""Promote the verified manual review for the two portal-gate assets.

Same contract as promote_map_exit_reviews_20260822.py, scoped to the
user_portal_gate_pack_20260916_v1 package: the catalog describes the imported
PNGs; this tool copies only the verified ``anchor_px`` and ``footprint_tiles``
values into the effective override document. Fail-closed preflight: the
catalog must be exactly the 2026-09-16 2-asset portal-gate package, both
reviews must be verified and must match their catalog fingerprints, and both
output PNGs must hash to the catalog.

``--check`` performs the complete read-only preflight. ``--write`` merges the
two target override records atomically while preserving every non-target
record.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CATALOG_REL = Path("assets/data/assets/map_portal_gate_asset_catalog.json")
REVIEW_REL = Path(
    "assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
)
OVERRIDES_REL = Path(
    "assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
)
PACKAGE_ID = "user_portal_gate_pack_20260916_v1"
EXPECTED_IDS = (
    "user.portal_gate.20260916.s01_r1_c1",
    "user.portal_gate.20260916.s02_r1_c1",
)
EXPECTED_ID_SET = frozenset(EXPECTED_IDS)
TARGET_PREFIX = "user.portal_gate.20260916."
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


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def integer_pair(value: Any, *, positive: bool) -> list[int] | None:
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
        raise ValueError(f"catalog.exact_id_set_mismatch:missing={missing}")
    return {asset_id: selected[asset_id] for asset_id in EXPECTED_IDS}


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
    review_state: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    assets = select_catalog_assets(catalog)
    items = review_state.get("items")
    if not isinstance(items, dict):
        raise ValueError("review.items_not_object")
    for asset_id in EXPECTED_IDS:
        review = items.get(asset_id)
        if not isinstance(review, dict):
            raise ValueError(f"review.missing:{asset_id}")
        if review.get("status") != "verified":
            raise ValueError(f"review.not_verified:{asset_id}")
        asset = assets[asset_id]
        for field in (
            "display_name",
            "palette_path",
            "image",
            "source_sha256",
            "output_sha256",
        ):
            if review.get(field) != asset.get(field):
                raise ValueError(f"review.{field}_mismatch:{asset_id}")
        if not is_sha256(review.get("source_sha256")) or not is_sha256(
            review.get("output_sha256")
        ):
            raise ValueError(f"review.fingerprint_invalid:{asset_id}")
        anchor = integer_pair(review.get("anchor_px"), positive=False)
        footprint = integer_pair(review.get("footprint_tiles"), positive=True)
        if anchor is None:
            raise ValueError(f"review.invalid_anchor:{asset_id}")
        if footprint is None:
            raise ValueError(f"review.invalid_footprint:{asset_id}")
        image_path = resolve_image(root, asset.get("image"))
        if image_path is None or not image_path.is_file():
            raise ValueError(f"catalog.image_missing_or_unsafe:{asset_id}")
        actual_sha = sha256_file(image_path)
        if actual_sha != asset.get("output_sha256"):
            raise ValueError(f"catalog.image_sha_mismatch:{asset_id}")
        if actual_sha != review.get("output_sha256"):
            raise ValueError(f"review.image_sha_mismatch:{asset_id}")
    return {asset_id: items[asset_id] for asset_id in EXPECTED_IDS}


def build_target_overrides(
    root: Path,
    catalog: dict[str, Any],
    review_state: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    validated = validate_authority(root, catalog, review_state)
    return {
        asset_id: expected_override(validated[asset_id])
        for asset_id in EXPECTED_IDS
    }


def write_overrides(
    overrides_doc: dict[str, Any],
    target_overrides: dict[str, dict[str, Any]],
) -> int:
    merged = copy.deepcopy(overrides_doc)
    records = merged.get("overrides")
    if not isinstance(records, dict):
        records = {}
        merged["overrides"] = records
    written = 0
    for asset_id, record in target_overrides.items():
        if records.get(asset_id) != record:
            records[asset_id] = copy.deepcopy(record)
            written += 1
    if written:
        atomic_write(OVERRIDES_REL, merged)
    return written


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        catalog = read_json(ROOT / CATALOG_REL)
        review_state = read_json(ROOT / REVIEW_REL)
        target_overrides = build_target_overrides(ROOT, catalog, review_state)
        if args.check:
            overrides_doc = read_json(ROOT / OVERRIDES_REL)
            pending = {
                asset_id
                for asset_id, record in target_overrides.items()
                if overrides_doc.get("overrides", {}).get(asset_id) != record
            }
            print(
                "PORTAL_GATE_REVIEW_PROMOTE_CHECK_PASS targets=2 "
                f"pending_write={len(pending)}"
            )
            return 0
        overrides_doc = read_json(ROOT / OVERRIDES_REL)
        written = write_overrides(overrides_doc, target_overrides)
        print(f"PORTAL_GATE_REVIEW_PROMOTE_WRITE records_written={written}")
        after = read_json(ROOT / OVERRIDES_REL)
        if any(
            after.get("overrides", {}).get(asset_id) != record
            for asset_id, record in target_overrides.items()
        ):
            raise ValueError("post_write_verification_failed")
        print("PORTAL_GATE_REVIEW_PROMOTE_VERIFY_PASS targets=2")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"PORTAL_GATE_REVIEW_PROMOTE_FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
