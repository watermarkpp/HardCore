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
WORLD_ROW_BANDS = ((0, 520), (520, 1050))
INVENTORY_REGION = (0, 1050, 362, 1640)
FROZEN_RUNTIME_SHA256 = {
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_idle.png": (
        "18aab75a74b57b6cf87500f13f07548a3a3bec6e05a337f1a0c72eb0b09aafa4"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_walk.png": (
        "1567249f8de1066e683ef007d3148a014021b7cf35687edd0ccab27d4ff1891b"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_attack.png": (
        "e7390493dc9b6830a9d876d7d05fdac362e362fab41af0e3e01b8f0cbbba4421"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_cast.png": (
        "bb44e65f62f699b58b8a3621582d137138f4b3cde970fefe9edbc6df7be3f741"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_hit.png": (
        "985eaf3f1308646deac11d2a06ea638f37739b97ecf79f3aedfacda857dc4b10"
    ),
    "assets/art/items/client/world_wear/helmet/male/"
    "prayer_helmet_death.png": (
        "4f8d34ddadb47b60b7c176e32e208bbb9267b9eca49c7f0419f597ffa7de9af6"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00224_head.png": (
        "7935787422e178a99cabf5c7c61016514542eec511ff85bc3e6221638b70624c"
    ),
    "assets/art/items/client/paper_doll/classic_flattened_head/"
    "item_00224_erase_mask.png": (
        "5cdca959c1c3c41dcc4b8b090c97ad19409219bed8a9132a11d32e84a6dc0bfb"
    ),
    "assets/art/items/client/inventory/110.png": (
        "54f2bbd0537d7b3c590953ca65f666fc7a7987f9c258058e9fa858dad80e485a"
    ),
    "assets/art/items/client/ground/110.png": (
        "94da20509c2e1ef8fb57d00bd47d18efe5b016398e1d448aa3664bb27ebd0531"
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
                / "tools/prepare_prayer_helmet_224_calibration_source.py"
            ),
            "--check",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(result.stdout)
    assert report["itemId"] == 224
    assert report["visualAssetId"] == "prayer"
    assert report["directionOrder"] == list(DIRECTIONS)
    assert report["sourceAlphaPolicy"] == (
        "user_authored_alpha_preserved_no_matte_removal"
    )
    assert report["transparentWorldSheet"]["size"] == [1148, 822]
    assert report["presentation"]["inventory"]["size"] == [274, 411]
    assert report["presentation"]["inventory"]["sourceDirection"] == "S"

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source/"
        "prayer_224_helmet_9view_user_20260729.png"
    ).convert("RGBA")
    assert source.size == (1448, 1640)
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

    target = json.loads(
        (
            ROOT / "assets/data/helmet_calibration_active_target.json"
        ).read_text(encoding="utf-8")
    )
    assert target["itemId"] == 224
    assert target["visualAssetId"] == "prayer"
    assert target["displayName"] == "祈祷头盔"
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
    print("equipment_prayer_helmet_224_calibration_source_test: PASS")


if __name__ == "__main__":
    main()
