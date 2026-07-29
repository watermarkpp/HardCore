#!/usr/bin/env python3
"""Validate item 228's user-approved sheet and true W/E profiles."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
SOURCE_ORDER = ["S", "SW", "W", "SE", "N", "NE", "E", "NW"]
CANONICAL_SLOTS = [4, 5, 6, 3, 0, 1, 2, 7]
FROZEN_CELL_HASHES = {
    0: "d480cd9e5512d742682862c929496a73d8350a9eb8ff3efcf1275bf12b29cbfe",
    1: "accb7c19af86f193dee9f30a906645ed994d38d631377395ed1ead8ba5b11d24",
    3: "0f49fecf1654454d411657c9839b2803a52352598a05049b845f0c13a47698d9",
    4: "90cbaaf8c0aa4e1465722b1ba1800d72e73fc1cb90348017dd0c4b212e2a155b",
    5: "ec01ec85d6902e8e9180c1ebcf50facc6c742b7cbc1bc1bae809824673a0acb0",
    7: "664f45c01cd9d887d443addbefedef47aa1f658e41b45fc73fc4d2424704482c",
}
PATCHED_CELL_HASHES = {
    2: "90c41712fad80fc05cecd95d464a85877270d3d4fd3cda5593ae04f758baa8f3",
    6: "8e3d706226930c88d68eeae6a306ca8835c7e844b16a717f7d2ebe4b61c33361",
}
SOURCE_SHEET_SHA256 = (
    "770778d6cdb5eee2346eb2b4c873de55a5bf73aa2112a6cefeb5742d5aa5b40a"
)


def load_json(relative_path: str) -> dict:
    return json.loads(
        (ROOT / relative_path).read_text(encoding="utf-8")
    )


def rgba_sha(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def main() -> None:
    recipes = load_json("assets/data/equipment_male_world_helmet_recipes.json")
    recipe = next(
        item for item in recipes["identities"]
        if item["identityId"] == "memory"
    )
    assert recipe["sourceSlotDirectionOrder"] == SOURCE_ORDER
    assert recipe["canonicalRowSourceSlots"] == CANONICAL_SLOTS
    assert recipe["calibrationSourceDirectionMap"] == {
        direction: index for index, direction in enumerate(DIRECTIONS)
    }
    assert recipe["directionPatches"]["W"]["sourceSlot"] == 2
    assert recipe["directionPatches"]["E"]["sourceSlot"] == 6
    assert recipe["directionPatches"]["W"]["referenceHalf"] == "left"
    assert recipe["directionPatches"]["E"]["referenceHalf"] == "right"
    assert recipe["directionPatches"]["W"]["referenceSha256"] == (
        "c7f7babb2d20e151b47e411a770539152ea322dff8a7279a5f7d45aa8ca59a19"
    )

    source = Image.open(
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/source"
        / "memory_helmet_8dir.png"
    ).convert("RGBA")
    assert source.size == (1536, 1024)
    for slot, expected_hash in (FROZEN_CELL_HASHES | PATCHED_CELL_HASHES).items():
        column = slot % 4
        row = slot // 4
        cell = source.crop(
            (
                column * 384,
                row * 512,
                (column + 1) * 384,
                (row + 1) * 512,
            )
        )
        assert rgba_sha(cell) == expected_hash, slot
    assert hashlib.sha256(
        (
            ROOT
            / "assets/art/items/client/world_wear/helmet/male/source"
            / "memory_helmet_8dir.png"
        ).read_bytes()
    ).hexdigest() == SOURCE_SHEET_SHA256

    contract = load_json("assets/data/equipment_helmet_visual_v2.json")
    assert contract["itemVisualAssetRefs"]["228"] == "memory"
    memory = contract["visualAssets"]["memory"]
    assert memory["source_direction_map"] == {
        direction: index for index, direction in enumerate(DIRECTIONS)
    }
    for index, direction in enumerate(DIRECTIONS):
        assert memory["directions"][direction]["source_row"] == index
        assert memory["directions"][direction]["flip_h"] is False

    world = load_json("assets/data/equipment_male_world_helmet.json")
    cutouts = world["visualIdentities"]["memory"]["directionCutouts"]
    assert len(
        {
            record["sourceCutoutRgbaSha256"]
            for record in cutouts.values()
        }
    ) == 8
    assert cutouts["W"]["sourceSlot"] == 2
    assert cutouts["E"]["sourceSlot"] == 6
    assert cutouts["W"]["sourceCutoutRgbaSha256"] != (
        cutouts["E"]["sourceCutoutRgbaSha256"]
    )

    print(
        "EQUIPMENT_MEMORY_HELMET_228_PROFILES_TEST_PASS "
        "W=slot2 E=slot6 unique=8 frozen_cells=6"
    )


if __name__ == "__main__":
    main()
