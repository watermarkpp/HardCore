"""Import six transparent carpet images into the map editor palette."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path.home() / "Desktop" / "sucai" / "新增" / "地毯"
DESTINATION = (
    ROOT / "assets/art/maps/_shared/user_palette/装饰物1/地毯"
)
CATALOG_PATH = ROOT / "assets/data/assets/map_new_carpet_asset_catalog.json"
PACKAGE_ID = "mse_new_carpet_6_v1"
PALETTE_PATH = "装饰物1/地毯"
EXPECTED_COUNT = 6
PADDING = 4
CLUSTER_JOIN_KERNEL = 15


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def source_sort_key(path: Path) -> tuple[int, str]:
    return (
        int(path.stem) if path.stem.isdecimal() else 1_000_000,
        path.name.casefold(),
    )


def discover_sources(source_directory: Path) -> list[Path]:
    sources = sorted(source_directory.glob("*.png"), key=source_sort_key)
    if len(sources) != EXPECTED_COUNT:
        raise SystemExit(
            f"expected {EXPECTED_COUNT} carpet PNG files, got {len(sources)}"
        )
    return sources


def retain_primary_cluster(image: Image.Image) -> tuple[Image.Image, int]:
    original_alpha = image.getchannel("A")
    binary = original_alpha.point(lambda alpha: 255 if alpha > 0 else 0)
    joined = binary.filter(ImageFilter.MaxFilter(CLUSTER_JOIN_KERNEL))
    width, height = joined.size
    foreground = joined.tobytes()
    visited = bytearray(width * height)
    largest_component: list[int] = []

    for start, value in enumerate(foreground):
        if value == 0 or visited[start]:
            continue
        visited[start] = 1
        pending = deque([start])
        component: list[int] = []
        while pending:
            index = pending.popleft()
            component.append(index)
            x = index % width
            y = index // width
            for neighbor in (
                index - 1 if x > 0 else -1,
                index + 1 if x + 1 < width else -1,
                index - width if y > 0 else -1,
                index + width if y + 1 < height else -1,
            ):
                if (
                    neighbor >= 0
                    and foreground[neighbor] != 0
                    and not visited[neighbor]
                ):
                    visited[neighbor] = 1
                    pending.append(neighbor)
        if len(component) > len(largest_component):
            largest_component = component

    if not largest_component:
        raise ValueError("carpet image has no foreground cluster")
    keep_bytes = bytearray(width * height)
    for index in largest_component:
        keep_bytes[index] = 255
    keep_mask = Image.frombytes("L", (width, height), bytes(keep_bytes))
    filtered_alpha = ImageChops.multiply(original_alpha, keep_mask)
    original_count = sum(original_alpha.histogram()[1:])
    filtered_count = sum(filtered_alpha.histogram()[1:])
    cleaned = image.copy()
    cleaned.putalpha(filtered_alpha)
    return cleaned, original_count - filtered_count


def crop_with_padding(
    source: Image.Image,
) -> tuple[Image.Image, list[int], int]:
    cleaned, discarded_alpha_pixels = retain_primary_cluster(source)
    source_bounds = cleaned.getchannel("A").getbbox()
    if source_bounds is None:
        raise ValueError("carpet image is fully transparent after cleanup")
    cropped = cleaned.crop(source_bounds)
    output = Image.new(
        "RGBA",
        (cropped.width + PADDING * 2, cropped.height + PADDING * 2),
        (0, 0, 0, 0),
    )
    output.alpha_composite(cropped, (PADDING, PADDING))
    return output, [int(value) for value in source_bounds], discarded_alpha_pixels


def png_payload(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def build_asset(
    index: int,
    source_path: Path,
    source_payload: bytes,
    output_path: Path,
    output_payload: bytes,
    output: Image.Image,
    source_size: tuple[int, int],
    source_bounds: list[int],
    discarded_alpha_pixels: int,
) -> dict:
    width, height = output.size
    project_image = output_path.relative_to(ROOT).as_posix()
    output_digest = sha256(output_payload)
    footprint = [8, 8]
    return {
        "asset_id": f"mse.new_carpet.{index:02d}",
        "display_name": f"地毯 {index:02d}",
        "asset_type": "decoration",
        "category": "decoration",
        "object_class": "carpet",
        "theme": "gothic_ritual",
        "image": project_image,
        "thumbnail": project_image,
        "canvas_size": [width, height],
        "image_size": [width, height],
        "visible_bounds_px": [
            PADDING,
            PADDING,
            width - PADDING,
            height - PADDING,
        ],
        "anchor_px": [width // 2, height // 2],
        "placement_anchor_px": [width // 2, height // 2],
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
        "calibration_source": "single_rgba_primary_alpha_cluster_crop_v1",
        "palette_path": PALETTE_PATH,
        "source_external_path": str(source_path),
        "source_sha256": sha256(source_payload),
        "output_sha256": output_digest,
        "thumbnail_source_sha256": output_digest,
        "processing": {
            "pipeline": "single_rgba_primary_alpha_cluster_crop_v1",
            "source_canvas": list(source_size),
            "source_bounds_px": source_bounds,
            "padding_px": PADDING,
            "cluster_join_kernel_px": CLUSTER_JOIN_KERNEL,
            "discarded_alpha_pixels": discarded_alpha_pixels,
        },
        "tags": [
            "new_local_asset",
            "carpet",
            "floor_decoration",
            "visual_only",
        ],
        "editable": True,
        "allows_edge_clipping": True,
        "semantic_role": "",
        "trigger_on_enter": False,
        "package_id": PACKAGE_ID,
        "source_index": index,
        "projection": "orthographic_isometric_2_to_1",
    }


def clear_destination() -> None:
    DESTINATION.resolve().relative_to(
        (ROOT / "assets/art/maps/_shared/user_palette").resolve()
    )
    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    DESTINATION.mkdir(parents=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source_directory = args.source.resolve()
    if not source_directory.is_dir():
        raise SystemExit(f"missing source directory: {source_directory}")
    sources = discover_sources(source_directory)
    clear_destination()

    assets = []
    for index, source_path in enumerate(sources, start=1):
        source_payload = source_path.read_bytes()
        with Image.open(io.BytesIO(source_payload)) as source_image:
            source = source_image.convert("RGBA")
            if source.getchannel("A").getextrema() != (0, 255):
                raise ValueError(
                    f"{source_path.name}: expected transparent and opaque pixels"
                )
            output, source_bounds, discarded_alpha_pixels = crop_with_padding(
                source
            )
        output_path = DESTINATION / f"gothic_carpet_{index:02d}.png"
        output_payload = png_payload(output)
        output_path.write_bytes(output_payload)
        assets.append(
            build_asset(
                index,
                source_path,
                source_payload,
                output_path,
                output_payload,
                output,
                source.size,
                source_bounds,
                discarded_alpha_pixels,
            )
        )

    asset_ids = [str(asset["asset_id"]) for asset in assets]
    if len(asset_ids) != len(set(asset_ids)):
        raise SystemExit("duplicate stable carpet asset id")
    catalog = {
        "asset_schema_version": 2,
        "package_id": PACKAGE_ID,
        "package_version": 1,
        "source_directory": str(source_directory),
        "source_count": len(sources),
        "asset_count": len(assets),
        "classification": PALETTE_PATH,
        "default_collision_policy": "none",
        "assets": assets,
    }
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "MSE_NEW_CARPET_IMPORT_PASS "
        "sources=6 assets=6 classification=装饰物1/地毯"
    )


if __name__ == "__main__":
    main()
