#!/usr/bin/env python3
"""Validate the user-authorized four-mode item 218 redesign."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def main() -> None:
    catalog = load_json("assets/data/equipment_visual_catalog.json")
    item = catalog["itemsById"]["218"]
    assert item["itemName"] == "神秘头盔"
    assert item["paperDoll"]["status"] == "user_authorized_redesign"
    assert item["paperDoll"]["designIdentity"] == (
        "mystery_japanese_kabuto_218"
    )

    expected_sizes = {
        "inventory": (40, 40),
        "equippedSlot": (48, 48),
        "ground": (18, 18),
    }
    source_roles = {
        "inventory": "backpack_inventory",
        "equippedSlot": "paper_doll_equipped",
        "ground": "ground_drop",
    }
    for role, record in item["icons"].items():
        image_path = disk_path(record["path"])
        source_path = disk_path(record["sourcePath"])
        image = Image.open(image_path).convert("RGBA")
        assert image.size == expected_sizes[role]
        assert image.getchannel("A").getbbox() is not None
        assert tuple(record["size"]) == image.size
        assert record["library"] == "user_authorized_redesign"
        assert record["sourceRole"] == source_roles[role]
        assert record["designIdentity"] == "mystery_japanese_kabuto_218"
        assert file_sha(source_path) == record["sourceFileSha256"]

    head_contract = load_json(
        "assets/data/equipment_classic_avatar_head_patches.json"
    )
    head = head_contract["itemsById"]["218"]["flattenedHeadPatch"]
    head_image = Image.open(disk_path(head["path"])).convert("RGBA")
    mask = Image.open(disk_path(head["eraseMaskPath"])).convert("RGBA")
    assert head["source"] == "user_authorized_redesign"
    assert tuple(head["size"]) == head_image.size == (48, 48)
    assert rgba_sha(head_image) == head["rgbaSha256"]
    assert rgba_sha(mask) == head["eraseMaskRgbaSha256"]
    assert [
        255 if alpha > 0 else 0
        for alpha in head_image.getchannel("A").get_flattened_data()
    ] == list(mask.getchannel("A").get_flattened_data())

    world = load_json("assets/data/equipment_male_world_helmet.json")
    identity = world["visualIdentities"]["mystery"]
    assert identity["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity["canonicalRowSourceSlots"] == list(range(8))
    assert identity["calibrationSourceMatte"] == (
        "transparent_user_authorized_redesign_despill_v1"
    )
    assert file_sha(disk_path(identity["calibrationSourceSheet"])) == (
        identity["calibrationSourceSheetSha256"]
    )
    cutouts = identity["directionCutouts"]
    assert len({cutouts[d]["sourceCutoutRgbaSha256"] for d in DIRECTIONS}) == 8
    for direction in DIRECTIONS:
        sizing = cutouts[direction]["bodyDrivenSizing"]
        assert sizing["excludedAccessory"] == "crescent_maedate"
        assert sizing["accessoryExcludedFromScaleCalculation"] is True
        assert sizing["hornsExcludedFromScaleCalculation"] is False
        assert sizing["generatedBodySize"][1] == 18
        assert sizing["fullGeneratedSize"] == cutouts[direction][
            "generatedSize"
        ]

    assert world["itemsById"]["218"]["identityId"] == "mystery"
    print(
        "EQUIPMENT_MYSTERY_HELMET_218_REDESIGN_TEST_PASS "
        "directions=8 unique=8 world_body_height=18 "
        "paper=48x48 inventory=40x40 ground=18x18"
    )


if __name__ == "__main__":
    main()
