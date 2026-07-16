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
OUTPUT = ROOT / "assets/art/maps/wooma_temple"
PROFILE_OUTPUT = ROOT / "assets/data/wooma_temple_source_profiles.json"
TILE_SIZE = (64, 32)
PROP_SIZE = (96, 128)
MAPS = {312: ("沃玛寺庙入口", "D021"), 313: ("沃玛寺庙一层", "D022"), 314: ("沃玛寺庙二层", "D023"), 315: ("沃玛寺庙大厅", "D024")}

sys.path.insert(0, str(WORKSPACE / "tools"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sprite(library: str, index: int) -> Image.Image:
    data, palette, offsets, _ = read_library(DATA_DIR / library)
    image, _ = decode_sprite(data, offsets[index], palette)
    return image.convert("RGBA")


def parse_map(path: Path) -> tuple[dict, Image.Image]:
    raw = path.read_bytes()
    width, height = struct.unpack_from("<HH", raw, 0)
    if len(raw) != 52 + width * height * 12:
        raise ValueError(f"地图结构错误：{path.name}")
    blocked = lights = doors = 0
    tiles, objects, areas = Counter(), Counter(), Counter()
    mask = Image.new("L", (width, height), 0)
    pixels = mask.load()
    for index, offset in enumerate(range(52, len(raw), 12)):
        bk, _mid, front, door, _door_offset, _ani, _tick, area, light = struct.unpack_from("<HHHBBBBBB", raw, offset)
        x, y = divmod(index, height)
        is_blocked = bool((bk | front) & 0x8000)
        pixels[x, y] = 40 if is_blocked else 225
        blocked += int(is_blocked)
        lights += int(light > 0)
        doors += int((door & 0x7F) > 0)
        if bk & 0x7FFF:
            tiles[bk & 0x7FFF] += 1
        if front & 0x7FFF:
            objects[f"Objects{area + 1}:{front & 0x7FFF}"] += 1
        areas[area] += 1
    return ({
        "width": width, "height": height, "blockedRatio": round(blocked / (width * height), 4),
        "lightCells": lights, "doorCells": doors,
        "topTileImageIds": [key for key, _ in tiles.most_common(10)],
        "topObjectImageIds": [key for key, _ in objects.most_common(14)],
        "areaCounts": {str(k): v for k, v in areas.items()},
    }, mask)


def diamond(image: Image.Image, brightness: float) -> Image.Image:
    tile = ImageEnhance.Brightness(image.resize(TILE_SIZE, Image.Resampling.LANCZOS)).enhance(brightness)
    mask = Image.new("L", TILE_SIZE, 0)
    ImageDraw.Draw(mask).polygon([(32, 0), (63, 15), (32, 31), (0, 15)], fill=255)
    tile.putalpha(mask)
    ImageDraw.Draw(tile).line([(32, 0), (63, 15), (32, 31), (0, 15), (32, 0)], fill=(42, 30, 19, 220), width=1)
    return tile


def build_ground() -> list[int]:
    indices = [2000, 2001, 2002, 2003, 2004, 2000, 2002, 2004]
    atlas = Image.new("RGBA", (512, 32), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        atlas.alpha_composite(diamond(sprite("Tiles.wil", index), 0.72 + slot * 0.025), (slot * 64, 0))
    atlas.save(OUTPUT / "wooma_temple_ground_tiles.png")
    return indices


def source_layer(index: int, max_size=(82, 112), brightness=0.9) -> Image.Image:
    image = ImageEnhance.Brightness(sprite("Objects2.wil", index)).enhance(brightness)
    image.thumbnail(max_size, Image.Resampling.LANCZOS)
    return image


def build_props() -> list[int]:
    # 墙体、柱脚和火焰均选择自D021—D024实际引用范围；祭坛等轮廓按手机视野重新组合。
    indices = [3697, 3716, 3738, 3703, 3722, 3488, 3732, 3719]
    atlas = Image.new("RGBA", (768, 128), (0, 0, 0, 0))
    for slot, index in enumerate(indices):
        part = source_layer(index)
        atlas.alpha_composite(part, (slot * 96 + (96 - part.width) // 2, 124 - part.height))
    draw = ImageDraw.Draw(atlas)
    stone = (104, 84, 58, 255); dark = (43, 34, 27, 255); gold = (173, 111, 36, 255); ember = (239, 91, 23, 255)
    # 0 石柱
    draw.polygon([(16, 119), (80, 119), (68, 103), (28, 103)], fill=dark)
    draw.polygon([(29, 103), (67, 103), (62, 30), (34, 30)], fill=stone, outline=dark)
    draw.polygon([(24, 34), (72, 34), (64, 19), (32, 19)], fill=(135, 106, 69, 255), outline=dark)
    # 1 墙段
    ox=96; draw.polygon([(ox+4,61),(ox+48,39),(ox+92,61),(ox+48,83)],fill=stone,outline=dark); draw.polygon([(ox+4,61),(ox+48,83),(ox+48,122),(ox+4,99)],fill=dark); draw.polygon([(ox+48,83),(ox+92,61),(ox+92,99),(ox+48,122)],fill=(73,57,43,255))
    # 2 雕像
    ox=192; draw.ellipse((ox+32,20,ox+64,50),fill=stone,outline=dark); draw.polygon([(ox+27,48),(ox+69,48),(ox+78,104),(ox+18,104)],fill=(85,67,51,255),outline=dark); draw.rectangle((ox+29,103,ox+67,120),fill=stone,outline=dark)
    # 3 祭坛
    ox=288; draw.polygon([(ox+9,89),(ox+48,68),(ox+88,89),(ox+48,111)],fill=(139,104,57,255),outline=dark); draw.polygon([(ox+17,91),(ox+48,77),(ox+80,91),(ox+48,103)],fill=(55,36,27,255)); draw.ellipse((ox+37,72,ox+59,88),fill=ember)
    # 4 门洞
    ox=384; draw.rectangle((ox+10,53,ox+29,122),fill=stone,outline=dark); draw.rectangle((ox+67,53,ox+86,122),fill=stone,outline=dark); draw.arc((ox+11,10,ox+85,84),180,360,fill=(130,100,65,255),width=18); draw.arc((ox+22,22,ox+74,74),180,360,fill=dark,width=9)
    # 5 火盆
    ox=480; draw.ellipse((ox+25,80,ox+72,104),fill=dark,outline=gold,width=3); draw.polygon([(ox+34,88),(ox+43,43),(ox+50,70),(ox+60,34),(ox+66,89)],fill=ember); draw.polygon([(ox+41,88),(ox+48,55),(ox+55,76),(ox+61,52),(ox+62,88)],fill=(255,184,53,255))
    # 6 符文碑
    ox=576; draw.polygon([(ox+26,116),(ox+70,116),(ox+65,33),(ox+31,33)],fill=(76,60,48,255),outline=dark); draw.line((ox+48,47,ox+39,65,ox+56,78,ox+43,99),fill=gold,width=3)
    # 7 教主席位
    ox=672; draw.polygon([(ox+12,111),(ox+84,111),(ox+72,82),(ox+24,82)],fill=dark,outline=gold); draw.polygon([(ox+24,82),(ox+48,61),(ox+72,82),(ox+48,96)],fill=(131,70,32,255)); draw.line((ox+48,61,ox+48,29),fill=gold,width=4); draw.ellipse((ox+41,21,ox+55,35),fill=ember)
    atlas.save(OUTPUT / "wooma_temple_props.png")
    return indices


def build_glow() -> None:
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0)); pixels=image.load()
    for y in range(128):
        for x in range(128):
            d=math.hypot(x-63.5,y-63.5)/64.0; a=int(190*max(0.0,1.0-d)**2); pixels[x,y]=(255,103,31,a)
    image.save(OUTPUT / "wooma_temple_fire_glow.png")


def build() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True); masks=OUTPUT/"source_masks"; masks.mkdir(exist_ok=True)
    profiles={}
    for map_id,(name,code) in MAPS.items():
        info,mask=parse_map(MAP_DIR/f"{code}.map"); mask.thumbnail((240,240),Image.Resampling.NEAREST); mask.save(masks/f"{map_id}_{code}.png")
        profiles[str(map_id)]={"name":name,"sourceMapCode":code,"sourceMapPath":f"research/mir2_client_raw/Map/{code}.map","sourceKind":"客户端原始MAP直接解析","confidence":"A",**info}
    tiles=build_ground(); objects=build_props(); build_glow()
    PROFILE_OUTPUT.write_text(json.dumps({"baseline":"2003官服1.76基准版","generatedFrom":"客户端D021—D024 MAP与WIL/WIX原始资源","mapProfiles":profiles,"assetSources":{"ground":{"library":"Data/Tiles.wil","indices":tiles},"props":{"library":"Data/Objects2.wil","indices":objects},"note":"石砖、墙体、柱脚和火焰取自客户端；大型场景物件按96×128手机图集重组。"}},ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"WOOMA_TEMPLE_PROFILES={PROFILE_OUTPUT}")
    print(f"WOOMA_TEMPLE_ASSETS={OUTPUT}")


if __name__ == "__main__": build()
