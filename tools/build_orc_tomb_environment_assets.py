from pathlib import Path
import math
import random

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dev_art_sources/maps/orc_tomb/orc_tomb_tiles_alpha.png"
OUTPUT_DIR = ROOT / "assets/art/maps/orc_tomb"
TILE_SIZE = (64, 32)
PROP_SIZE = (96, 128)


def build_ground_tiles() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    cell_width = source.width // 4
    cell_height = source.height // 2
    atlas = Image.new("RGBA", (TILE_SIZE[0] * 8, TILE_SIZE[1]), (0, 0, 0, 0))
    diamond = Image.new("L", TILE_SIZE, 0)
    ImageDraw.Draw(diamond).polygon([(32, 0), (63, 15), (32, 31), (0, 15)], fill=255)
    for index in range(8):
        column, row = index % 4, index // 4
        cell = source.crop((column * cell_width, row * cell_height, (column + 1) * cell_width, (row + 1) * cell_height))
        box = cell.getchannel("A").getbbox()
        if box is None:
            raise ValueError(f"empty orc tomb tile cell: {index}")
        tile = cell.crop(box).resize(TILE_SIZE, Image.Resampling.LANCZOS)
        tile.putalpha(Image.composite(tile.getchannel("A"), Image.new("L", TILE_SIZE, 0), diamond))
        ImageDraw.Draw(tile).line([(32, 0), (63, 15), (32, 31), (0, 15), (32, 0)], fill=(23, 18, 15, 190), width=1)
        atlas.alpha_composite(tile, (index * TILE_SIZE[0], 0))
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output = OUTPUT_DIR / "orc_tomb_ground_tiles.png"
    atlas.save(output)
    print(f"ORC_TOMB_GROUND_ATLAS={output} SIZE={atlas.size}")


def _wall(draw: ImageDraw.ImageDraw, ox: int) -> None:
    draw.polygon([(ox + 4, 56), (ox + 48, 34), (ox + 92, 56), (ox + 48, 80)], fill=(83, 76, 65, 255))
    draw.polygon([(ox + 4, 56), (ox + 48, 80), (ox + 48, 122), (ox + 4, 98)], fill=(45, 42, 39, 255))
    draw.polygon([(ox + 48, 80), (ox + 92, 56), (ox + 92, 98), (ox + 48, 122)], fill=(58, 53, 47, 255))
    for y in (66, 82, 98):
        draw.line((ox + 8, y, ox + 47, y + 20), fill=(27, 25, 24, 220), width=2)
        draw.line((ox + 49, y + 20, ox + 88, y), fill=(31, 28, 26, 220), width=2)


def _pillar(draw: ImageDraw.ImageDraw, ox: int) -> None:
    draw.polygon([(ox + 26, 112), (ox + 48, 101), (ox + 72, 112), (ox + 49, 124)], fill=(48, 44, 40, 255))
    draw.polygon([(ox + 34, 30), (ox + 49, 22), (ox + 65, 30), (ox + 62, 106), (ox + 48, 114), (ox + 36, 106)], fill=(66, 61, 54, 255))
    draw.polygon([(ox + 34, 30), (ox + 49, 40), (ox + 48, 114), (ox + 36, 106)], fill=(49, 46, 43, 255))
    draw.line((ox + 52, 45, ox + 44, 66, ox + 54, 83), fill=(31, 27, 25, 255), width=3)
    draw.polygon([(ox + 29, 29), (ox + 49, 17), (ox + 70, 29), (ox + 49, 42)], fill=(92, 82, 68, 255))


