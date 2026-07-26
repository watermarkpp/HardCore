from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs" / "visual_acceptance" / "equipment_helmet_directions"
MANIFEST = OUTPUT / "capture_manifest.json"
SHEETS = OUTPUT / "contact_sheets"
BG = (18, 27, 39, 255)
CARD = (29, 42, 58, 255)
GRID = (53, 195, 210, 120)
TEXT = (238, 243, 248, 255)
MUTED = (170, 187, 204, 255)
ACCENT = (255, 196, 85, 255)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/msyhbd.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)


TITLE = font(30)
LABEL = font(22)
SMALL = font(17)


def runtime_card(source: Image.Image, size: int, direction: str) -> Image.Image:
    card = Image.new("RGBA", (size, size + 38), CARD)
    draw = ImageDraw.Draw(card, "RGBA")
    scale = size / source.width
    foot_x = int(round(128 * scale))
    foot_y = int(round(190 * scale)) + 38
    draw.line((foot_x, 38, foot_x, card.height), fill=GRID, width=1)
    draw.line((0, foot_y, size, foot_y), fill=GRID, width=1)
    draw.text((12, 7), direction, font=LABEL, fill=TEXT)
    draw.text((size - 70, 10), "idle", font=SMALL, fill=MUTED)
    resized = source.resize((size, size), Image.Resampling.NEAREST)
    card.alpha_composite(resized, (0, 38))
    return card


def build_item_sheet(item: dict) -> Path:
    card_size = 512
    gap = 12
    title_height = 70
    width = card_size * 4 + gap * 5
    height = title_height + (card_size + 38) * 2 + gap * 3
    sheet = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    title = f"itemId {item['itemId']}  {item['itemName']}  /  {item['identityId']}"
    draw.text((gap, 14), title, font=TITLE, fill=ACCENT)
    draw.text((width - 380, 22), "PlayerVisual  男 / 布衣(男) / idle", font=SMALL, fill=MUTED)
    captures = {capture["direction"]: capture for capture in item["captures"]}
    for index, direction in enumerate(DIRECTIONS):
        capture = captures[direction]
        source = Image.open(ROOT / capture["path"].replace("res://", "")).convert("RGBA")
        card = runtime_card(source, card_size, direction)
        x = gap + (index % 4) * (card_size + gap)
        y = title_height + gap + (index // 4) * (card.height + gap)
        sheet.alpha_composite(card, (x, y))
    path = SHEETS / f"{item['itemId']}_{item['identityId']}_8_directions.png"
    sheet.convert("RGB").save(path, quality=95)
    return path


def build_overview(items: list[dict]) -> Path:
    label_width = 220
    card_size = 256
    header_height = 70
    row_height = 284
    gap = 6
    width = label_width + len(DIRECTIONS) * (card_size + gap) + gap
    height = header_height + len(items) * row_height + gap
    overview = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(overview)
    draw.text((12, 12), "全部男性世界头盔 · PlayerVisual 八方向 idle", font=TITLE, fill=ACCENT)
    for column, direction in enumerate(DIRECTIONS):
        x = label_width + column * (card_size + gap)
        draw.text((x + 10, 39), direction, font=LABEL, fill=TEXT)
    for row, item in enumerate(items):
        y = header_height + row * row_height
        draw.rectangle((0, y, width, y + row_height - gap), fill=CARD)
        draw.text((12, y + 72), f"itemId {item['itemId']}", font=LABEL, fill=ACCENT)
        draw.text((12, y + 108), item["itemName"], font=TITLE, fill=TEXT)
        draw.text((12, y + 152), item["identityId"], font=SMALL, fill=MUTED)
        captures = {capture["direction"]: capture for capture in item["captures"]}
        for column, direction in enumerate(DIRECTIONS):
            capture = captures[direction]
            source = Image.open(ROOT / capture["path"].replace("res://", "")).convert("RGBA")
            x = label_width + column * (card_size + gap)
            draw.line((x + 128, y, x + 128, y + card_size), fill=GRID, width=1)
            draw.line((x, y + 190, x + card_size, y + 190), fill=GRID, width=1)
            overview.alpha_composite(source, (x, y))
    path = SHEETS / "all_helmets_8_directions_overview.png"
    overview.convert("RGB").save(path, quality=95)
    return path


def main() -> None:
    with MANIFEST.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    assert manifest["runtimeComposite"] == (
        "PlayerVisual/BodySprite + PlayerVisual/ClientHelmetLayer"
    )
    assert manifest["paperDollOrStateItemPixelsUsed"] is False
    items = manifest["items"]
    assert len(items) == 12
    assert all(len(item["captures"]) == 8 for item in items)
    SHEETS.mkdir(parents=True, exist_ok=True)
    paths = [build_item_sheet(item) for item in items]
    paths.append(build_overview(items))
    print(
        "EQUIPMENT_HELMET_CONTACT_SHEETS_PASS "
        f"item_sheets={len(paths) - 1} overview={paths[-1]}"
    )


if __name__ == "__main__":
    main()
