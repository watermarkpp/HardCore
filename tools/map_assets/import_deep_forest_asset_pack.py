"""Import the verified 56-piece isometric deep-forest asset package."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import zipfile
from pathlib import Path, PurePosixPath

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ARCHIVE = Path(
    r"C:\Users\Administrator\Desktop\sucai\新增\树木"
    r"\MSE_ISO_Deep_Forest_AssetPack_56_v3_LOCAL_FREE.zip"
)
PACKAGE_DIRECTORY = "MSE_ISO_Deep_Forest_AssetPack_56_v3_LOCAL_FREE"
PACKAGE_ID = "MSE_ISO_Deep_Forest_AssetPack_56_v3_LOCAL_FREE"
DESTINATION = (
    ROOT
    / "assets/art/maps/_shared/user_palette/decorations_1/trees/mse_deep_forest_44"
)
LEGACY_DESTINATION = (
    ROOT
    / "assets/art/maps/_shared/user_palette/decorations_1/trees/MSE深林56"
)
CATALOG_PATH = ROOT / "assets/data/assets/map_deep_forest_asset_catalog.json"
CATEGORY_LABELS = {
    "single_trees": "独立树木",
    "fallen_trees": "倒木",
    "grass_groundcover": "草地覆盖",
    "stumps": "树墩",
}
EXPECTED_CATEGORY_COUNTS = {
    "single_trees": 10,
    "fallen_trees": 12,
    "grass_groundcover": 10,
    "stumps": 12,
}
SOURCE_CATEGORY_COUNTS = {
    "forest_clusters": 12,
    **EXPECTED_CATEGORY_COUNTS,
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def archive_member(relative_path: str) -> str:
    relative = PurePosixPath(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe archive member: {relative_path}")
    return f"{PACKAGE_DIRECTORY}/{relative.as_posix()}"


def read_json(archive: zipfile.ZipFile, relative_path: str) -> dict:
    return json.loads(archive.read(archive_member(relative_path)).decode("utf-8"))


def validate_package(manifest: dict, validation: dict) -> list[dict]:
    if str(manifest.get("pack_id", "")) != PACKAGE_ID:
        raise SystemExit("unexpected package id")
    source_assets = list(manifest.get("assets", []))
    source_count = len(source_assets)
    if source_count not in [44, 56]:
        raise SystemExit(f"expected 44 or 56 source assets, got {source_count}")
    if int(manifest.get("asset_count", 0)) != source_count:
        raise SystemExit("manifest asset count mismatch")
    category_counts = dict(manifest.get("category_counts", {}))
    source_counts_with_clusters = {
        **SOURCE_CATEGORY_COUNTS,
        "total": 56,
    }
    source_counts_without_clusters = {
        **EXPECTED_CATEGORY_COUNTS,
        "total": 44,
    }
    if category_counts not in [
        source_counts_with_clusters,
        source_counts_without_clusters,
    ]:
        raise SystemExit("unexpected category counts")
    if str(validation.get("status", "")) not in [
        "PASS",
        "PASS_WITH_MANUAL_REVIEW",
    ]:
        raise SystemExit("package validation status is not expected")
    allowed_manual_checks = {
        "visual_edge_quality",
        "anchor_footprint_collision_editor_calibration",
    }
    for check in validation.get("checks", []):
        status = str(check.get("status", ""))
        name = str(check.get("name", ""))
        if status == "PASS":
            continue
        if status == "MANUAL_REVIEW_REQUIRED" and name in allowed_manual_checks:
            continue
        raise SystemExit(f"package check failed: {name}={status}")
    return source_assets


def validate_image(
    payload: bytes,
    expected_size: list[int],
    anchor: list[int],
    visible_bounds: list[int],
    asset_id: str,
) -> tuple[int, int]:
    with Image.open(io.BytesIO(payload)) as image:
        image.load()
        width, height = image.size
        if [width, height] != [int(expected_size[0]), int(expected_size[1])]:
            raise ValueError(
                f"{asset_id}: size mismatch {(width, height)} != {expected_size}"
            )
        if image.mode != "RGBA":
            raise ValueError(f"{asset_id}: expected RGBA, got {image.mode}")
        alpha_min, alpha_max = image.getchannel("A").getextrema()
        if alpha_min >= 255 or alpha_max <= 0:
            raise ValueError(f"{asset_id}: missing mixed transparent/opaque pixels")
        if not (0 <= anchor[0] < width and 0 <= anchor[1] < height):
            raise ValueError(f"{asset_id}: anchor outside canvas: {anchor}")
        if (
            len(visible_bounds) != 4
            or not 0 <= visible_bounds[0] < visible_bounds[2] <= width
            or not 0 <= visible_bounds[1] < visible_bounds[3] <= height
        ):
            raise ValueError(f"{asset_id}: invalid visible bounds: {visible_bounds}")
        return width, height


def build_asset(
    source: dict,
    meta: dict,
    destination: Path,
    archive_path: Path,
    internal_image_path: str,
    payload: bytes,
) -> dict:
    package_asset_id = str(source["asset_id"])
    if package_asset_id != str(meta.get("asset_id", "")):
        raise ValueError(f"{package_asset_id}: manifest/meta id mismatch")
    category = str(meta["category"])
    if category not in CATEGORY_LABELS:
        raise ValueError(f"{package_asset_id}: unexpected category {category}")
    anchor = [int(meta["anchor"][0]), int(meta["anchor"][1])]
    visible_bounds = [int(value) for value in meta["visible_bounds_px"]]
    width, height = validate_image(
        payload,
        meta["canvas_size"],
        anchor,
        visible_bounds,
        package_asset_id,
    )
    footprint = [
        max(1, int(meta["footprint_tiles"][0])),
        max(1, int(meta["footprint_tiles"][1])),
    ]
    project_image = destination.relative_to(ROOT).as_posix()
    digest = sha256(payload)
    return {
        "asset_id": f"mse.deep_forest.{package_asset_id.lower()}",
        "display_name": str(meta["display_name"]),
        "asset_type": str(meta["asset_type"]),
        "category": "tree",
        "object_class": "tree",
        "source_category": category,
        "theme": "deep_forest",
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": [width, height],
        "image_size": [width, height],
        "visible_bounds_px": visible_bounds,
        "anchor_px": anchor,
        "placement_anchor_px": anchor,
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint,
        "visual_footprint_tiles": footprint,
        "occupancy_footprint_tiles": footprint,
        "base_footprint_tiles": footprint,
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "placement_clearance_cells": [],
        "tile_size": [64, 32],
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_layer": str(meta["default_layer"]),
        # This pack is visual-only in the user's workflow. Keeping the source
        # "obstacle" role makes the editor UI re-enable overlap blocking during
        # validation even though the catalog collision policy is "none".
        "authored_default_object_role": str(meta["default_object_role"]),
        "default_object_role": "decoration",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": True,
        "map_collision_override": "default",
        "collision_authority": "manual_by_user",
        "occlusion": bool(meta["occlusion"]),
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "calibration_source": "package_metadata_anchor_verified_v1",
        "palette_path": (
            "装饰物1/树木/MSE深林44/"
            + CATEGORY_LABELS[category]
        ),
        "source_external_path": f"{archive_path}::{internal_image_path}",
        "source_sha256": digest,
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "verified_package_rgba_passthrough",
        "tags": list(meta.get("tags", []))
        + ["tree", "manual_collision", category],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "package_asset_id": package_asset_id,
        "axis": str(meta.get("axis", "none")),
        "scene_intent": str(meta.get("scene_intent", "")),
        "source_sheet": str(meta.get("source_sheet", "")),
        "authored_collision_policy": str(meta.get("collision_policy", "none")),
        "authored_collision_preset": str(meta.get("collision_preset", "none")),
        "projection": "orthographic_isometric_2_to_1",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    args = parser.parse_args()
    archive_path = args.archive.resolve()
    if not archive_path.is_file():
        raise SystemExit(f"missing archive: {archive_path}")

    with zipfile.ZipFile(archive_path) as archive:
        manifest = read_json(archive, "manifest.json")
        validation = read_json(archive, "validation_report.json")
        source_assets = validate_package(manifest, validation)

        for generated_destination in [DESTINATION, LEGACY_DESTINATION]:
            if generated_destination.exists():
                shutil.rmtree(generated_destination)
        DESTINATION.mkdir(parents=True)

        catalog_assets = []
        category_counts: dict[str, int] = {}
        for source in source_assets:
            if str(source.get("category", "")) == "forest_clusters":
                continue
            relative_image = PurePosixPath(str(source["path"]))
            if (
                len(relative_image.parts) != 3
                or relative_image.parts[0] != "transparent_assets"
            ):
                raise SystemExit(f"unexpected image path: {relative_image}")
            meta = read_json(archive, str(source["meta"]))
            category = str(meta["category"])
            if category != relative_image.parts[1]:
                raise SystemExit(f"category/path mismatch: {relative_image}")
            destination = (
                DESTINATION
                / CATEGORY_LABELS[category]
                / relative_image.name
            )
            payload = archive.read(archive_member(relative_image.as_posix()))
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)
            catalog_assets.append(
                build_asset(
                    source,
                    meta,
                    destination,
                    archive_path,
                    relative_image.as_posix(),
                    payload,
                )
            )
            category_counts[category] = category_counts.get(category, 0) + 1

    if category_counts != EXPECTED_CATEGORY_COUNTS:
        raise SystemExit(f"unexpected imported category counts: {category_counts}")
    ids = [str(asset["asset_id"]) for asset in catalog_assets]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate stable asset id")
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 3,
        "source_archive": str(archive_path),
        "source_archive_sha256": sha256(archive_path.read_bytes()),
        "asset_count": len(catalog_assets),
        "category_counts": category_counts,
        "classification": "装饰物1/树木/MSE深林44",
        "default_collision_policy": "none",
        "collision_authority": "manual_by_user",
        "assets": catalog_assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_DEEP_FOREST_ASSET_PACK_IMPORT_PASS "
        f"assets={len(catalog_assets)} excluded_forest_clusters=12 "
        f"destination={DESTINATION}"
    )


if __name__ == "__main__":
    main()