def _brazier(draw: ImageDraw.ImageDraw, ox: int) -> None:
    draw.ellipse((ox + 23, 81, ox + 74, 106), fill=(35, 29, 25, 255))
    draw.ellipse((ox + 28, 78, ox + 69, 99), fill=(99, 62, 29, 255), outline=(154, 102, 46, 255), width=3)
    draw.polygon([(ox + 36, 89), (ox + 43, 45), (ox + 50, 68), (ox + 59, 34), (ox + 65, 89)], fill=(222, 72, 22, 235))
    draw.polygon([(ox + 41, 86), (ox + 49, 55), (ox + 54, 73), (ox + 59, 52), (ox + 61, 86)], fill=(255, 167, 47, 245))
    draw.polygon([(ox + 32, 103), (ox + 39, 119), (ox + 45, 117), (ox + 43, 102)], fill=(66, 52, 39, 255))
    draw.polygon([(ox + 64, 103), (ox + 58, 119), (ox + 52, 117), (ox + 55, 102)], fill=(66, 52, 39, 255))


def _skull_pile(draw: ImageDraw.ImageDraw, ox: int) -> None:
    rng = random.Random(176 + ox)
    for _ in range(13):
        x, y = ox + rng.randint(23, 73), rng.randint(78, 111)
        r = rng.randint(6, 10)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(145, 129, 93, 255), outline=(54, 48, 39, 255), width=2)
        draw.rectangle((x - 4, y + 4, x + 4, y + 9), fill=(102, 91, 68, 255))
        draw.ellipse((x - 5, y - 2, x - 1, y + 2), fill=(31, 28, 25, 255))
        draw.ellipse((x + 1, y - 2, x + 5, y + 2), fill=(31, 28, 25, 255))


def _rubble(draw: ImageDraw.ImageDraw, ox: int) -> None:
    rng = random.Random(405 + ox)
    for _ in range(18):
        x, y = ox + rng.randint(12, 83), rng.randint(78, 119)
        w, h = rng.randint(8, 18), rng.randint(5, 12)
        color = rng.choice([(59, 55, 50, 255), (74, 67, 58, 255), (91, 79, 64, 255)])
        draw.polygon([(x - w, y), (x, y - h), (x + w, y), (x, y + h // 2)], fill=color, outline=(35, 31, 29, 255))


def _arch(draw: ImageDraw.ImageDraw, ox: int) -> None:
    draw.rectangle((ox + 10, 48, ox + 29, 121), fill=(54, 49, 44, 255), outline=(31, 28, 26, 255), width=3)
    draw.rectangle((ox + 67, 48, ox + 86, 121), fill=(54, 49, 44, 255), outline=(31, 28, 26, 255), width=3)
    draw.arc((ox + 11, 8, ox + 85, 82), 180, 360, fill=(102, 88, 69, 255), width=18)
    draw.arc((ox + 19, 17, ox + 77, 74), 180, 360, fill=(45, 41, 38, 255), width=8)
    for x in (20, 48, 76):
        draw.line((ox + x, 27, ox + x - 4, 49), fill=(30, 27, 25, 230), width=2)


def _make_light_texture() -> Image.Image:
    size = 128
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - 63.5, y - 63.5) / 64.0
            alpha = int(190 * max(0.0, 1.0 - distance) ** 2)
            pixels[x, y] = (255, 116, 34, alpha)
    return image


def build_props() -> None:
    atlas = Image.new("RGBA", (PROP_SIZE[0] * 6, PROP_SIZE[1]), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    _wall(draw, 0)
    _pillar(draw, 96)
    _brazier(draw, 192)
    _skull_pile(draw, 288)
    _rubble(draw, 384)
    _arch(draw, 480)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    props = OUTPUT_DIR / "orc_tomb_props.png"
    atlas.save(props)
    light = OUTPUT_DIR / "orc_tomb_fire_glow.png"
    _make_light_texture().save(light)
    print(f"ORC_TOMB_PROP_ATLAS={props} SIZE={atlas.size}")
    print(f"ORC_TOMB_LIGHT_TEXTURE={light} SIZE=(128, 128)")


def build() -> None:
    # 兼容旧入口；正式资源已改由D001/D002/D003客户端原MAP构建器生成。
    from build_orc_tomb_client_assets import main
    main()


if __name__ == "__main__":
    build()
