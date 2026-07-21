"""Crop and import six standalone transparent throne sprites."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path.home() / "Desktop" / "sucai" / "新增" / "王座"
DESTINATION = ROOT / "assets/art/maps/_shared/user_palette/装饰物1/王座"
CATALOG_PATH = ROOT / "assets/data/assets/map_new_throne_asset_catalog.json"
PACKAGE_ID = "mse_new_throne_addition_6_v1"
PALETTE_PATH = "装饰物1/王座"
CROP_PADDING = 4
FIRST_STABLE_INDEX = 7
EXPECTED_SOURCE_NAMES = tuple(f"{index}.png" for index in range(1, 7))


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def png_payload(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def crop_transparent_source(source_path: Path) -> tuple[bytes, dict]:
    source_payload = source_path.read_bytes()
    with Image.open(io.BytesIO(source_payload)) as raw:
        raw.load()
        if raw.mode != "RGBA":
            raise ValueError(f"{source_path.name}: expected RGBA, got {raw.mode}")
        source = raw.copy()
    alpha = source.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise ValueError(f"{source_path.name}: expected transparent and opaque pixels")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"{source_path.name}: image is fully transparent")
    cropped = source.crop(bounds)
    output = Image.new(
        "RGBA",
        (cropped.width + CROP_PADDING * 2, cropped.height + CROP_PADDING * 2),
        (0, 0, 0, 0),
    )
    output.alpha_composite(cropped, (CROP_PADDING, CROP_PADDING))
    return png_payload(output), {
        "source_payload": source_payload,
        "source_size": list(source.size),
        "source_bounds_px": list(bounds),
        "output_size": list(output.size),
        "visible_bounds_px": [
            CROP_PADDING,
            CROP_PADDING,
            output.width - CROP_PADDING,
            output.height - CROP_PADDING,
        ],
    }


def build_asset(
    source_path: Path,
    source_index: int,
    stable_index: int,
    destination: Path,
    output_payload: bytes,
    geometry: dict,
) -> dict:
    width, height = geometry["output_size"]
    visible_bounds = geometry["visible_bounds_px"]
    anchor = [width // 2, visible_bounds[3] - 1]
    project_image = destination.relative_to(ROOT).as_posix()
    footprint = [6, 6]
    return {
        "asset_id": f"mse.new_throne.{stable_index:02d}",
        "display_name": f"王座 {stable_index:02d}",
        "asset_type": "large_prop",
        "category": "decoration",
        "object_class": "decoration",
        "theme": "gothic_ruins",
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
        "default_layer": "object_base",
        "default_object_role": "decoration",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "manual_collision_expected": True,
        "map_collision_override": "default",
        "collision_authority": "manual_by_user",
        "occlusion": True,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "calibration_source": "single_rgba_alpha_bbox_crop_v1",
        "palette_path": PALETTE_PATH,
        "source_external_path": str(source_path),
        "source_sha256": sha256(geometry["source_payload"]),
        "output_sha256": sha256(output_payload),
        "thumbnail_source_sha256": sha256(output_payload),
        "processing": {
            "pipeline": "single_rgba_alpha_bbox_crop_v1",
            "source_canvas": geometry["source_size"],
            "source_bounds_px": geometry["source_bounds_px"],
            "padding_px": CROP_PADDING,
            "discarded_alpha_pixels": 0,
        },
        "tags": ["new_local_asset", "throne", "gothic", "large_prop"],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "source_group": "王座",
        "source_index": source_index,
        "projection": "orthographic_isometric_2_to_1",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source_directory = args.source_dir.resolve()
    if not source_directory.is_dir():
        raise SystemExit(f"missing throne source directory: {source_directory}")
    sources = sorted(source_directory.glob("*.png"), key=lambda path: path.name)
    if tuple(path.name for path in sources) != EXPECTED_SOURCE_NAMES:
        raise SystemExit(
            f"expected throne sources {EXPECTED_SOURCE_NAMES}, "
            f"got {tuple(path.name for path in sources)}"
        )

    DESTINATION.mkdir(parents=True, exist_ok=True)
    assets = []
    for source_index, source_path in enumerate(sources, start=1):
        stable_index = FIRST_STABLE_INDEX + source_index - 1
        output_payload, geometry = crop_transparent_source(source_path)
        destination = DESTINATION / f"gothic_throne_{stable_index:02d}.png"
        destination.write_bytes(output_payload)
        assets.append(
            build_asset(
                source_path,
                source_index,
                stable_index,
                destination,
                output_payload,
                geometry,
            )
        )

    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_directory": str(source_directory),
        "source_count": len(sources),
        "asset_count": len(assets),
        "classification": PALETTE_PATH,
        "cutting_policy": "single_rgba_alpha_bbox_with_padding",
        "default_collision_policy": "none",
        "assets": assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_NEW_THRONE_IMPORT_PASS "
        "sources=6 assets=6 stable_ids=07-12 classification=装饰物1/王座"
    )


if __name__ == "__main__":
    main()
