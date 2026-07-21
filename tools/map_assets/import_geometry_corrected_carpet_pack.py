"""Import the verified six-piece geometry-corrected carpet package."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path, PurePosixPath

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ARCHIVE = (
    Path.home()
    / "Desktop"
    / "sucai"
    / "新增"
    / "地毯"
    / "MSE_ISO_CARPETS_6_GEOMETRY_CORRECTED.zip"
)
PACKAGE_DIRECTORY = "MSE_ISO_CARPETS_6_GEOMETRY_CORRECTED"
PACKAGE_ID = "MSE_ISO_CARPETS_6_GEOMETRY_CORRECTED"
REPLACED_PACKAGE_ID = "mse_new_carpet_6_v1"
DESTINATION = ROOT / "assets/art/maps/_shared/user_palette/decorations_1/carpets"
CATALOG_PATH = ROOT / "assets/data/assets/map_new_carpet_asset_catalog.json"
PALETTE_PATH = "装饰物1/地毯"
ASSET_ORDER = (
    ("CARPET_RED_SKULL_LEFT", "mse.new_carpet.01"),
    ("CARPET_BLACK_ARCANE_LEFT", "mse.new_carpet.02"),
    ("CARPET_PURPLE_GOTHIC_LEFT", "mse.new_carpet.03"),
    ("CARPET_RED_SKULL_RIGHT", "mse.new_carpet.04"),
    ("CARPET_BLACK_ARCANE_RIGHT", "mse.new_carpet.05"),
    ("CARPET_PURPLE_GOTHIC_RIGHT", "mse.new_carpet.06"),
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def archive_member(relative_path: str) -> str:
    relative = PurePosixPath(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe archive member: {relative_path}")
    return f"{PACKAGE_DIRECTORY}/{relative.as_posix()}"


def read_json(archive: zipfile.ZipFile, relative_path: str) -> dict:
    return json.loads(archive.read(archive_member(relative_path)).decode("utf-8"))


def validate_manifest(manifest: dict) -> None:
    if str(manifest.get("pack_id", "")) != PACKAGE_ID:
        raise SystemExit("unexpected carpet package id")
    if manifest.get("tile_size", []) != [64, 32]:
        raise SystemExit("carpet package tile size is not 64x32")
    if int(manifest.get("asset_count", 0)) != len(ASSET_ORDER):
        raise SystemExit("carpet package asset count mismatch")
    if str(manifest.get("projection", "")) != "fixed_2_1_orthographic_isometric":
        raise SystemExit("carpet package projection mismatch")
    if set(manifest.get("assets", [])) != {
        package_asset_id for package_asset_id, _stable_id in ASSET_ORDER
    }:
        raise SystemExit("carpet package asset list mismatch")
    geometry = manifest.get("geometry", {})
    if (
        geometry.get("iso_x_vector", []) != [64, 32]
        or geometry.get("iso_y_vector", []) != [-64, 32]
        or geometry.get("long_edge_slopes", []) != [0.5, -0.5]
        or geometry.get("short_edge_slopes", []) != [-0.5, 0.5]
        or not bool(geometry.get("short_ends_are_seamless", False))
    ):
        raise SystemExit("carpet package geometry contract mismatch")


def validate_asset(
    package_asset_id: str,
    meta: dict,
    payload: bytes,
) -> tuple[Image.Image, list[int]]:
    if str(meta.get("asset_id", "")) != package_asset_id:
        raise ValueError(f"{package_asset_id}: metadata id mismatch")
    direction = str(meta.get("direction", ""))
    expected_direction = "left" if package_asset_id.endswith("_LEFT") else "right"
    expected_footprint = [10, 5] if expected_direction == "left" else [5, 10]
    if direction != expected_direction:
        raise ValueError(f"{package_asset_id}: direction mismatch")
    if meta.get("tile_size", []) != [64, 32]:
        raise ValueError(f"{package_asset_id}: tile size mismatch")
    if meta.get("footprint_tiles", []) != expected_footprint:
        raise ValueError(f"{package_asset_id}: footprint mismatch")
    if meta.get("canvas_size", []) != [960, 480]:
        raise ValueError(f"{package_asset_id}: canvas size mismatch")
    if meta.get("anchor", []) != [480, 240]:
        raise ValueError(f"{package_asset_id}: anchor mismatch")
    if (
        str(meta.get("default_layer", "")) != "ground_overlay"
        or str(meta.get("collision_policy", "")) != "none"
        or str(meta.get("navigation_policy", "")) != "ignore"
        or bool(meta.get("runtime_rotation_required", True))
        or bool(meta.get("runtime_mirroring_required", True))
        or not bool(meta.get("short_end_seamless", False))
    ):
        raise ValueError(f"{package_asset_id}: runtime contract mismatch")

    with Image.open(io.BytesIO(payload)) as source:
        source.load()
        image = source.convert("RGBA")
    if image.size != (960, 480):
        raise ValueError(f"{package_asset_id}: PNG size mismatch")
    if image.getchannel("A").getextrema() != (0, 255):
        raise ValueError(f"{package_asset_id}: PNG is not mixed-alpha RGBA")
    visible_bounds = image.getchannel("A").getbbox()
    if visible_bounds is None:
        raise ValueError(f"{package_asset_id}: PNG is fully transparent")
    return image, [int(value) for value in visible_bounds]


def build_asset(
    stable_id: str,
    package_asset_id: str,
    meta: dict,
    archive_path: Path,
    internal_image_path: str,
    destination: Path,
    payload: bytes,
    visible_bounds: list[int],
) -> dict:
    project_image = destination.relative_to(ROOT).as_posix()
    digest = sha256(payload)
    footprint = [int(value) for value in meta["footprint_tiles"]]
    anchor = [int(value) for value in meta["anchor"]]
    direction = str(meta["direction"])
    theme = str(meta["theme"])
    return {
        "asset_id": stable_id,
        "display_name": package_asset_id.replace("CARPET_", "地毯 ").replace("_", " "),
        "asset_type": "decoration",
        "category": "decoration",
        "object_class": "carpet",
        "theme": "gothic_ritual",
        "carpet_style": theme,
        "direction": direction,
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": [960, 480],
        "image_size": [960, 480],
        "visible_bounds_px": visible_bounds,
        "anchor_px": anchor,
        "placement_anchor_px": anchor,
        "anchor_tile": [0, 0],
        "anchor_mode": "tile_center",
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
        "authored_default_layer": "ground_overlay",
        "default_layer": "object_base",
        "default_object_role": "decoration",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": False,
        "map_collision_override": "default",
        "collision_authority": "visual_only",
        "occlusion": False,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "source_calibration_status": str(meta.get("calibration_status", "")),
        "calibration_source": "package_geometry_contract_and_editor_visual_review_v1",
        "palette_path": PALETTE_PATH,
        "source_external_path": f"{archive_path}::{internal_image_path}",
        "source_sha256": digest,
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "verified_geometry_corrected_package_rgba_passthrough",
        "tags": [
            "carpet",
            "floor_decoration",
            "geometry_corrected",
            "short_end_seamless",
            theme,
            direction,
        ],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "package_asset_id": package_asset_id,
        "projection": "fixed_2_1_orthographic_isometric",
        "iso_x_vector": [64, 32],
        "iso_y_vector": [-64, 32],
        "long_edge_screen_slope": float(meta["long_edge_screen_slope"]),
        "short_edge_screen_slope": float(meta["short_edge_screen_slope"]),
        "short_end_seamless": True,
        "runtime_rotation_required": False,
        "runtime_mirroring_required": False,
    }


def ensure_destination() -> None:
    DESTINATION.resolve().relative_to(
        (ROOT / "assets/art/maps/_shared/user_palette").resolve()
    )
    DESTINATION.mkdir(parents=True, exist_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    args = parser.parse_args()
    archive_path = args.archive.resolve()
    if not archive_path.is_file():
        raise SystemExit(f"missing carpet archive: {archive_path}")

    with zipfile.ZipFile(archive_path) as archive:
        manifest = read_json(archive, "manifest.json")
        validate_manifest(manifest)
        imported_assets = []
        pending_outputs: list[tuple[Path, bytes]] = []
        for index, (package_asset_id, stable_id) in enumerate(ASSET_ORDER, start=1):
            internal_image_path = f"transparent_assets/{package_asset_id}.png"
            payload = archive.read(archive_member(internal_image_path))
            meta = read_json(archive, f"meta/{package_asset_id}.json")
            _image, visible_bounds = validate_asset(package_asset_id, meta, payload)
            destination = DESTINATION / f"gothic_carpet_{index:02d}.png"
            pending_outputs.append((destination, payload))
            imported_assets.append(
                build_asset(
                    stable_id,
                    package_asset_id,
                    meta,
                    archive_path,
                    internal_image_path,
                    destination,
                    payload,
                    visible_bounds,
                )
            )

    ensure_destination()
    for destination, payload in pending_outputs:
        destination.write_bytes(payload)
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "replaces_package_id": REPLACED_PACKAGE_ID,
        "source_archive": str(archive_path),
        "source_archive_sha256": sha256(archive_path.read_bytes()),
        "source_count": len(imported_assets),
        "asset_count": len(imported_assets),
        "classification": PALETTE_PATH,
        "projection": str(manifest["projection"]),
        "geometry": manifest["geometry"],
        "editor_review_status": "passed",
        "promotion_policy": "package_contract_plus_visual_review",
        "default_collision_policy": "none",
        "assets": imported_assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_GEOMETRY_CORRECTED_CARPET_IMPORT_PASS "
        "assets=6 stable_ids=preserved classification=装饰物1/地毯"
    )


if __name__ == "__main__":
    main()
