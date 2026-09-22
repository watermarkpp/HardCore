#!/usr/bin/env python3
"""Import the six user-provided Stone Tomb floor variants as canonical 1x1 brushes."""
from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets/raw_import/map_assets/ground_sources/stone_tomb_floor_v1"
SOURCE = RAW / "stone_tomb_floor_source_v1.png"
KEYED = RAW / "stone_tomb_floor_keyed_v1.png"
OUTPUT = ROOT / "assets/art/maps/stone_tomb/floor"
CATALOG = ROOT / "assets/data/assets/map_stone_tomb_floor_asset_catalog.json"
PALETTE_PATH = "洞穴与地下城/地板/石墓石板"
PROCESSING = "imagegen_chroma_mask_original_rgb_premultiplied_resize_64x32_v1"
COMPONENT_ALPHA_THRESHOLD = 16


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def connected_components(alpha: Image.Image) -> list[tuple[int, tuple[int, int, int, int]]]:
    width, height = alpha.size
    pixels = alpha.load()
    seen = bytearray(width * height)
    components: list[tuple[int, tuple[int, int, int, int]]] = []
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if seen[index] or pixels[x, y] <= COMPONENT_ALPHA_THRESHOLD:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            seen[index] = 1
            min_x = max_x = x
            min_y = max_y = y
            count = 0
            while queue:
                current_x, current_y = queue.pop()
                count += 1
                min_x = min(min_x, current_x)
                max_x = max(max_x, current_x)
                min_y = min(min_y, current_y)
                max_y = max(max_y, current_y)
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_index = next_y * width + next_x
                    if seen[next_index] or pixels[next_x, next_y] <= COMPONENT_ALPHA_THRESHOLD:
                        continue
                    seen[next_index] = 1
                    queue.append((next_x, next_y))
            if count >= 10_000:
                components.append((count, (min_x, min_y, max_x + 1, max_y + 1)))
    return components


def premultiplied_resize(source: Image.Image, alpha: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    rgba.putalpha(alpha)
    red, green, blue, source_alpha = rgba.split()
    premultiplied = [ImageChops.multiply(channel, source_alpha) for channel in (red, green, blue)]
    resized_alpha = source_alpha.resize((64, 32), Image.Resampling.LANCZOS)
    resized_premultiplied = [channel.resize((64, 32), Image.Resampling.LANCZOS) for channel in premultiplied]
    output = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    output_pixels = output.load()
    alpha_pixels = resized_alpha.load()
    channel_pixels = [channel.load() for channel in resized_premultiplied]
    for y in range(32):
        for x in range(64):
            alpha_value = int(alpha_pixels[x, y])
            if alpha_value <= 0:
                continue
            rgb = tuple(
                min(255, int(round(int(channel[x, y]) * 255.0 / alpha_value)))
                for channel in channel_pixels
            )
            output_pixels[x, y] = (*rgb, alpha_value)
    return output


def asset_record(index: int, source_sha: str, mask_sha: str, output_path: Path, crop_box: tuple[int, int, int, int]) -> dict:
    relative_output = output_path.relative_to(ROOT).as_posix()
    output_sha = sha256(output_path)
    return {
        "asset_id": f"mse.ground.stone_tomb_floor.{index:02d}",
        "display_name": f"石墓石板 {index:02d}",
        "asset_type": "ground_brush",
        "category": "ground",
        "object_class": "ground",
        "theme": "cave_dungeon",
        "image": relative_output,
        "thumbnail": relative_output,
        "canvas_size": [64, 32],
        "image_size": [64, 32],
        "logical_bounds_px": [0, 0, 64, 32],
        "visible_bounds_px": [0, 0, 64, 32],
        "anchor_px": [32, 16],
        "placement_anchor_px": [32, 16],
        "anchor_tile": [0, 0],
        "anchor_mode": "tile_center",
        "footprint_tiles": [1, 1],
        "visual_footprint_tiles": [1, 1],
        "occupancy_footprint_tiles": [1, 1],
        "base_footprint_tiles": [1, 1],
        "collision_footprint_tiles": [0, 0],
        "tile_size": [64, 32],
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "default_layer": "ground_base",
        "default_object_role": "decoration",
        "collision_policy": "none",
        "collision_profile_id": "none_visual",
        "navigation_policy": "ignore",
        "occlusion": False,
        "content_layer": "personal_expansion",
        "placeable": True,
        "calibration_status": "placeable",
        "palette_path": PALETTE_PATH,
        "source_distribution": "user_provided_primary",
        "source_path": SOURCE.relative_to(ROOT).as_posix(),
        "mask_path": KEYED.relative_to(ROOT).as_posix(),
        "source_crop_box": list(crop_box),
        "source_sha256": source_sha,
        "mask_sha256": mask_sha,
        "output_sha256": output_sha,
        "thumbnail_source_sha256": output_sha,
        "processing": PROCESSING,
        "ground_brush_role": "base_tile",
        "terrain_type": "stone_tomb_cracked_slab",
        "variation_group_id": "mse.ground.stone_tomb_floor.v1",
        "paintable": True,
        "normalization": "canonical_64x32_one_cell_diamond_v1",
        "diamond_inner_coverage": 1.0,
    }


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    keyed = Image.open(KEYED).convert("RGBA")
    keyed_alpha = keyed.getchannel("A")
    components = connected_components(keyed_alpha)
    if len(components) != 6:
        raise SystemExit(f"expected 6 floor components, got {len(components)}")
    boxes = [box for _count, box in components]
    boxes.sort(key=lambda box: (box[1], box[0]))
    source_alpha = keyed_alpha.resize(source.size, Image.Resampling.BILINEAR)
    scale_x = source.width / keyed.width
    scale_y = source.height / keyed.height
    source_sha = sha256(SOURCE)
    mask_sha = sha256(KEYED)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    assets = []
    for index, keyed_box in enumerate(boxes, start=1):
        source_box = (
            max(0, int(round(keyed_box[0] * scale_x)) - 1),
            max(0, int(round(keyed_box[1] * scale_y)) - 1),
            min(source.width, int(round(keyed_box[2] * scale_x)) + 1),
            min(source.height, int(round(keyed_box[3] * scale_y)) + 1),
        )
        tile = premultiplied_resize(source.crop(source_box), source_alpha.crop(source_box))
        output_path = OUTPUT / f"stone_tomb_floor_{index:02d}.png"
        tile.save(output_path, optimize=True)
        if tile.getpixel((0, 0))[3] != 0 or tile.getpixel((63, 0))[3] != 0:
            raise SystemExit(f"variant {index} has opaque top corner")
        if tile.getpixel((32, 16))[3] < 220:
            raise SystemExit(f"variant {index} has transparent center")
        assets.append(asset_record(index, source_sha, mask_sha, output_path, source_box))
    catalog = {
        "asset_schema_version": 2,
        "package_id": "mse_stone_tomb_floor_6_v1",
        "package_version": 1,
        "source_count": 1,
        "asset_count": len(assets),
        "classification": PALETTE_PATH,
        "projection": "orthographic_isometric_2_to_1",
        "processing_pipeline": PROCESSING,
        "source_distribution": "user_provided_primary",
        "source_path_hint": "ChatGPT Image 2026年8月15日 16_11_19.png",
        "source_sha256": source_sha,
        "mask_sha256": mask_sha,
        "assets": assets,
    }
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"STONE_TOMB_FLOOR_IMPORT_PASS assets={len(assets)} palette={PALETTE_PATH}")


if __name__ == "__main__":
    main()
