from __future__ import annotations

import json
import math
import struct
import sys
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parents[1]
CLIENT = WORKSPACE / "research/mir2_client_raw"
MAP_DIR = CLIENT / "Map"
DATA_DIR = CLIENT / "Data"
OUTPUT = ROOT / "assets/art/maps/mine"
PROFILE_OUTPUT = ROOT / "assets/data/mine_source_profiles.json"
TILE_SIZE = (64, 32)
PROP_SIZE = (96, 128)

sys.path.insert(0, str(WORKSPACE / "tools"))
from extract_wil import decode_sprite, read_library  # noqa: E402


MAP_MAPPING = {
    401: "D401", 402: "D411", 403: "D413", 404: "D402",
    405: "D414", 406: "D403", 407: "D412", 408: "D404",
    409: "D415", 410: "D405", 411: "D416", 412: "D406",
    1578: "Q004",
}
MAP_NAMES = {
    401: "废矿入口", 402: "矿区B一层", 403: "矿区A一层", 404: "废矿区东部",
    405: "矿区C一层", 406: "矿区一层", 407: "桥一", 408: "矿区B二层",
    409: "桥二", 410: "矿物回收站", 411: "桥三", 412: "废矿区南部", 1578: "尸王殿",
}


def parse_map(path: Path) -> dict:
    raw = path.read_bytes()
    width, height = struct.unpack_from("<HH", raw, 0)
    if len(raw) != 52 + width * height * 12:
        raise ValueError(f"地图尺寸与文件长度不符：{path.name}")
    blocked = lights = door_cells = 0
    tiles, objects, areas = Counter(), Counter(), Counter()
    mask = Image.new("L", (width, height), 0)
    pixels = mask.load()
    for index, offset in enumerate(range(52, len(raw), 12)):
        bk, _mid, front, door_index, _door_offset, _ani_frame, _ani_tick, area, light = struct.unpack_from("<HHHBBBBBB", raw, offset)
        x, y = divmod(index, height)
        is_blocked = bool((bk | front) & 0x8000)
        pixels[x, y] = 38 if is_blocked else 225
        blocked += int(is_blocked)
        lights += int(light > 0)
        door_cells += int((door_index & 0x7F) > 0)
        if bk & 0x7FFF:
            tiles[bk & 0x7FFF] += 1
        if front & 0x7FFF:
            objects[f"Objects{area + 1}:{front & 0x7FFF}"] += 1
        areas[area] += 1
    return {
        "width": width, "height": height, "blockedRatio": round(blocked / (width * height), 4),
        "lightCells": lights, "doorCells": door_cells,
        "topTileImageIds": [key for key, _ in tiles.most_common(8)],
        "topObjectImageIds": [key for key, _ in objects.most_common(12)],
        "areaCounts": {str(key): value for key, value in areas.items()}, "mask": mask,
    }


def source_sprite(library: Path, index: int) -> Image.Image:
    data, palette, offsets, _info = read_library(library)
    image, _meta = decode_sprite(data, offsets[index], palette)
    return image


def diamond_tile(source: Image.Image, variant: int) -> Image.Image:
    tile = source.convert("RGBA").resize(TILE_SIZE, Image.Resampling.LANCZOS)
    tile = ImageEnhance.Brightness(tile).enhance(0.72 + variant * 0.035)
    mask = Image.new("L", TILE_SIZE, 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(32, 0), (63, 15), (32, 31), (0, 15)], fill=255)
    tile.putalpha(mask)
    ImageDraw.Draw(tile).line([(32, 0), (63, 15), (32, 31), (0, 15), (32, 0)], fill=(32, 25, 19, 210), width=1)
    return tile


