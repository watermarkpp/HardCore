#!/usr/bin/env python3
"""Focused regression checks for the user-approved item 232 redesign."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APPROVED = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "holy_war_helmet_approved_20260727.png"
)
PROCESSED = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "holy_war_helmet_8dir.png"
)
WORLD = ROOT / "assets/data/equipment_male_world_helmet.json"
RECIPE = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
HELMET_V2 = ROOT / "assets/data/equipment_helmet_visual_v2.json"
HEAD = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00232_head.png"
)
ERASE = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00232_erase_mask.png"
)
INVENTORY = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/holy_war"
    / "item_00232_inventory.png"
)
GROUND = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/holy_war"
    / "item_00232_ground.png"
)
REPORT = ROOT / "outputs/helmet_232/holy_war_232_validation_report.json"
WORN_PREVIEW_1X = ROOT / "outputs/helmet_232/holy_war_232_worn_idle_8dir_1x.png"
WORN_PREVIEW_8X = ROOT / "outputs/helmet_232/holy_war_232_worn_idle_8dir_8x.png"
BUILDER = ROOT / "tools/build_holy_war_helmet_232.py"
EXPECTED_APPROVED_SHA = (
    "93307c79e0d5d697d269eec3ba2c318385be96130026e1dbe1b67779437b583b"
)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
WORLD_HEIGHT = {
    "N": 23,
    "NE": 21,
    "E": 20,
    "SE": 22,
    "S": 23,
    "SW": 22,
    "W": 22,
    "NW": 23,
}
HORIZONTAL_DIAMETER_SCALE = 0.8
FROZEN_SOURCE_MAP = {
    "N": 0,
    "NE": 7,
    "E": 3,
    "SE": 6,
    "S": 4,
    "SW": 5,
    "W": 2,
    "NW": 1,
}
SOURCE_VARIANT_HEIGHT = {
    DIRECTIONS[source_row]: WORLD_HEIGHT[target_direction]
    for target_direction, source_row in FROZEN_SOURCE_MAP.items()
}
PREVIOUS_TARGET_BBOX_SIZE = {
    "N": [21, 23],
    "NE": [16, 21],
    "E": [15, 20],
    "SE": [17, 22],
    "S": [19, 23],
    "SW": [16, 22],
    "W": [15, 22],
    "NW": [17, 23],
}
EXPECTED_TARGET_BBOX_SIZE = {
    direction: [
        round(PREVIOUS_TARGET_BBOX_SIZE[direction][0] * 0.8),
        PREVIOUS_TARGET_BBOX_SIZE[direction][1],
    ]
    for direction in DIRECTIONS
}
SOURCE_VARIANT_SIZE = {
    DIRECTIONS[source_row]: EXPECTED_TARGET_BBOX_SIZE[target_direction]
    for target_direction, source_row in FROZEN_SOURCE_MAP.items()
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    assert sha256(APPROVED) == EXPECTED_APPROVED_SHA
    recipe = load_json(RECIPE)
    identity_recipe = next(
        value
        for value in recipe["identities"]
        if value["identityId"] == "holy_war"
    )
    assert identity_recipe["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity_recipe["canonicalRowSourceSlots"] == list(range(8))
    assert identity_recipe["approvedSourceFileSha256"] == EXPECTED_APPROVED_SHA
    assert set(identity_recipe["faceAperturePolicy"].values()) == {"closed"}
    assert set(identity_recipe["faceApertureShape"].values()) == {"none"}
    assert identity_recipe["paperDollFaceWindow"] == "none_opaque_black_mask"
    assert identity_recipe["paperDollEraseMask"] == "no_cutout_all_transparent"

    processed = Image.open(PROCESSED).convert("RGBA")
    assert processed.size == (1536, 1024)
    signatures = []
    for slot in range(8):
        x = slot % 4
        y = slot // 4
        cell = processed.crop((x * 384, y * 512, (x + 1) * 384, (y + 1) * 512))
        signatures.append(hashlib.sha256(cell.tobytes()).hexdigest())
    assert len(set(signatures)) == 8
    assert not any(
        green >= 245 and red <= 12 and blue <= 12 and alpha > 0
        for red, green, blue, alpha in processed.get_flattened_data()
    )

    world = load_json(WORLD)
    identity = world["visualIdentities"]["holy_war"]
    assert identity["approvedSourceFileSha256"] == EXPECTED_APPROVED_SHA
    assert identity["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity["canonicalRowSourceSlots"] == list(range(8))
    assert set(identity["faceAperturePolicy"].values()) == {"closed"}
    assert set(identity["faceApertureShape"].values()) == {"none"}
    assert all(
        identity["directionCutouts"][direction]["runtimeScale"] == 1
        for direction in DIRECTIONS
    )
    assert identity["sourceBakePolicy"] == "approved_high_res_single_pass"
    assert identity["horizontalDiameterScale"] == HORIZONTAL_DIAMETER_SCALE
    assert identity["offlineDownsampleFilter"] == "premultiplied_alpha_lanczos"
    assert identity["worldDirectionHeights"] == WORLD_HEIGHT
    assert identity["sourceRowDirectionHeights"] == SOURCE_VARIANT_HEIGHT
    assert identity["sourceRowDirectionSizes"] == SOURCE_VARIANT_SIZE
    for direction in DIRECTIONS:
        cutout = identity["directionCutouts"][direction]
        assert cutout["generatedSize"] == SOURCE_VARIANT_SIZE[direction]
        assert cutout["resizeFilter"] == (
            "premultiplied_alpha_lanczos_high_res_single_pass"
        )
        assert cutout["horizontalDiameterScale"] == HORIZONTAL_DIAMETER_SCALE

    erase = Image.open(ERASE).convert("RGBA")
    assert erase.getchannel("A").getbbox() is None
    paper = Image.open(HEAD).convert("RGBA")
    paper_box = paper.getchannel("A").getbbox()
    assert paper.size == (32, 41)
    assert paper_box is not None
    assert paper_box[3] - paper_box[1] == 29
    assert paper_box[2] - paper_box[0] <= 20
    inventory = Image.open(INVENTORY).convert("RGBA")
    ground = Image.open(GROUND).convert("RGBA")
    assert paper.getpixel((16, 28))[3] == 255
    assert inventory.getpixel((18, 24))[3] == 255
    assert ground.getpixel((8, 12))[3] == 255

    v2 = load_json(HELMET_V2)["visualAssets"]["holy_war"]
    assert v2["source_direction_map"] == FROZEN_SOURCE_MAP
    for direction, source_row in FROZEN_SOURCE_MAP.items():
        assert v2["directions"][direction]["source_row"] == source_row
        assert v2["directions"][direction]["runtime_scale"] == [1, 1]
    for action_name, action in identity["actions"].items():
        assert v2["source"]["actions"][action_name]["sha256"] == action["fileSha256"]

    report = load_json(REPORT)
    assert report["sourceSlotDirectionOrder"] == DIRECTIONS
    assert report["canonicalRowSourceSlots"] == list(range(8))
    assert report["wearableFaceWindowTransparent"] is False
    assert report["paperDollFaceWindowTransparent"] is False
    assert report["paperDollEraseMaskAllTransparent"] is True
    assert report["inventoryFaceWindowOpaque"] is True
    assert report["groundFaceWindowOpaque"] is True
    assert report["frozenNon232FilesUnchanged"] is True
    assert report["non232ContractDataUnchanged"] is True
    assert report["generatedHelmetV2FilesUnchanged"] is True
    assert report["helmetV2OverridesUnchanged"] is True
    assert report["sourceBakePolicy"] == "approved_high_res_single_pass"
    assert report["horizontalDiameterScale"] == HORIZONTAL_DIAMETER_SCALE
    assert report["worldSizingAudit"]["bakePolicy"] == (
        "approved_high_res_single_pass"
    )
    assert report["worldSizingAudit"]["horizontalDiameterScale"] == (
        HORIZONTAL_DIAMETER_SCALE
    )
    assert report["worldSizingAudit"]["heightsUnchanged"] is True
    assert report["worldSizingAudit"]["worldDirectionHeights"] == WORLD_HEIGHT
    assert report["worldSizingAudit"]["paperDollContentSize"][1] == 29
    assert report["worldSizingAudit"]["paperDollContentSize"][0] <= 20
    audit = report["acceptedHelmetPixelParameterAudit"]
    assert audit["referenceItemIds"] == [146, 147, 149, 151]
    assert audit["hornedReferenceItemId"] == 150
    assert set(audit["items"]) == {"146", "147", "149", "150", "151", "232"}
    assert audit["targetBodyCoreWidthRange"][1] <= (
        audit["acceptedBodyCoreWidthRange"][1]
        + audit["armoredShellDecorationAllowancePx"]
    )
    for record in audit["items"]["232"]["directionMetrics"].values():
        assert record["transparentRgbLeakPixels"] == 0
        assert record["totalBboxSize"][1] > 0
        assert record["bodyCoreWidth"] > 0
    for direction, record in audit["targetSemanticOldToNewBbox"].items():
        assert record["previousTargetSemanticBboxSize"] == (
            PREVIOUS_TARGET_BBOX_SIZE[direction]
        )
        assert record["actualTargetSemanticBboxSize"][1] == WORLD_HEIGHT[direction]
        assert record["actualTargetSemanticBboxSize"] == (
            EXPECTED_TARGET_BBOX_SIZE[direction]
        )
        assert abs(record["actualWidthRatio"] - 0.8) <= 0.08
        assert record["sourceRow"] == FROZEN_SOURCE_MAP[direction]
    assert WORN_PREVIEW_1X.exists()
    assert WORN_PREVIEW_8X.exists()
    assert all(
        record["allOpaque"] is True
        and all(alpha == 255 for alpha in record["alpha"])
        for record in report["opaqueFaceMaskRoiEvidence"].values()
    )
    assert all(
        record["clear"] is True and record["opaquePixels"] == 0
        for record in report["furClearanceRoiEvidence"].values()
    )

    rejected = subprocess.run(
        [sys.executable, str(BUILDER), "--identity", "black_iron"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert rejected.returncode != 0
    assert "only 'holy_war' is legal" in rejected.stderr
    print(
        "EQUIPMENT_HOLY_WAR_HELMET_232_TEST_PASS "
        "source_sha=true directions=8 no_cutout=true "
        "high_res_single_pass=true horizontal_diameter=0.8 "
        "paper_inventory_ground_opaque=true non232_guard=true"
    )


if __name__ == "__main__":
    main()
