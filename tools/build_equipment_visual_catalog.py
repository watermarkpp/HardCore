#!/usr/bin/env python3
"""Build the data-driven visual catalog for every formal wearable item.

The nine developer profiles are acceptance samples only. This builder walks
the complete immutable vanilla equipment directory and records icon,
paper-doll and world-wear policy by stable item_id. World atlases are decoded
from the classic client; an absent client layer is recorded explicitly and is
never replaced by generated geometry.
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/data/vanilla_176/items.json"
CLIENT_ART = ROOT / "assets/data/equipment_client_art_sources.json"
PAPER_DOLL_SOURCE = ROOT / "assets/data/warrior_paper_doll_sources.json"
LOADOUTS = ROOT / "assets/data/equipment_test_loadouts.json"
SERVICE_CATALOG = ROOT / "assets/data/service_item_catalog.json"
SOURCE_POLICY = ROOT / "assets/data/source_priority_policy.json"
SOURCE_CSV = ROOT / "dev_art_sources/reference/mir2_database/angelk727/2_物品数据.csv"
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
OUTPUT = ROOT / "assets/art/items/client/world_wear"
MANIFEST = ROOT / "assets/data/equipment_visual_catalog.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


WEARABLE_CATEGORIES = {"武器", "盔甲", "头盔", "项链", "手镯", "戒指"}
VISUAL_CATEGORIES = {"武器", "盔甲", "头盔"}
GENDERS = ("男", "女")

BODY_CELL = (192, 160)
BODY_FOOT_ANCHOR = (64, 80)
# Full Weapon.wil audit across features 0..67 and the six formal actions gives
# source bounds x=-79..130, y=-116..88.  A 224px cell with this source anchor
# preserves every pixel while the runtime still aligns the classic actor
# origin through footAnchor; it does not alter the accepted world foot point.
WEAPON_CELL = (224, 224)
WEAPON_FOOT_ANCHOR = (80, 116)
LAYOUTS = {
    "dressAppearance": {"cell": BODY_CELL, "foot_anchor": BODY_FOOT_ANCHOR},
    "weaponAppearance": {"cell": WEAPON_CELL, "foot_anchor": WEAPON_FOOT_ANCHOR},
}
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

# Preserve the accepted warrior delivery: candidate/server Shape 21 points at
# a thin staff, while the classic Judgement Staff pixel block is Shape 24.
CLASSIC_WEAPON_SHAPE_OVERRIDES = {"裁决之杖": 24}

# Hum.wil contains exactly 18 HUMANFRAME blocks: Shape 0..8, interleaved
# male/female. StateItem 85..90 and the canonical six-armour order establish
# the final three pairs.
CLASSIC_LATE_ARMOR_SHAPES = {
    "天魔神甲": 6,
    "圣战宝甲": 6,
    "法神披风": 7,
    "霓裳羽衣": 7,
    "天尊道袍": 8,
    "天师长袍": 8,
}
EXPLICIT_ARMOR_GENDER = {
    "天魔神甲": "男",
    "圣战宝甲": "女",
    "法神披风": "男",
    "霓裳羽衣": "女",
    "天尊道袍": "男",
    "天师长袍": "女",
}

BLACK_IRON_HELMET_ACTIONS = {
    action: f"res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_{action}.png"
    for action in ("idle", "walk", "attack", "hit", "death")
}


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_source_rows() -> dict[str, dict]:
    with SOURCE_CSV.open("r", encoding="utf-8-sig", newline="") as handle:
        return {
            str(row.get("ItemName", "")): row
            for row in csv.DictReader(handle)
            if row.get("ItemName")
        }


def primary_service_rows() -> tuple[str, dict[str, dict]]:
    policy = load_json(SOURCE_POLICY)
    sources = policy.get("lanes", {}).get("server_data", {}).get("sources", [])
    if not sources or sources[0].get("tier") != "primary":
        raise ValueError("server_data primary source is not configured")
    distribution = str(sources[0].get("distribution", ""))
    records = load_json(SERVICE_CATALOG).get("serviceEquipmentReference", [])
    result: dict[str, dict] = {}
    for record in records:
        if record.get("source", {}).get("distribution") != distribution:
            continue
        name = str(record.get("name", ""))
        if name and name not in result:
            result[name] = record
    return distribution, result


def item_gender(name: str, category: str) -> str:
    if category != "盔甲":
        return "通用"
    if name in EXPLICIT_ARMOR_GENDER:
        return EXPLICIT_ARMOR_GENDER[name]
    if "(女)" in name:
        return "女"
    if "(男)" in name:
        return "男"
    return "通用"


def shape_for_item(
    item: dict,
    source_rows: dict[str, dict],
    service_rows: dict[str, dict],
    distribution: str,
) -> tuple[int | None, dict]:
    name = str(item["name"])
    category = str(item["category"])
    if category == "盔甲" and name in CLASSIC_LATE_ARMOR_SHAPES:
        return CLASSIC_LATE_ARMOR_SHAPES[name], {
            "confidence": "B",
            "source": "classic Hum.wil 18-block capacity + StateItem 85..90 canonical pair order",
            "rule": "feature = Shape*2 + gender",
        }
    if category == "武器" and name in CLASSIC_WEAPON_SHAPE_OVERRIDES:
        return CLASSIC_WEAPON_SHAPE_OVERRIDES[name], {
            "confidence": "manually_confirmed",
            "source": (
                "user-confirmed Judgement Staff Weapon.wil "
                "shape24 feature48"
            ),
            "rule": "feature = Shape*2 + gender",
        }
    service = service_rows.get(name)
    if service is not None and str(service.get("shape", "")).lstrip("-").isdigit():
        return int(service["shape"]), {
            "confidence": "B",
            "source": f"{distribution} Server.MirDB ItemInfo[{int(service['serviceIndex'])}]",
            "rule": "feature = Shape*2 + gender",
        }
    row = source_rows.get(name)
    value = str(row.get("ItemShape", "")) if row else ""
    if value.isdigit():
        return int(value), {
            "confidence": "B",
            "source": "angelk727/Mir2ServerDatabases Exports/2_物品数据.csv",
            "rule": "feature = Shape*2 + gender",
        }
    return None, {
        "confidence": "none",
        "source": "none",
        "reason": "no evidence-backed Shape in configured formal sources",
    }


def weapon_tip_offset(image: Image.Image, meta: dict) -> list[int]:
    rgba = image.convert("RGBA")
    points = [
        (x + int(meta["x"]), y + int(meta["y"]))
        for y in range(rgba.height)
        for x in range(rgba.width)
        if rgba.getpixel((x, y))[3] > 32
    ]
    if not points:
        return [0, 0]
    maximum = max(x * x + y * y for x, y in points)
    distal = [(x, y) for x, y in points if x * x + y * y >= maximum * 0.85]
    return [
        round(sum(x for x, _ in distal) / len(distal)),
        round(sum(y for _, y in distal) / len(distal)),
    ]


def build_action(
    decoded_library: tuple,
    feature: int,
    action: str,
    target: Path,
    appearance_type: str,
) -> dict:
    data, palette, offsets, info = decoded_library
    spec = ACTIONS[action]
    frame_count = int(spec["frames"])
    layout = LAYOUTS[appearance_type]
    cell = layout["cell"]
    anchor = layout["foot_anchor"]
    atlas = Image.new("RGBA", (cell[0] * frame_count, cell[1] * 8), (0, 0, 0, 0))
    frames: list[dict] = []
    missing: list[int] = []
    for direction in range(8):
        for frame in range(frame_count):
            within_block = int(spec["start"]) + direction * 8 + frame
            index = feature * 600 + within_block
            if index >= len(offsets):
                missing.append(index)
                continue
            try:
                image, meta = decode_sprite(data, offsets[index], palette)
            except ValueError:
                missing.append(index)
                continue
            local_x = anchor[0] + int(meta["x"])
            local_y = anchor[1] + int(meta["y"])
            if (
                local_x < 0
                or local_y < 0
                or local_x + image.width > cell[0]
                or local_y + image.height > cell[1]
            ):
                raise RuntimeError(
                    f"{appearance_type} feature={feature} {action} "
                    f"direction={direction} frame={frame} does not fit "
                    f"cell={cell} anchor={anchor}: offset=({meta['x']},{meta['y']}) "
                    f"size={image.size}"
                )
            atlas.alpha_composite(
                image.convert("RGBA"),
                (frame * cell[0] + local_x, direction * cell[1] + local_y),
            )
            record = {
                "index": index,
                "direction": direction,
                "frame": frame,
                "drawOffset": [int(meta["x"]), int(meta["y"])],
                "sourceSize": [image.width, image.height],
            }
            if appearance_type == "weaponAppearance" and action == "attack":
                record["weaponTipOffset"] = weapon_tip_offset(image, meta)
            frames.append(record)
    if missing:
        raise RuntimeError(
            f"{appearance_type} feature={feature} action={action} has missing frames: {missing}"
        )
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(target)
    result = {
        "path": resource_path(target),
        "cell": list(cell),
        "footAnchor": list(anchor),
        "directions": 8,
        "framesPerDirection": frame_count,
        "sourceFeature": feature,
        "decodedFrameCount": len(frames),
        "missingFrames": [],
        "libraryImageCount": int(info["image_count"]),
        "confidence": "A",
    }
    # Runtime only consumes per-frame metadata to align weapon-head effects.
    # Omitting redundant body/non-attack frame records keeps the startup JSON
    # compact without weakening build-time missing-frame validation.
    if appearance_type == "weaponAppearance" and action == "attack":
        result["sourceFrames"] = frames
    return result


def build_appearance(
    appearance_type: str,
    shape: int,
    gender: str,
    decoded_library: tuple,
    cache: dict[tuple[str, int], dict],
) -> dict:
    feature = shape * 2 + (1 if gender == "女" else 0)
    cache_key = (appearance_type, feature)
    if cache_key not in cache:
        prefix = "weapon" if appearance_type == "weaponAppearance" else "dress"
        actions: dict[str, dict] = {}
        for action in ACTIONS:
            target = (
                OUTPUT
                / prefix
                / ("female" if gender == "女" else "male")
                / f"{prefix}_{feature:03d}_{action}.png"
            )
            actions[action] = build_action(
                decoded_library, feature, action, target, appearance_type
            )
        cache[cache_key] = actions
    return {
        "shape": shape,
        "feature": feature,
        "gender": gender,
        "visible": True,
        "actions": cache[cache_key],
        "actionFallbacks": {},
    }


def paper_overlay(item: dict, icon_mapping: dict) -> dict:
    equipped = icon_mapping["equippedIcon"]
    raw_offset = [int(value) for value in equipped.get("drawOffset", [0, 0])]
    return {
        "status": "exact_client_record",
        "slot": "衣服" if item["category"] == "盔甲" else item["category"],
        "gender": item_gender(str(item["name"]), str(item["category"])),
        "sourceIndex": int(equipped["index"]),
        "path": str(equipped["path"]),
        "drawOffset": [raw_offset[0] - 7, raw_offset[1] + 44],
        "rawDrawOffset": raw_offset,
        "size": [int(value) for value in equipped.get("size", [0, 0])],
        "source": "stateitem.wil",
        "mappingConfidence": "A",
    }


def main() -> None:
    for source in (
        CATALOG,
        CLIENT_ART,
        PAPER_DOLL_SOURCE,
        LOADOUTS,
        SERVICE_CATALOG,
        SOURCE_POLICY,
        SOURCE_CSV,
        CLIENT_DATA / "Hum.wil",
        CLIENT_DATA / "Weapon.wil",
    ):
        if not source.exists():
            raise FileNotFoundError(f"missing visual-catalog input: {source}")

    formal_items = [
        item
        for item in load_json(CATALOG).get("records", [])
        if item.get("category") in WEARABLE_CATEGORIES
    ]
    icon_mappings = load_json(CLIENT_ART).get("runtimeMappings", {})
    paper_source = load_json(PAPER_DOLL_SOURCE)
    loadouts = load_json(LOADOUTS).get("loadouts", [])
    source_rows = load_source_rows()
    distribution, service_rows = primary_service_rows()
    libraries = {
        "dressAppearance": read_library(CLIENT_DATA / "Hum.wil"),
        "weaponAppearance": read_library(CLIENT_DATA / "Weapon.wil"),
    }
    max_features = {
        appearance_type: len(decoded[2]) // 600
        for appearance_type, decoded in libraries.items()
    }
    atlas_cache: dict[tuple[str, int], dict] = {}
    world_base_by_gender = {
        gender: build_appearance(
            "dressAppearance",
            0,
            gender,
            libraries["dressAppearance"],
            atlas_cache,
        )
        for gender in GENDERS
    }
    entries: dict[str, dict] = {}
    runtime_mappings: dict[str, dict] = {}

    coverage = {
        "formalWearables": len(formal_items),
        "exactInventoryIcons": 0,
        "exactEquippedIcons": 0,
        "exactGroundIcons": 0,
        "visualWearables": 0,
        "exactPaperDollOverlays": 0,
        "exactMaleWorldWear": 0,
        "exactFemaleWorldWear": 0,
        "explicitNoWorldLayer": 0,
        "unresolvedWorldShape": 0,
    }

    for item in formal_items:
        item_id = str(int(item["itemId"]))
        name = str(item["name"])
        category = str(item["category"])
        icons = icon_mappings.get(name)
        if not isinstance(icons, dict):
            raise ValueError(f"formal item lacks exact icon mapping: {item_id} {name}")
        for field, counter in (
            ("inventoryIcon", "exactInventoryIcons"),
            ("equippedIcon", "exactEquippedIcons"),
            ("groundIcon", "exactGroundIcons"),
        ):
            resource = icons.get(field, {})
            path = str(resource.get("path", "")) if isinstance(resource, dict) else ""
            if not path or not (ROOT / path.removeprefix("res://")).exists():
                raise ValueError(f"{item_id} {name} lacks {field} resource")
            coverage[counter] += 1

        slot = "衣服" if category == "盔甲" else category
        entry = {
            "itemId": int(item_id),
            "itemName": name,
            "profession": str(item.get("profession", "通用")),
            "category": category,
            "slot": slot,
            "gender": item_gender(name, category),
            "icons": {
                "inventory": icons["inventoryIcon"],
                "equippedSlot": icons["equippedIcon"],
                "ground": icons["groundIcon"],
            },
        }

        if category in VISUAL_CATEGORIES:
            coverage["visualWearables"] += 1
            entry["paperDoll"] = paper_overlay(item, icons)
            coverage["exactPaperDollOverlays"] += 1
        else:
            entry["paperDoll"] = {
                "status": "slot_icon_only",
                "reason": "classic client renders this accessory in its equipment slot, not as an actor overlay",
            }

        if category in {"武器", "盔甲"}:
            shape, evidence = shape_for_item(
                item, source_rows, service_rows, distribution
            )
            if shape is None:
                entry["worldWear"] = {
                    "status": "unresolved_no_placeholder",
                    "shapeEvidence": evidence,
                    "runtimePolicy": "keep exact profession world base and hide this item layer",
                }
                coverage["unresolvedWorldShape"] += 1
            elif category == "武器" and shape == 0:
                hidden_appearances = {
                    gender: {
                        "shape": shape,
                        "feature": shape * 2 + (1 if gender == "女" else 0),
                        "gender": gender,
                        "visible": False,
                        "actions": {},
                        "actionFallbacks": {},
                    }
                    for gender in GENDERS
                }
                entry["worldWear"] = {
                    "status": "classic_client_hidden_weapon",
                    "appearanceType": "weaponAppearance",
                    "shape": shape,
                    "shapeEvidence": evidence,
                    "appearancesByGender": hidden_appearances,
                    "actionFallbacks": {},
                    "runtimePolicy": "classic m_btWeapon<2: keep exact profession world base and draw no weapon layer",
                }
                runtime_mappings[name] = {
                    "weaponAppearance": hidden_appearances["男"],
                }
                coverage["explicitNoWorldLayer"] += 1
            else:
                appearance_type = (
                    "weaponAppearance" if category == "武器" else "dressAppearance"
                )
                supported_genders = (
                    GENDERS if category == "武器" else (item_gender(name, category),)
                )
                appearances: dict[str, dict] = {}
                rejected_genders: dict[str, dict] = {}
                for gender in supported_genders:
                    feature = shape * 2 + (1 if gender == "女" else 0)
                    if feature >= max_features[appearance_type]:
                        rejected_genders[gender] = {
                            "feature": feature,
                            "reason": "Shape exceeds configured classic client library capacity",
                        }
                        continue
                    appearances[gender] = build_appearance(
                        appearance_type,
                        shape,
                        gender,
                        libraries[appearance_type],
                        atlas_cache,
                    )
                    coverage[
                        "exactFemaleWorldWear"
                        if gender == "女"
                        else "exactMaleWorldWear"
                    ] += 1
                if appearances:
                    entry["worldWear"] = {
                        "status": "exact_client_animation",
                        "appearanceType": appearance_type,
                        "shape": shape,
                        "shapeEvidence": evidence,
                        "appearancesByGender": appearances,
                        "actionFallbacks": {},
                        "rejectedGenders": rejected_genders,
                    }
                    male = appearances.get("男")
                    if male is not None:
                        runtime_mappings[name] = {appearance_type: male}
                else:
                    entry["worldWear"] = {
                        "status": "unresolved_no_placeholder",
                        "shape": shape,
                        "shapeEvidence": evidence,
                        "rejectedGenders": rejected_genders,
                        "runtimePolicy": "keep exact profession world base and hide this item layer",
                    }
                    coverage["unresolvedWorldShape"] += 1
        elif category == "头盔":
            if name == "黑铁头盔":
                missing = [
                    path
                    for path in BLACK_IRON_HELMET_ACTIONS.values()
                    if not (ROOT / path.removeprefix("res://")).exists()
                ]
                if missing:
                    raise ValueError(f"black-iron world extension missing: {missing}")
                helmet_appearance = {
                    "visible": True,
                    "actions": {
                        action: {
                            "path": path,
                            "cell": list(BODY_CELL),
                            "footAnchor": list(BODY_FOOT_ANCHOR),
                            "directions": 8,
                            "framesPerDirection": int(
                                ACTIONS.get(action, ACTIONS["idle"])["frames"]
                            ),
                            "confidence": "project_approved_exact",
                        }
                        for action, path in BLACK_IRON_HELMET_ACTIONS.items()
                    },
                    "actionFallbacks": {"cast": "idle"},
                }
                entry["worldWear"] = {
                    "status": "approved_project_extension",
                    "helmetAppearance": helmet_appearance,
                    "reason": "classic actor does not draw item helmets; this existing extension is independently approved",
                }
                runtime_mappings[name] = {"helmetAppearance": helmet_appearance}
                coverage["exactMaleWorldWear"] += 1
            else:
                entry["worldWear"] = {
                    "status": "classic_client_no_world_layer",
                    "reason": "classic actor protocol has no evidence-backed item helmet Shape; StateItem is paper-doll art and must not be used as world animation",
                }
                coverage["explicitNoWorldLayer"] += 1
        else:
            entry["worldWear"] = {
                "status": "classic_client_no_world_layer",
                "reason": "accessory affects stats and equipment-slot icon only",
            }
            coverage["explicitNoWorldLayer"] += 1
        entries[item_id] = entry

    loadout_contracts: dict[str, dict] = {}
    for loadout in loadouts:
        visual_slots: dict[str, dict] = {}
        for slot in ("武器", "衣服", "头盔"):
            record = loadout.get("equipment", {}).get(slot, {})
            item_id = str(int(record.get("itemId", -1)))
            if item_id not in entries:
                raise ValueError(
                    f"loadout {loadout['loadoutId']} references absent visual item {item_id}"
                )
            visual_slots[slot] = {
                "itemId": int(item_id),
                "itemName": str(record.get("itemName", "")),
                "catalogEntry": item_id,
            }
        loadout_contracts[str(loadout["loadoutId"])] = {
            "profileId": str(loadout["profileId"]),
            "profession": str(loadout["profession"]),
            "gender": str(loadout["gender"]),
            "tierId": str(loadout["tierId"]),
            "visualSlots": visual_slots,
            "baseActionTemplate": "player.visual.classic_eight_direction.v1",
        }

    paper_base = paper_source.get("base", {})
    paper_hair = paper_source.get("hair", {})
    paper_composition = paper_source.get("composition", {})
    profession_names = {
        "warrior": "战士",
        "wizard": "法师",
        "taoist": "道士",
    }
    profession_manifests = {
        profession_id: {
            "professionId": profession_id,
            "professionName": profession_name,
            # Classic client paper-doll anatomy is shared. Profession identity
            # comes from the data-driven dress and weapon layers.
            "base": paper_base,
            "hair": paper_hair,
            "composition": paper_composition,
            "canvasSize": paper_composition.get("canvasSize", [168, 199]),
            "footAnchor": [84, 186],
            "paperDollFootAnchor": [84, 186],
            "worldActorSourceFootAnchor": list(BODY_FOOT_ANCHOR),
            "worldBaseByGender": world_base_by_gender,
            "actionTemplate": "player.visual.classic_eight_direction.v1",
            "paperDollItemIndex": "itemsById[*].paperDoll",
            "baseSharingPolicy": "classic_client_shared_human_base; profession is expressed by exact dress/weapon layers",
        }
        for profession_id, profession_name in profession_names.items()
    }

    payload = {
        "schemaVersion": 1,
        "contractId": "equipment.visual_catalog.formal_wearables.v1",
        "catalogSource": "res://assets/data/vanilla_176/items.json",
        "sourcePolicy": {
            "clientAssets": "client.classic_raw_complete",
            "serverShapeDistribution": distribution,
            "noPlaceholderRule": True,
        },
        "actorTemplate": {
            "contractId": "player.visual.classic_eight_direction.v1",
            "rule": "all three professions reuse the accepted warrior foot anchor, eight directions, action-state interface and equipment front/back sorting",
            "actions": ACTIONS,
            "blockFrames": 600,
            "dressLayout": {
                "cell": list(BODY_CELL),
                "footAnchor": list(BODY_FOOT_ANCHOR),
            },
            "weaponLayout": {
                "cell": list(WEAPON_CELL),
                "footAnchor": list(WEAPON_FOOT_ANCHOR),
            },
            "paperDollFootAnchor": [84, 186],
            "worldActorSourceFootAnchor": list(BODY_FOOT_ANCHOR),
        },
        "professionManifests": profession_manifests,
        "coverage": coverage,
        "itemsById": entries,
        "runtimeMappings": runtime_mappings,
        "loadoutVisualContracts": loadout_contracts,
        "generatedAtlases": len(atlas_cache) * len(ACTIONS),
    }
    MANIFEST.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    # Keep the item-id-first male dress contract synchronized with the
    # existing name-keyed runtime catalog. The contract revalidates every
    # atlas against Hum.wil and records every source-frame Hot coordinate.
    from build_male_dress_world_wear_contract import main as build_male_dress

    build_male_dress()
    from build_male_weapon_world_wear_contract import main as build_male_weapon

    build_male_weapon()
    print(
        "EQUIPMENT_VISUAL_CATALOG_PASS "
        f"formal={coverage['formalWearables']} "
        f"visual={coverage['visualWearables']} "
        f"paper={coverage['exactPaperDollOverlays']} "
        f"male_world={coverage['exactMaleWorldWear']} "
        f"female_world={coverage['exactFemaleWorldWear']} "
        f"unresolved={coverage['unresolvedWorldShape']} "
        f"atlases={payload['generatedAtlases']}"
    )


if __name__ == "__main__":
    main()
