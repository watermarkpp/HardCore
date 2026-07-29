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
    "heavenly_taoist_helmet_idle.png": (
        "cd5c255f226343f2d4bb6119ff33bdbc89d1b0817ddcf3013f2dfd5353ab43b3"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "heavenly_taoist_helmet_walk.png": (
        "e1030c5a53ae4066d96226401f11f498a8c422e20c1129aa979b7b58ff5d8487"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "heavenly_taoist_helmet_attack.png": (
        "b5a32c5c24b5d1d8b50949f80f806862357428ea41333e9652c221a2466484b6"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "heavenly_taoist_helmet_cast.png": (
        "8658d90f240857c038832d272872f3b61c8dc52772d2f05fb7838e77e57f8c16"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "heavenly_taoist_helmet_hit.png": (
        "7adaa6f5e533b9cad97efea643385ad9edbf11e03c35737917d30b75f42be6bb"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "heavenly_taoist_helmet_death.png": (
        "1b33c0ff195d78ee05cb2044dbdf87941045ec4958ead1d55f4ba0a9add492c7"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00240_head.png": (
        "bda1b588d5aeaf6a61085c65040e46ac5f0351b44be073e55e32083d298c3ce0"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00240_erase_mask.png": (
        "50ddb61ae3de07ed0dff387bc8b062b87be569bf74a7816cab52163c0d4a70e2"
    ),
    "assets/art/items/client/project_redesign/helmet/heavenly_taoist/"
    "item_00240_inventory.png": (
        "748996fde82303b911acf650e254d16d8d79d7da42ab8a1d94dda82e6fbe4a4c"
    ),
    "assets/art/items/client/project_redesign/helmet/heavenly_taoist/"
    "item_00240_ground.png": (
        "332915019c4173e2a48f9d9c1837be003253b62964396234fc1a3b7574f23da0"
    ),
    "assets/art/items/client/inventory/102.png": (
        "74a4d65967a9a164019eaef64c33fe0c1d20501ccca1db6c992927677ee2bf88"
    ),
    "assets/art/items/client/ground/102.png": (
        "2821736341680ffe2ae952cb037d8ae844c31219957731342f68e60ae0b01f07"
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
    y0 = round(row * sheet.height / 3)
    y1 = round((row + 1) * sheet.height / 3)
    return sheet.crop((x0, y0, x1, y1))


def main() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(
                ROOT
                / "tools/"
                "prepare_heavenly_taoist_helmet_240_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 240
    assert report["visualAssetId"] == "heavenly_taoist"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [956, 722]

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "heavenly_taoist_240_helmet_10view_user_20260729.png"
    ).convert("RGBA")
    assert source.size == (1774, 1333)
    assert source.getchannel("A").getextrema() == (0, 255)
    for slot, direction in enumerate(DIRECTIONS):
        expected = alpha_crop(source_cell(source, slot))
        output = Image.open(
            ROOT / report["directions"][direction]["path"]
        ).convert("RGBA")
        assert output.size == expected.size
        assert output.tobytes() == expected.tobytes(), direction

    expected_inventory = alpha_crop(source_cell(source, 8))
    expected_ground = alpha_crop(source_cell(source, 9))
    inventory = Image.open(
        ROOT / report["presentation"]["inventory"]["path"]
    ).convert("RGBA")
    ground = Image.open(
        ROOT / report["presentation"]["ground"]["path"]
    ).convert("RGBA")
    assert inventory.size == (208, 354)
    assert ground.size == (214, 356)
    assert inventory.tobytes() == expected_inventory.tobytes()
    assert ground.tobytes() == expected_ground.tobytes()
    assert report["presentation"]["inventory"]["sourceSlot"] == 8
    assert report["presentation"]["ground"]["sourceSlot"] == 9
    assert source_cell(source, 10).getchannel("A").getbbox() is None
    assert source_cell(source, 11).getchannel("A").getbbox() is None

    target = json.loads(
        (
            ROOT / "assets/data/helmet_calibration_active_target.json"
        ).read_text(encoding="utf-8")
    )
    assert target["itemId"] == 240
    assert target["visualAssetId"] == "heavenly_taoist"
    assert target["displayName"] == "天尊头盔"
    assert target["sourceDirectionOrder"] == list(DIRECTIONS)
    assert target["initializeSessionDirectionMapping"] is True
    assert set(target["preparedDirectionFiles"]) == set(DIRECTIONS)
    assert set(target["preparedPresentationFiles"]) == {
        "inventory", "ground",
    }
    assert set(target["preparedPresentationSha256"]) == {
        "inventory", "ground",
    }
    for direction in DIRECTIONS:
        path = ROOT / target["preparedDirectionFiles"][direction][6:]
        assert file_sha256(path) == target["preparedDirectionSha256"][direction]
    for role in ("inventory", "ground"):
        path = ROOT / target["preparedPresentationFiles"][role][6:]
        assert file_sha256(path) == (
            target["preparedPresentationSha256"][role]
        )
    assert target["provenance"]["derivation"] == (
        "world_slots_0_to_7_inventory_slot_8_ground_slot_9_alpha_bounds_crop_"
        "only_no_matte_removal_no_face_window_edit_no_resample"
    )

    for relative, expected in FROZEN_RUNTIME_SHA256.items():
        assert file_sha256(ROOT / relative) == expected, relative
    print("equipment_heavenly_taoist_helmet_240_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
