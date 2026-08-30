#!/usr/bin/env python3
"""Validate the male-only ActRun preparation authority and source pixels."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "assets/data/equipment_male_run_world_wear.json"
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
DRESS_CONTRACT = ROOT / "assets/data/equipment_male_dress_world_wear.json"
WEAPON_CONTRACT = ROOT / "assets/data/equipment_male_weapon_world_wear.json"
HAIR_POLICY = ROOT / "assets/data/equipment_world_helmet_runtime_policy.json"
HUM = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
WEAPON = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
HAIR = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hair.wil"

DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
WALK_START = 64
RUN_START = 128
FRAME_COUNT = 6
BLOCK_FRAMES = 600
LEGACY_ACTIONS = {"idle", "walk", "attack", "cast", "hit", "death"}
MALE_ACTIONS = LEGACY_ACTIONS | {"run"}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def disk_path(value: str) -> Path:
    assert value.startswith("res://"), value
    return ROOT / value.removeprefix("res://")


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def verify_source_atlas(
    ref: dict,
    library: tuple,
    *,
    feature: int,
    source_start: int,
    cell: tuple[int, int],
    anchor: tuple[int, int],
    require_non_empty: bool,
) -> None:
    data, palette, offsets, _info = library
    output = Image.open(disk_path(str(ref["path"]))).convert("RGBA")
    assert output.size == (cell[0] * FRAME_COUNT, cell[1] * len(DIRECTIONS))
    rebuilt = Image.new("RGBA", output.size, (0, 0, 0, 0))
    assert int(ref["sourceFeature"]) == feature
    assert int(ref["sourceStart"]) == source_start
    assert ref["directionOrder"] == DIRECTIONS
    assert int(ref["directions"]) == len(DIRECTIONS)
    assert int(ref["framesPerDirection"]) == FRAME_COUNT
    assert int(ref["decodedFrameCount"]) == FRAME_COUNT * len(DIRECTIONS)
    assert ref["missingFrames"] == []
    for direction in range(len(DIRECTIONS)):
        for frame in range(FRAME_COUNT):
            source_index = (
                feature * BLOCK_FRAMES
                + source_start
                + direction * 8
                + frame
            )
            image, metadata = decode_sprite(data, offsets[source_index], palette)
            image = image.convert("RGBA")
            opaque = sum(alpha != 0 for alpha in image.getchannel("A").tobytes())
            if require_non_empty:
                assert opaque > 0, (ref["path"], direction, frame, source_index)
            local_x = anchor[0] + int(metadata["x"])
            local_y = anchor[1] + int(metadata["y"])
            assert local_x >= 0 and local_y >= 0
            assert local_x + image.width <= cell[0]
            assert local_y + image.height <= cell[1]
            rebuilt.alpha_composite(
                image,
                (
                    frame * cell[0] + local_x,
                    direction * cell[1] + local_y,
                ),
            )
    assert rgba_sha256(output) == str(ref["atlasRgbaSha256"])
    assert rebuilt.tobytes() == output.tobytes(), ref["path"]


def assert_movement_pair(
    actions: dict,
    *,
    expected_feature: int,
    expected_anchor: list[int],
    expected_cell: list[int],
) -> None:
    assert set(actions) == {"walk", "run"}
    walk = actions["walk"]
    run = actions["run"]
    assert int(walk["sourceFeature"]) == expected_feature
    assert int(run["sourceFeature"]) == expected_feature
    assert int(walk["directions"]) == len(DIRECTIONS)
    assert int(run["directions"]) == len(DIRECTIONS)
    if "directionOrder" in walk or "directionOrder" in run:
        assert walk["directionOrder"] == DIRECTIONS
        assert run["directionOrder"] == DIRECTIONS
    assert walk["footAnchor"] == expected_anchor
    assert run["footAnchor"] == expected_anchor
    assert walk["cell"] == expected_cell
    assert run["cell"] == expected_cell
    assert walk["path"] != run["path"]
    assert "/female/" not in str(walk["path"])
    assert "/female/" not in str(run["path"])
    if "sourceStart" in walk or "sourceStart" in run:
        assert int(walk["sourceStart"]) == WALK_START
        assert int(run["sourceStart"]) == RUN_START


def main() -> None:
    authority = load_json(AUTHORITY)
    catalog = load_json(CATALOG)
    dress_contract = load_json(DRESS_CONTRACT)
    weapon_contract = load_json(WEAPON_CONTRACT)
    hair_policy = load_json(HAIR_POLICY)

    assert authority["contractId"] == "equipment.world_wear.male_run.v1"
    source_policy = authority["sourcePolicy"]
    assert source_policy["femaleExcluded"] is True
    assert source_policy["femaleAssetsGenerated"] == 0
    assert source_policy["helmetRunGenerated"] is False
    assert authority["worldHelmet"]["visible"] is False
    assert authority["worldHelmet"]["frontLayerVisible"] is False
    assert authority["worldHelmet"]["backLayerVisible"] is False
    assert authority["worldHelmet"]["headOcclusionMaskEnabled"] is False
    assert authority["worldHelmet"]["runAssetsGenerated"] is False
    assert authority["worldHelmet"]["presentationScopesPreserved"] == [
        "paper_doll",
        "inventory",
        "ground",
    ]
    assert authority["coverage"]["femaleItems"] == 0
    assert authority["coverage"]["helmetRunAtlases"] == 0
    assert authority["coverage"]["unresolvedWeaponItemIds"] == [111]
    assert authority["source"]["directions"] == DIRECTIONS
    assert authority["source"]["actionStart"] == RUN_START
    assert authority["source"]["framesPerDirection"] == FRAME_COUNT

    for key, path in (
        ("humWil", HUM),
        ("weaponWil", WEAPON),
        ("hairWil", HAIR),
    ):
        assert authority["source"][key]["fileSha256"] == file_sha256(path)

    assert hair_policy["worldHelmet"]["visible"] is False
    assert hair_policy["worldHelmet"]["frontLayerVisible"] is False
    assert hair_policy["worldHelmet"]["backLayerVisible"] is False
    assert hair_policy["worldHelmet"]["runAssetsGenerated"] is False
    assert set(hair_policy["hairAppearance"]["actions"]) == MALE_ACTIONS
    policy_hair_run = hair_policy["hairAppearance"]["actions"]["run"]
    assert int(policy_hair_run["sourceFeature"]) == 4
    assert int(policy_hair_run["framesPerDirection"]) == FRAME_COUNT
    assert int(policy_hair_run["decodedFrameCount"]) == 48
    assert policy_hair_run["missingFrames"] == []
    assert len(policy_hair_run["frames"]) == 48
    for frame in policy_hair_run["frames"]:
        expected_index = (
            4 * BLOCK_FRAMES
            + RUN_START
            + int(frame["directionRow"]) * 8
            + int(frame["frame"])
        )
        assert int(frame["sourceIndex"]) == expected_index

    # The formal visual catalog extends male body/dress/weapon only.  Female
    # catalog records retain the classic six actions with no run key.
    assert catalog["actorTemplate"]["actions"].keys() == LEGACY_ACTIONS
    assert catalog["actorTemplate"]["maleActions"]["run"] == {
        "start": RUN_START,
        "frames": FRAME_COUNT,
    }
    for manifest in catalog["professionManifests"].values():
        bases = manifest["worldBaseByGender"]
        assert set(bases["男"]["actions"]) == MALE_ACTIONS
        assert set(bases["女"]["actions"]) == LEGACY_ACTIONS
        assert_movement_pair(
            {key: bases["男"]["actions"][key] for key in ("walk", "run")},
            expected_feature=0,
            expected_anchor=[64, 80],
            expected_cell=[192, 160],
        )

    for item_key, entry in catalog["itemsById"].items():
        category = entry.get("category")
        appearances = entry.get("worldWear", {}).get(
            "appearancesByGender", {}
        )
        if category in {"盔甲", "武器"} and "男" in appearances:
            male = appearances["男"]
            assert set(male["actions"]) == MALE_ACTIONS, item_key
            assert_movement_pair(
                {key: male["actions"][key] for key in ("walk", "run")},
                expected_feature=int(male["feature"]),
                expected_anchor=(
                    [64, 80] if category == "盔甲" else [80, 116]
                ),
                expected_cell=(
                    [192, 160] if category == "盔甲" else [224, 224]
                ),
            )
        if "女" in appearances:
            assert set(appearances["女"]["actions"]) == LEGACY_ACTIONS
            assert "run" not in appearances["女"]["actions"]

    contract_items = {}
    for item_key, item in authority["itemsById"].items():
        assert str(item["itemId"]) == item_key
        assert item["sex"] == "male"
        assert item["category"] in {"dress", "weapon"}
        contract_items[item_key] = item
    dress_items = [item for item in contract_items.values() if item["category"] == "dress"]
    weapon_items = [item for item in contract_items.values() if item["category"] == "weapon"]
    assert len(dress_items) == 12
    assert len(weapon_items) == 36
    assert len({int(item["sourceFeature"]) for item in weapon_items}) == 33
    assert {int(item["sourceFeature"]) for item in weapon_items} == set(
        range(2, 68, 2)
    )
    assert "111" not in contract_items
    assert weapon_contract["itemsById"]["111"]["status"] == "unresolved"
    assert weapon_contract["itemsById"]["111"]["itemName"] == catalog["itemsById"]["111"]["itemName"]
    assert weapon_contract["itemsById"]["111"]["itemName"] not in catalog["runtimeMappings"]

    assert dress_contract["coverage"]["actionsPerFeature"] == 7
    assert set(map(int, dress_contract["featureFamilies"])) == set(
        range(0, 18, 2)
    )
    assert all(
        set(family["actions"]) == MALE_ACTIONS
        for family in dress_contract["featureFamilies"].values()
    )
    assert weapon_contract["coverage"]["actionsPerMappedFeature"] == 7
    assert weapon_contract["coverage"]["unmappedFeatureZeroActions"] == 6
    assert set(weapon_contract["featureFamilies"]["0"]["actions"]) == (
        LEGACY_ACTIONS
    )
    for feature in range(2, 68, 2):
        assert set(
            weapon_contract["featureFamilies"][str(feature)]["actions"]
        ) == MALE_ACTIONS

    dress_library = read_library(HUM)
    weapon_library = read_library(WEAPON)
    verified: set[tuple[str, int, str]] = set()
    base_body = authority["baseBodyAppearance"]
    assert base_body["sex"] == "male"
    assert int(base_body["sourceFeature"]) == 0
    assert_movement_pair(
        base_body["actions"],
        expected_feature=0,
        expected_anchor=[64, 80],
        expected_cell=[192, 160],
    )
    for action_name, start in (("walk", WALK_START), ("run", RUN_START)):
        verify_source_atlas(
            base_body["actions"][action_name],
            dress_library,
            feature=0,
            source_start=start,
            cell=(192, 160),
            anchor=(64, 80),
            require_non_empty=True,
        )
        verified.add(("dress", 0, action_name))
    for item in dress_items:
        feature = int(item["sourceFeature"])
        assert feature in {2, 4, 6, 8, 10, 12, 14, 16}
        assert_movement_pair(
            item["actions"],
            expected_feature=feature,
            expected_anchor=[64, 80],
            expected_cell=[192, 160],
        )
        for action_name, start in (("walk", WALK_START), ("run", RUN_START)):
            key = ("dress", feature, action_name)
            if key in verified:
                continue
            ref = item["actions"][action_name]
            verify_source_atlas(
                ref,
                dress_library,
                feature=feature,
                source_start=start,
                cell=(192, 160),
                anchor=(64, 80),
                require_non_empty=True,
            )
            verified.add(key)

    for item in weapon_items:
        feature = int(item["sourceFeature"])
        assert feature in range(2, 68, 2)
        assert_movement_pair(
            item["actions"],
            expected_feature=feature,
            expected_anchor=[80, 116],
            expected_cell=[224, 224],
        )
        for action_name, start in (("walk", WALK_START), ("run", RUN_START)):
            key = ("weapon", feature, action_name)
            if key in verified:
                continue
            ref = item["actions"][action_name]
            verify_source_atlas(
                ref,
                weapon_library,
                feature=feature,
                source_start=start,
                cell=(224, 224),
                anchor=(80, 116),
                require_non_empty=True,
            )
            verified.add(key)

    hair = authority["hairAppearance"]
    assert hair["sex"] == "male"
    assert hair["appearance"] == 2
    assert hair["sourceBlock"] == 4
    assert set(hair["actions"]) == {"walk", "run"}
    assert_movement_pair(
        hair["actions"],
        expected_feature=4,
        expected_anchor=[64, 80],
        expected_cell=[192, 160],
    )
    hair_library = read_library(HAIR)
    for action_name, start in (("walk", WALK_START), ("run", RUN_START)):
        key = ("hair", 4, action_name)
        if key in verified:
            continue
        verify_source_atlas(
            hair["actions"][action_name],
            hair_library,
            feature=4,
            source_start=start,
            cell=(192, 160),
            anchor=(64, 80),
            require_non_empty=True,
        )
        verified.add(key)

    # A serialized authority must not smuggle in female or helmet run paths.
    authority_text = AUTHORITY.read_text(encoding="utf-8")
    assert "/female/" not in authority_text
    assert "helmet_" + "run.png" not in authority_text
    assert authority["coverage"]["maleDressFeaturesIncludingBase"] == [
        0,
        2,
        4,
        6,
        8,
        10,
        12,
        14,
        16,
    ]
    assert authority["coverage"]["maleWeaponFeaturesMapped"] == 33

    print(
        "EQUIPMENT_MALE_RUN_WORLD_WEAR_TEST_PASS "
        f"dress_items={len(dress_items)} dress_features=8 "
        f"weapon_items={len(weapon_items)} weapon_features=33 "
        "hair_block=4 actions=walk,run directions=8 frames=6 "
        f"verified_atlases={len(verified)} female=0 helmet_run=0 unresolved=111"
    )


if __name__ == "__main__":
    main()
