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
    "holy_war_helmet_idle.png": (
        "3379be9725838e8f9965f93074ccf1e66916459f65fc79e836e157ae2d342355"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "holy_war_helmet_walk.png": (
        "575899c1dcc036ea54717707dbc36862a3a36b9a21d3c2c40b4781f7f0106ffb"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "holy_war_helmet_attack.png": (
        "0e079079c04fc8e0aa9c4b965a7ce8a506cd459e2b0b998aa9eab303bc77c314"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "holy_war_helmet_cast.png": (
        "6b4011b209ec50f00cb3a638f4c1688a35d636ff4054b0cbeb6d34e656af575d"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "holy_war_helmet_hit.png": (
        "6be7a53491e623a856eab1f4858ce83fec79f797473dcfbdee0c31171349af13"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "holy_war_helmet_death.png": (
        "2e3b471eb80b92869babd9ce9663d3cfa2763ae9d82ce02beedbecea69d1cc74"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00232_head.png": (
        "3e24c0231e8c1de5d60eeb7a2464d28eba0c9ff9268965ef350ac6bc74b59b9d"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00232_erase_mask.png": (
        "61412e7c269c1c85399dea214740e972e3f0352179cbe2746711d945c38ecac6"
    ),
    "assets/art/items/client/project_redesign/helmet/holy_war/"
    "item_00232_inventory.png": (
        "bdf5bc691c85a9e79baca8dd6814766bd9a0d65ef3e1d951664f34e04efb8662"
    ),
    "assets/art/items/client/project_redesign/helmet/holy_war/"
    "item_00232_ground.png": (
        "3f0a88664a3d129ef85e91c7c9dbf1b8935b017c31412c1fb3ff271cfd4d42dd"
    ),
    "assets/art/items/client/inventory/104.png": (
        "c5df71af0b508d51c2dfaea0c8b57bd34b64ae222e20756fe83165746e138844"
    ),
    "assets/art/items/client/ground/104.png": (
        "8abdb045ea9d088055ffa70a0da993aaef0b86ddd31ea5a08fa6f4a492e4057c"
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
                / "tools/prepare_holy_war_helmet_232_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 232
    assert report["visualAssetId"] == "holy_war"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1264, 810]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "holy_war_232_helmet_8dir_user_20260729.png"
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
    print("equipment_holy_war_helmet_232_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
