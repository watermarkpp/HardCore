#!/usr/bin/env python3
"""Focused regression checks for the user-supplied item 240 replacement."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ENVELOPES = {
    "N": [13, 16],
    "NE": [18, 18],
    "E": [15, 20],
    "SE": [16, 23],
    "S": [14, 21],
    "SW": [16, 23],
    "W": [16, 20],
    "NW": [16, 17],
}
EXPECTED_SHA = "a5e474da3c081ad2f5dd0926bd9dd1358e4179737e6b8d5614a77cf7b2ba9e8e"
APPROVED = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_helmet_approved_20260727.png"
)
PROCESSED = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "heavenly_taoist_helmet_8dir.png"
)
WORLD = ROOT / "assets/data/equipment_male_world_helmet.json"
RECIPE = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
V2 = ROOT / "assets/data/equipment_helmet_visual_v2.json"
HEAD_CONTRACT = ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
HEAD = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00240_head.png"
)
ERASE = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00240_erase_mask.png"
)
INVENTORY = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/heavenly_taoist"
    / "item_00240_inventory.png"
)
GROUND = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/heavenly_taoist"
    / "item_00240_ground.png"
)
BUILDER = ROOT / "tools/build_heavenly_taoist_helmet_240.py"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    assert sha256(APPROVED) == EXPECTED_SHA
    recipe = next(
        value
        for value in load_json(RECIPE)["identities"]
        if value["identityId"] == "heavenly_taoist"
    )
    assert recipe["sourceSlotDirectionOrder"] == DIRECTIONS
    assert recipe["canonicalRowSourceSlots"] == list(range(8))
    assert recipe["approvedSourceFileSha256"] == EXPECTED_SHA
    assert recipe["worldDirectionEnvelopes"] == ENVELOPES
    assert recipe["singlePassDownsampleFromApprovedSource"] is True
    assert recipe["runtimeScale"] == 1
    assert recipe["textureFilter"] == "nearest"

    processed = Image.open(PROCESSED).convert("RGBA")
    assert processed.size == (1448, 1086)
    assert not any(
        red >= 120
        and blue >= 120
        and min(red, blue) >= green + 35
        and abs(red - blue) <= 105
        and alpha > 0
        for red, green, blue, alpha in processed.get_flattened_data()
    )

    world = load_json(WORLD)
    identity = world["visualIdentities"]["heavenly_taoist"]
    assert identity["approvedSourceFileSha256"] == EXPECTED_SHA
    assert identity["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity["canonicalRowSourceSlots"] == list(range(8))
    assert identity["worldDirectionEnvelopes"] == ENVELOPES
    assert identity["faceAperturePolicy"]["S"] == "open_crown"
    assert identity["faceAperturePolicy"]["N"] == "closed"
    for direction in DIRECTIONS:
        size = identity["directionCutouts"][direction]["generatedSize"]
        assert size[0] <= ENVELOPES[direction][0]
        assert size[1] <= ENVELOPES[direction][1]
        assert identity["directionCutouts"][direction]["runtimeScale"] == 1
    for action, frame_count in {
        "idle": 4,
        "walk": 6,
        "attack": 6,
        "cast": 6,
        "hit": 3,
        "death": 4,
    }.items():
        record = identity["actions"][action]
        atlas = Image.open(ROOT / record["path"].removeprefix("res://"))
        assert atlas.size == (192 * frame_count, 160 * 8)
        assert sha256(ROOT / record["path"].removeprefix("res://")) == record["fileSha256"]

    head = load_json(HEAD_CONTRACT)["itemsById"]["240"]["flattenedHeadPatch"]
    assert head["source"] == "user_final_helmet_calibration"
    assert head["calibrationDraftSha256"] == (
        "e114ad10fc5ac48492cb932828200712f1aa2de0717436426a7f4b9639beaf70"
    )
    assert head["singlePassDownsample"] is True
    assert head["sourceAspectPreserved"] is True
    assert head["subjectEvidence"]["sourceVariant"] == "direction"
    assert head["subjectEvidence"]["sourceDirection"] == "S"
    assert head["subjectEvidence"]["scalePercent"] == 65
    paper = Image.open(
        ROOT / head["path"].removeprefix("res://")
    ).convert("RGBA")
    erase = Image.open(
        ROOT / head["eraseMaskPath"].removeprefix("res://")
    ).convert("RGBA")
    assert paper.size == tuple(head["size"]) == (18, 29)
    assert paper.getchannel("A").getbbox() is not None
    assert erase.getchannel("A").getbbox() is not None
    assert sha256(ROOT / head["path"].removeprefix("res://")) == head["fileSha256"]
    assert sha256(ROOT / head["eraseMaskPath"].removeprefix("res://")) == (
        head["eraseMaskFileSha256"]
    )

    catalog = load_json(CATALOG)["itemsById"]["240"]
    inventory_record = catalog["icons"]["inventory"]
    ground_record = catalog["icons"]["ground"]
    assert inventory_record["sourceVariant"] == "dedicated_inventory"
    assert ground_record["sourceVariant"] == "dedicated_ground"
    inventory = Image.open(
        ROOT / inventory_record["path"].removeprefix("res://")
    ).convert("RGBA")
    ground = Image.open(
        ROOT / ground_record["path"].removeprefix("res://")
    ).convert("RGBA")
    assert inventory.size == tuple(inventory_record["size"]) == (21, 36)
    assert ground.size == tuple(ground_record["size"]) == (11, 18)
    assert inventory.getchannel("A").getbbox() is not None
    assert ground.getchannel("A").getbbox() is not None

    v2 = load_json(V2)["visualAssets"]["heavenly_taoist"]
    expected_map = {direction: index for index, direction in enumerate(DIRECTIONS)}
    assert v2["source_direction_map"] == expected_map
    assert v2["source"]["sourceSlotDirectionOrder"] == DIRECTIONS
    for action in identity["actions"]:
        assert (
            v2["source"]["actions"][action]["sha256"]
            == identity["actions"][action]["fileSha256"]
        )

    rejected = subprocess.run(
        [sys.executable, str(BUILDER), "--identity", "god_magic"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert rejected.returncode != 0
    assert "accepts only 'heavenly_taoist'" in rejected.stderr
    print(
        "EQUIPMENT_HEAVENLY_TAOIST_HELMET_240_TEST_PASS "
        "source_sha=true directions=8 default_envelopes=true "
        "paper_inventory_ground=true v2=true non240_guard=true"
    )


if __name__ == "__main__":
    main()
