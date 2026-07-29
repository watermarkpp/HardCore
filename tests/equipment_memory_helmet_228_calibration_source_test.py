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
FROZEN_RUNTIME_SHA256 = {
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_idle.png": (
        "05173ae4ad4dcfaaec72ab4bb728d364cbcc8b8189c5870e0af08bceb5588a9a"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_walk.png": (
        "99dbf26a32a8c39be2400dcc7920730de4025c5366bfb7b9bb53e3ff8884032c"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_attack.png": (
        "8b437f10416af84ca9ffde136227081ded37930f624be82816f440a024ec9e1a"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_cast.png": (
        "f3cf01031fdf5c8c5d9009d7f3ec0e2c8614e36a1a6414e6ef9d6c2d68ad28a9"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_hit.png": (
        "c2a3805259e6d7eee620ee09dd679c2a83de93274abee065925c8e6ed5eb9549"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "memory_helmet_death.png": (
        "ad0c21d9cfcf39d2a03f57a84f81bf520996bf5b76d9d0dfc8503374be81988d"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00228_head.png": (
        "7c05f80c3567f3f8a520ada3e37b92e112b2b6613b0ededd81ead17f1b321b57"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00228_erase_mask.png": (
        "25f2cbbfeb7d15fb614d71ef608f51967edba9b015eb2b18226a198b89390860"
    ),
    "assets/art/items/client/inventory/109.png": (
        "f6ad5fea1ee29c0def0d9b11a9ddea7bcf8151db1a5df5fcfd203eb471e125d4"
    ),
    "assets/art/items/client/ground/109.png": (
        "fdf1ec44f786b87b986d8bab8ed522bb4dccf6a91f536703dd70f7ab40de6114"
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


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(
                ROOT
                / "tools/prepare_memory_helmet_228_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 228
    assert report["visualAssetId"] == "memory"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1192, 834]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "memory_228_helmet_8dir_user_20260729.png"
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

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_memory_helmet_228_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
