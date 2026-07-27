#!/usr/bin/env python3
"""Patch only item 224's missing NE/NW source cells from the approved reference."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "prayer_helmet_8dir.png"
)
REFERENCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "prayer_helmet_ne_nw_generated_reference.png"
)
GRID_COLUMNS = 4
GRID_ROWS = 2
TARGET_HEIGHT = 282
GREEN = (0, 255, 0, 255)
PATCHES = {
    "NE": {"source_slot": 7, "reference_half": 0},
    "NW": {"source_slot": 1, "reference_half": 1},
}


def chroma_subject(image: Image.Image) -> Image.Image:
    pixels: list[tuple[int, int, int, int]] = []
    for red, green, blue, _alpha in image.getdata():
        is_green_background = (
            green >= 140
            and green > red * 1.45
            and green > blue * 1.45
        )
        pixels.append(
            (red, green, blue, 0 if is_green_background else 255)
        )
    keyed = Image.new("RGBA", image.size)
    keyed.putdata(pixels)
    bbox = keyed.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("generated diagonal reference has no visible subject")
    return keyed.crop(bbox)


def main() -> None:
    atlas = Image.open(SOURCE).convert("RGBA")
    before = atlas.copy()
    reference = Image.open(REFERENCE).convert("RGBA")
    cell_width = atlas.width // GRID_COLUMNS
    cell_height = atlas.height // GRID_ROWS
    half_width = reference.width // 2

    if atlas.size != (1536, 1024):
        raise ValueError(f"unexpected prayer source size: {atlas.size}")
    if reference.size != (1536, 1024):
        raise ValueError(f"unexpected diagonal reference size: {reference.size}")

    target_boxes: list[tuple[int, int, int, int]] = []
    for direction, patch in PATCHES.items():
        half = int(patch["reference_half"])
        subject = chroma_subject(
            reference.crop(
                (
                    half * half_width,
                    0,
                    (half + 1) * half_width,
                    reference.height,
                )
            )
        )
        target_width = round(subject.width * TARGET_HEIGHT / subject.height)
        subject = subject.resize(
            (target_width, TARGET_HEIGHT),
            Image.Resampling.NEAREST,
        )

        source_slot = int(patch["source_slot"])
        cell_x = (source_slot % GRID_COLUMNS) * cell_width
        cell_y = (source_slot // GRID_COLUMNS) * cell_height
        cell_box = (
            cell_x,
            cell_y,
            cell_x + cell_width,
            cell_y + cell_height,
        )
        target_boxes.append(cell_box)
        atlas.paste(GREEN, cell_box)
        paste_x = cell_x + (cell_width - subject.width) // 2
        paste_y = cell_y + (cell_height - subject.height) // 2
        atlas.alpha_composite(subject, (paste_x, paste_y))
        print(
            f"{direction}: slot={source_slot} "
            f"subject={subject.width}x{subject.height}"
        )

    before_pixels = before.load()
    after_pixels = atlas.load()
    for y in range(atlas.height):
        for x in range(atlas.width):
            inside_target = any(
                left <= x < right and top <= y < bottom
                for left, top, right, bottom in target_boxes
            )
            if not inside_target and before_pixels[x, y] != after_pixels[x, y]:
                raise AssertionError(f"non-target source pixel changed at {x},{y}")

    atlas.save(SOURCE, format="PNG", optimize=False, compress_level=9)
    print(
        "PATCH_PRAYER_224_MISSING_DIAGONALS_PASS "
        "NE=slot7 NW=slot1 other_source_cells_unchanged=true"
    )


if __name__ == "__main__":
    main()
