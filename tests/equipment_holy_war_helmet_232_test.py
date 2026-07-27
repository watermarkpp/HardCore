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
BUILDER = ROOT / "tools/build_holy_war_helmet_232.py"
EXPECTED_APPROVED_SHA = (
    "93307c79e0d5d697d269eec3ba2c318385be96130026e1dbe1b67779437b583b"
)
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


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

    erase = Image.open(ERASE).convert("RGBA")
    assert erase.getchannel("A").getbbox() is None
    paper = Image.open(HEAD).convert("RGBA")
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
    assert report["paperDollEraseMaskAllTransparent"] is True
    assert report["inventoryFaceWindowOpaque"] is True
    assert report["groundFaceWindowOpaque"] is True
    assert report["frozenNon232FilesUnchanged"] is True
    assert report["non232ContractDataUnchanged"] is True
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
        "paper_inventory_ground_opaque=true non232_guard=true"
    )


if __name__ == "__main__":
    main()
