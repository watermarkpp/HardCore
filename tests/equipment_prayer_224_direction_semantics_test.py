#!/usr/bin/env python3
"""Validate item 224 row 1/7 direction semantics without pixel replacement."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
EXPECTED_SOURCE_MAP = {
    "N": 0,
    "NE": 1,
    "E": 3,
    "SE": 6,
    "S": 4,
    "SW": 5,
    "W": 2,
    "NW": 7,
}


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def main() -> None:
    recipes = load_json(
        "assets/data/equipment_male_world_helmet_recipes.json"
    )
    prayer_recipe = next(
        record
        for record in recipes["identities"]
        if record["identityId"] == "prayer"
    )
    assert prayer_recipe["calibrationSourceDirectionMap"] == (
        EXPECTED_SOURCE_MAP
    )
    patches = prayer_recipe["directionPatches"]
    assert patches["NE"]["sourceSlot"] == 7
    assert patches["NE"]["referenceHalf"] == "left"
    assert patches["NW"]["sourceSlot"] == 1
    assert patches["NW"]["referenceHalf"] == "right"
    assert patches["NE"]["referenceSha256"] == (
        "fcf6ed6d455eb818027846e30dbcb05346097cb4ee46b29ffda6ad5aa9540a8c"
    )
    assert patches["NW"]["referenceSha256"] == (
        patches["NE"]["referenceSha256"]
    )
    contract = load_json("assets/data/equipment_helmet_visual_v2.json")
    assert contract["itemVisualAssetRefs"]["224"] == "prayer"
    prayer = contract["visualAssets"]["prayer"]
    assert prayer["source_direction_map"] == EXPECTED_SOURCE_MAP
    assert prayer["source"]["calibrationSourceDirectionMap"] == (
        EXPECTED_SOURCE_MAP
    )
    assert prayer["sourceSlotSemantics"] == (
        "explicit_user_confirmed_calibration_direction_map"
    )
    assert sorted(prayer["source_direction_map"].values()) == list(range(8))

    for direction in DIRECTIONS:
        record = prayer["directions"][direction]
        assert record["source_direction"] == direction
        assert record["source_row"] == EXPECTED_SOURCE_MAP[direction]
        assert record["source_slot_id"] == (
            f"slot_{EXPECTED_SOURCE_MAP[direction]}"
        )

    assert prayer["directions"]["NW"]["source_row"] == 7
    assert prayer["directions"]["NE"]["source_row"] == 1
    world = load_json("assets/data/equipment_male_world_helmet.json")
    cutouts = world["visualIdentities"]["prayer"]["directionCutouts"]
    assert len(
        {
            record["sourceCutoutRgbaSha256"]
            for record in cutouts.values()
        }
    ) == 8
    print(
        "EQUIPMENT_PRAYER_224_DIRECTION_SEMANTICS_TEST_PASS "
        "row1=NE row7=NW unique=8 other_source_cells_unchanged=true"
    )


if __name__ == "__main__":
    main()
