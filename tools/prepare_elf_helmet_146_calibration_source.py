from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import deque
from io import BytesIO
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "vendor"))

from PIL import Image  # noqa: E402


DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
SOURCE_SIZE = (1448, 1086)
SOURCE_SHA256 = (
    "bf2b0c9741e2dfd7545c444996ea0def2cfb40b619a1ef447dce876deebf7b3c"
)
SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "elf_146_helmet_8dir_user_20260728.png"
)
TRANSPARENT_SHEET = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "elf_146_helmet_8dir_transparent.png"
)
DIRECTION_ROOT = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "elf_146_directions"
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=False)
    return buffer.getvalue()


def is_magenta_matte(red: int, green: int, blue: int) -> bool:
    return (
        red >= 120
        and blue >= 120
        and min(red, blue) >= green + 35
        and abs(red - blue) <= 105
    )


def is_white_matte(red: int, green: int, blue: int) -> bool:
    return min(red, green, blue) >= 245 and max(red, green, blue) - min(
        red, green, blue
    ) <= 12


def touches_transparency(
    pixels: object,
    x: int,
    y: int,
    width: int,
    height: int,
) -> bool:
    return any(
        0 <= x + dx < width
        and 0 <= y + dy < height
        and pixels[x + dx, y + dy][3] == 0
        for dx, dy in (
            (-1, -1),
            (0, -1),
            (1, -1),
            (-1, 0),
            (1, 0),
            (-1, 1),
            (0, 1),
            (1, 1),
        )
    )


def remove_mixed_matte(image: Image.Image) -> Image.Image:
    """Remove connected white/magenta generation mattes without resampling."""
    output = image.convert("RGBA")
    width, height = output.size
    pixels = output.load()
    background = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def enqueue_if_background(x: int, y: int) -> None:
        index = y * width + x
        if background[index]:
            return
        red, green, blue, _ = pixels[x, y]
        if not (
            is_magenta_matte(red, green, blue)
            or is_white_matte(red, green, blue)
        ):
            return
        background[index] = 1
        queue.append((x, y))

    for x in range(width):
        enqueue_if_background(x, 0)
        enqueue_if_background(x, height - 1)
    for y in range(height):
        enqueue_if_background(0, y)
        enqueue_if_background(width - 1, y)
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx = x + dx
            ny = y + dy
            if 0 <= nx < width and 0 <= ny < height:
                enqueue_if_background(nx, ny)
    for y in range(height):
        for x in range(width):
            if background[y * width + x]:
                pixels[x, y] = (0, 0, 0, 0)

    # Peel only matte-coloured antialiasing that touches the new boundary.
    for _ in range(8):
        clear: list[tuple[int, int]] = []
        for y in range(height):
            for x in range(width):
                red, green, blue, alpha = pixels[x, y]
                if alpha == 0 or not touches_transparency(
                    pixels, x, y, width, height
                ):
                    continue
                magenta_fringe = (
                    red >= 40
                    and blue >= 40
                    and min(red, blue) >= green + 15
                    and abs(red - blue) <= 140
                )
                white_fringe = (
                    min(red, green, blue) >= 218
                    and max(red, green, blue) - min(red, green, blue) <= 38
                )
                if magenta_fringe or white_fringe:
                    clear.append((x, y))
        if not clear:
            break
        for x, y in clear:
            pixels[x, y] = (0, 0, 0, 0)

    # Transparent pixels must carry zero RGB for the later one-pass bake.
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] == 0:
                pixels[x, y] = (0, 0, 0, 0)
    return output


def crop_alpha(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("empty item-146 direction after matte removal")
    return image.crop(box)


def source_cell(sheet: Image.Image, slot: int) -> Image.Image:
    column = slot % 4
    row = slot // 4
    x0 = round(column * sheet.width / 4)
    x1 = round((column + 1) * sheet.width / 4)
    y0 = round(row * sheet.height / 2)
    y1 = round((row + 1) * sheet.height / 2)
    return sheet.crop((x0, y0, x1, y1))


def prepare(check: bool) -> dict[str, object]:
    if file_sha256(SOURCE) != SOURCE_SHA256:
        raise AssertionError("item-146 user source hash changed")
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != SOURCE_SIZE:
        raise AssertionError(
            f"item-146 user source size changed: {source.size}"
        )

    transparent = Image.new("RGBA", SOURCE_SIZE, (0, 0, 0, 0))
    direction_images: dict[str, Image.Image] = {}
    cell_width = SOURCE_SIZE[0] // 4
    cell_height = SOURCE_SIZE[1] // 2
    for slot, direction in enumerate(DIRECTIONS):
        cleaned_cell = remove_mixed_matte(source_cell(source, slot))
        transparent.alpha_composite(
            cleaned_cell,
            ((slot % 4) * cell_width, (slot // 4) * cell_height),
        )
        direction_images[direction] = crop_alpha(cleaned_cell)

    expected_files = {
        TRANSPARENT_SHEET: png_bytes(transparent),
        **{
            DIRECTION_ROOT / f"{direction.lower()}.png": png_bytes(image)
            for direction, image in direction_images.items()
        },
    }
    if check:
        for path, expected in expected_files.items():
            if not path.exists() or path.read_bytes() != expected:
                raise AssertionError(
                    f"{path.relative_to(ROOT)} needs calibration-source rebuild"
                )
    else:
        DIRECTION_ROOT.mkdir(parents=True, exist_ok=True)
        for path, expected in expected_files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)

    return {
        "itemId": 146,
        "visualAssetId": "elf_146",
        "sourceSha256": SOURCE_SHA256,
        "transparentSheet": {
            "path": TRANSPARENT_SHEET.relative_to(ROOT).as_posix(),
            "sha256": file_sha256(TRANSPARENT_SHEET),
            "size": list(SOURCE_SIZE),
        },
        "directions": {
            direction: {
                "path": (
                    DIRECTION_ROOT / f"{direction.lower()}.png"
                ).relative_to(ROOT).as_posix(),
                "sha256": file_sha256(
                    DIRECTION_ROOT / f"{direction.lower()}.png"
                ),
                "size": list(direction_images[direction].size),
            }
            for direction in DIRECTIONS
        },
        "directionOrder": list(DIRECTIONS),
        "resolutionPolicy": (
            "original_direction_cutouts_no_resize_until_final_runtime_bake"
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(args.check), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
