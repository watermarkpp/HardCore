#!/usr/bin/env python3
"""Compose stable in-game Black Iron Helmet acceptance sheets."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "outputs/visual_acceptance/player_states"
OUTPUT = ROOT / "outputs/visual_acceptance/black_iron_helmet_runtime_acceptance.png"
HEAD_OUTPUT = ROOT / "outputs/visual_acceptance/black_iron_helmet_runtime_head_zoom.png"
VERSION_TAG = "v07225_w_flipped_20260715b"
VERSIONED_OUTPUT = ROOT / f"outputs/visual_acceptance/black_iron_helmet_runtime_acceptance_{VERSION_TAG}.png"
VERSIONED_HEAD_OUTPUT = ROOT / f"outputs/visual_acceptance/black_iron_helmet_runtime_head_zoom_{VERSION_TAG}.png"
DIRECTION_FILES = [
    ("N", f"{VERSION_TAG}_idle_n.png"),
    ("NE", f"{VERSION_TAG}_idle_ne.png"),
    ("E", f"{VERSION_TAG}_idle_e.png"),
    ("SE", f"{VERSION_TAG}_idle_se.png"),
    ("S", f"{VERSION_TAG}_idle_s.png"),
    ("SW", f"{VERSION_TAG}_idle_sw.png"),
    ("W", f"{VERSION_TAG}_idle_w.png"),
    ("NW", f"{VERSION_TAG}_idle_nw.png"),
]
ACTION_FILES = [
    ("IDLE S", f"{VERSION_TAG}_idle_s.png"),
    ("WALK E", f"{VERSION_TAG}_walk_east.png"),
    ("ATTACK E", f"{VERSION_TAG}_attack_east.png"),
    ("HIT S", f"{VERSION_TAG}_hit_south.png"),
    ("DEATH S", f"{VERSION_TAG}_death_south.png"),
]
CROP = (180, 105, 480, 535)
TILE = (300, 462)


def tile(label: str, path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    cropped = image.crop(CROP)
    result = Image.new("RGB", TILE, (16, 17, 20))
    result.paste(cropped, (0, 32))
    draw = ImageDraw.Draw(result)
    draw.text((10, 9), label, fill=(255, 222, 92))
    return result


def main() -> None:
    records = DIRECTION_FILES + ACTION_FILES
    missing = [str(SOURCE / filename) for _, filename in records if not (SOURCE / filename).exists()]
    if missing:
        raise FileNotFoundError("Missing acceptance captures: " + ", ".join(missing))
    columns = 4
    rows = 4
    sheet = Image.new("RGB", (columns * TILE[0], rows * TILE[1]), (10, 11, 14))
    for index, (label, filename) in enumerate(records):
        sheet.paste(tile(label, SOURCE / filename), ((index % columns) * TILE[0], (index // columns) * TILE[1]))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, rows * TILE[1] - 24), "8 idle directions + 5 action samples; captured from Godot runtime", fill=(220, 220, 220))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT)
    sheet.save(VERSIONED_OUTPUT)
    head_tile = (240, 280)
    head_sheet = Image.new("RGB", (head_tile[0] * 4, head_tile[1] * 2), (10, 11, 14))
    for index, (label, filename) in enumerate(DIRECTION_FILES):
        image = Image.open(SOURCE / filename).convert("RGB")
        head = image.crop((225, 155, 345, 285)).resize((240, 260), Image.Resampling.NEAREST)
        target = Image.new("RGB", head_tile, (16, 17, 20))
        target.paste(head, (0, 20))
        ImageDraw.Draw(target).text((8, 4), label, fill=(255, 222, 92))
        head_sheet.paste(target, ((index % 4) * head_tile[0], (index // 4) * head_tile[1]))
    head_sheet.save(HEAD_OUTPUT)
    head_sheet.save(VERSIONED_HEAD_OUTPUT)
    print(
        "BLACK_IRON_HELMET_ACCEPTANCE_SHEET_PASS "
        f"path={VERSIONED_OUTPUT.relative_to(ROOT).as_posix()} "
        f"head={VERSIONED_HEAD_OUTPUT.relative_to(ROOT).as_posix()}"
    )


if __name__ == "__main__":
    main()
