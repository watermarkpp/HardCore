from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "vendor"))

from PIL import Image  # noqa: E402


DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
EXPECTED_COMPONENT_COUNTS = {
    "N": 3,
    "NE": 3,
    "E": 1,
    "SE": 1,
    "S": 1,
    "SW": 1,
    "W": 1,
    "NW": 3,
}
FROZEN_RUNTIME_SHA256 = {
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_idle.png": (
        "c5f77ca64c823cedab3d95578b9874f9bd8e8e482ed9d723d0f6f188c815799f"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_walk.png": (
        "ec339bd71740fc712666bd7ac3097970dcac7e240475b0c7ccf6718e8956147f"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_attack.png": (
        "8a40cff083b6481a93633c5f1e9ebeabf4a6a2f0968e73e86238ee24bca2d626"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_cast.png": (
        "40e02b152c15997c1ae41ff510a0e125b793c819b1975b95ec002c2b0db5f21a"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_hit.png": (
        "a2ebc69c2374b4ce7e99ea042c3d403a9680bd3743fbcc583337ee69c9b7182a"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "god_magic_helmet_death.png": (
        "f6e58e5a6fe462312bfea4dd68ace5222e5b9d24cc1ebda2b8e850eabee005d7"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00236_head.png": (
        "0ee91aa38c22da3de642377566f346ba585a0d1b0c079f7b06596bb9a7b57186"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00236_erase_mask.png": (
        "005ab196b6c403ec4b468e847798d30ed8ede4b6f1dc67015ccc4afca9122377"
    ),
    "assets/art/items/client/project_redesign/helmet/god_magic/"
    "item_00236_inventory.png": (
        "36f6ae682386ac1d19d50dc1bac6d63d109ce2b616d0f9d82a4019641fb1eb66"
    ),
    "assets/art/items/client/project_redesign/helmet/god_magic/"
    "item_00236_ground.png": (
        "46ae36492bf68154cdd7ebbaf13bbb905f1658dc9e2d04d7f0ded0ae2a8d3301"
    ),
    "assets/art/items/client/inventory/101.png": (
        "6843206589487a5781c5763268cf1a3f5669c236d5eca8add98be91c893ed5b7"
    ),
    "assets/art/items/client/ground/101.png": (
        "097c77e68a10b71a23bdba45a6565dcfaeb3a20abf758e4d33902f8979fd5389"
    ),
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_crop(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    assert box is not None
    return image.crop(box)


def source_cell(sheet: Image.Image, slot: int) -> Image.Image:
    column = slot % 4
    row = slot // 4
    x0 = round(column * sheet.width / 4)
    x1 = round((column + 1) * sheet.width / 4)
    y0 = round(row * sheet.height / 2)
    y1 = round((row + 1) * sheet.height / 2)
    return sheet.crop((x0, y0, x1, y1))


def alpha_component_count(
    image: Image.Image, threshold: int = 8, minimum_pixels: int = 20
) -> int:
    alpha = image.getchannel("A")
    width, height = alpha.size
    pixels = alpha.load()
    seen = bytearray(width * height)
    component_count = 0
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if seen[index] or pixels[x, y] <= threshold:
                continue
            seen[index] = 1
            queue = [(x, y)]
            pixel_count = 0
            for current_x, current_y in queue:
                pixel_count += 1
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (
                        0 <= next_x < width and 0 <= next_y < height
                    ):
                        continue
                    next_index = next_y * width + next_x
                    if (
                        not seen[next_index]
                        and pixels[next_x, next_y] > threshold
                    ):
                        seen[next_index] = 1
                        queue.append((next_x, next_y))
            if pixel_count >= minimum_pixels:
                component_count += 1
    return component_count


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(
                ROOT
                / "tools/prepare_god_magic_helmet_236_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 236
    assert report["visualAssetId"] == "god_magic"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1384, 624]
    assert report["disconnectedComponentPolicy"] == (
        "preserve_all_alpha_components_in_each_direction_union_bounds"
    )

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "god_magic_236_helmet_8dir_user_20260729.png"
    ).convert("RGBA")
    assert source.size == (1448, 1086)
    assert source.getchannel("A").getextrema() == (0, 255)
    for slot, direction in enumerate(DIRECTIONS):
        expected = alpha_crop(source_cell(source, slot))
        output = Image.open(
            ROOT / report["directions"][direction]["path"]
        ).convert("RGBA")
        assert output.size == expected.size
        assert output.tobytes() == expected.tobytes(), direction
        assert alpha_component_count(output) == (
            EXPECTED_COMPONENT_COUNTS[direction]
        ), direction

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_god_magic_helmet_236_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
