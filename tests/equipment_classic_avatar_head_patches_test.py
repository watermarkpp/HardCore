#!/usr/bin/env python3
"""Validate all original-client flattened male head patches."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
PRESENTATION = ROOT / "assets/data/equipment_paper_doll_presentation_modes.json"
EXPECTED_IDS = [146, 147, 148, 149, 150, 151, 218, 224, 228, 232, 236, 240]
TEST_IDS = [148, 149, 150, 151, 232, 236, 240]


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def rgba_sha(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert (
        manifest["contractId"]
        == "equipment.paper_doll.classic_flattened_head_patch.v1"
    )
    assert manifest["sourcePolicy"]["tier"] == "primary"
    assert manifest["sourcePolicy"]["fallbackUsed"] is False
    assert manifest["sourcePolicy"]["aiGeneratedAssets"] == 0
    assert manifest["coverage"]["itemIds"] == EXPECTED_IDS
    assert manifest["coverage"]["officialTestHelmetItemIds"] == TEST_IDS
    assert manifest["coverage"]["formalMaleHelmetItems"] == 12
    assert manifest["coverage"]["uniqueStateItemRecords"] == 11
    assert manifest["coverage"]["femaleAssetsGenerated"] == 0
    assert len(manifest["itemsById"]) == 12

    for item_id, item in manifest["itemsById"].items():
        record = item["flattenedHeadPatch"]
        patch = Image.open(disk_path(record["path"])).convert("RGBA")
        mask = Image.open(disk_path(record["eraseMaskPath"])).convert("RGBA")
        assert patch.size == mask.size == tuple(record["size"])
        assert patch.getbbox() is not None, f"{item_id} patch is empty"
        assert rgba_sha(patch) == record["rgbaSha256"]
        assert rgba_sha(mask) == record["eraseMaskRgbaSha256"]
        assert patch.getpixel((0, patch.height - 1))[3] == 0
        assert patch.getpixel((patch.width - 1, patch.height - 1))[3] == 0
        assert record["headOnlyEvidence"]["bottomLeftAlpha"] == 0
        assert record["headOnlyEvidence"]["bottomRightAlpha"] == 0
        assert record["drawOrder"] == [
            "male_head_anatomy",
            "male_hair",
            "helmet",
        ]
        for before, erase in zip(patch.getdata(), mask.getdata()):
            expected_alpha = 255 if before[3] > 0 else 0
            assert erase[3] == expected_alpha

    # Magic and Bronze intentionally share the same primary StateItem #100.
    assert (
        manifest["itemsById"]["147"]["flattenedHeadPatch"]["rgbaSha256"]
        == manifest["itemsById"]["148"]["flattenedHeadPatch"]["rgbaSha256"]
    )
    # Black Iron must retain a complete single subject component.
    black_iron = manifest["itemsById"]["151"]["flattenedHeadPatch"]
    assert black_iron["sourceIndex"] == 344
    assert black_iron["subjectEvidence"]["subjectComponents"] == 1
    assert black_iron["subjectEvidence"]["subjectOpaquePixels"] == 354

    presentation = json.loads(PRESENTATION.read_text(encoding="utf-8"))
    classic = presentation["modes"]["classic_avatar"]["avatarOnly"]
    assert classic["headPatchSelector"].endswith(
        "equipment_classic_avatar_head_patches.json#/"
        "itemsById/{itemId}/flattenedHeadPatch"
    )
    assert classic["drawOrder"] == [
        "base",
        "dress",
        "weapon",
        "flattenedHeadPatch",
    ]
    print(
        "EQUIPMENT_CLASSIC_AVATAR_HEAD_PATCHES_TEST_PASS "
        "items=12 records=11 primary=true ai=0"
    )


if __name__ == "__main__":
    main()
