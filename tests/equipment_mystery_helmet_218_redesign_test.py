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
    assert item["paperDoll"]["status"] == "user_final_helmet_calibration"
    assert item["paperDoll"]["sourceIndex"] == 218
    assert item["paperDoll"]["mappingConfidence"] == "user_approved_exact"
    assert tuple(item["paperDoll"]["size"]) == (20, 26)
    inventory = item["icons"]["inventory"]
    equipped = item["icons"]["equippedSlot"]
    ground = item["icons"]["ground"]
    assert inventory["sourceVariant"] == "dedicated_inventory"
    assert ground["sourceVariant"] == "direction"
    assert ground["sourceDirection"] == "E"
    assert tuple(inventory["size"]) == (27, 36)
    assert tuple(equipped["size"]) == (20, 26)
    assert tuple(ground["size"]) == (15, 18)
    for record in (inventory, equipped, ground):
        image = Image.open(disk_path(record["path"])).convert("RGBA")
        assert image.size == tuple(record["size"])
        assert image.getchannel("A").getbbox() is not None
        assert file_sha(disk_path(record["path"])) == record["fileSha256"]

    head_contract = load_json(
        "assets/data/equipment_classic_avatar_head_patches.json"
    )
    head = head_contract["itemsById"]["218"]["flattenedHeadPatch"]
    head_image = Image.open(disk_path(head["path"])).convert("RGBA")
    mask = Image.open(disk_path(head["eraseMaskPath"])).convert("RGBA")
    assert head["source"] == "user_final_helmet_calibration"
    assert tuple(head["size"]) == head_image.size == (20, 26)
    assert head["calibrationDraftSha256"] == (
        "8e347ccb67df29f18bd4511172fc29e9ce2e14e626c6db8ef404499f47472307"
    )
    assert head["singlePassDownsample"] is True
    assert head["sourceAspectPreserved"] is True
    assert head["subjectEvidence"]["sourceVariant"] == "direction"
    assert head["subjectEvidence"]["sourceDirection"] == "S"
    assert head["subjectEvidence"]["scalePercent"] == 50
    head_box = head_image.getchannel("A").getbbox()
    assert head_box is not None
    assert rgba_sha(head_image) == head["rgbaSha256"]
    assert rgba_sha(mask) == head["eraseMaskRgbaSha256"]
    assert list(head_image.getchannel("A").get_flattened_data()) == list(
        mask.getchannel("A").get_flattened_data()
    )

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
        diameter = cutouts[direction]["angleAwareHorizontalDiameter"]
        assert sizing["excludedAccessory"] == "crescent_maedate"
        assert sizing["accessoryExcludedFromScaleCalculation"] is True
        assert sizing["hornsExcludedFromScaleCalculation"] is False
        assert sizing["generatedBodySize"][1] == 18
        assert sizing["fullGeneratedSize"] == diameter[
            "preProjectionSize"
        ]
        assert diameter["postProjectionSize"] == cutouts[direction][
            "generatedSize"
        ]
        assert diameter["lateralDiameterPercent"] == 80.0
        assert diameter["depthDiameterPercent"] == 80.0
        assert diameter["projectedHorizontalPercent"] == 80.0
        assert diameter["integerPixelHorizontalPercent"] <= 80.0
        assert diameter["heightPercent"] == 100
        assert diameter["postProjectionSize"][1] == (
            diameter["preProjectionSize"][1]
        )

    assert world["itemsById"]["218"]["identityId"] == "mystery"
    print(
        "EQUIPMENT_MYSTERY_HELMET_218_REDESIGN_TEST_PASS "
        "directions=8 unique=8 final_draft=true single_pass=true "
        "paper=20x26 inventory=27x36 ground=15x18"
    )


if __name__ == "__main__":
    main()
