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
WORLD_ROW_BANDS = ((0, 450), (450, 900))
INVENTORY_REGION = (0, 900, 444, 1343)
FROZEN_RUNTIME_SHA256 = {
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_idle.png": (
        "b8d9658de50325291fded0e1c31f17a59d5fa3b23915332e0822b2f8aef0c741"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_walk.png": (
        "a7988e47368e6f3945c9730a145c26585be72e466491ab72f1fb0e255d27fe94"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_attack.png": (
        "942cde53d75cac1234d0797d8c57df7608b7fa65f2b9d21b06078a727d9b8f3e"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_cast.png": (
        "92f9ea8f9cd3c4095320cbc6b9e88ef2a54cee5152178d04cffbe5947f2f37ad"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_hit.png": (
        "0e6a714ea1fa51dcd82aaaf9ae1c85626c1fb511443fb3bfdbe1edc1c3aa7589"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "mystery_helmet_death.png": (
        "2228a5e8f21e8a650ecb431e125334d4646fcb9f339d8e630e70002f82d24ce4"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00218_head.png": (
        "95a76a98bacb9578d6921e64bb863ee6b13a66b4837e6918fae039a1cfa491f4"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00218_erase_mask.png": (
        "9d3d608b0ad92c37feb2527ab1974829a901d6b943998e9559ed05621a112b3c"
    ),
    "assets/art/items/client/inventory/111.png": (
        "8deb42b545d76cf9294c90c220bcd5e699c6412d5ecd3502cb9b3580b987baa5"
    ),
    "assets/art/items/client/ground/111.png": (
        "ec769c9facec28c468b1ced267fecb03ad877fa44e66a020bf5b80c70f850efc"
    ),
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_crop(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    assert box is not None
    return image.crop(box)


def world_cell(sheet: Image.Image, slot: int) -> Image.Image:
    column = slot % 4
    row = slot // 4
    x0 = round(column * sheet.width / 4)
    x1 = round((column + 1) * sheet.width / 4)
    y0, y1 = WORLD_ROW_BANDS[row]
    return sheet.crop((x0, y0, x1, y1))


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(
                ROOT
                / "tools/prepare_mystery_helmet_218_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 218
    assert report["visualAssetId"] == "mystery"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1248, 762]
    assert report["presentation"]["inventory"]["size"] == [281, 376]
    assert report["presentation"]["inventory"]["sourceDirection"] == "S"

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "mystery_218_helmet_9view_user_20260729.png"
    ).convert("RGBA")
    assert source.size == (1774, 1343)
    assert source.getchannel("A").getextrema() == (0, 255)
    for slot, direction in enumerate(DIRECTIONS):
        expected = alpha_crop(world_cell(source, slot))
        output = Image.open(
            ROOT / report["directions"][direction]["path"]
        ).convert("RGBA")
        assert output.size == expected.size
        assert output.tobytes() == expected.tobytes(), direction

    expected_inventory = alpha_crop(source.crop(INVENTORY_REGION))
    inventory_record = report["presentation"]["inventory"]
    inventory = Image.open(
        ROOT / inventory_record["path"]
    ).convert("RGBA")
    assert inventory.size == expected_inventory.size
    assert inventory.tobytes() == expected_inventory.tobytes()
    assert inventory.tobytes() != Image.open(
        ROOT / report["directions"]["S"]["path"]
    ).convert("RGBA").tobytes()

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_mystery_helmet_218_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
