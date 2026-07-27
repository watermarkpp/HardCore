#!/usr/bin/env python3
"""Focused regression checks for the user-approved item 236 replacement."""

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
    / "god_magic_helmet_approved_20260727.png"
)
PROCESSED = (
    ROOT
    / "assets/art/items/client/world_wear/helmet/male/source"
    / "god_magic_helmet_8dir.png"
)
WORLD = ROOT / "assets/data/equipment_male_world_helmet.json"
RECIPE = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
HEAD = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00236_head.png"
)
ERASE = (
    ROOT
    / "assets/art/items/client/paper_doll/classic_flattened_head"
    / "item_00236_erase_mask.png"
)
INVENTORY = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/god_magic"
    / "item_00236_inventory.png"
)
GROUND = (
    ROOT
    / "assets/art/items/client/project_redesign/helmet/god_magic"
    / "item_00236_ground.png"
)
REPORT = ROOT / "outputs/helmet_236/god_magic_236_validation_report.json"
BUILDER = ROOT / "tools/build_god_magic_helmet_236.py"
EXPECTED_APPROVED_SHA = (
    "b676e30dbb335c55df10ac89aac4636f5a7b557cbd978f0edfd8a419c12afa14"
)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
EXPECTED_WORLD_HEIGHTS = {
    "N": 23,
    "NE": 23,
    "E": 22,
    "SE": 23,
    "S": 23,
    "SW": 23,
    "W": 22,
    "NW": 23,
}
SOURCE_SIZE = (1774, 887)
SOURCE_X_BOUNDS = [0, 444, 887, 1331, 1774]
SOURCE_Y_BOUNDS = [0, 444, 887]


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
        if value["identityId"] == "god_magic"
    )
    assert identity_recipe["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity_recipe["canonicalRowSourceSlots"] == list(range(8))
    assert identity_recipe["approvedSourceFileSha256"] == EXPECTED_APPROVED_SHA
    assert set(identity_recipe["faceAperturePolicy"].values()) == {"closed"}
    assert set(identity_recipe["faceApertureShape"].values()) == {"none"}
    assert identity_recipe["paperDollFaceWindow"] == "none_opaque_black_mask"
    assert (
        identity_recipe["paperDollEraseMask"]
        == "clear_exact_approved_S_silhouette"
    )

    processed = Image.open(PROCESSED).convert("RGBA")
    assert processed.size == SOURCE_SIZE
    signatures = []
    for slot in range(8):
        x = slot % 4
        y = slot // 4
        cell = processed.crop(
            (
                SOURCE_X_BOUNDS[x],
                SOURCE_Y_BOUNDS[y],
                SOURCE_X_BOUNDS[x + 1],
                SOURCE_Y_BOUNDS[y + 1],
            )
        )
        signatures.append(hashlib.sha256(cell.tobytes()).hexdigest())
    assert len(set(signatures)) == 8
    assert not any(
        green >= 245 and red <= 12 and blue <= 12 and alpha > 0
        for red, green, blue, alpha in processed.get_flattened_data()
    )

    world = load_json(WORLD)
    identity = world["visualIdentities"]["god_magic"]
    assert identity["approvedSourceFileSha256"] == EXPECTED_APPROVED_SHA
    assert identity["sourceSlotDirectionOrder"] == DIRECTIONS
    assert identity["canonicalRowSourceSlots"] == list(range(8))
    assert set(identity["faceAperturePolicy"].values()) == {"closed"}
    assert set(identity["faceApertureShape"].values()) == {"none"}
    assert all(
        identity["directionCutouts"][direction]["runtimeScale"] == 1
        for direction in DIRECTIONS
    )
    generated_sizes = {
        direction: identity["directionCutouts"][direction]["generatedSize"]
        for direction in DIRECTIONS
    }
    assert all(
        generated_sizes[direction][1] == EXPECTED_WORLD_HEIGHTS[direction]
        for direction in DIRECTIONS
    )
    assert max(size[0] for size in generated_sizes.values()) <= 19
    assert max(size[1] for size in generated_sizes.values()) <= 23
    assert all(
        identity["directionCutouts"][direction]["worldScaleRatio"] == 0.64
        for direction in DIRECTIONS
    )
    assert all(
        identity["directionCutouts"][direction]["resizeFilter"]
        == "nearest_baked_source_to_integer_pixels"
        for direction in DIRECTIONS
    )

    erase = Image.open(ERASE).convert("RGBA")
    assert erase.getchannel("A").getbbox() is not None
    assert erase.getpixel((0, 0))[3] == 0
    assert erase.getpixel((erase.width - 1, erase.height - 1))[3] == 0
    paper = Image.open(HEAD).convert("RGBA")
    paper_bounds = paper.getchannel("A").getbbox()
    assert paper_bounds is not None
    assert paper_bounds[2] - paper_bounds[0] <= 24
    assert paper_bounds[3] - paper_bounds[1] <= 29
    inventory = Image.open(INVENTORY).convert("RGBA")
    ground = Image.open(GROUND).convert("RGBA")
    assert paper.getpixel((16, 28))[3] == 255
    assert inventory.getpixel((18, 24))[3] == 255
    assert ground.getpixel((8, 12))[3] == 255

    report = load_json(REPORT)
    assert report["sourceSlotDirectionOrder"] == DIRECTIONS
    assert report["canonicalRowSourceSlots"] == list(range(8))
    assert report["wearableFaceWindowTransparent"] is False
    assert report["paperDollFaceWindowTransparent"] is False
    assert report["paperDollEraseMaskHasTransparentAndOpaquePixels"] is True
    assert report["inventoryFaceWindowOpaque"] is True
    assert report["groundFaceWindowOpaque"] is True
    assert report["worldScaleRatio"] == 0.64
    assert report["worldMaximumSize"][0] <= 19
    assert report["worldMaximumSize"][1] <= 23
    assert report["paperDollContentEnvelope"] == [24, 29]
    assert report["frozenNon236FilesUnchanged"] is True
    assert report["non236ContractDataUnchanged"] is True
    assert all(
        record["allOpaque"] is True
        and record["alpha"] == 255
        for record in report["opaqueBlackClothVeilEvidence"].values()
    )

    rejected = subprocess.run(
        [sys.executable, str(BUILDER), "--identity", "black_iron"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert rejected.returncode != 0
    assert "only 'god_magic' is legal" in rejected.stderr
    print(
        "EQUIPMENT_GOD_MAGIC_HELMET_236_TEST_PASS "
        "source_sha=true directions=8 no_cutout=true "
        "default_world_size=true paper_inventory_ground_opaque=true "
        "non236_guard=true"
    )


if __name__ == "__main__":
    main()
