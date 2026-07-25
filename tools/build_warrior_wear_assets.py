#!/usr/bin/env python3
"""Build male-warrior Hum/Weapon action atlases from Shape candidates."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
SOURCE_CSV = ROOT / "dev_art_sources/reference/mir2_database/angelk727/2_物品数据.csv"
CATALOG = ROOT / "assets/data/legend176_data.json"
SERVICE_CATALOG = ROOT / "assets/data/service_item_catalog.json"
SOURCE_POLICY = ROOT / "assets/data/source_priority_policy.json"
OUTPUT = ROOT / "assets/art/characters/warrior/wear"
MANIFEST = ROOT / "assets/data/warrior_wear_sources.json"
PRIMARY_WEAPON_COMPATIBILITY = (
    ROOT / "assets/data/equipment_primary_weapon_compatibility.json"
)
FORMAL_VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


BODY_CELL = (192, 160)
BODY_FOOT_ANCHOR = (64, 80)
# Weapon.wil attacks extend as far as y=-109 relative to the classic actor
# origin.  The former 160px-high body cell started at y=-80 and silently
# cropped long weapons in W/NW/SE attack frames.  Weapons keep the same actor
# origin but receive an independent cell large enough for every mapped frame.
WEAPON_CELL = (192, 224)
WEAPON_FOOT_ANCHOR = (68, 112)
LAYOUTS = {
    "dressAppearance": {"cell": BODY_CELL, "foot_anchor": BODY_FOOT_ANCHOR},
    "weaponAppearance": {"cell": WEAPON_CELL, "foot_anchor": WEAPON_FOOT_ANCHOR},
}
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
# The imported CSV is only a candidate data source.  Its Judgement Staff entry
# uses the wrong Shape (21, the thin staff block).  Classic Weapon.wil tables
# map 裁决之杖 to Shape 24; male feature is Shape * 2 = 48.
CLASSIC_SHAPE_OVERRIDES = {
    "裁决之杖": 24,
}
# Immutable EQUIPMENT-WEAR-1 acceptance baseline from the integration tree.
# New source snapshots may fill rejected gaps, but must never silently remap
# these 24 names or regenerate them under different Weapon/Hum features.
ACCEPTED_BASELINE_SHAPES = {
    "木剑": 0, "匕首": 1, "乌木剑": 0, "青铜剑": 2, "短剑": 3,
    "铁剑": 2, "青铜斧": 4, "八荒": 5, "凌风": 8, "破魂": 12,
    "斩马刀": 9, "修罗": 14, "凝霜": 15, "炼狱": 16, "井中月": 19,
    "裁决之杖": 24, "屠龙": 26, "命运之刃": 29, "赤血魔剑": 25,
    "祈祷之刃": 13, "布衣(男)": 1, "轻型盔甲(男)": 2,
    "重盔甲(男)": 3, "战神盔甲(男)": 3,
}
# These records were absent or unusable when EQUIPMENT-WEAR-1 was accepted.
# The complete item scan subsequently found three matching records in the
# authorized primary server distribution.  Only use that primary source to
# revisit the original gaps; never replace the 24 already accepted mappings.
PRIMARY_GAP_NAMES = {"鹤嘴锄", "怒斩", "中型盔甲(男)"}
FEMALE_ONLY_ARMOR = {"圣战宝甲"}
USER_CONFIRMED_PRIMARY_WEAPONS = {"屠龙", "命运之刃"}
PRIMARY_UNRESOLVED_WEAPONS = {"落魄神兵"}


def sync_primary_weapon_runtime_bridge() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    compatibility = json.loads(
        PRIMARY_WEAPON_COMPATIBILITY.read_text(encoding="utf-8")
    )
    formal_catalog = json.loads(
        FORMAL_VISUAL_CATALOG.read_text(encoding="utf-8")
    )
    mappings = manifest.get("runtimeMappings", {})
    formal_mappings = formal_catalog.get("runtimeMappings", {})
    items_by_id = compatibility.get("itemsById", {})

    dragon_record = items_by_id.get("108", {})
    dragon_mapping = formal_mappings.get("屠龙", {})
    if (
        dragon_record.get("mappingType")
        != "user_confirmed_semantic_primary_weapon_feature"
        or int(dragon_record.get("maleFeature", -1)) != 52
        or int(dragon_mapping.get("weaponAppearance", {}).get(
            "feature",
            -1,
        )) != 52
    ):
        raise ValueError("formal primary 屠龙 feature 52 mapping is missing")
    mappings["屠龙"] = dragon_mapping

    destiny_record = items_by_id.get("110", {})
    destiny_mapping = formal_mappings.get("命运之刃", {})
    if (
        destiny_record.get("mappingType")
        != "user_confirmed_semantic_primary_weapon_feature"
        or int(destiny_record.get("maleFeature", -1)) != 58
        or int(destiny_mapping.get("weaponAppearance", {}).get(
            "feature",
            -1,
        )) != 58
    ):
        raise ValueError("formal primary 命运之刃 feature 58 mapping is missing")
    mappings["命运之刃"] = destiny_mapping

    rejected = [
        value
        for value in manifest.get("rejectedMappings", [])
        if value.get("name") not in {"命运之刃", "落魄神兵"}
    ]
    rejected.append({
        "name": "落魄神兵",
        "reason": (
            "primary compatibility contract has no evidence-backed "
            "Weapon feature; runtime layer must remain hidden"
        ),
        "compatibilityRef": (
            "res://assets/data/"
            "equipment_primary_weapon_compatibility.json#/itemsById/111"
        ),
    })
    manifest["runtimeMappings"] = mappings
    manifest["rejectedMappings"] = rejected
    manifest["primaryWeaponCompatibilityBridge"] = {
        "source": (
            "res://assets/data/"
            "equipment_primary_weapon_compatibility.json"
        ),
        "formalCatalog": (
            "res://assets/data/equipment_visual_catalog.json"
        ),
        "policy": (
            "primary formal weapon mappings override the legacy warrior "
            "candidate table for the explicitly affected names"
        ),
        "synced": {
            "屠龙": {
                "itemId": 108,
                "maleFeature": 52,
                "mappingType": (
                    "user_confirmed_semantic_primary_weapon_feature"
                ),
            },
            "命运之刃": {
                "itemId": 110,
                "maleFeature": 58,
                "mappingType": (
                    "user_confirmed_semantic_primary_weapon_feature"
                ),
            },
        },
        "removedUnresolved": ["落魄神兵"],
    }
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "WARRIOR_WEAR_PRIMARY_WEAPON_SYNC_PASS "
        "屠龙=feature52 命运之刃=feature58 落魄神兵=unresolved"
    )


def source_rows() -> dict[str, dict]:
    with SOURCE_CSV.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    result = {}
    for row in rows:
        name = str(row.get("ItemName", ""))
        if name and name not in result:
            result[name] = row
    return result


def primary_service_rows() -> tuple[str, dict[str, dict]]:
    policy = json.loads(SOURCE_POLICY.read_text(encoding="utf-8"))
    server_sources = policy.get("lanes", {}).get("server_data", {}).get("sources", [])
    if not server_sources or server_sources[0].get("tier") != "primary":
        raise ValueError("server_data primary source is not configured")
    primary_distribution = str(server_sources[0].get("distribution", ""))
    catalog = json.loads(SERVICE_CATALOG.read_text(encoding="utf-8"))
    rows = {}
    for record in catalog.get("serviceEquipmentReference", []):
        if record.get("source", {}).get("distribution") != primary_distribution:
            continue
        name = str(record.get("name", ""))
        if name and name not in rows:
            rows[name] = record
    return primary_distribution, rows


def weapon_tip_offset(image: Image.Image, meta: dict) -> list[int]:
    """Return the centroid of the distal opaque weapon-head pixels."""
    rgba = image.convert("RGBA")
    points = [
        (x + int(meta["x"]), y + int(meta["y"]))
        for y in range(rgba.height)
        for x in range(rgba.width)
        if rgba.getpixel((x, y))[3] > 32
    ]
    if not points:
        return [0, 0]
    max_distance = max(x * x + y * y for x, y in points)
    distal = [(x, y) for x, y in points if x * x + y * y >= max_distance * 0.85]
    return [round(sum(x for x, _ in distal) / len(distal)), round(sum(y for _, y in distal) / len(distal))]


def build_action(library: Path, feature: int, action: str, target: Path, appearance_type: str) -> dict:
    data, palette, offsets, info = read_library(library)
    spec = ACTIONS[action]
    frame_count = int(spec["frames"])
    layout = LAYOUTS[appearance_type]
    cell = layout["cell"]
    foot_anchor = layout["foot_anchor"]
    atlas = Image.new("RGBA", (cell[0] * frame_count, cell[1] * 8), (0, 0, 0, 0))
    frames, missing = [], []
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
            local_x = foot_anchor[0] + meta["x"]
            local_y = foot_anchor[1] + meta["y"]
            if local_x < 0 or local_y < 0 or local_x + image.width > cell[0] or local_y + image.height > cell[1]:
                raise RuntimeError(
                    f"{appearance_type} feature={feature} {action} direction={direction} frame={frame} "
                    f"does not fit cell={cell} anchor={foot_anchor}: "
                    f"offset=({meta['x']},{meta['y']}) size={image.size}"
                )
            paste = (frame * cell[0] + local_x, direction * cell[1] + local_y)
            atlas.alpha_composite(image.convert("RGBA"), paste)
            frame_record = {
                "index": index,
                "direction": direction,
                "frame": frame,
                "drawOffset": [meta["x"], meta["y"]],
                "sourceSize": [image.width, image.height],
            }
            if appearance_type == "weaponAppearance" and action == "attack":
                frame_record["weaponTipOffset"] = weapon_tip_offset(image, meta)
            frames.append(frame_record)
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(target)
    return {
        "path": f"res://{target.relative_to(ROOT).as_posix()}",
        "cell": list(cell),
        "footAnchor": list(foot_anchor),
        "directions": 8,
        "framesPerDirection": frame_count,
        "sourceFeature": feature,
        "sourceFrames": frames,
        "missingFrames": missing,
        "libraryImageCount": info["image_count"],
        "confidence": "A",
    }


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")).get("items", [])
    candidates = source_rows()
    primary_distribution, primary_rows = primary_service_rows()
    primary_compatibility = json.loads(
        PRIMARY_WEAPON_COMPATIBILITY.read_text(encoding="utf-8")
    )
    formal_weapon_mappings = json.loads(
        FORMAL_VISUAL_CATALOG.read_text(encoding="utf-8")
    ).get("runtimeMappings", {})
    primary_items_by_name = {
        str(value.get("itemName", "")): value
        for value in primary_compatibility.get("itemsById", {}).values()
    }
    target_names = {
        str(item.get("name", "")): item
        for item in catalog
        if item.get("category") in ["武器", "盔甲"] and item.get("profession") in ["通用", "战士"]
        and not (item.get("category") == "盔甲" and "(女)" in str(item.get("name", "")))
    }
    libraries = {
        "weaponAppearance": CLIENT_DATA / "Weapon.wil",
        "dressAppearance": CLIENT_DATA / "Hum.wil",
    }
    decoded = {key: read_library(path) for key, path in libraries.items()}
    max_features = {key: len(value[2]) // 600 for key, value in decoded.items()}
    del decoded

    mappings, rejected = {}, []
    atlas_cache = {}
    for name, item in target_names.items():
        if name in FEMALE_ONLY_ARMOR:
            rejected.append({"name": name, "reason": "女性角色不在当前开发范围"})
            continue
        if (
            item.get("category") == "武器"
            and name in PRIMARY_UNRESOLVED_WEAPONS
        ):
            rejected.append({
                "name": name,
                "reason": (
                    "primary compatibility contract is unresolved; "
                    "do not adopt a lower-tier Shape"
                ),
            })
            continue
        if (
            item.get("category") == "武器"
            and name in USER_CONFIRMED_PRIMARY_WEAPONS
        ):
            compatibility_record = primary_items_by_name.get(name, {})
            formal_mapping = formal_weapon_mappings.get(name, {})
            expected_feature = ACCEPTED_BASELINE_SHAPES[name] * 2
            if (
                compatibility_record.get("mappingType")
                != "user_confirmed_semantic_primary_weapon_feature"
                or int(compatibility_record.get("maleFeature", -1))
                != expected_feature
                or int(formal_mapping.get("weaponAppearance", {}).get(
                    "feature",
                    -1,
                )) != expected_feature
            ):
                raise ValueError(
                    f"{name} formal primary semantic mapping changed"
                )
            mappings[name] = formal_mapping
            continue
        primary_row = primary_rows.get(name) if name in PRIMARY_GAP_NAMES else None
        row = candidates.get(name)
        if primary_row is not None:
            shape = int(primary_row["shape"])
            mapping_source = (
                f"{primary_distribution} Server.MirDB "
                f"ItemInfo[{int(primary_row['serviceIndex'])}]"
            )
            mapping_confidence = "B"
        elif row is not None and str(row.get("ItemShape", "")).isdigit():
            shape = CLASSIC_SHAPE_OVERRIDES.get(name, int(row["ItemShape"]))
            mapping_source = (
                "经典 Weapon.wil 外观表：裁决之杖 Shape 24（覆盖候选CSV Shape 21）"
                if name in CLASSIC_SHAPE_OVERRIDES
                else "angelk727/Mir2ServerDatabases Exports/2_物品数据.csv"
            )
            mapping_confidence = "B"
        else:
            rejected.append({"name": name, "reason": "候选数据库无同名Shape"})
            continue
        if name in ACCEPTED_BASELINE_SHAPES and shape != ACCEPTED_BASELINE_SHAPES[name]:
            raise ValueError(
                f"accepted male-warrior baseline changed: {name} "
                f"expected Shape {ACCEPTED_BASELINE_SHAPES[name]}, got {shape}"
            )
        appearance_type = "weaponAppearance" if item.get("category") == "武器" else "dressAppearance"
        # This task targets the current male warrior; classic server feature = Shape*2 + gender(0).
        feature = shape * 2
        if feature >= max_features[appearance_type]:
            rejected.append({"name": name, "shape": shape, "feature": feature, "reason": "候选Shape超出当前客户端库容量"})
            continue
        if appearance_type == "weaponAppearance" and feature < 2:
            mappings[name] = {
                appearance_type: {
                    "shape": shape,
                    "feature": feature,
                    "visible": False,
                    "actions": {},
                    "mappingConfidence": mapping_confidence,
                    "mappingSource": mapping_source,
                    "runtimeRule": "经典客户端m_btWeapon<2不绘制武器层",
                }
            }
            continue
        cache_key = (appearance_type, feature)
        if cache_key not in atlas_cache:
            actions = {}
            library = libraries[appearance_type]
            prefix = "weapon" if appearance_type == "weaponAppearance" else "dress"
            for action in ACTIONS:
                target = OUTPUT / prefix / f"{prefix}_{feature:03d}_{action}.png"
                actions[action] = build_action(library, feature, action, target, appearance_type)
            atlas_cache[cache_key] = actions
        mappings[name] = {
            appearance_type: {
                "shape": shape,
                "feature": feature,
                "visible": True,
                "actions": atlas_cache[cache_key],
                "mappingConfidence": mapping_confidence,
                "mappingSource": mapping_source,
                "clientSource": f"dev_art_sources/reference/mir2_client_raw/Data/{libraries[appearance_type].name}",
            }
        }

    missing_baseline = [name for name in ACCEPTED_BASELINE_SHAPES if name not in mappings]
    if missing_baseline:
        raise ValueError(f"accepted male-warrior mappings disappeared: {missing_baseline}")
    ordered_mappings = {name: mappings[name] for name in ACCEPTED_BASELINE_SHAPES}
    ordered_mappings.update({name: value for name, value in mappings.items() if name not in ordered_mappings})

    payload = {
        "schemaVersion": 2,
        "target": "当前男性战士",
        "formulaEvidence": {
            "server": "M2Server/ObjBase.pas GetFeature: Shape*2+gender",
            "client": "Client/Actor.pas HUMANFRAME=600 and HA action table",
            "confidence": "A",
        },
        "shapeCandidateSource": {
            "repository": "https://github.com/angelk727/Mir2ServerDatabases",
            "path": "Exports/2_物品数据.csv",
            "confidence": "B",
            "reason": "非2003官服StdItems；仅在名称匹配且客户端容量有效时采用",
        },
        "primaryGapShapeSource": {
            "distributionId": primary_distribution,
            "catalog": "res://assets/data/service_item_catalog.json",
            "scope": sorted(PRIMARY_GAP_NAMES),
            "confidence": "B",
            "reason": "只补EQUIPMENT-WEAR-1拒绝项；不覆盖24条已验收男战士映射，也不声明等同官服1.76",
        },
        "sourcePolicy": {
            "lane": "client_assets",
            "distributionId": "client.classic_raw_complete",
            "priority": 100,
            "role": "primary",
        },
        "actionLayouts": {
            "dressAppearance": {"cell": list(BODY_CELL), "footAnchor": list(BODY_FOOT_ANCHOR)},
            "weaponAppearance": {"cell": list(WEAPON_CELL), "footAnchor": list(WEAPON_FOOT_ANCHOR)},
            "blockFrames": 600,
            "actions": ACTIONS,
        },
        "runtimeMappings": ordered_mappings,
        "rejectedMappings": rejected,
        "generatedAtlases": len(atlas_cache) * len(ACTIONS),
        "policy": "帧公式和客户端像素为A；逐件Shape为B。越界、缺名或不兼容值拒绝运行，不猜测替换。",
        "primaryWeaponCompatibilityBridge": {
            "source": (
                "res://assets/data/"
                "equipment_primary_weapon_compatibility.json"
            ),
            "formalCatalog": (
                "res://assets/data/equipment_visual_catalog.json"
            ),
            "userConfirmedSemanticWeapons": {
                name: {
                    "feature": ACCEPTED_BASELINE_SHAPES[name] * 2,
                    "lowerTierShapeAdopted": False,
                }
                for name in sorted(USER_CONFIRMED_PRIMARY_WEAPONS)
            },
            "unresolvedWeapons": sorted(PRIMARY_UNRESOLVED_WEAPONS),
        },
    }
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WARRIOR_WEAR_MAPPINGS={len(mappings)} REJECTED={len(rejected)} ATLASES={payload['generatedAtlases']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sync-primary-weapons-only",
        action="store_true",
        help=(
            "Update only the affected legacy runtime weapon entries from "
            "the formal primary contracts"
        ),
    )
    arguments = parser.parse_args()
    if arguments.sync_primary_weapons_only:
        sync_primary_weapon_runtime_bridge()
    else:
        main()
