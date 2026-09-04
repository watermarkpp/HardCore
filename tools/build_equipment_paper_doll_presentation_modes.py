#!/usr/bin/env python3
"""Build the player-facing paper-doll presentation-mode contract.

The accepted world-wear catalog remains the default avatar source.  The
classic client StateItem composition is retained as a transparent alternate,
while the complete Prguse #376 equipment panel is audit-only.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_POLICY = ROOT / "assets/data/source_priority_policy.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
CLASSIC_SOURCE = ROOT / "assets/data/warrior_paper_doll_sources.json"
CLASSIC_HEAD_PATCHES = (
    ROOT / "assets/data/equipment_classic_avatar_head_patches.json"
)
LEGACY_FULL_PANEL = (
    ROOT / "assets/data/equipment_original_client_paper_doll_stage.json"
)
OUTPUT = ROOT / "assets/data/equipment_paper_doll_presentation_modes.json"

CONTRACT_ID = "equipment.paper_doll.presentation_modes.v1"
WORLD_CONTRACT_ID = "equipment.paper_doll.world_avatar.v1"
CLASSIC_CONTRACT_ID = "equipment.paper_doll.avatar_only.v1"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def primary_distribution(policy: dict, lane_name: str) -> str:
    sources = policy.get("lanes", {}).get(lane_name, {}).get("sources", [])
    if not sources or sources[0].get("tier") != "primary":
        raise ValueError(f"{lane_name} primary source is not configured")
    return str(sources[0].get("distribution", ""))


def main() -> None:
    policy = load_json(SOURCE_POLICY)
    visual = load_json(VISUAL_CATALOG)
    classic = load_json(CLASSIC_SOURCE)
    classic_head_patches = load_json(CLASSIC_HEAD_PATCHES)
    legacy = load_json(LEGACY_FULL_PANEL)

    client_assets_primary = primary_distribution(policy, "client_assets")
    client_rules_primary = primary_distribution(policy, "client_rules")
    if visual.get("contractId") != "equipment.visual_catalog.formal_wearables.v1":
        raise ValueError("formal visual catalog contract changed")
    if legacy.get("contractId") != "equipment.paper_doll.original_client_stage.v1":
        raise ValueError("legacy full-panel contract changed")
    if (
        classic_head_patches.get("contractId")
        != "equipment.paper_doll.classic_flattened_head_patch.v1"
    ):
        raise ValueError("classic flattened head-patch contract changed")

    base = classic.get("base", {})
    hair = classic.get("hair", {})
    loadout_ids = sorted(visual.get("loadoutVisualContracts", {}).keys())
    if len(loadout_ids) != 9:
        raise ValueError("expected three professions x three equipment tiers")

    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "defaultMode": "world_avatar",
        "sex": "male",
        "sourcePolicy": {
            "clientAssetsLane": "client_assets",
            "clientAssetsPrimary": client_assets_primary,
            "clientRulesLane": "client_rules",
            "clientRulesPrimary": client_rules_primary,
            "visualCatalog": (
                "res://assets/data/equipment_visual_catalog.json"
            ),
            "classicSource": (
                "res://assets/data/warrior_paper_doll_sources.json"
            ),
            "legacyFullPanel": (
                "res://assets/data/"
                "equipment_original_client_paper_doll_stage.json"
            ),
            "fallbackUsed": False,
        },
        "modes": {
            "world_avatar": {
                "contractId": WORLD_CONTRACT_ID,
                "playerUiAllowed": True,
                "maleOnly": True,
                "transparentOnly": True,
                "sourceCatalog": (
                    "res://assets/data/equipment_visual_catalog.json"
                ),
                "canvasSize": [288, 224],
                "viewportOrigin": [0, 0],
                "viewportBounds": [0, 0, 288, 224],
                "footAnchor": [144, 116],
                "frameSelection": {
                    "action": "idle",
                    "direction": "S",
                    "directionIndex": 4,
                    "frame": 0,
                },
                "drawOrder": ["base", "dress", "weapon", "helmet"],
                "dressPolicy": "equipped_dress_replaces_base",
                "selectors": {
                    "profession": "professionManifests.{professionId}",
                    "base": (
                        "worldBaseByGender.* where gender=male; "
                        "actions.{action}"
                    ),
                    "equippedItem": "itemsById.{itemId}.worldWear",
                    "dress": (
                        "appearancesByGender.male.actions.{action}"
                    ),
                    "weapon": (
                        "appearancesByGender.male.actions.{action}"
                    ),
                    "helmet": "helmetAppearance.actions.{action}",
                },
                "layerLayouts": {
                    "base": {
                        "cell": [192, 160],
                        "sourceFootAnchor": [64, 80],
                        "stagePosition": [80, 36],
                    },
                    "dress": {
                        "cell": [192, 160],
                        "sourceFootAnchor": [64, 80],
                        "stagePosition": [80, 36],
                    },
                    "weapon": {
                        "cell": [224, 224],
                        "sourceFootAnchor": [80, 116],
                        "stagePosition": [64, 0],
                    },
                    "helmet": {
                        "cell": [192, 160],
                        "sourceFootAnchor": [64, 80],
                        "stagePosition": [80, 36],
                    },
                },
            },
            "classic_avatar": {
                "contractId": CLASSIC_CONTRACT_ID,
                "playerUiAllowed": True,
                "maleOnly": True,
                "transparentOnly": True,
                "avatarOnly": {
                    "contractId": CLASSIC_CONTRACT_ID,
                    "base": {
                        "source": "Prguse.wil",
                        "sourceIndex": int(base.get("sourceIndex", 376)),
                        "pairedBackgroundIndex": int(
                            base.get("pairedBackgroundIndex", 377)
                        ),
                        "path": str(base.get("path", "")),
                        "stagePosition": [0, 0],
                        "size": list(base.get("size", [168, 199])),
                        "recordPolicy": (
                            "transparent male anatomy isolated from the "
                            "primary Prguse #376/#377 pair"
                        ),
                    },
                    "hair": {
                        "source": "Prguse.wil",
                        "sourceIndex": int(hair.get("sourceIndex", 442)),
                        "path": str(hair.get("path", "")),
                        "stagePosition": list(
                            hair.get("drawOffset", [80, 44])
                        ),
                        "size": list(hair.get("size", [16, 14])),
                    },
                    "itemSelector": (
                        "res://assets/data/equipment_visual_catalog.json#/"
                        "itemsById/{itemId}/paperDoll"
                    ),
                    "headPatchSelector": (
                        "res://assets/data/"
                        "equipment_classic_avatar_head_patches.json#/"
                        "itemsById/{itemId}/flattenedHeadPatch"
                    ),
                    "stagePosition": [0, 0],
                    "canvasSize": [168, 199],
                    "viewportOrigin": [0, 0],
                    "viewportBounds": [0, 0, 168, 199],
                    "footAnchor": [84, 186],
                    "drawOrder": [
                        "base",
                        "dress",
                        "weapon",
                        "flattenedHeadPatch",
                    ],
                    "slotExclusionRects": [
                        [130, 33, 38, 43],
                        [130, 77, 38, 42],
                        [4, 119, 35, 43],
                        [129, 119, 39, 43],
                        [4, 163, 35, 36],
                        [129, 163, 39, 36],
                    ],
                    "consumerRule": (
                        "draw only transparent anatomy, hair and equipped "
                        "StateItem layers; never draw Prguse #376 full panel"
                    ),
                },
            },
        },
        "legacyFullPanel": {
            "contractId": "equipment.paper_doll.original_client_stage.v1",
            "path": (
                "res://assets/data/"
                "equipment_original_client_paper_doll_stage.json"
            ),
            "presentationRole": "legacy_audit_full_panel",
            "forbiddenForPlayerUI": True,
            "containsBackground": True,
            "containsEquipmentSlotFrames": True,
        },
        "validation": {
            "loadoutContractIds": loadout_ids,
            "professionIds": ["warrior", "wizard", "taoist"],
            "tierIds": ["wooma", "zuma", "chiyue"],
            "femaleAssetsGenerated": 0,
        },
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "EQUIPMENT_PAPER_DOLL_PRESENTATION_MODES_BUILD_PASS "
        f"default=world_avatar loadouts={len(loadout_ids)}"
    )


if __name__ == "__main__":
    main()
