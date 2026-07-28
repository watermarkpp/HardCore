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
    "skeleton_helmet_idle.png": (
        "f7c7e59ff4757e915997225778b7933142d26976c455292748ca0cd27c891fbe"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "skeleton_helmet_walk.png": (
        "373af3c58dfdab4f9dc615b151ea65887f5df214af21c6fe708b1f96e8f73ca3"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "skeleton_helmet_attack.png": (
        "d0976052d548a6adc7a47f3f6b4a37d0ead0875c9b22dd5e71f8a28664556be9"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "skeleton_helmet_cast.png": (
        "21058ba7b06b2bfb0e4b7f5b401403aa65f00210135c181a5d6d13429c14f7cd"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "skeleton_helmet_hit.png": (
        "ca0974187389c9cf3ca7948aaba75a0f35ae14c5c8ca024e2e13d9da63767a10"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "skeleton_helmet_death.png": (
        "a0a7b46d964f2fcdf82ae7c02c40ccc5bf5e8db05876f0e085b70d4782cfa4a7"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00150_head.png": (
        "216bab487f4051dda8726b271aed97fcb945eafdf78e739bd66deadfdeacbf6d"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00150_erase_mask.png": (
        "2064f40192c3e0d124c0a293c07d91c30f743fa4f4ebbd5257c06e89cae4d4e4"
    ),
    "assets/art/items/client/inventory/103.png": (
        "7610e928336c751a1fc45b89c141680c164e9913354baa7cc526ebb6ee51a05f"
    ),
    "assets/art/items/client/ground/103.png": (
        "bde2a7a589ca9d3a445ac186bb999cc61bb7b5d2d3b35bedaf46b470dd486ff0"
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
                / "tools/prepare_skeleton_helmet_150_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 150
    assert report["visualAssetId"] == "skeleton"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1456, 862]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "skeleton_150_helmet_8dir_user_20260728.png"
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

    target = json.loads(
        (
            ROOT / "assets/data/helmet_calibration_active_target.json"
        ).read_text(encoding="utf-8")
    )
    assert target["itemId"] == 150
    assert target["visualAssetId"] == "skeleton"
    assert target["displayName"] == "骷髅头盔"
    assert target["sourceDirectionOrder"] == list(DIRECTIONS)
    assert target["initializeSessionDirectionMapping"] is True
    assert target["preparedPresentationFiles"] == {}
    assert set(target["preparedDirectionFiles"]) == set(DIRECTIONS)
    for direction in DIRECTIONS:
        path = ROOT / target["preparedDirectionFiles"][direction][6:]
        assert file_sha256(path) == target["preparedDirectionSha256"][direction]
    assert target["provenance"]["derivation"] == (
        "alpha_bounds_crop_only_no_matte_removal_no_hollowing_edit_no_resample"
    )

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_skeleton_helmet_150_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
