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
COMPATIBILITY = (
    ROOT / "assets/data/equipment_primary_weapon_compatibility.json"
)
WEAPON = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
HIDDEN_IDS: set[int] = set()
UNRESOLVED_IDS = {110, 111}
REQUIRED_PRIMARY_APPEARANCES = {
    80: (2, "sword"),
    82: (2, "sword"),
    88: (14, "axe"),
    99: (22, "axe"),
    105: (48, "staff"),
    107: (50, "sword"),
    108: (58, "blade"),
    109: (54, "staff"),
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
    compatibility = load_json(COMPATIBILITY)
    assert contract["contractId"] == "equipment.world_wear.male_weapon.v1"
    assert (
        compatibility["contractId"]
        == "equipment.weapon_compatibility.primary.v1"
    )
    assert compatibility["coverage"] == {
        "formalWeapons": 37,
        "resolvedPrimaryPixels": 35,
        "integrationSharedPrimaryAppearance": 1,
        "unresolved": 2,
        "crystalShapeDiffersFromClassicShape": 31,
        "directCrystalShapeMultiplication": 0,
        "lowerTierValuesAdopted": 0,
    }
    compatibility_text = COMPATIBILITY.read_text(encoding="utf-8")
    for forbidden in ("mylgd", "21CQ", "external/mir2opensource"):
        assert forbidden not in compatibility_text
    for compat_key, compat in compatibility["itemsById"].items():
        assert int(compat["itemId"]) == int(compat_key)
        primary = compat["primaryServerQuery"]
        assert primary["lane"] == "server_data"
        assert primary["distribution"] == "server.crystal.cjlaaa"
        assert primary["tier"] == "primary"
        assert len(primary["sha256"]) == 64
        if compat["status"] == "resolved_primary_pixels":
            assert compat["stateItemEvidence"]["distribution"] == (
                "client.classic_raw_complete"
            )
            assert compat["weaponEvidence"]["distribution"] == (
                "client.classic_raw_complete"
            )
            assert compat["crystalShapeUsedAsClassicShape"] is False
        else:
            assert int(compat_key) in UNRESOLVED_IDS
            assert "maleFeature" not in compat
    luosha = compatibility["itemsById"]["88"]
    assert (
        luosha["mappingType"]
        == "integration_user_required_shared_primary_appearance"
    )
    assert luosha["primaryServerQuery"]["targetNameResult"]["status"] == (
        "missing"
    )
    assert luosha["crystalShape"] is None
    assert int(luosha["stateItemEvidence"]["sourceIndex"]) == 40
    assert int(luosha["classicWeaponShape"]) == 7
    assert int(luosha["maleFeature"]) == 14
    luosha_fallback = luosha["fallbackEvidence"]
    assert luosha_fallback["adopted"] is False
    assert luosha_fallback["configuredChainExhausted"] is True
    assert len(luosha_fallback["queriesInPolicyOrder"]) == 5
    assert all(
        query["status"] == "missing"
        and query["adopted"] is False
        and len(query["sha256"]) == 64
        for query in luosha_fallback["queriesInPolicyOrder"]
    )
    assert [
        query["distribution"]
        for query in luosha_fallback["queriesInPolicyOrder"]
    ] == [
        "server.angelk727_full",
        "server.angelk727_exports",
        "server_reference.angelk727",
        "server.crystal.Jev",
        "server.crystal.Daneo1989",
    ]
    assert len(luosha_fallback["rejectedAliases"]) == 2
    for rejected in luosha_fallback["rejectedAliases"]:
        assert rejected["status"] == "rejected_incompatible_identity"
        assert rejected["adopted"] is False
        assert rejected["matchCount"] == 1
        assert int(rejected["matches"][0]["requiredAmount"]) == 52
        assert int(rejected["matches"][0]["image"]) == 1153
        assert rejected["compatibility"]["primaryStateItemCapacity"][
            "candidateWithinPrimaryLibrary"
        ] is False
    assert contract["sex"] == "male"
    assert contract["actorContract"]["cell"] == [224, 224]
    assert contract["actorContract"]["actorOrigin"] == [80, 116]
    assert contract["actorContract"]["footPoint"] == [80, 116]
    assert contract["actorContract"]["directions"] == 8
    assert contract["actorContract"]["footPointContractChanged"] is False
    assert contract["mappingPolicy"]["femaleExcluded"] is True
    assert contract["mappingPolicy"]["crystalShapeDirectMapping"] is False
    assert contract["coverage"] == {
        "formalWeapons": 37,
        "visible": 35,
        "hiddenByClassicRule": 0,
        "unresolved": 2,
        "maleWeaponFeatureFamilies": 34,
        "actionsPerFeature": 6,
        "directionsPerAction": 8,
        "missingFrames": 0,
        "transparentEmptyFrames": 232,
        "femaleItems": 0,
    }
    assert set(contract["classification"]["hidden_by_classic_rule"]) == HIDDEN_IDS
    assert set(contract["classification"]["unresolved"]) == UNRESOLVED_IDS
    assert len(contract["classification"]["visible"]) == 35
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
            assert "maleAppearance" not in item
            assert item["itemName"] not in runtime
            compat = compatibility["itemsById"][item_key]
            assert compat["status"] == "unresolved"
            assert compat["visualWeaponClass"] == "unresolved"
            continue
        appearance = item["maleAppearance"]
        assert appearance["sex"] == "male"
        assert int(appearance["feature"]) == int(
            appearance["classicShape"]
        ) * 2
        assert int(appearance["shape"]) == int(appearance["classicShape"])
        compat = compatibility["itemsById"][item_key]
        assert compat["status"] == "resolved_primary_pixels"
        if item_id == 88:
            assert "crystalShape" not in appearance
            assert "missing_after_complete_configured_fallback" in (
                appearance["crystalShapeStatus"]
            )
            assert compat["crystalShape"] is None
        else:
            assert int(appearance["crystalShape"]) == int(
                compat["crystalShape"]
            )
        assert int(appearance["classicShape"]) == int(
            compat["classicWeaponShape"]
        )
        assert appearance["visualWeaponClass"] == compat["visualWeaponClass"]
        assert compat["crystalShapeUsedAsClassicShape"] is False
        assessment = item["mappingAssessment"]
        if item_id == 88:
            expected_confidence = (
                "integration_user_required_shared_primary_appearance"
            )
        elif item_id in {99, 105, 107, 108}:
            expected_confidence = (
                "user_confirmed_primary_pixel_compatibility"
            )
        else:
            expected_confidence = "primary_pixel_compatibility"
        assert assessment["confidence"] == expected_confidence
        assert assessment["crystalShapeUsedAsClassicShape"] is False
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

    for item_id, expected in REQUIRED_PRIMARY_APPEARANCES.items():
        item = items[str(item_id)]
        appearance = item["maleAppearance"]
        assert int(appearance["feature"]) == expected[0]
        assert appearance["visualWeaponClass"] == expected[1]
        evidence = catalog["itemsById"][str(item_id)]["worldWear"][
            "shapeEvidence"
        ]
        assert evidence["confidence"] == "primary_pixel_compatibility"
        assert evidence["source"].endswith(f"/itemsById/{item_id}")

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
        "items=37 visible=35 hidden=0 unresolved=2 "
        "features=34 actions=6 directions=8"
    )


if __name__ == "__main__":
    main()
