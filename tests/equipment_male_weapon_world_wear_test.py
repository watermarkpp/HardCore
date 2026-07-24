#!/usr/bin/env python3
"""Source and runtime validation for the male Weapon.wil contract."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "assets/data/equipment_male_weapon_world_wear.json"
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
WEAPON = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
HIDDEN_IDS: set[int] = set()
UNRESOLVED_IDS = {111}
USER_EVIDENCE_IDS = {80, 82, 88, 108, 109}
REQUIRED_IDENTITIES = {
    80: (1, 2, "sword", "通用"),
    81: (6, 12, "dagger", "通用"),
    82: (1, 2, "sword", "通用"),
    83: (2, 4, "sword", "通用"),
    84: (4, 8, "sword", "通用"),
    85: (2, 4, "sword", "通用"),
    86: (19, 38, "pickaxe", "通用"),
    87: (3, 6, "axe", "通用"),
    88: (7, 14, "axe", "战士"),
    89: (15, 30, "blade", "战士"),
    90: (8, 16, "staff", "法师"),
    91: (16, 32, "blade", "道士"),
    92: (5, 10, "sword", "战士"),
    93: (20, 40, "dagger", "战士"),
    94: (10, 20, "blade", "战士"),
    95: (18, 36, "staff", "法师"),
    96: (14, 28, "sword", "道士"),
    97: (7, 14, "axe", "战士"),
    98: (13, 26, "sword", "战士"),
    99: (11, 22, "axe", "战士"),
    100: (12, 24, "staff", "法师"),
    101: (9, 18, "sword", "道士"),
    102: (17, 34, "blade", "战士"),
    103: (22, 44, "sword", "法师"),
    104: (21, 42, "staff", "道士"),
    105: (24, 48, "staff", "战士"),
    106: (28, 56, "staff", "法师"),
    107: (25, 50, "sword", "道士"),
    108: (26, 52, "blade", "战士"),
    109: (27, 54, "staff", "法师"),
    110: (29, 58, "blade", "战士"),
    112: (30, 60, "sword", "战士"),
    113: (32, 64, "axe", "战士"),
    114: (31, 62, "sword", "法师"),
    115: (33, 66, "fan", "道士"),
    223: (23, 46, "blade", "战士"),
}
ACTION_FRAMES = {
    "idle": 4,
    "walk": 6,
    "attack": 6,
    "cast": 6,
    "hit": 3,
    "death": 4,
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(resource_path: str) -> Path:
    assert resource_path.startswith("res://")
    return ROOT / resource_path.removeprefix("res://")


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def unpack_frame(value: str) -> dict:
    parts = value.split("|")
    assert len(parts) == 10
    return {
        "sourceIndex": int(parts[0]),
        "direction": int(parts[1]),
        "frame": int(parts[2]),
        "hotX": int(parts[3]),
        "hotY": int(parts[4]),
        "width": int(parts[5]),
        "height": int(parts[6]),
        "sourceOpaquePixelCount": int(parts[7]),
        "transparentEmpty": parts[8] == "1",
        "rgbaSha256": parts[9],
    }


def main() -> None:
    contract = load_json(CONTRACT)
    catalog = load_json(CATALOG)
    assert contract["contractId"] == "equipment.world_wear.male_weapon.v1"
    assert contract["sex"] == "male"
    assert contract["actorContract"]["cell"] == [224, 224]
    assert contract["actorContract"]["actorOrigin"] == [80, 116]
    assert contract["actorContract"]["footPoint"] == [80, 116]
    assert contract["actorContract"]["directions"] == 8
    assert contract["actorContract"]["footPointContractChanged"] is False
    assert contract["mappingPolicy"]["femaleExcluded"] is True
    taxonomy = contract["visualWeaponClassTaxonomy"]
    assert set(taxonomy["classes"]) == {
        "sword",
        "dagger",
        "axe",
        "blade",
        "staff",
        "pickaxe",
        "fan",
    }
    assert "independent from profession" in taxonomy["axis"]
    assert "long-handled" in taxonomy["classes"]["staff"]["semantic"]
    assert contract["coverage"] == {
        "formalWeapons": 37,
        "visible": 36,
        "hiddenByClassicRule": 0,
        "unresolved": 1,
        "maleWeaponFeatureFamilies": 34,
        "actionsPerFeature": 6,
        "directionsPerAction": 8,
        "missingFrames": 0,
        "transparentEmptyFrames": 232,
        "femaleItems": 0,
    }
    assert set(contract["classification"]["hidden_by_classic_rule"]) == HIDDEN_IDS
    assert set(contract["classification"]["unresolved"]) == UNRESOLVED_IDS
    assert len(contract["classification"]["visible"]) == 36
    visible_ids = set(contract["classification"]["visible"])
    assert set(map(int, contract["runtimeMappingsByItemId"])) == visible_ids
    assert "appearancesByGender" not in CONTRACT.read_text(encoding="utf-8")

    features = contract["featureFamilies"]
    assert {int(value) for value in features} == set(range(0, 68, 2))
    items = contract["itemsById"]
    assert len(items) == 37
    runtime = catalog["runtimeMappings"]
    for item_key, item in items.items():
        item_id = int(item_key)
        assert int(item["itemId"]) == item_id
        assert item["sex"] == "male"
        assert item["slot"] == "weapon"
        status = item["status"]
        if item_id in UNRESOLVED_IDS:
            assert status == "unresolved"
            assert item["mappingAssessment"]["confidence"] == "unresolved"
            assert item["visualWeaponClass"] == "unresolved"
            assert item["visualWeaponClassEvidence"]["confidence"] == (
                "unresolved"
            )
            assert item["profession"] == "战士"
            assert item["weaponHoldAnchorProfile"] == "unresolved"
            assert "maleAppearance" not in item
            assert item["itemName"] not in runtime
            continue
        appearance = item["maleAppearance"]
        assert appearance["sex"] == "male"
        assert int(appearance["feature"]) == int(appearance["shape"]) * 2
        assessment = item["mappingAssessment"]
        assert assessment["confidence"] == "A"
        assert assessment["sourceSha256"] == (
            "7978a8164b950a96b47ae15c0414f2925fa2418661dc74a1ac4d0427b1c0372b"
        )
        assert "mylgd_mir2server_176" in assessment["source"]
        assert item["visualWeaponClass"] == appearance["visualWeaponClass"]
        assert item["visualWeaponClassEvidence"]["confidence"] == (
            "manually_verified"
        )
        class_source = item["visualWeaponClassEvidence"]["source"]
        if int(appearance["shape"]) <= 24:
            assert "auxiliary material/impact evidence only" in class_source
        else:
            assert "StdItems Shape/Looks and StateItem identity" in class_source
        expected_hold_profile = (
            f"weapon.hold.{item['visualWeaponClass']}.source_hot.v1"
        )
        assert item["weaponHoldAnchorProfile"] == expected_hold_profile
        assert appearance["holdAnchorProfile"] == expected_hold_profile
        runtime_appearance = runtime[item["itemName"]]["weaponAppearance"]
        assert int(runtime_appearance["shape"]) == int(appearance["shape"])
        assert int(runtime_appearance["feature"]) == int(appearance["feature"])
        assert status == "visible"
        assert appearance["visible"] is True
        assert set(appearance["actions"]) == set(ACTION_FRAMES)
        for action, frame_count in ACTION_FRAMES.items():
            reference = appearance["actions"][action]
            feature_action = features[str(appearance["feature"])][
                "actions"
            ][action]
            assert reference["path"] == feature_action["path"]
            assert runtime_appearance["actions"][action]["path"] == (
                feature_action["path"]
            )
            assert runtime_appearance["actions"][action][
                "missingFrames"
            ] == []
            assert int(reference["framesPerDirection"]) == frame_count
        contract_runtime = contract["runtimeMappingsByItemId"][item_key][
            "weaponAppearance"
        ]
        assert contract_runtime == appearance
        if item_id in USER_EVIDENCE_IDS:
            catalog_evidence = catalog["itemsById"][item_key]["worldWear"][
                "shapeEvidence"
            ]
            assert catalog_evidence["confidence"] == "A"
            assert "userEvidence" in catalog_evidence
            assert assessment["userEvidence"]
        if item_id in REQUIRED_IDENTITIES:
            expected_shape, expected_feature, expected_class, profession = (
                REQUIRED_IDENTITIES[item_id]
            )
            assert int(appearance["shape"]) == expected_shape
            assert int(appearance["feature"]) == expected_feature
            assert appearance["visualWeaponClass"] == expected_class
            assert item["profession"] == profession

    data, palette, offsets, _info = read_library(WEAPON)
    action_specs = contract["actorContract"]["actions"]
    transparent_frame_count = 0
    for feature_key, feature in features.items():
        feature_id = int(feature_key)
        assert feature_id % 2 == 0
        assert feature["sex"] == "male"
        assert feature["cell"] == [224, 224]
        assert feature["actorOrigin"] == [80, 116]
        assert feature["footPoint"] == [80, 116]
        for action, frame_count in ACTION_FRAMES.items():
            record = feature["actions"][action]
            assert record["directions"] == 8
            assert record["framesPerDirection"] == frame_count
            assert record["decodedFrameCount"] == 8 * frame_count
            assert record["missingFrames"] == []
            assert record["pixelActionConfidence"] == "A"
            assert "prior frames" in record["transparentFramePolicy"]
            assert record["actorOrigin"] == [80, 116]
            assert record["footPoint"] == [80, 116]
            assert len(record["sourceFramesPacked"]) == 8 * frame_count
            assert "/weapon/male/" in record["path"]
            assert "/female/" not in record["path"]

            atlas = Image.open(disk_path(record["path"])).convert("RGBA")
            assert atlas.size == (224 * frame_count, 224 * 8)
            assert rgba_sha256(atlas) == record["atlasRgbaSha256"]
            rebuilt = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
            transparent_indices: list[int] = []
            for packed in record["sourceFramesPacked"]:
                frame = unpack_frame(packed)
                expected_index = (
                    feature_id * 600
                    + int(action_specs[action]["start"])
                    + frame["direction"] * 8
                    + frame["frame"]
                )
                assert frame["sourceIndex"] == expected_index
                image, metadata = decode_sprite(
                    data,
                    offsets[frame["sourceIndex"]],
                    palette,
                )
                image = image.convert("RGBA")
                assert [int(metadata["x"]), int(metadata["y"])] == [
                    frame["hotX"],
                    frame["hotY"],
                ]
                assert [image.width, image.height] == [
                    frame["width"],
                    frame["height"],
                ]
                assert rgba_sha256(image) == frame["rgbaSha256"]
                opaque_pixels = sum(
                    alpha != 0 for alpha in image.getchannel("A").tobytes()
                )
                assert opaque_pixels == frame["sourceOpaquePixelCount"]
                if frame["transparentEmpty"]:
                    assert feature_id == 0
                    assert [image.width, image.height] == [4, 1]
                    assert [frame["hotX"], frame["hotY"]] == [7, -44]
                    assert opaque_pixels == 1
                    transparent_indices.append(frame["sourceIndex"])
                    transparent_frame_count += 1
                    image = Image.new("RGBA", image.size, (0, 0, 0, 0))
                else:
                    assert feature_id != 0
                    assert opaque_pixels > 0
                rebuilt.alpha_composite(
                    image,
                    (
                        frame["frame"] * 224 + 80 + frame["hotX"],
                        frame["direction"] * 224 + 116 + frame["hotY"],
                    ),
                )
            assert transparent_indices == record["transparentEmptyFrames"]
            assert rebuilt.tobytes() == atlas.tobytes()
            if feature_id == 0:
                assert not atlas.getbbox()

    assert transparent_frame_count == 232
    print(
        "EQUIPMENT_MALE_WEAPON_WORLD_WEAR_TEST_PASS "
        "items=37 visible=36 hidden=0 unresolved=1 "
        "features=34 actions=6 directions=8"
    )


if __name__ == "__main__":
    main()
