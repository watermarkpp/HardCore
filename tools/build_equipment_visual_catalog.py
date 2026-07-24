#!/usr/bin/env python3
"""Build the data-driven visual catalog for every formal wearable item.

The nine developer profiles are acceptance samples only. This builder walks
the complete immutable vanilla equipment directory and records icon,
paper-doll and world-wear policy by stable item_id. World atlases are decoded
from the classic client except for the explicitly contracted male helmet
extension, whose generated atlases retain their source and Hair-anchor
provenance. Every other absent client layer remains explicitly unresolved.
"""

from __future__ import annotations

import csv
import hashlib
import json
import struct
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
CLASSIC_STD_ITEMS = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "mylgd_mir2server_176/Mud2/DB/StdItems.DB"
)
CLIENT_DATA = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
MALE_WORLD_HELMET = ROOT / "assets/data/equipment_male_world_helmet.json"
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

# This is a visual taxonomy, not an equip/profession restriction.  The shape
# groups are manually audited against the first male idle/attack pixels in
# Weapon.wil.  For Shape 1..24 the original_gameofmir Client/Actor.pas attack
# sound groups are only auxiliary material/impact evidence, not silhouette
# authority; Shape 25..33 are cross-checked through StdItems Shape/Looks and
# StateItem identity instead.  In particular, Shape 24 is the Judgement staff,
# Shape 25 is the Dragon Sword, and Shape 11 is the Purgatory axe.
CLASSIC_WEAPON_VISUAL_CLASSES_BY_SHAPE = {
    1: "sword",
    2: "sword",
    3: "axe",
    4: "sword",
    5: "sword",
    6: "dagger",
    7: "axe",
    8: "staff",
    9: "sword",
    10: "blade",
    11: "axe",
    12: "staff",
    13: "sword",
    14: "sword",
    15: "blade",
    16: "blade",
    17: "blade",
    18: "staff",
    19: "pickaxe",
    20: "dagger",
    21: "staff",
    22: "sword",
    23: "blade",
    24: "staff",
    25: "sword",
    26: "blade",
    27: "staff",
    28: "staff",
    29: "blade",
    30: "sword",
    31: "sword",
    32: "axe",
    33: "fan",
}
VISUAL_WEAPON_CLASS_PROFILES = {
    "sword": {
        "profileId": "weapon.hold.sword.source_hot.v1",
        "semantic": "sword-shaped one-handed or long sword silhouette",
    },
    "dagger": {
        "profileId": "weapon.hold.dagger.source_hot.v1",
        "semantic": "short blade or short paired-prong silhouette",
    },
    "axe": {
        "profileId": "weapon.hold.axe.source_hot.v1",
        "semantic": "axe or heavy cleaving-head silhouette",
    },
    "blade": {
        "profileId": "weapon.hold.blade.source_hot.v1",
        "semantic": "broad, curved or single-edged blade silhouette",
    },
    "staff": {
        "profileId": "weapon.hold.staff.source_hot.v1",
        "semantic": (
            "long-handled family including staff, wand, rod and "
            "hooked polearm silhouettes"
        ),
    },
    "pickaxe": {
        "profileId": "weapon.hold.pickaxe.source_hot.v1",
        "semantic": "mining pick silhouette",
    },
    "fan": {
        "profileId": "weapon.hold.fan.source_hot.v1",
        "semantic": "folding fan silhouette",
    },
}
USER_ORIGINAL_GAME_WORLD_EVIDENCE = {
    "木剑",
    "乌木剑",
    "罗刹",
    "嗜魂法杖",
    "屠龙",
}

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


def _decode_paradox_int(raw: bytes) -> int | None:
    value = struct.unpack(">i", raw)[0]
    if value == 0:
        return None
    complement = 1 << 31
    return value + complement if value < 0 else value - complement


