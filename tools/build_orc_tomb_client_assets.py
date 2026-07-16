#!/usr/bin/env python3
"""Build D001/D002/D003 evidence and client-derived orc-tomb runtime atlases."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
MAP_DIR = WORKSPACE / "research/mir2_client_raw/Map"
OUTPUT = ROOT / "assets/art/maps/orc_tomb"
PROFILE = ROOT / "assets/data/orc_tomb_source_profiles.json"
MAPS = {217: ("兽人古墓一层", "D001"), 218: ("兽人古墓二层", "D002"), 221: ("兽人古墓三层", "D003")}

sys.path.insert(0, str(ROOT / "tools"))
from build_natural_cave_assets import diamond_tile, parse_map, wil  # noqa: E402


def build_ground(indices: list[int]) -> None:
    atlas = Image.new("RGBA", (512, 32), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        atlas.alpha_composite(diamond_tile(wil("Tiles.wil", index), 0.66 + slot * 0.022), (slot * 64, 0))
    atlas.save(OUTPUT / "orc_tomb_ground_tiles.png")


def build_props(indices: list[int]) -> None:
    atlas = Image.new("RGBA", (768, 128), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        image = ImageEnhance.Brightness(wil("Objects.wil", index)).enhance(0.82)
        image.thumbnail((88, 118), Image.Resampling.LANCZOS)
        atlas.alpha_composite(image, (slot * 96 + (96 - image.width) // 2, 124 - image.height))
    atlas.save(OUTPUT / "orc_tomb_props.png")


def build_glow() -> None:
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(128):
        for x in range(128):
            distance = math.hypot(x - 63.5, y - 63.5) / 64.0
            pixels[x, y] = (220, 105, 38, int(155 * max(0.0, 1.0 - distance) ** 2))
    image.save(OUTPUT / "orc_tomb_fire_glow.png")


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
    ground_indices = [1901, 1902, 1903, 1904, 1905, 1901, 1903, 1905]
    object_indices = [4439, 4440, 4441, 4453, 4478, 4479, 4480, 4510]
    build_ground(ground_indices)
    build_props(object_indices)
    build_glow()
    payload = {
        "schemaVersion": 1,
        "baseline": "2003官服1.76基准优先",
        "generatedFrom": "客户端D001/D002/D003 MAP与Tiles/Objects WIL/WIX原始资源",
        "mapProfiles": profiles,
        "runtimeProjection": {
            "policy": "原MAP证据保持400×400；手机垂直切片压缩最大连通区、路线与Boss战空间，运行门点不冒充服务端原坐标。",
            "217": {"sourcePortalCandidates": [[25, 374], [381, 23]]},
            "218": {"sourcePortalCandidates": [[30, 357], [364, 44]], "sourceBossCell": [200, 200]},
            "221": {"sourcePortalCandidates": [[66, 298]], "sourceBossCell": [196, 204]},
            "portalConfidence": "C：当前客户端包缺服务端MapInfo连接坐标，运行门点只保证单机闭环与安全落点。",
        },
        "assetSources": {
            "ground": {"library": "Data/Tiles.wil", "indices": ground_indices, "confidence": "A"},
            "props": {"library": "Data/Objects.wil", "indices": object_indices, "confidence": "A"},
            "walkabilityMasks": [
                "assets/art/maps/orc_tomb/source_masks/217_D001_walkability.png",
                "assets/art/maps/orc_tomb/source_masks/218_D002_walkability.png",
                "assets/art/maps/orc_tomb/source_masks/221_D003_walkability.png",
            ],
        },
    }
    PROFILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"ORC_TOMB_CLIENT_PROFILES={len(profiles)} ASSETS={OUTPUT}")


if __name__ == "__main__":
    main()
