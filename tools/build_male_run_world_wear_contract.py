#!/usr/bin/env python3
"""Build the male-only ActRun preparation authority.

This stage prepares source-exact run atlases and an item-id-first authority
without changing the runtime player visual code.  It deliberately reads the
existing six-action helmet policy but never writes it and never generates a
helmet atlas.  Female records are not traversed or emitted.
"""

from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
DRESS_CONTRACT = ROOT / "assets/data/equipment_male_dress_world_wear.json"
WEAPON_CONTRACT = ROOT / "assets/data/equipment_male_weapon_world_wear.json"
HAIR_POLICY = ROOT / "assets/data/equipment_world_helmet_runtime_policy.json"
OUTPUT = ROOT / "assets/data/equipment_male_run_world_wear.json"
HAIR_SOURCE = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hair.wil"
HUM_SOURCE = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Hum.wil"
WEAPON_SOURCE = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"

CONTRACT_ID = "equipment.world_wear.male_run.v1"
ACTION = {"start": 128, "frames": 6}
ACTION_NAME = "run"
WALK_ACTION = {"start": 64, "frames": 6}
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
BODY_ANCHOR = [64, 80]
WEAPON_ANCHOR = [80, 116]
HAIR_APPEARANCE = 2
HAIR_SOURCE_BLOCK = 4
HAIR_STRIDE = 600
UNRESOLVED_WEAPON_ITEM_IDS = [111]

def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def disk_path(path: str) -> Path:
    if not path.startswith("res://"):
        raise ValueError(f"not a project resource: {path}")
    return ROOT / path.removeprefix("res://")


def layer_action_ref(
    record: dict,
    layer: str,
    feature: int,
    action: str,
    source_library: str,
) -> dict:
    anchor = record.get("footAnchor")
    if anchor is None:
        anchor = record.get("actorOrigin")
    if anchor is None:
        anchor = record.get("footPoint")
    if anchor is None:
        raise ValueError(f"{layer}/{action} lacks a source foot anchor")
    return {
        "featureActionRef": f"{layer}FeatureFamilies.{feature}.actions.{action}",
        "path": str(record["path"]),
        "sourceLibrary": source_library,
        "sourceFeature": feature,
        "sourceAction": action,
        "sourceStart": int(ACTION["start"] if action == ACTION_NAME else WALK_ACTION["start"]),
        "cell": [int(value) for value in record["cell"]],
        "footAnchor": [int(value) for value in anchor],
        "directions": int(record["directions"]),
        "directionOrder": DIRECTIONS,
        "framesPerDirection": int(record["framesPerDirection"]),
        "decodedFrameCount": int(
            record.get("decodedFrameCount", len(record.get("frames", [])))
        ),
        "missingFrames": list(record.get("missingFrames", [])),
        "atlasRgbaSha256": str(record.get("atlasRgbaSha256", "")),
        "fileSha256": str(record.get("fileSha256", "")),
        "confidence": str(
            record.get("confidence", record.get("pixelActionConfidence", ""))
        ),
    }


def make_item_record(
    item: dict,
    layer: str,
    appearance: dict,
    feature_family: dict,
    contract_path: str,
    source_library: str,
) -> dict:
    feature = int(appearance["feature"])
    actions = feature_family["actions"]
    return {
        "itemId": int(item["itemId"]),
        "itemName": str(item["itemName"]),
        "category": layer,
        "sex": "male",
        "sourceFeature": feature,
        "sourceContract": f"{contract_path}#/featureFamilies/{feature}",
        "actions": {
            "walk": layer_action_ref(
                actions["walk"], layer, feature, "walk", source_library
            ),
            ACTION_NAME: layer_action_ref(
                actions[ACTION_NAME], layer, feature, ACTION_NAME, source_library
            ),
        },
    }