def read_classic_weapon_rows() -> tuple[dict[str, dict], dict]:
    """Read weapon identity/Shape rows from the selected 1.76 Paradox table."""
    payload = CLASSIC_STD_ITEMS.read_bytes()
    if len(payload) < 4096:
        raise ValueError("classic StdItems.DB is truncated")
    header_size = struct.unpack(">H", payload[2:4])[0] * 1024 // 4
    block_size = int(payload[5]) * 1024
    field_count = int(payload[33])
    header = payload[:header_size]
    # The distributed table was exported through a temporary BDE table and
    # retains this internal name even though its selected path is StdItems.DB.
    internal_name = b"resttemp.DB"
    filename_offset = header.find(internal_name)
    if filename_offset < 0:
        raise ValueError("StdItems.DB header lacks the expected BDE table name")
    definitions = header[120:]
    names = (
        header[filename_offset + len(internal_name):]
        .strip(b"\x00")
        .split(b"\x00")[:field_count]
    )
    fields = [
        {
            "name": names[index].decode("ascii"),
            "type": int(definitions[index * 2]),
            "size": int(definitions[index * 2 + 1]),
        }
        for index in range(field_count)
    ]
    expected_prefix = ["Idx", "Name", "Stdmode", "Shape"]
    if [field["name"] for field in fields[:4]] != expected_prefix:
        raise ValueError("StdItems.DB field layout does not match the 1.76 schema")
    if any(field["type"] not in {1, 3, 4} for field in fields):
        raise ValueError("StdItems.DB contains an unsupported Paradox field type")

    record_size = sum(int(field["size"]) for field in fields)
    rows: list[dict] = []
    previous_record: bytes | None = None
    block_count = (len(payload) - header_size) // block_size
    for block_index in range(block_count):
        block_start = header_size + block_index * block_size
        block_header = payload[block_start:block_start + 6]
        offset = block_start + 6
        block_end = min(len(payload), block_start + block_size)
        while offset + record_size <= block_end:
            record = payload[offset:offset + record_size]
            offset += record_size
            if not record.strip(b"\x00"):
                break
            if record == previous_record:
                continue
            previous_record = record
            row: dict = {}
            cursor = 0
            for field in fields:
                size = int(field["size"])
                raw = record[cursor:cursor + size]
                cursor += size
                if int(field["type"]) == 1:
                    row[str(field["name"])] = raw.rstrip(b"\x00").decode(
                        "gbk",
                        errors="strict",
                    )
                elif int(field["type"]) == 4:
                    row[str(field["name"])] = _decode_paradox_int(raw)
                else:
                    row[str(field["name"])] = struct.unpack(">h", raw)[0]
            rows.append(row)
        if (
            len(block_header) == 6
            and struct.unpack(">H", block_header[:2])[0] == 0
        ):
            break

    weapons = {
        str(row["Name"]): row
        for row in rows
        if int(row.get("Stdmode") or -1) in {5, 6}
    }
    if len(weapons) < 35:
        raise ValueError(
            f"classic StdItems.DB exposed only {len(weapons)} weapon rows"
        )
    return weapons, {
        "path": (
            "dev_art_sources/reference/mir2_database_candidates/"
            "mylgd_mir2server_176/Mud2/DB/StdItems.DB"
        ),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "fieldCount": field_count,
        "recordSize": record_size,
        "decodedRowCount": len(rows),
        "weaponRowCount": len(weapons),
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
    classic_weapon_rows: dict[str, dict],
    classic_weapon_source: dict,
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
    if category == "武器":
        classic_row = classic_weapon_rows.get(name)
        if classic_row is not None:
            evidence = {
                "confidence": "A",
                "source": (
                    f"{classic_weapon_source['path']} "
                    f"row Idx={int(classic_row['Idx'])} Name={name}"
                ),
                "sourceSha256": str(classic_weapon_source["sha256"]),
                "stdMode": int(classic_row["Stdmode"]),
                "looks": int(classic_row["Looks"]),
                "rule": (
                    "original_gameofmir/M2Server/ObjBase.pas: "
                    "male feature = StdItems.Shape * 2"
                ),
            }
            if name in USER_ORIGINAL_GAME_WORLD_EVIDENCE:
                evidence["userEvidence"] = (
                    "user original-game experience confirms a visible "
                    "world weapon; technical Shape/Feature remains sourced "
                    "from the selected 1.76 StdItems.DB and Weapon.wil"
                )
            return int(classic_row["Shape"]), evidence
        return None, {
            "confidence": "none",
            "source": classic_weapon_source["path"],
            "sourceSha256": classic_weapon_source["sha256"],
            "reason": (
                "item name is absent from the selected 1.76 StdItems.DB; "
                "do not infer a world Shape from its name or slot icon"
            ),
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


def weapon_visual_class(shape: int) -> tuple[str, dict]:
    visual_class = CLASSIC_WEAPON_VISUAL_CLASSES_BY_SHAPE.get(shape)
    if visual_class is None:
        raise ValueError(
            f"classic Weapon.wil Shape {shape} lacks a visual class audit"
        )
    profile = VISUAL_WEAPON_CLASS_PROFILES[visual_class]
    source = (
        "Weapon.wil male idle/attack pixel silhouette + "
        "original_gameofmir/Client/Actor.pas Shape attack-sound group "
        "(auxiliary material/impact evidence only)"
        if shape <= 24
        else (
            "Weapon.wil male idle/attack pixel silhouette + "
            "StdItems Shape/Looks and StateItem identity cross-check"
        )
    )
    return visual_class, {
        "confidence": "manually_verified",
        "shape": shape,
        "maleFeature": shape * 2,
        "holdAnchorProfile": profile["profileId"],
        "holdAnchorRule": (
            "preserve each original Weapon.wil frame HotX/HotY; never "
            "select an anchor from profession"
        ),
        "source": source,
        "rule": (
            "visualWeaponClass selects silhouette/hold behavior only; "
            "profession remains an independent equip-rule field"
        ),
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
        CLASSIC_STD_ITEMS,
        MALE_WORLD_HELMET,
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
    helmet_contract = load_json(MALE_WORLD_HELMET)
    if helmet_contract.get("contractId") != (
        "equipment.world_helmet.male.extension.v1"
    ):
        raise AssertionError("male world helmet extension contract changed")
    helmet_items = helmet_contract.get("itemsById", {})
    if len(helmet_items) != 12:
        raise AssertionError("male world helmet extension must contain 12 items")
    source_rows = load_source_rows()
    classic_weapon_rows, classic_weapon_source = read_classic_weapon_rows()
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
        "classicWeaponShapeRows": 0,
        "visualWeaponClassAudited": 0,
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
                item,
                classic_weapon_rows,
                classic_weapon_source,
                source_rows,
                service_rows,
                distribution,
            )
            visual_weapon_class = ""
            visual_weapon_class_evidence: dict = {}
            if category == "武器":
                if shape is None:
                    visual_weapon_class = "unresolved"
                    visual_weapon_class_evidence = {
                        "confidence": "unresolved",
                        "source": str(evidence.get("source", "none")),
                        "reason": (
                            "world Shape is unresolved; visual class must not "
                            "be inferred from profession, name or slot icon"
                        ),
                    }
                else:
                    (
                        visual_weapon_class,
                        visual_weapon_class_evidence,
                    ) = weapon_visual_class(shape)
                    coverage["classicWeaponShapeRows"] += 1
                    coverage["visualWeaponClassAudited"] += 1
                entry["visualWeaponClass"] = visual_weapon_class
                entry["visualWeaponClassEvidence"] = (
                    visual_weapon_class_evidence
                )
                entry["weaponHoldAnchorProfile"] = (
                    visual_weapon_class_evidence.get(
                        "holdAnchorProfile",
                        "unresolved",
                    )
                )
            if shape is None:
                entry["worldWear"] = {
                    "status": "unresolved_no_placeholder",
                    "shapeEvidence": evidence,
                    "runtimePolicy": "keep exact profession world base and hide this item layer",
                }
                if category == "武器":
                    entry["worldWear"]["visualWeaponClass"] = (
                        visual_weapon_class
                    )
                coverage["unresolvedWorldShape"] += 1
            else:
                appearance_type = (
                    "weaponAppearance" if category == "武器" else "dressAppearance"
                )
                supported_genders = (
                    ("男",)
                    if category == "武器"
                    else (item_gender(name, category),)
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
                    if category == "武器":
                        appearances[gender]["visualWeaponClass"] = (
                            visual_weapon_class
                        )
                        appearances[gender]["holdAnchorProfile"] = (
                            visual_weapon_class_evidence[
                                "holdAnchorProfile"
                            ]
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
                    if category == "武器":
                        entry["worldWear"]["visualWeaponClass"] = (
                            visual_weapon_class
                        )
                        entry["worldWear"][
                            "visualWeaponClassEvidence"
                        ] = visual_weapon_class_evidence
                        entry["worldWear"]["holdAnchorProfile"] = (
                            visual_weapon_class_evidence[
                                "holdAnchorProfile"
                            ]
                        )
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
            helmet_item = helmet_items.get(item_id, {})
            if not helmet_item:
                raise ValueError(
                    f"formal helmet is absent from male extension: "
                    f"{item_id} {name}"
                )
            if (
                str(helmet_item.get("itemName", "")) != name
                or int(helmet_item.get("sourceIndex", -1))
                != int(entry["paperDoll"].get("sourceIndex", -2))
            ):
                raise ValueError(
                    f"male helmet identity evidence mismatch: {item_id} {name}"
                )
            helmet_appearance = helmet_item.get("maleAppearance", {})
            if (
                helmet_appearance.get("sex") != "male"
                or set(helmet_appearance.get("actions", {})) != set(ACTIONS)
                or helmet_appearance.get("actionFallbacks", {}) != {}
            ):
                raise ValueError(
                    f"male helmet action contract is incomplete: {item_id} {name}"
                )
            entry["worldWear"] = {
                "status": "approved_project_extension",
                "contractId": helmet_contract["contractId"],
                "identityId": str(helmet_item["identityId"]),
                "sourceIndex": int(helmet_item["sourceIndex"]),
                "helmetAppearance": helmet_appearance,
                "reason": (
                    "StateItem identifies the helmet only; transparent world "
                    "atlases are project-generated and anchored to same-frame "
                    "male Hair.wil head motion"
                ),
            }
            runtime_mappings[name] = {
                "helmetAppearance": helmet_appearance
            }
            coverage["exactMaleWorldWear"] += 1
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
            "classicWeaponShapeSource": classic_weapon_source,
            "classicWeaponShapeScope": (
                "version-matched classic appearance identity only "
                "(Shape/Looks); it does not replace profession, attributes, "
                "requirements, durability or other runtime item rules"
            ),
            "noPlaceholderRule": True,
            "maleWorldHelmetContract": resource_path(MALE_WORLD_HELMET),
            "professionVisualClassSeparation": (
                "profession controls equip eligibility; visualWeaponClass "
                "controls silhouette/hold behavior and is derived from "
                "StdItems.Shape plus Weapon.wil pixels"
            ),
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
        "visualWeaponClassTaxonomy": {
            "axis": (
                "independent from profession; selects silhouette and "
                "source-Hot hold-anchor profile"
            ),
            "classes": VISUAL_WEAPON_CLASS_PROFILES,
        },
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
