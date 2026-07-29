#!/usr/bin/env python3
"""Add action/frame/direction labels outside the 240 acceptance cells."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ACTIONS = {
    "idle": 4,
    "walk": 6,
    "attack": 6,
    "cast": 6,
    "hit": 3,
    "death": 4,
}
ACTION_ORDER = tuple(ACTIONS)
DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
CELL = (256, 256)
LEFT = 72
TOP = 42
BACKGROUND = (17, 20, 24, 255)
TEXT = (235, 240, 246, 255)
ACCENT = (245, 194, 66, 255)


def font(size: int) -> ImageFont.ImageFont:
    candidates = (
        Path("C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arial.ttf"),
    )
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def annotate_action(root: Path, action: str, frames: int) -> None:
    source_path = root / f"item_240_{action}_all_frames.png"
    source = Image.open(source_path).convert("RGBA")
    output = Image.new(
        "RGBA", (source.width + LEFT, source.height + TOP), BACKGROUND
    )
    output.alpha_composite(source, (LEFT, TOP))
    draw = ImageDraw.Draw(output)
    header_font = font(20)
    label_font = font(18)
    draw.text((8, 9), action.upper(), fill=ACCENT, font=header_font)
    for frame in range(frames):
        draw.text(
            (LEFT + frame * CELL[0] + 12, 10),
            f"frame {frame}",
            fill=TEXT,
            font=label_font,
        )
    for row, direction in enumerate(DIRECTIONS):
        draw.text(
            (12, TOP + row * CELL[1] + 12),
            direction,
            fill=TEXT,
            font=label_font,
        )
    output.save(
        root / f"item_240_{action}_all_frames_annotated.png",
        optimize=True,
    )


def annotate_overview(root: Path) -> None:
    source = Image.open(root / "item_240_loaded_overview.png").convert("RGBA")
    output = Image.new(
        "RGBA", (source.width + LEFT, source.height + TOP), BACKGROUND
    )
    output.alpha_composite(source, (LEFT, TOP))
    draw = ImageDraw.Draw(output)
    label_font = font(18)
    for column, action in enumerate(ACTION_ORDER):
        draw.text(
            (LEFT + column * CELL[0] + 12, 10),
            action.upper(),
            fill=ACCENT,
            font=label_font,
        )
    for row, direction in enumerate(DIRECTIONS):
        draw.text(
            (12, TOP + row * CELL[1] + 12),
            direction,
            fill=TEXT,
            font=label_font,
        )
    output.save(root / "item_240_loaded_overview_annotated.png", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.preview_root.resolve()
    for action, frames in ACTIONS.items():
        annotate_action(root, action, frames)
    annotate_overview(root)
    print("HELMET_240_PREVIEW_ANNOTATION_PASS sheets=7")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