def main() -> None:
    for source in (
        CATALOG,
        DRESS_CONTRACT,
        WEAPON_CONTRACT,
        HAIR_POLICY,
        HUM_SOURCE,
        WEAPON_SOURCE,
        HAIR_SOURCE,
    ):
        if not source.exists():
            raise FileNotFoundError(f"missing male run input: {source}")

    catalog = load_json(CATALOG)
    dress = load_json(DRESS_CONTRACT)
    weapon = load_json(WEAPON_CONTRACT)
    hair_policy = load_json(HAIR_POLICY)
    if hair_policy.get("worldHelmet", {}).get("visible", True):
        raise AssertionError("world helmet must remain hidden")
    if hair_policy.get("worldHelmet", {}).get("frontLayerVisible", True):
        raise AssertionError("world helmet front layer must remain hidden")
    if hair_policy.get("worldHelmet", {}).get("backLayerVisible", True):
        raise AssertionError("world helmet back layer must remain hidden")

    # Hair run must come from the formal extractor output/policy.  This builder
    # is authority-only and must not manufacture an unregistered side output.
    hair_actions = hair_policy.get("hairAppearance", {}).get("actions", {})
    hair_run = hair_actions.get(ACTION_NAME, {})
    hair_walk = hair_actions.get("walk", {})
    if not hair_walk:
        raise ValueError("existing primary male hair walk authority is missing")
    if not hair_run:
        raise ValueError(
            "formal male hair run authority is missing; run "
            "tools/extract_world_hair_atlases.py first"
        )
    if str(hair_walk.get("path", "")).find("/female/") >= 0:
        raise AssertionError("male hair walk authority points to a female asset")
    if int(hair_run.get("sourceFeature", -1)) != HAIR_SOURCE_BLOCK:
        raise AssertionError("male hair run source block changed")
    if int(hair_run.get("framesPerDirection", -1)) != int(ACTION["frames"]):
        raise AssertionError("male hair run frame count changed")
    if int(hair_run.get("decodedFrameCount", -1)) != 48:
        raise AssertionError("male hair run must contain 48 decoded frames")
    if hair_run.get("missingFrames") != []:
        raise AssertionError("male hair run contains missing frames")

    dress_items = []
    for item_key, item in sorted(dress.get("itemsById", {}).items(), key=lambda row: int(row[0])):
        appearance = item.get("maleAppearance", {})
        if item.get("sex") != "male" or not appearance:
            raise AssertionError(f"dress item {item_key} is not a male appearance")
        feature = int(appearance["feature"])
        family = dress["featureFamilies"].get(str(feature), {})
        if not family:
            raise AssertionError(f"dress feature family {feature} is missing")
        dress_items.append(
            make_item_record(
                item,
                "dress",
                appearance,
                family,
                resource_path(DRESS_CONTRACT),
                "Hum.wil",
            )
        )

    base_dress_family = dress.get("featureFamilies", {}).get("0", {})
    if not base_dress_family:
        raise AssertionError("male base body feature family 0 is missing")
    base_body = {
        "sex": "male",
        "sourceFeature": 0,
        "sourceContract": f"{resource_path(DRESS_CONTRACT)}#/featureFamilies/0",
        "actions": {
            "walk": layer_action_ref(
                base_dress_family["actions"]["walk"],
                "dress",
                0,
                "walk",
                "Hum.wil",
            ),
            ACTION_NAME: layer_action_ref(
                base_dress_family["actions"][ACTION_NAME],
                "dress",
                0,
                ACTION_NAME,
                "Hum.wil",
            ),
        },
    }

    weapon_items = []
    unresolved_ids = []
    for item_key, item in sorted(weapon.get("itemsById", {}).items(), key=lambda row: int(row[0])):
        item_id = int(item_key)
        if item.get("status") == "unresolved":
            unresolved_ids.append(item_id)
            continue
        if item.get("sex") != "male" or item.get("status") != "visible":
            raise AssertionError(f"weapon item {item_key} is not a visible male mapping")
        appearance = item.get("maleAppearance", {})
        feature = int(appearance["feature"])
        family = weapon["featureFamilies"].get(str(feature), {})
        if not family:
            raise AssertionError(f"weapon feature family {feature} is missing")
        weapon_items.append(
            make_item_record(
                item,
                "weapon",
                appearance,
                family,
                resource_path(WEAPON_CONTRACT),
                "Weapon.wil",
            )
        )

    if len(dress_items) != 12:
        raise AssertionError(f"expected 12 male dress items, got {len(dress_items)}")
    if len(weapon_items) != 36:
        raise AssertionError(f"expected 36 mapped male weapons, got {len(weapon_items)}")
    if sorted(unresolved_ids) != UNRESOLVED_WEAPON_ITEM_IDS:
        raise AssertionError(f"unresolved weapon IDs changed: {unresolved_ids}")
    weapon_features = sorted({int(item["sourceFeature"]) for item in weapon_items})
    if len(weapon_features) != 33 or weapon_features != list(range(2, 68, 2)):
        raise AssertionError(f"expected 33 mapped weapon features, got {weapon_features}")

    # The contract carries both movement refs for every item.  This makes the
    # later runtime adapter consume the same feature/direction/anchor identity
    # for walk and run instead of falling back by item name or category.
    items_by_id = {str(item["itemId"]): item for item in dress_items + weapon_items}
    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "scope": "male_world_actor_run_preparation_only",
        "sourcePolicy": {
            "lane": "client_assets",
            "tier": "primary",
            "distribution": "client.classic_raw_complete",
            "femaleExcluded": True,
            "femaleAssetsGenerated": 0,
            "helmetRunGenerated": False,
            "unresolvedWeaponPolicy": "retain unresolved_no_placeholder; never guess feature",
        },
        "source": {
            "action": ACTION_NAME,
            "actionStart": int(ACTION["start"]),
            "framesPerDirection": int(ACTION["frames"]),
            "blockFrames": 600,
            "directions": DIRECTIONS,
            "indexRule": "feature*600 + actionStart + directionRow*8 + frame",
            "humWil": {
                "path": resource_path(HUM_SOURCE),
                "fileSha256": file_sha256(HUM_SOURCE),
            },
            "weaponWil": {
                "path": resource_path(WEAPON_SOURCE),
                "fileSha256": file_sha256(WEAPON_SOURCE),
            },
            "hairWil": {
                "path": resource_path(HAIR_SOURCE),
                "fileSha256": file_sha256(HAIR_SOURCE),
            },
        },
        "actorContract": {
            "contractId": "player.visual.classic_eight_direction.v1",
            "directionOrder": DIRECTIONS,
            "movementActions": {
                "walk": deepcopy(WALK_ACTION),
                ACTION_NAME: deepcopy(ACTION),
            },
            "dress": {
                "cell": [192, 160],
                "footAnchor": BODY_ANCHOR,
                "sourceLibrary": "Hum.wil",
            },
            "weapon": {
                "cell": [224, 224],
                "footAnchor": WEAPON_ANCHOR,
                "sourceLibrary": "Weapon.wil",
            },
            "hair": {
                "cell": [192, 160],
                "footAnchor": BODY_ANCHOR,
                "sourceLibrary": "Hair.wil",
                "appearance": HAIR_APPEARANCE,
                "sourceBlock": HAIR_SOURCE_BLOCK,
                "appearanceStride": HAIR_STRIDE,
            },
            "footPointContractChanged": False,
        },
        "worldHelmet": {
            "visible": False,
            "frontLayerVisible": False,
            "backLayerVisible": False,
            "headOcclusionMaskEnabled": False,
            "runAssetsGenerated": False,
            "presentationScopesPreserved": ["paper_doll", "inventory", "ground"],
        },
        "coverage": {
            "maleDressItems": len(dress_items),
            "maleDressFeaturesIncludingBase": sorted({0, *[int(item["sourceFeature"]) for item in dress_items]}),
            "maleWeaponItemsMapped": len(weapon_items),
            "maleWeaponFeaturesMapped": len(weapon_features),
            "unresolvedWeaponItemIds": sorted(unresolved_ids),
            "maleHairBlock": HAIR_SOURCE_BLOCK,
            "actionsPerItem": 2,
            "directionsPerAction": 8,
            "framesPerDirection": int(ACTION["frames"]),
            "femaleItems": 0,
            "helmetRunAtlases": 0,
        },
        "contracts": {
            "catalog": resource_path(CATALOG),
            "dress": resource_path(DRESS_CONTRACT),
            "weapon": resource_path(WEAPON_CONTRACT),
            "existingHairPolicy": resource_path(HAIR_POLICY),
        },
        "baseBodyAppearance": base_body,
        "itemsById": items_by_id,
        "hairAppearance": {
            "sex": "male",
            "appearance": HAIR_APPEARANCE,
            "sourceBlock": HAIR_SOURCE_BLOCK,
            "sourceContract": resource_path(HAIR_POLICY) + "#/hairAppearance",
            "actions": {
                "walk": {
                    **layer_action_ref(
                        hair_walk,
                        "hair",
                        HAIR_SOURCE_BLOCK,
                        "walk",
                        "Hair.wil",
                    ),
                    "sourceIndexBase": HAIR_SOURCE_BLOCK * HAIR_STRIDE,
                    "sourceIndexRule": "sourceBlock*600 + actionStart + directionRow*8 + frame",
                },
                ACTION_NAME: {
                    **layer_action_ref(
                        hair_run,
                        "hair",
                        HAIR_SOURCE_BLOCK,
                        ACTION_NAME,
                        "Hair.wil",
                    ),
                    "sourceIndexBase": HAIR_SOURCE_BLOCK * HAIR_STRIDE,
                    "sourceIndexRule": "sourceBlock*600 + actionStart + directionRow*8 + frame",
                },
            },
        },
    }
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(
        "EQUIPMENT_MALE_RUN_WORLD_WEAR_PASS "
        f"dress_items={len(dress_items)} dress_features={len(payload['coverage']['maleDressFeaturesIncludingBase'])} "
        f"weapon_items={len(weapon_items)} weapon_features={len(weapon_features)} "
        f"hair_block={HAIR_SOURCE_BLOCK} action={ACTION_NAME} start={ACTION['start']} frames={ACTION['frames']} "
        "female=0 helmet_run=0 unresolved=111"
    )


if __name__ == "__main__":
    main()
