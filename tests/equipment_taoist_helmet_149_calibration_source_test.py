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
WORLD_ROW_BANDS = ((0, 600), (600, 1100))
INVENTORY_REGION = (0, 1100, 338, 1637)
FROZEN_RUNTIME_SHA256 = {
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_idle.png": (
        "a479e6a4ff8ce028a47959c6e7b4677efb9c360ee2dc9ced6cb3c3930fb47f89"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_walk.png": (
        "4207bbc6bc0f4d79aabe756f1b79140f3030a697310cab2960212eefcc9c815b"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_attack.png": (
        "8190630956f72be2b9cee768aa9553cc787c91d4aa7322314f2c1154bfa189d0"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_cast.png": (
        "3016c204c37d84c36e7c3c5843ff182efaac06b564c26b5056ab0a4d6ef6fbea"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_hit.png": (
        "c20b884e659328c4cdb8fba252f713e9a7cf5d7d51beaaf74f73968501f36dae"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "taoist_helmet_death.png": (
        "4456892985df33ce4bc1094231df618bb982f569c94296ab8ea1a989bc629203"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00149_head.png": (
        "8ef7f4db379a9402bef829b56a6fe046946255adb08f6fe43821abce94e22bbe"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00149_erase_mask.png": (
        "d98445776704f2cde7361020148c8393dd28c1250d23e33e0ab2f3e18200cd91"
    ),
    "assets/art/items/client/inventory/106.png": (
        "d2567be1c34295302a744d082c07af8fb275a55b5506a56aa08b8bea8ba44d09"
    ),
    "assets/art/items/client/ground/106.png": (
        "fd271abb5b6cc753c894380f9408a7a3b80213ef65488ab01841626824a5ea0b"
    ),
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_crop(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    assert box is not None
    return image.crop(box)


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(
                ROOT
                / "tools/prepare_taoist_helmet_149_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 149
    assert report["visualAssetId"] == "taoist"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1044, 802]
    assert report["presentation"]["inventory"]["size"] == [232, 378]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "taoist_149_helmet_9view_user_20260728.png"
    ).convert("RGBA")
    assert source.size == (1350, 1637)
    assert source.getchannel("A").getextrema() == (0, 255)
    for slot, direction in enumerate(DIRECTIONS):
        column = slot % 4
        row = slot // 4
        x0 = round(column * source.width / 4)
        x1 = round((column + 1) * source.width / 4)
        y0, y1 = WORLD_ROW_BANDS[row]
        expected = alpha_crop(source.crop((x0, y0, x1, y1)))
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

    target = json.loads(
        (
            ROOT / "assets/data/helmet_calibration_active_target.json"
        ).read_text(encoding="utf-8")
    )
    assert target["itemId"] == 149
    assert target["visualAssetId"] == "taoist"
    assert target["sourceDirectionOrder"] == list(DIRECTIONS)
    assert target["initializeSessionDirectionMapping"] is True
    assert set(target["preparedDirectionFiles"]) == set(DIRECTIONS)
    for direction in DIRECTIONS:
        path = ROOT / target["preparedDirectionFiles"][direction][6:]
        assert file_sha256(path) == target["preparedDirectionSha256"][direction]
    inventory_path = (
        ROOT / target["preparedPresentationFiles"]["inventory"][6:]
    )
    assert file_sha256(inventory_path) == (
        target["preparedPresentationSha256"]["inventory"]
    )
    assert target["provenance"]["derivation"] == (
        "alpha_bounds_crop_only_no_matte_removal_no_face_window_edit_no_resample"
    )

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_taoist_helmet_149_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