def build_ground_atlas() -> list[int]:
    indices = [2150, 2151, 2152, 2153, 2154, 2150, 2152, 2154]
    atlas = Image.new("RGBA", (TILE_SIZE[0] * len(indices), TILE_SIZE[1]), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        atlas.alpha_composite(diamond_tile(source_sprite(DATA_DIR / "Tiles.wil", index), slot), (slot * TILE_SIZE[0], 0))
    atlas.save(OUTPUT / "mine_ground_tiles.png")
    return indices


def fit_source(image: Image.Image, box: tuple[int, int, int, int], brightness: float = 0.9) -> Image.Image:
    image = ImageEnhance.Brightness(image.convert("RGBA")).enhance(brightness)
    image.thumbnail((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
    return image


def build_prop_atlas() -> list[int]:
    # 每格都以矿区MAP实际引用的Objects2图像为材质底稿，再补画手机视角需要的清晰轮廓。
    indices = [7063, 4210, 7498, 7519, 7558, 7633, 8025, 7067]
    atlas = Image.new("RGBA", (PROP_SIZE[0] * 8, PROP_SIZE[1]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    for slot, index in enumerate(indices):
        sprite = fit_source(source_sprite(DATA_DIR / "Objects2.wil", index), (8, 12, 88, 122))
        x = slot * 96 + (96 - sprite.width) // 2
        y = 124 - sprite.height
        atlas.alpha_composite(sprite, (x, y))

    wood_dark, wood, iron, stone = (43, 30, 20, 255), (103, 69, 37, 255), (52, 57, 58, 255), (89, 78, 62, 255)
    # 0 木支架
    draw.polygon([(13, 121), (22, 121), (29, 40), (21, 36)], fill=wood_dark)
    draw.polygon([(74, 121), (83, 121), (76, 36), (68, 40)], fill=wood_dark)
    draw.polygon([(19, 43), (77, 43), (72, 31), (24, 31)], fill=wood, outline=wood_dark)
    # 1 矿轨
    ox = 96
    draw.line((ox + 10, 111, ox + 82, 70), fill=iron, width=5)
    draw.line((ox + 19, 120, ox + 91, 79), fill=iron, width=5)
    for t in range(8):
        x, y = ox + 13 + t * 10, 111 - t * 6
        draw.line((x - 7, y - 4, x + 8, y + 7), fill=wood, width=4)
    # 2 矿车
    ox = 192
    draw.polygon([(ox + 15, 68), (ox + 82, 68), (ox + 71, 104), (ox + 27, 104)], fill=(61, 66, 65, 255), outline=(24, 25, 24, 255))
    draw.polygon([(ox + 22, 72), (ox + 75, 72), (ox + 63, 91), (ox + 33, 91)], fill=(47, 39, 30, 255))
    draw.ellipse((ox + 24, 98, ox + 40, 114), fill=iron)
    draw.ellipse((ox + 57, 98, ox + 73, 114), fill=iron)
    # 3 岩壁
    ox = 288
    draw.polygon([(ox + 8, 122), (ox + 12, 45), (ox + 30, 19), (ox + 73, 25), (ox + 89, 54), (ox + 87, 122)], fill=(55, 48, 40, 220), outline=(28, 25, 22, 255))
    draw.line((ox + 28, 35, ox + 43, 68, ox + 35, 111), fill=stone, width=3)
    draw.line((ox + 70, 31, ox + 57, 58, ox + 69, 105), fill=(112, 94, 70, 255), width=2)
    # 4 桥梁木板
    ox = 384
    draw.polygon([(ox + 4, 105), (ox + 60, 49), (ox + 92, 65), (ox + 36, 121)], fill=wood_dark)
    for t in range(7):
        x, y = ox + 14 + t * 10, 103 - t * 8
        draw.polygon([(x - 9, y), (x + 6, y - 14), (x + 16, y - 8), (x, y + 7)], fill=wood, outline=wood_dark)
    # 5 碎石/塌方
    ox = 480
    for cx, cy, r in [(20, 107, 15), (43, 99, 20), (68, 108, 17), (52, 79, 13), (78, 88, 11)]:
        draw.polygon([(ox + cx - r, cy + 5), (ox + cx - 4, cy - r), (ox + cx + r, cy), (ox + cx + 5, cy + r // 2)], fill=stone, outline=(38, 32, 27, 255))
    # 6 矿灯
    ox = 576
    draw.line((ox + 48, 119, ox + 48, 51), fill=wood, width=7)
    draw.line((ox + 48, 54, ox + 73, 54), fill=wood, width=6)
    draw.ellipse((ox + 61, 54, ox + 82, 78), fill=(230, 142, 46, 255), outline=(62, 47, 31, 255), width=3)
    # 7 竖井入口
    ox = 672
    draw.rectangle((ox + 15, 48, ox + 28, 122), fill=wood_dark)
    draw.rectangle((ox + 68, 48, ox + 81, 122), fill=wood_dark)
    draw.arc((ox + 17, 13, ox + 79, 78), 180, 360, fill=wood, width=12)
    draw.ellipse((ox + 28, 47, ox + 68, 122), fill=(8, 8, 8, 225))
    atlas.save(OUTPUT / "mine_props.png")
    return indices


def build_light() -> None:
    size = 128
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - 63.5, y - 63.5) / 64.0
            alpha = int(175 * max(0.0, 1.0 - distance) ** 2)
            pixels[x, y] = (255, 174, 67, alpha)
    image.save(OUTPUT / "mine_lamp_glow.png")


def build() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    profiles = {}
    preview_dir = OUTPUT / "source_masks"
    preview_dir.mkdir(exist_ok=True)
    for map_id, source_code in MAP_MAPPING.items():
        info = parse_map(MAP_DIR / f"{source_code}.map")
        mask = info.pop("mask")
        mask.thumbnail((240, 240), Image.Resampling.NEAREST)
        mask.save(preview_dir / f"{map_id}_{source_code}.png")
        profiles[str(map_id)] = {
            "name": MAP_NAMES[map_id], "sourceMapCode": source_code,
            "sourceMapPath": f"research/mir2_client_raw/Map/{source_code}.map",
            "sourceKind": "客户端原始MAP直接解析", "confidence": "A", **info,
        }
    tile_indices = build_ground_atlas()
    object_indices = build_prop_atlas()
    build_light()
    output = {
        "baseline": "2003官服1.76基准版", "generatedFrom": "客户端MAP与WIL/WIX原始资源",
        "mapProfiles": profiles,
        "runtimeCoordinateMapping": {
            "projection": "isometric_64x32_full_size",
            "cellHalfWidth": 32, "cellHalfHeight": 16,
            "maps": {str(map_id): [profiles[str(map_id)]["width"], profiles[str(map_id)]["height"]] for map_id in MAP_MAPPING},
            "candidatePolicy": "缺MapInfo时将旧样板位置展开为source_coordinate并标C；原MAP尺寸保持A",
            "renderPolicy": "仅绘制镜头附近57×57逻辑格，世界坐标不压缩",
        },
        "assetSources": {
            "ground": {"library": "Data/Tiles.wil", "indices": tile_indices},
            "props": {"library": "Data/Objects2.wil", "indices": object_indices},
            "note": "地面和岩石纹理直接来自客户端；木支架、矿车、桥梁和矿灯以原图材质为底稿重组，以适应96×128手机场景图集。",
        },
    }
    PROFILE_OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"MINE_SOURCE_PROFILES={PROFILE_OUTPUT}")
    print(f"MINE_GROUND_ATLAS={OUTPUT / 'mine_ground_tiles.png'}")
    print(f"MINE_PROP_ATLAS={OUTPUT / 'mine_props.png'}")


if __name__ == "__main__":
    build()
