#!/usr/bin/env python3
"""Build D011/D012 natural-cave evidence, masks and client-derived runtime atlases."""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from collections import Counter, deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
CLIENT = WORKSPACE / "research/mir2_client_raw"
MAP_DIR = CLIENT / "Map"
DATA_DIR = CLIENT / "Data"
OUTPUT = ROOT / "assets/art/maps/natural_cave"
PROFILE = ROOT / "assets/data/natural_cave_source_profiles.json"
MAPS = {248: ("洞穴一层", "D011"), 249: ("洞穴二层", "D012")}

sys.path.insert(0, str(WORKSPACE / "tools"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def wil(library: str, index: int) -> Image.Image:
    data, palette, offsets, _ = read_library(DATA_DIR / library)
    image, _ = decode_sprite(data, offsets[index], palette)
    return image.convert("RGBA")


def connected_components(walkable: set[tuple[int, int]]) -> list[dict]:
    remaining = set(walkable)
    result = []
    while remaining:
        seed = remaining.pop()
        queue = deque([seed])
        cells = [seed]
        while queue:
            x, y = queue.popleft()
            for neighbour in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    queue.append(neighbour)
                    cells.append(neighbour)
        xs = [cell[0] for cell in cells]
        ys = [cell[1] for cell in cells]
        result.append({
            "cells": len(cells),
            "bounds": [min(xs), min(ys), max(xs), max(ys)],
            "centroid": [round(sum(xs) / len(cells)), round(sum(ys) / len(cells))],
        })
    return sorted(result, key=lambda item: item["cells"], reverse=True)


def parse_map(path: Path) -> tuple[dict, Image.Image]:
    raw = path.read_bytes()
    width, height = struct.unpack_from("<HH", raw, 0)
    if len(raw) != 52 + width * height * 12:
        raise ValueError(f"{path.name}长度与经典12字节单元格式不符")
    mask = Image.new("RGBA", (width, height), (18, 14, 12, 255))
    pixels = mask.load()
    tiles, objects, areas = Counter(), Counter(), Counter()
    walkable: set[tuple[int, int]] = set()
    blocked = lights = doors = 0
    door_cells = []
    light_cells = []
    for cell_index, offset in enumerate(range(52, len(raw), 12)):
        back, middle, front, door_index, door_offset, anim_frame, anim_tick, area, light = struct.unpack_from("<HHHBBBBBB", raw, offset)
        x, y = divmod(cell_index, height)
        is_blocked = bool((back | front) & 0x8000)
        if is_blocked:
            blocked += 1
            pixels[x, y] = (35, 27, 24, 255)
        else:
            walkable.add((x, y))
            pixels[x, y] = (190, 174, 132, 255)
        if light:
            lights += 1
            light_cells.append([x, y, light])
            pixels[x, y] = (242, 187, 72, 255)
        if door_index & 0x7F:
            doors += 1
            door_cells.append([x, y, door_index & 0x7F, door_offset])
            pixels[x, y] = (72, 174, 235, 255)
        areas[area] += 1
        if back & 0x7FFF:
            tiles[back & 0x7FFF] += 1
        if front & 0x7FFF:
            objects[f"Objects{area + 1}:{front & 0x7FFF}"] += 1
    components = connected_components(walkable)
    return {
        "width": width,
        "height": height,
        "byteLength": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "blockedRatio": round(blocked / (width * height), 4),
        "walkableCells": width * height - blocked,
        "lightCells": lights,
        "doorCells": doors,
        "doorRecords": door_cells,
        "lightRecords": light_cells,
        "largestWalkableComponents": components[:5],
        "topTileImageIds": [index for index, _ in tiles.most_common(12)],
        "topObjectImageIds": [key for key, _ in objects.most_common(24)],
        "areaCounts": {str(key): value for key, value in sorted(areas.items())},
    }, mask


def diamond_tile(source: Image.Image, brightness: float) -> Image.Image:
    tile = ImageEnhance.Brightness(source.resize((64, 32), Image.Resampling.LANCZOS)).enhance(brightness)
    alpha = Image.new("L", (64, 32), 0)
    draw = ImageDraw.Draw(alpha)
    draw.polygon([(32, 0), (63, 15), (32, 31), (0, 15)], fill=255)
    tile.putalpha(alpha)
    return tile


def build_ground(indices: list[int]) -> None:
    atlas = Image.new("RGBA", (512, 32), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        atlas.alpha_composite(diamond_tile(wil("Tiles.wil", index), 0.70 + slot * 0.025), (slot * 64, 0))
    atlas.save(OUTPUT / "natural_cave_ground_tiles.png")


def build_props(indices: list[int]) -> None:
    atlas = Image.new("RGBA", (768, 128), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        image = ImageEnhance.Brightness(wil("Objects.wil", index)).enhance(0.88)
        image.thumbnail((88, 118), Image.Resampling.LANCZOS)
        atlas.alpha_composite(image, (slot * 96 + (96 - image.width) // 2, 124 - image.height))
    atlas.save(OUTPUT / "natural_cave_props.png")


def build_glow() -> None:
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(128):
        for x in range(128):
            distance = math.hypot(x - 63.5, y - 63.5) / 64.0
            pixels[x, y] = (106, 150, 87, int(120 * max(0.0, 1.0 - distance) ** 2))
    image.save(OUTPUT / "natural_cave_glow.png")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mask_dir = OUTPUT / "source_masks"
    mask_dir.mkdir(exist_ok=True)
    profiles = {}
    for map_id, (name, source_code) in MAPS.items():
        info, mask = parse_map(MAP_DIR / f"{source_code}.map")
        mask.save(mask_dir / f"{map_id}_{source_code}_walkability.png")
        profiles[str(map_id)] = {
            "name": name,
            "sourceMapCode": source_code,
            "sourceMapPath": f"research/mir2_client_raw/Map/{source_code}.map",
            "sourceKind": "客户端原始MAP直接解析",
            "confidence": "A",
            **info,
        }
    # 1951—1961在该客户端库中是近黑色结构/空白底，保留在统计证据中，
    # 运行图集选用两张原图实际引用且具有可见像素的洞穴地块。
    ground_indices = [1901, 1902, 1903, 1904, 1905, 1901, 1903, 1905]
    object_indices = [4439, 4440, 4441, 4478, 4479, 4480, 4510, 4531]
    build_ground(ground_indices)
    build_props(object_indices)
    build_glow()
    payload = {
        "schemaVersion": 1,
        "baseline": "2003官服1.76基准优先",
        "generatedFrom": "客户端D011/D012 MAP与Tiles/Objects WIL/WIX原始资源",
        "mapProfiles": profiles,
        "runtimeProjection": {
            "policy": "原MAP证据保持400×400；手机垂直切片仅压缩最大连通区与路线骨架，运行门点不冒充服务端原坐标。",
            "248": {
                "sourceSpawnCells": [[89, 75], [312, 92], [113, 327], [309, 314]],
                "sourcePortalCandidates": [[28, 352], [314, 31]],
            },
            "249": {
                "sourceSpawnCells": [[46, 80], [326, 87], [94, 332], [306, 340]],
                "sourcePortalCandidates": [[38, 375]],
            },
            "portalConfidence": "C：当前客户端包缺服务端MapInfo连接坐标，运行门点只保证单机闭环与安全落点。",
        },
        "assetSources": {
            "ground": {"library": "Data/Tiles.wil", "indices": ground_indices, "confidence": "A"},
            "props": {"library": "Data/Objects.wil", "indices": object_indices, "confidence": "A"},
            "walkabilityMasks": ["assets/art/maps/natural_cave/source_masks/248_D011_walkability.png", "assets/art/maps/natural_cave/source_masks/249_D012_walkability.png"],
        },
    }
    PROFILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"NATURAL_CAVE_PROFILES={len(profiles)} ASSETS={OUTPUT}")


if __name__ == "__main__":
    main()
