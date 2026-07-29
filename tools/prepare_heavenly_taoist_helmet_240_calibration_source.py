from __future__ import annotations

import argparse
import hashlib
import json
import sys
from io import BytesIO
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "vendor"))

from PIL import Image  # noqa: E402


DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
SOURCE_SIZE = (1774, 1333)
SOURCE_SHA256 = (
    "b82153c7888f258ea783a24bcb43a6302c3c52ef58bc66310a52c6ec2e6b39c7"
)
EXTERNAL_SOURCE = Path(
    "C:/Users/Administrator/Desktop/sucai/装备/"
    "ChatGPT Image 2026年7月29日 10_45_07.png"
)
SOURCE = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_240_helmet_10view_user_20260729.png"
)
TRANSPARENT_WORLD_SHEET = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_240_helmet_8dir_transparent.png"
)
DIRECTION_ROOT = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_240_directions"
)
PRESENTATION_ROOT = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_240_presentation"
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=False)
    return buffer.getvalue()


def alpha_crop(image: Image.Image, label: str) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError(f"empty item-240 view: {label}")
    return image.crop(box)


def source_cell(sheet: Image.Image, slot: int) -> Image.Image:
    column = slot % 4
    row = slot // 4
    x0 = round(column * sheet.width / 4)
    x1 = round((column + 1) * sheet.width / 4)
    y0 = round(row * sheet.height / 3)
    y1 = round((row + 1) * sheet.height / 3)
    return sheet.crop((x0, y0, x1, y1))


def import_project_source() -> None:
    if SOURCE.exists():
        return
    if not EXTERNAL_SOURCE.exists():
        raise FileNotFoundError(
            "item-240 project source is absent and the authorized external "
            f"source cannot be found: {EXTERNAL_SOURCE}"
        )
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    SOURCE.write_bytes(EXTERNAL_SOURCE.read_bytes())


def prepare(check: bool) -> dict[str, object]:
    if not check:
        import_project_source()
    if not SOURCE.exists() or file_sha256(SOURCE) != SOURCE_SHA256:
        raise AssertionError("item-240 user source hash changed")
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != SOURCE_SIZE:
        raise AssertionError(
            f"item-240 user source size changed: {source.size}"
        )

    direction_images = {
        direction: alpha_crop(source_cell(source, slot), direction)
        for slot, direction in enumerate(DIRECTIONS)
    }
    presentation_images = {
        "inventory": alpha_crop(source_cell(source, 8), "inventory"),
        "ground": alpha_crop(source_cell(source, 9), "ground"),
    }
    if source_cell(source, 10).getchannel("A").getbbox() is not None:
        raise AssertionError("item-240 source slot 10 must remain empty")
    if source_cell(source, 11).getchannel("A").getbbox() is not None:
        raise AssertionError("item-240 source slot 11 must remain empty")

    cell_width = max(image.width for image in direction_images.values())
    cell_height = max(image.height for image in direction_images.values())
    transparent_world_sheet = Image.new(
        "RGBA", (cell_width * 4, cell_height * 2), (0, 0, 0, 0)
    )
    for slot, direction in enumerate(DIRECTIONS):
        image = direction_images[direction]
        cell_x = (slot % 4) * cell_width
        cell_y = (slot // 4) * cell_height
        destination = (
            cell_x + (cell_width - image.width) // 2,
            cell_y + (cell_height - image.height) // 2,
        )
        transparent_world_sheet.paste(image, destination)

    expected_files = {
        TRANSPARENT_WORLD_SHEET: png_bytes(transparent_world_sheet),
        **{
            DIRECTION_ROOT / f"{direction.lower()}.png": png_bytes(image)
            for direction, image in direction_images.items()
        },
        **{
            PRESENTATION_ROOT / f"{role}.png": png_bytes(image)
            for role, image in presentation_images.items()
        },
    }
    if check:
        for path, expected in expected_files.items():
            if not path.exists() or path.read_bytes() != expected:
                raise AssertionError(
                    f"{path.relative_to(ROOT)} needs calibration-source rebuild"
                )
    else:
        for path, expected in expected_files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)

    return {
        "itemId": 240,
        "visualAssetId": "heavenly_taoist",
        "sourceSha256": SOURCE_SHA256,
        "sourceAlphaPolicy": (
            "user_authored_alpha_preserved_no_matte_removal"
        ),
        "transparentWorldSheet": {
            "path": TRANSPARENT_WORLD_SHEET.relative_to(ROOT).as_posix(),
            "sha256": file_sha256(TRANSPARENT_WORLD_SHEET),
            "size": list(transparent_world_sheet.size),
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
        "presentation": {
            role: {
                "path": (
                    PRESENTATION_ROOT / f"{role}.png"
                ).relative_to(ROOT).as_posix(),
                "sha256": file_sha256(
                    PRESENTATION_ROOT / f"{role}.png"
                ),
                "size": list(image.size),
                "sourceSlot": 8 if role == "inventory" else 9,
                "dedicatedRole": role,
            }
            for role, image in presentation_images.items()
        },
        "directionOrder": list(DIRECTIONS),
        "resolutionPolicy": (
            "original_rgba_cutouts_no_resize_until_final_runtime_bake"
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(args.check), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
