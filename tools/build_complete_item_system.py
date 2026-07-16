#!/usr/bin/env python3
"""Build the complete runtime item catalog and exact inventory/ground pixels.

The item records always come from the primary Crystal server database.  Pixel
selection is primary-client first, then the authorized auxiliary client only
when the same frame is missing.  Category fallbacks are explicit and never
masquerade as original client art.
"""

from __future__ import annotations

import hashlib
import io
import json
import shutil
import struct
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

from vendor.extract_wil import decode_sprite, read_library


ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa/Server.MirDB"
PRIMARY = ROOT / "dev_art_sources/reference/mir2_client_raw/Data"
AUXILIARY = ROOT / "dev_art_sources/external/mir2opensource_full/Data"
OUTPUT = ROOT / "assets/art/items/service"
MANIFEST = ROOT / "assets/data/service_item_catalog.json"

TYPE_NAMES = {
    0: "Nothing", 1: "Weapon", 2: "Armour", 4: "Helmet", 5: "Necklace",
    6: "Bracelet", 7: "Ring", 8: "Amulet", 9: "Belt", 10: "Boots",
    11: "Stone", 12: "Torch", 13: "Potion", 14: "Ore", 15: "Meat",
    16: "CraftingMaterial", 17: "Scroll", 18: "Gem", 19: "Mount",
    20: "Book", 21: "Script", 22: "Reins", 23: "Bells", 24: "Saddle",
    25: "Ribbon", 26: "Mask", 27: "Food", 28: "Hook", 29: "Float",
    30: "Bait", 31: "Finder", 32: "Reel", 33: "Fish", 34: "Quest",
    35: "Awakening", 36: "Pets", 37: "Transform", 38: "Deco",
    39: "Socket", 40: "MonsterSpawn", 41: "SiegeAmmo", 42: "SealedHero",
}
EQUIPMENT_TYPES = {1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 19, 22, 23, 24, 25, 26, 28, 29, 30, 31, 32, 38, 39}
STAT_NAMES = {
    0: "MinAC", 1: "MaxAC", 2: "MinMAC", 3: "MaxMAC", 4: "MinDC",
    5: "MaxDC", 6: "MinMC", 7: "MaxMC", 8: "MinSC", 9: "MaxSC",
    10: "Accuracy", 11: "Agility", 12: "HP", 13: "MP", 14: "AttackSpeed",
    15: "Luck", 16: "BagWeight", 17: "HandWeight", 18: "WearWeight",
    19: "Reflect", 20: "Strong", 21: "Holy", 22: "Freezing",
    23: "PoisonAttack", 30: "MagicResist", 31: "PoisonResist",
    32: "HealthRecovery", 33: "SpellRecovery", 34: "PoisonRecovery",
    35: "CriticalRate", 36: "CriticalDamage", 100: "ExpRatePercent",
    101: "ItemDropRatePercent", 102: "GoldDropRatePercent",
}
KIND_CATEGORY = {
    13: ("consumable", "药品"), 17: ("scroll", "卷轴"), 20: ("skill_book", "技能书"),
    14: ("material", "矿石"), 15: ("material", "肉类"), 16: ("material", "制作材料"),
    18: ("material", "宝石"), 21: ("consumable", "脚本道具"), 27: ("consumable", "食物"),
    33: ("material", "鱼类"), 34: ("quest_item", "任务物品"), 35: ("material", "觉醒材料"),
    36: ("material", "宠物道具"), 37: ("consumable", "变身道具"), 40: ("material", "召唤道具"),
    41: ("material", "攻城弹药"), 42: ("quest_item", "英雄道具"), 0: ("material", "其他物品"),
}
ALIASES = {"金疮药": "金创药"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Reader:
    def __init__(self, data: bytes, pos: int = 0):
        self.data, self.pos = data, pos

    def take(self, fmt: str):
        size = struct.calcsize(fmt)
        if self.pos + size > len(self.data):
            raise ValueError("unexpected end of database")
        result = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return result[0] if len(result) == 1 else result

    def string(self) -> str:
        length, shift = 0, 0
        for _ in range(5):
            value = self.take("<B")
            length |= (value & 0x7F) << shift
            if not value & 0x80:
                break
            shift += 7
        if length < 0 or self.pos + length > len(self.data):
            raise ValueError("invalid .NET string length")
        raw = self.data[self.pos:self.pos + length]
        self.pos += length
        return raw.decode("utf-8")


def parse_item(reader: Reader) -> dict[str, Any]:
    record = {
        "serviceIndex": reader.take("<i"), "serviceName": reader.string(),
        "serviceType": reader.take("<B"), "grade": reader.take("<B"),
        "requiredType": reader.take("<B"), "requiredClass": reader.take("<B"),
        "requiredGender": reader.take("<B"), "set": reader.take("<B"),
        "shape": reader.take("<h"), "weight": reader.take("<B"),
        "light": reader.take("<B"), "requiredAmount": reader.take("<B"),
        "image": reader.take("<H"), "durability": reader.take("<H"),
        "maxStack": reader.take("<H"), "price": reader.take("<I"),
        "startItem": bool(reader.take("<?")), "effect": reader.take("<B"),
        "flags": reader.take("<B"), "bind": reader.take("<h"),
        "unique": reader.take("<h"), "randomStatsId": reader.take("<B"),
        "canFastRun": bool(reader.take("<?")), "canAwakening": bool(reader.take("<?")),
        "slots": reader.take("<B"),
    }
    stat_count = reader.take("<i")
    if stat_count < 0 or stat_count > 256:
        raise ValueError(f"invalid stat count {stat_count}")
    stats = {}
    for _ in range(stat_count):
        stat = reader.take("<B")
        stats[STAT_NAMES.get(stat, f"Stat{stat}")] = reader.take("<i")
    record["stats"] = stats
    if reader.take("<?"):
        record["toolTip"] = reader.string()
    return record


def parse_database() -> tuple[dict, list[dict]]:
    data = DB.read_bytes()
    version, custom_version = struct.unpack_from("<ii", data, 0)
    if version != 105:
        raise ValueError(f"expected database version 105, got {version}")
    candidates = []
    needle = struct.pack("<i", 1349)
    offset = 0
    while True:
        offset = data.find(needle, offset)
        if offset < 0:
            break
        try:
            reader = Reader(data, offset + 4)
            records = [parse_item(reader) for _ in range(1349)]
            next_count = reader.take("<i")
            if next_count == 544 and records[0]["serviceIndex"] >= 0:
                candidates.append((offset, reader.pos, records))
        except (ValueError, UnicodeDecodeError, struct.error):
            pass
        offset += 1
    if len(candidates) != 1:
        raise ValueError(f"item list structural match count={len(candidates)}")
    item_offset, end_offset, records = candidates[0]
    header_indices = list(struct.unpack_from("<8i", data, 8))
    return {
        "version": version, "customVersion": custom_version, "headerIndices": header_indices,
        "itemCount": len(records), "itemListOffset": item_offset, "itemListEnd": end_offset - 4,
        "nextMonsterCount": 544,
    }, records


def canonical_name(name: str) -> str:
    for old, new in ALIASES.items():
        name = name.replace(old, new)
    return name


def classify(record: dict) -> tuple[str, str]:
    item_type = int(record["serviceType"])
    if item_type in EQUIPMENT_TYPES:
        return "equipment_reference", "装备参考"
    return KIND_CATEGORY.get(item_type, ("material", "其他物品"))


def use_effect(record: dict, kind: str) -> tuple[str, bool]:
    item_type, shape = int(record["serviceType"]), int(record["shape"])
    if item_type == 13:
        return {0: "delayed_restore", 1: "restore_both", 2: "unlock_curse", 3: "temporary_buff", 4: "experience_buff", 5: "drop_buff"}.get(shape, "unsupported_potion"), shape <= 3
    if item_type == 17:
        return {0: "dungeon_escape", 1: "town_teleport", 2: "random_teleport", 3: "blessing_oil", 4: "repair_oil", 5: "war_god_oil", 6: "resurrection"}.get(shape, "unsupported_scroll"), shape <= 6
    if item_type == 20:
        return "learn_skill", True
    if item_type in (21, 27, 37):
        return "server_script_required", False
    return "none", False


def fallback_key(record: dict) -> str:
    return {
        13: "potion", 17: "scroll", 20: "book", 14: "ore", 15: "meat",
        16: "material", 18: "gem", 27: "food", 33: "fish", 34: "quest",
    }.get(int(record["serviceType"]), "material")


def build_fallbacks() -> dict[str, dict]:
    fallback_dir = OUTPUT / "fallback"
    fallback_dir.mkdir(parents=True, exist_ok=True)
    colors = {
        "potion": (196, 48, 55), "scroll": (221, 196, 125), "book": (104, 67, 148),
        "ore": (120, 137, 145), "meat": (166, 72, 54), "material": (157, 119, 69),
        "gem": (54, 181, 211), "food": (104, 170, 76), "fish": (70, 139, 178),
        "quest": (230, 150, 45),
    }
    result = {}
    for key, color in colors.items():
        for role, size in (("inventory", 40), ("ground", 28)):
            image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            if key == "potion":
                draw.rectangle((size*0.42, size*0.13, size*0.58, size*0.27), fill=(205, 190, 145, 255))
                draw.rounded_rectangle((size*0.25, size*0.25, size*0.75, size*0.86), radius=max(2, size//8), fill=(*color, 255), outline=(245, 220, 165, 255), width=max(1, size//14))
            elif key == "scroll":
                draw.rounded_rectangle((size*0.18, size*0.20, size*0.82, size*0.80), radius=3, fill=(*color, 255), outline=(105, 75, 42, 255), width=2)
                draw.line((size*0.32, size*0.40, size*0.68, size*0.40), fill=(105, 75, 42, 255), width=2)
                draw.line((size*0.32, size*0.56, size*0.63, size*0.56), fill=(105, 75, 42, 255), width=2)
            elif key == "book":
                draw.rounded_rectangle((size*0.20, size*0.17, size*0.80, size*0.84), radius=3, fill=(*color, 255), outline=(225, 194, 112, 255), width=2)
                draw.line((size*0.34, size*0.20, size*0.34, size*0.81), fill=(55, 38, 70, 255), width=2)
            elif key in ("ore", "gem", "quest"):
                draw.polygon([(size*0.50,size*0.10),(size*0.84,size*0.42),(size*0.67,size*0.86),(size*0.28,size*0.78),(size*0.14,size*0.38)], fill=(*color,255), outline=(235,225,190,255))
            elif key == "fish":
                draw.ellipse((size*0.17,size*0.31,size*0.72,size*0.70), fill=(*color,255), outline=(215,230,225,255), width=2)
                draw.polygon([(size*0.68,size*0.50),(size*0.90,size*0.28),(size*0.90,size*0.72)], fill=(*color,255))
            else:
                draw.ellipse((size*0.20,size*0.24,size*0.80,size*0.80), fill=(*color,255), outline=(235,220,178,255), width=2)
                draw.line((size*0.28,size*0.30,size*0.72,size*0.70), fill=(90,62,38,255), width=2)
            path = fallback_dir / f"{key}_{role}.png"
            image.save(path)
            result.setdefault(key, {})[role] = "res://" + path.relative_to(ROOT).as_posix()
    return result


def load_libraries() -> dict:
    libraries = {}
    for source_key, root in (("client.classic_raw_complete", PRIMARY), ("client.mir2opensource_2013_complete", AUXILIARY)):
        libraries[source_key] = {}
        for stem in ("Items", "StateItem", "DnItems"):
            path = next((p for p in (root / f"{stem}.wil", root / f"{stem.lower()}.wil", root / f"{stem}.Wil") if p.exists()), None)
            if path is None:
                raise FileNotFoundError(f"missing {stem}.wil under {root}")
            data, palette, offsets, info = read_library(path)
            libraries[source_key][stem] = {"path": path, "data": data, "palette": palette, "offsets": offsets, "info": info}
    return libraries


def extract_art(libraries: dict, image_index: int, stem: str, cache: dict) -> tuple[dict | None, list[dict]]:
    key = (stem, image_index)
    if key in cache:
        return cache[key]
    failures = []
    role = {"Items": "inventory", "StateItem": "state", "DnItems": "ground"}[stem]
    for source_key in ("client.classic_raw_complete", "client.mir2opensource_2013_complete"):
        library = libraries[source_key][stem]
        if image_index < 0 or image_index >= len(library["offsets"]):
            failures.append({"distribution": source_key, "status": "missing", "reason": "index_out_of_range"})
            continue
        try:
            sprite, metadata = decode_sprite(library["data"], library["offsets"][image_index], library["palette"])
            visible_box = sprite.getbbox()
            opaque_pixels = sum(1 for alpha in sprite.getchannel("A").get_flattened_data() if alpha > 0)
            if visible_box is None or visible_box[2] - visible_box[0] < 2 or visible_box[3] - visible_box[1] < 2 or opaque_pixels < 4:
                raise ValueError("empty_or_placeholder_pixel_frame")
            target = OUTPUT / role / source_key / f"{stem}_{image_index:05d}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                sprite.save(target)
            result = {
                "path": "res://" + target.relative_to(ROOT).as_posix(), "exact": True,
                "distribution": source_key, "sourceLibrary": library["path"].relative_to(ROOT).as_posix(),
                "sourceIndex": image_index, "width": metadata["width"], "height": metadata["height"],
                "offsetX": metadata["x"], "offsetY": metadata["y"], "higherPriorityFailures": failures,
            }
            cache[key] = (result, failures)
            return result, failures
        except ValueError as exc:
            failures.append({"distribution": source_key, "status": "unusable", "reason": str(exc)})
    cache[key] = (None, failures)
    return None, failures


def build() -> dict:
    if OUTPUT.exists():
        resolved = OUTPUT.resolve()
        if resolved.parent != (ROOT / "assets/art/items").resolve():
            raise ValueError(f"refusing to clean unexpected output path: {resolved}")
        shutil.rmtree(resolved)
    header, records = parse_database()
    libraries = load_libraries()
    fallbacks = build_fallbacks()
    art_cache = {}
    runtime_items, service_equipment, art_counts = [], [], {"primary": 0, "auxiliary_1": 0, "fallback": 0}
    seen_names = set()
    for raw in records:
        record = dict(raw)
        record["name"] = canonical_name(record["serviceName"])
        record["typeName"] = TYPE_NAMES.get(record["serviceType"], f"Unknown{record['serviceType']}")
        kind, category = classify(record)
        record["kind"], record["category"] = kind, category
        record["stackable"] = int(record["maxStack"]) > 1
        record["maxStack"] = max(1, int(record["maxStack"]))
        effect, usable = use_effect(record, kind)
        record["useEffect"], record["usable"] = effect, usable
        record["restoreHealth"] = int(record["stats"].get("HP", 0))
        record["restoreMana"] = int(record["stats"].get("MP", 0))
        record["durationMinutes"] = int(record["durability"]) if effect in ("temporary_buff", "experience_buff", "drop_buff") else 0
        record["source"] = {
            "distribution": "server.crystal.cjlaaa", "path": DB.relative_to(ROOT).as_posix(),
            "databaseVersion": header["version"], "parserRuleDistribution": "source.minipizza_mir2.server",
        }
        art = {}
        all_failures = {}
        for stem, field in (("Items", "inventoryIcon"), ("StateItem", "stateIcon"), ("DnItems", "groundIcon")):
            exact, failures = extract_art(libraries, int(record["image"]), stem, art_cache)
            all_failures[field] = failures
            if exact:
                art[field] = exact
            else:
                role = "ground" if stem == "DnItems" else "inventory"
                path = fallbacks[fallback_key(record)][role]
                art[field] = {"path": path, "exact": False, "distribution": "project.category_fallback", "sourceIndex": int(record["image"]), "failureEvidence": failures}
        record["art"] = art
        record["artExact"] = all(bool(art[field]["exact"]) for field in ("inventoryIcon", "groundIcon"))
        if art["groundIcon"]["distribution"] == "client.classic_raw_complete": art_counts["primary"] += 1
        elif art["groundIcon"]["distribution"] == "client.mir2opensource_2013_complete": art_counts["auxiliary_1"] += 1
        else: art_counts["fallback"] += 1
        if kind == "equipment_reference":
            service_equipment.append(record)
        elif record["name"] not in seen_names:
            seen_names.add(record["name"])
            runtime_items.append(record)
    currency_art = {}
    for stem, field in (("Items", "inventoryIcon"), ("StateItem", "stateIcon"), ("DnItems", "groundIcon")):
        exact, _failures = extract_art(libraries, 112, stem, art_cache)
        if exact is None and stem == "StateItem" and "inventoryIcon" in currency_art:
            exact = dict(currency_art["inventoryIcon"])
            exact["roleFallback"] = "StateItem #112 is a one-pixel placeholder; inventory gold pixel is reused"
        if exact is None:
            raise ValueError("primary client gold frame #112 must be available")
        currency_art[field] = exact
    runtime_specials = {
        "金币": {
            "name": "金币", "kind": "currency", "category": "货币", "stackable": True,
            "maxStack": 999999999, "currencyAmount": 1, "useEffect": "add_gold", "usable": False,
            "art": currency_art,
            "source": {"distribution": "client.classic_raw_complete", "rule": "classic DnItems/Items gold frame #112"},
        }
    }
    payload = {
        "schemaVersion": 1, "taskId": "COMPLETE-ITEM-SYSTEM-1",
        "policy": "main server records; primary client pixels; auxiliary1 same-index pixels only after recorded primary failure; explicit category fallback last",
        "database": {**header, "path": DB.relative_to(ROOT).as_posix(), "sha256": sha256(DB)},
        "sources": {
            "serverData": "server.crystal.cjlaaa", "serverParserRules": "source.minipizza_mir2.server",
            "clientPrimary": "client.classic_raw_complete", "clientAuxiliary1": "client.mir2opensource_2013_complete",
        },
        "counts": {"allServiceRecords": len(records), "runtimeNonEquipment": len(runtime_items), "serviceEquipmentReference": len(service_equipment), "groundArt": art_counts},
        "aliases": {"金疮药": "金创药", "强效金创药": "超级金创药", "强效魔法药": "超级魔法药"},
        "runtimeItems": runtime_items, "runtimeSpecials": runtime_specials,
        "runtimeFallbackArt": fallbacks, "serviceEquipmentReference": service_equipment,
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


if __name__ == "__main__":
    result = build()
    print("COMPLETE_ITEM_BUILD_PASS " + json.dumps(result["counts"], ensure_ascii=False))
