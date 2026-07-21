"""Import eight transparent ground-graffiti images at 3x3 and 10x10 sizes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path(
    r"C:\Users\Administrator\Desktop\sucai\新增\地面涂鸦"
)
DESTINATION = (
    ROOT
    / "assets/art/maps/_shared/user_palette/decorations_1/ground_graffiti"
)
CATALOG_PATH = ROOT / "assets/data/assets/map_ground_graffiti_asset_catalog.json"
PACKAGE_ID = "mse_ground_graffiti_8_dual_size_v1"
TILE_SIZE = (64, 32)
SOURCE_INDEX_PATTERN = re.compile(r"\((\d+)\)\.png$", re.IGNORECASE)
SIZE_VARIANTS = {
    "3x3": {
        "label": "3×3",
        "footprint": [3, 3],
        "canvas": [192, 96],
        "inner": [184, 88],
    },
    "10x10": {
        "label": "10×10",
        "footprint": [10, 10],
        "canvas": [640, 320],
        "inner": [620, 300],
    },
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def source_index(path: Path) -> int:
    match = SOURCE_INDEX_PATTERN.search(path.name)
    if match is None:
        raise ValueError(f"cannot determine source index: {path.name}")
    return int(match.group(1))


def discover_sources(source_directory: Path) -> list[tuple[int, Path]]:
    indexed = sorted(
        ((source_index(path), path) for path in source_directory.glob("*.png")),
        key=lambda entry: entry[0],
    )
    if [index for index, _path in indexed] != list(range(1, 9)):
        raise SystemExit("expected exactly eight PNG files numbered 1 through 8")
    return indexed


def alpha_bbox(image: Image.Image, source_name: str) -> tuple[int, int, int, int]:
    if image.mode != "RGBA":
        raise ValueError(f"{source_name}: expected RGBA, got {image.mode}")
    alpha = image.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise ValueError(f"{source_name}: expected transparent and opaque pixels")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"{source_name}: image is fully transparent")
    return bbox


def render_variant(
    source: Image.Image,
    source_name: str,
    canvas_size: list[int],
    inner_size: list[int],
) -> tuple[Image.Image, list[int]]:
    bbox = alpha_bbox(source, source_name)
    cropped = source.crop(bbox)
    # RGBa is Pillow's premultiplied-alpha mode. Resampling in this mode keeps
    # the transparent white source pixels from creating pale edge fringes.
    resized = (
        cropped.convert("RGBa")
        .resize(tuple(inner_size), Image.Resampling.LANCZOS)
        .convert("RGBA")
    )
    output = Image.new("RGBA", tuple(canvas_size), (0, 0, 0, 0))
    origin = (
        (canvas_size[0] - inner_size[0]) // 2,
        (canvas_size[1] - inner_size[1]) // 2,
    )
    output.alpha_composite(resized, origin)
    output_bbox = output.getchannel("A").getbbox()
    if output_bbox is None:
        raise ValueError(f"{source_name}: rendered variant is fully transparent")
    return output, [int(value) for value in output_bbox]


def build_asset(
    index: int,
    source_path: Path,
    source_payload: bytes,
    output_path: Path,
    output_payload: bytes,
    variant_id: str,
    variant: dict,
    visible_bounds: list[int],
) -> dict:
    canvas = [int(value) for value in variant["canvas"]]
    footprint = [int(value) for value in variant["footprint"]]
    anchor = [canvas[0] // 2, canvas[1] // 2]
    project_image = output_path.relative_to(ROOT).as_posix()
    source_digest = sha256(source_payload)
    output_digest = sha256(output_payload)
    label = str(variant["label"])
    return {
        "asset_id": f"mse.ground_graffiti.{variant_id}.{index:02d}",
        "display_name": f"地面涂鸦 {index:02d}（{label}）",
        "asset_type": "decoration",
        "category": "ground_graffiti",
        "object_class": "ground_graffiti",
        "theme": "dark_ritual",
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": canvas,
        "image_size": canvas,
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
        "tile_size": list(TILE_SIZE),
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
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
        "calibration_source": "alpha_crop_isometric_projection_v1",
        "palette_path": f"装饰物1/地面涂鸦/{label}",
        "source_external_path": str(source_path),
        "source_sha256": source_digest,
        "output_sha256": output_digest,
        "thumbnail_source_sha256": output_digest,
        "processing": {
            "pipeline": "alpha_crop_premultiplied_lanczos_isometric_v1",
            "source_canvas": [1254, 1254],
            "target_canvas": canvas,
            "target_inner": list(variant["inner"]),
            "projection": "orthographic_isometric_2_to_1",
        },
        "tags": [
            "ground_graffiti",
            "dark_ritual",
            variant_id,
            "visual_only",
        ],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "source_index": index,
        "size_variant": variant_id,
        "size_label": label,
        "requires_runtime_rotation": False,
        "allow_flip": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source_directory = args.source.resolve()
    if not source_directory.is_dir():
        raise SystemExit(f"missing source directory: {source_directory}")
    sources = discover_sources(source_directory)

    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    DESTINATION.mkdir(parents=True)

    catalog_assets = []
    for index, source_path in sources:
        source_payload = source_path.read_bytes()
        with Image.open(source_path) as raw_source:
            source = raw_source.convert("RGBA")
            if source.size != (1254, 1254):
                raise ValueError(
                    f"{source_path.name}: expected 1254x1254, got {source.size}"
                )
            for variant_id, variant in SIZE_VARIANTS.items():
                label = str(variant["label"])
                output_path = DESTINATION / label / f"graffiti_{index:02d}.png"
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output, visible_bounds = render_variant(
                    source,
                    source_path.name,
                    list(variant["canvas"]),
                    list(variant["inner"]),
                )
                output.save(output_path, format="PNG", optimize=True)
                output_payload = output_path.read_bytes()
                catalog_assets.append(
                    build_asset(
                        index,
                        source_path,
                        source_payload,
                        output_path,
                        output_payload,
                        variant_id,
                        variant,
                        visible_bounds,
                    )
                )

    ids = [str(asset["asset_id"]) for asset in catalog_assets]
    if len(catalog_assets) != 16 or len(ids) != len(set(ids)):
        raise SystemExit("expected sixteen unique catalog assets")
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_directory": str(source_directory),
        "source_count": 8,
        "asset_count": 16,
        "variant_counts": {"3x3": 8, "10x10": 8},
        "classification": "装饰物1/地面涂鸦",
        "default_collision_policy": "none",
        "assets": catalog_assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_GROUND_GRAFFITI_IMPORT_PASS "
        "sources=8 assets=16 variants=3x3,10x10 collision=none"
    )


if __name__ == "__main__":
    main()
