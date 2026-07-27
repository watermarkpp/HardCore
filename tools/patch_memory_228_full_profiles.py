#!/usr/bin/env python3
"""Replace only item 228 source column three with true W/E profiles."""

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "memory_helmet_8dir.png"
)
REFERENCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "memory_helmet_full_profiles_generated_reference.png"
)
GRID_COLUMNS = 4
GRID_ROWS = 2
TARGET_HEIGHT = 319
GREEN = (0, 255, 0, 255)
PATCHES = {
    "W": {"source_slot": 2, "reference_half": 0},
    "E": {"source_slot": 6, "reference_half": 1},
}


def alpha_subject(image: Image.Image) -> Image.Image:
    bbox = image.getchannel("A").point(
        lambda value: 255 if value > 32 else 0
    ).getbbox()
    if bbox is None:
        raise ValueError("profile reference has no visible subject")
    return image.crop(bbox)


def main() -> None:
    atlas = Image.open(SOURCE).convert("RGBA")
    before = atlas.copy()
    reference = Image.open(REFERENCE).convert("RGBA")
    cell_width = atlas.width // GRID_COLUMNS
    cell_height = atlas.height // GRID_ROWS
    half_width = reference.width // 2

    if atlas.size != (1536, 1024):
        raise ValueError(f"unexpected memory source size: {atlas.size}")
    if reference.size != (1536, 1024):
        raise ValueError(f"unexpected profile reference size: {reference.size}")

    target_boxes: list[tuple[int, int, int, int]] = []
    for direction, patch in PATCHES.items():
        half = int(patch["reference_half"])
        subject = alpha_subject(
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
        "PATCH_MEMORY_228_FULL_PROFILES_PASS "
        "W=slot2 E=slot6 other_source_cells_unchanged=true"
    )


if __name__ == "__main__":
    main()
