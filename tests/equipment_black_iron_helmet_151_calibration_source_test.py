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
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_idle.png": (
        "8a78c841d88b47946ef6f559f731cbbe9c08313e11c7ef48e5457d12d839e052"
    ),
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_walk.png": (
        "8b32472b1dd8ebe2723b34cb1fd2d5d73d151891c7372dfc4f93a4f5d3ceb4a6"
    ),
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_attack.png": (
        "427855f0a799fd8cc442071255861e6a22456532facb3801e9774c4236f069ca"
    ),
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_cast.png": (
        "92fc7557bad923e567183c7ae6590a2066e4a42389367ff21142e248b0a588f4"
    ),
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_hit.png": (
        "605d12ebd303bbc9be5ee3da645145ad53f9077d28e0fff83ac5d95970575cf7"
    ),
    "assets/art/characters/warrior/wear/helmet/"
    "black_iron_helmet_death.png": (
        "f99492398eadb01b1b7e50f1f7c5bb347b42994054a165e3318922fd5599beec"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00151_head.png": (
        "804ad4e1864bf6987d61e176f3a435ce58832c81b9522999853f0153f91ffd17"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00151_erase_mask.png": (
        "4c5a74b5e23d43667184544fee830041eb319e4b488299cf7d81fd3f47c844e4"
    ),
    "assets/art/items/client/inventory/344.png": (
        "038d79137e1dd99177054604fc781b084992a3fd7f087cd080641305cd52abaa"
    ),
    "assets/art/items/client/ground/344.png": (
        "806faa549083dac5c7a9722e4c6a31c1872d41b533655b1c3a29f9290b21f5c7"
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
                / "tools/prepare_black_iron_helmet_151_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 151
    assert report["visualAssetId"] == "black_iron_golden_151"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1176, 786]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "black_iron_151_helmet_8dir_user_20260729.png"
    ).convert("RGBA")
    assert source.size == (1491, 1055)
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
    print("equipment_black_iron_helmet_151_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
