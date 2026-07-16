from __future__ import annotations

import json
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
OUTPUT_DIR = ROOT / "assets/art/maps/bich"
PROFILE_OUTPUT = ROOT / "assets/data/bich_source_profiles.json"
TILE_SIZE = (64, 32)
PROP_SIZE = (96, 128)

sys.path.insert(0, str(WORKSPACE / "tools"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def wil(library: str, index: int) -> Image.Image:
    data, palette, offsets, _ = read_library(DATA_DIR / library)
    image, _ = decode_sprite(data, offsets[index], palette)
    return image.convert("RGBA")


def parse_map(path: Path) -> tuple[dict, Image.Image]:
    raw = path.read_bytes()
    width, height = struct.unpack_from("<HH", raw, 0)
    if len(raw) != 52 + width * height * 12:
        raise ValueError(f"地图尺寸与文件长度不符：{path.name}")
    blocked = lights = doors = 0
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
        doors += int((door_index & 0x7F) > 0)
        if bk & 0x7FFF:
            tiles[bk & 0x7FFF] += 1
        if front & 0x7FFF:
            objects[f"Objects{area + 1}:{front & 0x7FFF}"] += 1
        areas[area] += 1
    return ({
        "width": width,
        "height": height,
        "blockedRatio": round(blocked / (width * height), 4),
        "lightCells": lights,
        "doorCells": doors,
        "topTileImageIds": [key for key, _ in tiles.most_common(12)],
        "topObjectImageIds": [key for key, _ in objects.most_common(20)],
        "areaCounts": {str(key): value for key, value in areas.items()},
    }, mask)


def diamond(image: Image.Image, brightness: float) -> Image.Image:
    result = ImageEnhance.Brightness(image.resize(TILE_SIZE, Image.Resampling.LANCZOS)).enhance(brightness)
    mask = Image.new("L", TILE_SIZE, 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(32, 0), (63, 15), (32, 31), (0, 15)], fill=255)
    result.putalpha(mask)
    ImageDraw.Draw(result).line([(32, 0), (63, 15), (32, 31), (0, 15), (32, 0)], fill=(31, 27, 18, 205), width=1)
    return result


def build_ground() -> list[int]:
    # 0.map中使用频率最高的草地、浅草和土路块。
    indices = [1454, 1451, 1452, 1455, 1453, 951, 54, 55]
    atlas = Image.new("RGBA", (TILE_SIZE[0] * 8, TILE_SIZE[1]), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        atlas.alpha_composite(diamond(wil("Tiles.wil", index), 0.76 + slot * 0.018), (slot * TILE_SIZE[0], 0))
    atlas.save(OUTPUT_DIR / "bich_ground_tiles.png")
    return indices


def source_part(index: int, maximum: tuple[int, int] = (84, 112)) -> Image.Image:
    image = ImageEnhance.Brightness(wil("Objects.wil", index)).enhance(0.92)
    alpha_box = image.getchannel("A").getbbox()
    if alpha_box is not None:
        image = image.crop(alpha_box)
    image.thumbnail(maximum, Image.Resampling.LANCZOS)
    return image


def build_props() -> list[int]:
    # 这些编号均由0.map实际引用。原图按地图格保存为碎片，因此在96×128手机图集中重组轮廓。
    indices = [1376, 1386, 1402, 1408, 1412, 1370, 5885, 5884]
    atlas = Image.new("RGBA", (PROP_SIZE[0] * 4, PROP_SIZE[1]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    trunk = (67, 43, 24, 255)
    stone = (105, 99, 78, 255)
    dark = (38, 34, 27, 255)

    # 两种树：枝叶纹理直接采用0.map的Objects碎片。
    for slot, source_indices in enumerate([(1376, 1386, 1402, 1397), (1408, 1412, 1370, 1388)]):
        ox = slot * 96
        draw.rectangle((ox + 43, 61, ox + 55, 124), fill=trunk)
        for part_index, px, py in zip(source_indices, [4, 25, 48, 63], [26, 5, 18, 36]):
            part = source_part(part_index, (48, 90))
            atlas.alpha_composite(part, (ox + px, py))

    # 石块：保留原图岩壁纹理并补出清晰碰撞轮廓。
    ox = 192
    rock_texture = source_part(5885, (80, 100))
    atlas.alpha_composite(rock_texture, (ox + 8, 20))
    draw.polygon([(ox + 13, 105), (ox + 25, 72), (ox + 55, 60), (ox + 82, 82), (ox + 75, 119), (ox + 31, 119)], fill=(91, 87, 72, 215), outline=dark)
    draw.line((ox + 29, 76, ox + 50, 93, ox + 67, 116), fill=stone, width=3)

    # 城墙：使用0.map城镇建筑碎片，并补齐手机视野需要的整体块面。
    ox = 288
    wall_texture = source_part(5884, (88, 118))
    atlas.alpha_composite(wall_texture, (ox + 4, 4))
    draw.polygon([(ox + 5, 69), (ox + 48, 46), (ox + 91, 69), (ox + 48, 92)], fill=(125, 116, 91, 220), outline=dark)
    draw.polygon([(ox + 5, 69), (ox + 48, 92), (ox + 48, 121), (ox + 5, 97)], fill=(75, 70, 59, 235), outline=dark)
    draw.polygon([(ox + 48, 92), (ox + 91, 69), (ox + 91, 97), (ox + 48, 121)], fill=(91, 84, 69, 235), outline=dark)
    atlas.save(OUTPUT_DIR / "bich_props.png")
    return indices


def build_interior_reference() -> dict[str, list[int]]:
    # 0100没有独立Tiles层，地面和室内陈设均存于Objects.wil。
    floor_indices = [3629, 3630, 3631, 3632, 3633, 3634, 3636, 3637]
    prop_indices = [3596, 3597, 3598, 3599, 3600, 3601, 3618, 3621]
    ground = Image.new("RGBA", (512, 32), (0, 0, 0, 0))
    for slot, index in enumerate(floor_indices):
        ground.alpha_composite(diamond(wil("Objects.wil", index), 0.90), (slot * 64, 0))
    ground.save(OUTPUT_DIR / "bich_0100_interior_tiles.png")
    props = Image.new("RGBA", (768, 128), (0, 0, 0, 0))
    for slot, index in enumerate(prop_indices):
        image = source_part(index)
        props.alpha_composite(image, (slot * 96 + (96 - image.width) // 2, 124 - image.height))
    props.save(OUTPUT_DIR / "bich_0100_interior_props.png")
    return {"floor": floor_indices, "props": prop_indices}


def build() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    mask_dir = OUTPUT_DIR / "source_masks"
    mask_dir.mkdir(exist_ok=True)
    profiles = {}
    for code, label in [("0", "比奇省"), ("0100", "客户端小型室内图（具体功能待服务端MapInfo核定）")]:
        info, mask = parse_map(MAP_DIR / f"{code}.map")
        mask.save(mask_dir / f"{code}_walkability.png")
        preview = mask.copy()
        preview.thumbnail((280, 280), Image.Resampling.NEAREST)
        preview.save(mask_dir / f"{code}.png")
        profiles[code] = {
            "name": label,
            "sourceMapCode": code,
            "sourceMapPath": f"research/mir2_client_raw/Map/{code}.map",
            "sourceKind": "客户端原始MAP直接解析",
            "confidence": "A" if code == "0" else "B",
            **info,
        }

    ground_indices = build_ground()
    prop_indices = build_props()
    interior_indices = build_interior_reference()
    payload = {
        "baseline": "2003官服1.76基准版",
        "generatedFrom": "客户端0/0100 MAP与WIL/WIX原始资源，服务端!Setup出生点",
        "mapProfiles": profiles,
        "serviceMapping": {
            "serviceHomeMap": 0,
            "serviceHomePoint": [289, 618],
            "runtimeMapId": 4,
            "runtimeMapName": "比奇省",
            "source": "research/MIR2/GameOfMir/MirServer/Mir200/!Setup.txt",
            "confidence": "A",
        },
        "runtimeCoordinateMapping": {
            "projection": "isometric_64x32_full_size",
            "sourceSize": [700, 700],
            "cellHalfWidth": 32,
            "cellHalfHeight": 16,
            "centeredOnSourceMap": True,
            "sourceHomePoint": [289, 618],
            "worldHomePoint": [-10528, 3328],
            "worldBounds": [-22368, -11184, 44736, 22368],
            "renderPolicy": "仅绘制镜头附近57×57逻辑格；世界坐标与地图尺寸不压缩",
        },
        "classificationCorrection": "0.map是完整比奇省；0100.map仅15×18，证据不足以认定为整座比奇城，因此只按小型室内图保留，不与比奇城概念混同。",
        "assetSources": {
            "ground": {"library": "Data/Tiles.wil", "indices": ground_indices},
            "props": {"library": "Data/Objects.wil", "indices": prop_indices},
            "interior0100": {"library": "Data/Objects.wil", **interior_indices},
            "note": "地面直接提取；0.map大型物件由原客户端分格碎片重组为手机图集，补画部分仅用于连成碰撞可读轮廓。",
        },
    }
    PROFILE_OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BICH_SOURCE_PROFILES={PROFILE_OUTPUT}")
    print(f"BICH_SOURCE_ASSETS={OUTPUT_DIR}")


if __name__ == "__main__":
    build()
