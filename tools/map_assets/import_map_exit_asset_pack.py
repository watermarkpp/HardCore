"""Import the verified 64-piece isometric map-exit package."""
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
    r"C:\Users\Administrator\Desktop\sucai\新增\地图出入口"
    r"\MSE_ISO_Map_Exit_Assets_64_v1.zip"
)
PACKAGE_DIRECTORY = "MSE_ISO_Map_Exit_Assets_64_v1"
PACKAGE_ID = "mse_iso_map_exit_assets_64_v1"
DESTINATION = (
    ROOT
    / "assets/art/maps/_shared/user_palette/decorations_1/map_entrances/mse_fixed_64"
)
CATALOG_PATH = ROOT / "assets/data/assets/map_exit_asset_catalog.json"
THEME_LABELS = {
    "deep_forest": "深林",
    "desert_cave": "沙漠洞穴",
    "shrine": "圣坛",
    "temple": "寺庙",
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


def validate_image(payload: bytes, expected_size: list[int], asset_id: str) -> tuple[int, int]:
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
        return width, height


def build_asset(
    source: dict,
    destination: Path,
    archive_path: Path,
    internal_image_path: str,
    payload: bytes,
) -> dict:
    width, height = validate_image(
        payload,
        source["canvas_size"],
        str(source["asset_id"]),
    )
    theme = str(source["theme"])
    set_id = str(source["set_id"]).upper()
    anchor = [int(source["suggested_anchor"][0]), int(source["suggested_anchor"][1])]
    footprint = [8, 6]
    project_image = destination.relative_to(ROOT).as_posix()
    digest = sha256(payload)
    package_asset_id = str(source["asset_id"])
    return {
        "asset_id": f"mse.map_exit.{package_asset_id}",
        "display_name": str(source["display_name"]),
        "asset_type": "large_prop",
        "category": "map_entrance",
        "object_class": "map_entrance",
        "theme": theme,
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": [width, height],
        "image_size": [width, height],
        "visible_bounds_px": [0, 0, width, height],
        "anchor_px": anchor,
        "placement_anchor_px": anchor,
        "door_anchor_px": anchor,
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "footprint_tiles": footprint,
        "visual_footprint_tiles": footprint,
        "occupancy_footprint_tiles": footprint,
        "base_footprint_tiles": footprint,
        "collision_footprint_tiles": [0, 0],
        "collision_cells": [],
        "tile_size": [64, 32],
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_layer": "object_base",
        "default_object_role": "terrain",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": False,
        "occlusion": False,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "calibration_source": "package_suggested_anchor_v1",
        "palette_path": (
            f"装饰物1/地图出入口/MSE固定64/"
            f"{THEME_LABELS.get(theme, theme)}/{set_id}套"
        ),
        "source_external_path": f"{archive_path}::{internal_image_path}",
        "source_sha256": digest,
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "verified_package_rgba_passthrough",
        "tags": [
            "map_exit",
            "map_entrance",
            theme,
            f"set_{set_id.lower()}",
            str(source["placement_kind"]),
            str(source["logical_direction"]),
            str(source["screen_position"]),
        ],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "map_portal",
        "trigger_on_enter": True,
        "package_id": PACKAGE_ID,
        "package_asset_id": package_asset_id,
        "set_id": set_id,
        "placement_kind": str(source["placement_kind"]),
        "logical_direction": str(source["logical_direction"]),
        "screen_position": str(source["screen_position"]),
        "view": str(source["view"]),
        "opening_visible": bool(source["opening_visible"]),
        "requires_runtime_rotation": False,
        "allow_flip": False,
        "source_sheet": str(source["source_sheet"]),
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
        source_assets = list(manifest.get("assets", []))
        if str(manifest.get("package_id", "")) != PACKAGE_ID:
            raise SystemExit("unexpected package id")
        if len(source_assets) != 64:
            raise SystemExit(f"expected 64 assets, got {len(source_assets)}")
        if not bool(validation.get("passed", False)):
            raise SystemExit("package validation report did not pass")

        if DESTINATION.exists():
            shutil.rmtree(DESTINATION)
        DESTINATION.mkdir(parents=True)

        catalog_assets = []
        for source in source_assets:
            relative_image = PurePosixPath(str(source["image"]))
            if (
                len(relative_image.parts) != 4
                or relative_image.parts[0] != "transparent_assets"
            ):
                raise SystemExit(f"unexpected image path: {relative_image}")
            theme = str(source["theme"])
            set_id = str(source["set_id"]).upper()
            destination = (
                DESTINATION
                / THEME_LABELS.get(theme, theme)
                / f"{set_id}套"
                / relative_image.name
            )
            payload = archive.read(archive_member(relative_image.as_posix()))
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)
            catalog_assets.append(
                build_asset(
                    source,
                    destination,
                    archive_path,
                    relative_image.as_posix(),
                    payload,
                )
            )

    ids = [str(asset["asset_id"]) for asset in catalog_assets]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate stable asset id")
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_archive": str(archive_path),
        "asset_count": len(catalog_assets),
        "classification": "装饰物1/地图出入口/MSE固定64",
        "default_collision_policy": "none",
        "assets": catalog_assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_MAP_EXIT_ASSET_PACK_IMPORT_PASS "
        f"assets={len(catalog_assets)} destination={DESTINATION}"
    )


if __name__ == "__main__":
    main()
