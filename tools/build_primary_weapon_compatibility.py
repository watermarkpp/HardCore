#!/usr/bin/env python3
"""Build the audited Crystal-Image to classic-Weapon compatibility table.

Crystal ``ItemInfo.Shape`` is retained as server evidence, but it is never
used as a classic Weapon.wil shape.  Every resolved formal weapon is joined
through the primary database ``Image`` field to primary StateItem pixels and
then to a manually reviewed primary Weapon.wil silhouette family.
"""

from __future__ import annotations

import csv
import hashlib
import json
import struct
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
FORMAL_CATALOG = ROOT / "assets/data/vanilla_176/items.json"
SOURCE_POLICY = ROOT / "assets/data/source_priority_policy.json"
PRIMARY_DB = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "suprcode_crystal_database/cjlaaa/Server.MirDB"
)
STATE_ITEM = (
    ROOT / "dev_art_sources/reference/mir2_client_raw/Data/stateitem.wil"
)
WEAPON = ROOT / "dev_art_sources/reference/mir2_client_raw/Data/Weapon.wil"
CLIENT_RULE = (
    ROOT / "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas"
)
SERVER_RULE = (
    ROOT / "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas"
)
AUXILIARY_1_FULL_ITEMS = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "angelk727_full/Exports/2_物品数据.csv"
)
AUXILIARY_1_EXPORT_ITEMS = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "angelk727/2_物品数据.csv"
)
AUXILIARY_1_REFERENCE_ITEMS = (
    ROOT
    / "dev_art_sources/reference/mir2_database/"
    "angelk727/2_物品数据.csv"
)
AUXILIARY_2_DB = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "suprcode_crystal_database/Jev/Server.MirDB"
)
AUXILIARY_3_DB = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "suprcode_crystal_database/Daneo1989/Server.MirDB"
)
OUTPUT = ROOT / "assets/data/equipment_primary_weapon_compatibility.json"

CONTRACT_ID = "equipment.weapon_compatibility.primary.v1"
PRIMARY_SERVER_DISTRIBUTION = "server.crystal.cjlaaa"
PRIMARY_CLIENT_DISTRIBUTION = "client.classic_raw_complete"
PRIMARY_CLIENT_RULE_DISTRIBUTION = "source.original_gameofmir.mirclient"
PRIMARY_SERVER_RULE_DISTRIBUTION = "source.original_gameofmir.server_suite"

PROFESSIONS = {
    80: "通用",
    81: "通用",
    82: "通用",
    83: "通用",
    84: "通用",
    85: "通用",
    86: "通用",
    87: "通用",
    88: "战士",
    89: "战士",
    90: "法师",
    91: "道士",
    92: "战士",
    93: "战士",
    94: "战士",
    95: "法师",
    96: "道士",
    97: "战士",
    98: "战士",
    99: "战士",
    100: "法师",
    101: "道士",
    102: "战士",
    103: "法师",
    104: "道士",
    105: "战士",
    106: "法师",
    107: "道士",
    108: "战士",
    109: "法师",
    110: "战士",
    111: "战士",
    112: "战士",
    113: "战士",
    114: "法师",
    115: "道士",
    223: "战士",
}

# Only explicit primary aliases are allowed.  The target-name query is still
# recorded as missing before the alias is queried.
PRIMARY_ALIASES = {
    "嗜魂法杖": {
        "name": "噬魂法杖",
        "reason": "primary database uses the 噬 glyph; the complete item name and staff identity otherwise match",
    },
    "赤血魔剑": {
        "name": "RedMoonSword",
        "reason": "primary English record points to the unique red StateItem #66 and matching red Weapon family",
    },
    "祈祷之刃": {
        "name": "祈祷之剑",
        "reason": "primary database uses 剑 for the same complete 祈祷 weapon identity",
    },
}

# Primary pixel review.  The tuple is
# (StateItem index, classic Weapon shape, visual class, review note).
# ``classic Weapon shape`` is a compatibility result, never Crystal Shape.
PIXEL_COMPATIBILITY = {
    "木剑": (30, 1, "sword", "wooden straight sword"),
    "匕首": (35, 6, "dagger", "short dagger"),
    "乌木剑": (43, 1, "sword", "wooden straight sword family"),
    "青铜剑": (31, 2, "sword", "straight sword"),
    "短剑": (33, 4, "dagger", "short single-hand blade"),
    "铁剑": (36, 2, "sword", "straight sword family"),
    "鹤嘴锄": (50, 19, "pickaxe", "pickaxe head and long handle"),
    "青铜斧": (32, 3, "axe", "single-head axe"),
    "八荒": (44, 15, "blade", "broad curved blade"),
    "海魂": (39, 8, "staff", "trident-tipped staff"),
    "半月": (46, 16, "blade", "strongly curved blade"),
    "凌风": (34, 5, "blade", "curved blade"),
    "破魂": (51, 20, "dagger", "short twin-prong blade"),
    "斩马刀": (37, 10, "blade", "large curved blade"),
    "偃月": (49, 18, "polearm", "long-handled curved blade"),
    "降魔": (47, 14, "sword", "wavy sword"),
    "修罗": (40, 7, "axe", "double-head axe"),
    "凝霜": (45, 13, "sword", "straight sword"),
    "炼狱": (41, 11, "axe", "large double-head axe"),
    "魔杖": (42, 12, "staff", "hooked casting staff"),
    "银蛇": (38, 9, "sword", "serpentine sword"),
    "井中月": (48, 17, "blade", "wide single-edge blade"),
    "血饮": (53, 22, "sword", "long narrow sword"),
    "无极棍": (52, 21, "staff", "segmented long staff"),
    "裁决之杖": (55, 24, "staff", "heavy judgement staff"),
    "骨玉权杖": (59, 28, "staff", "white-gold casting staff"),
    "龙纹剑": (56, 25, "sword", "curved dragon-pattern sword"),
    "屠龙": (57, 29, "blade", "massive dragon-slaying blade"),
    "嗜魂法杖": (58, 27, "staff", "twisted soul-eater staff"),
    "赤血魔剑": (66, 30, "sword", "red magic sword"),
    "怒斩": (70, 32, "blade", "crescent rage blade"),
    "龙牙": (69, 31, "sword", "jagged dragon-tooth sword"),
    "逍遥扇": (71, 33, "fan", "folding combat fan"),
    "祈祷之刃": (54, 23, "sword", "prayer sword"),
    "罗刹": (
        40,
        7,
        "axe",
        (
            "integration-approved shared primary axe appearance; "
            "StateItem #40 and classic Weapon shape 7 are primary pixels"
        ),
    ),
}

INTEGRATION_SHARED_PRIMARY_APPEARANCE = {
    "罗刹": {
        "mappingType": (
            "integration_user_required_shared_primary_appearance"
        ),
        "stateItemIndex": 40,
        "classicWeaponShape": 7,
        "visualWeaponClass": "axe",
        "decision": (
            "user explicitly requires 罗刹 to retain a visible world "
            "appearance; integration selected an existing shared primary "
            "client axe family after the complete configured server-data "
            "fallback chain returned no compatible identity"
        ),
        "prohibitions": [
            "not a Server.MirDB Shape",
            "not derived from any unconfigured database",
            "does not adopt HellYamaBlade",
        ],
    },
}

USER_CONFIRMED_CLASSIFICATION = {
    "炼狱": ("战士", "axe"),
    "裁决之杖": ("战士", "staff"),
    "龙纹剑": ("道士", "sword"),
    "屠龙": ("战士", "blade"),
}
USER_REQUIRED_VISIBLE = {"木剑", "乌木剑", "罗刹", "嗜魂法杖", "屠龙"}
UNRESOLVED_NAMES = {"命运之刃", "落魄神兵"}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def source_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


class Reader:
    def __init__(self, data: bytes, position: int = 0):
        self.data = data
        self.position = position

    def take(self, format_string: str) -> Any:
        size = struct.calcsize(format_string)
        if self.position + size > len(self.data):
            raise ValueError("unexpected end of primary Server.MirDB")
        result = struct.unpack_from(format_string, self.data, self.position)
        self.position += size
        return result[0] if len(result) == 1 else result

    def string(self) -> str:
        length = 0
        shift = 0
        for _ in range(5):
            value = self.take("<B")
            length |= (value & 0x7F) << shift
            if not value & 0x80:
                break
            shift += 7
        if self.position + length > len(self.data):
            raise ValueError("invalid primary Server.MirDB string")
        raw = self.data[self.position:self.position + length]
        self.position += length
        return raw.decode("utf-8")


def parse_item(reader: Reader) -> dict[str, Any]:
    record = {
        "serviceIndex": reader.take("<i"),
        "serviceName": reader.string(),
        "serviceType": reader.take("<B"),
        "grade": reader.take("<B"),
        "requiredType": reader.take("<B"),
        "requiredClass": reader.take("<B"),
        "requiredGender": reader.take("<B"),
        "set": reader.take("<B"),
        "crystalShape": reader.take("<h"),
        "weight": reader.take("<B"),
        "light": reader.take("<B"),
        "requiredAmount": reader.take("<B"),
        "image": reader.take("<H"),
        "durability": reader.take("<H"),
        "maxStack": reader.take("<H"),
        "price": reader.take("<I"),
        "startItem": bool(reader.take("<?")),
        "effect": reader.take("<B"),
        "flags": reader.take("<B"),
        "bind": reader.take("<h"),
        "unique": reader.take("<h"),
        "randomStatsId": reader.take("<B"),
        "canFastRun": bool(reader.take("<?")),
        "canAwakening": bool(reader.take("<?")),
        "slots": reader.take("<B"),
    }
    stat_count = reader.take("<i")
    if stat_count < 0 or stat_count > 256:
        raise ValueError(f"invalid primary stat count {stat_count}")
    for _ in range(stat_count):
        reader.take("<B")
        reader.take("<i")
    if reader.take("<?"):
        reader.string()
    return record


def parse_primary_items() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data = PRIMARY_DB.read_bytes()
    version, custom_version = struct.unpack_from("<ii", data, 0)
    if version != 105:
        raise ValueError(f"primary Server.MirDB version changed: {version}")
    candidates: list[tuple[int, int, list[dict[str, Any]]]] = []
    needle = struct.pack("<i", 1349)
    position = 0
    while True:
        position = data.find(needle, position)
        if position < 0:
            break
        try:
            reader = Reader(data, position + 4)
            records = [parse_item(reader) for _ in range(1349)]
            next_count = reader.take("<i")
            if next_count == 544 and int(records[0]["serviceIndex"]) >= 0:
                candidates.append((position, reader.position, records))
        except (UnicodeDecodeError, ValueError, struct.error):
            pass
        position += 1
    if len(candidates) != 1:
        raise ValueError(
            f"primary Server.MirDB item-list structural matches={len(candidates)}"
        )
    offset, end, records = candidates[0]
    return {
        "version": version,
        "customVersion": custom_version,
        "itemCount": len(records),
        "itemListOffset": offset,
        "itemListEnd": end - 4,
    }, records


def summarize_match(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "serviceIndex": int(record["serviceIndex"]),
        "serviceName": str(record["serviceName"]),
        "serviceType": int(record["serviceType"]),
        "requiredClass": int(record["requiredClass"]),
        "crystalShape": int(record["crystalShape"]),
        "image": int(record["image"]),
    }


def query_result(name: str, by_name: dict[str, list[dict[str, Any]]]) -> dict:
    matches = by_name.get(name, [])
    return {
        "query": {
            "recordType": "ItemInfo",
            "field": "serviceName",
            "operator": "exact",
            "value": name,
        },
        "status": "exact" if matches else "missing",
        "matchCount": len(matches),
        "matches": [summarize_match(record) for record in matches],
    }


def sprite_evidence(
    library: tuple,
    source_index: int,
) -> dict[str, Any]:
    data, palette, offsets, _info = library
    image, metadata = decode_sprite(data, offsets[source_index], palette)
    image = image.convert("RGBA")
    return {
        "sourceIndex": source_index,
        "hotX": int(metadata["x"]),
        "hotY": int(metadata["y"]),
        "width": image.width,
        "height": image.height,
        "opaquePixels": sum(
            alpha != 0 for alpha in image.getchannel("A").tobytes()
        ),
        "rgbaSha256": rgba_sha256(image),
    }


def csv_item_query_evidence(
    path: Path,
    distribution: str,
    tier: str,
    order: int,
    name: str,
    companion_of: str = "",
) -> dict[str, Any]:
    with path.open(
        "r",
        encoding="utf-8-sig",
        newline="",
    ) as stream:
        matches = [
            row
            for row in csv.DictReader(stream)
            if str(row.get("ItemName", "")) == name
        ]
    evidence = {
        "lane": "server_data",
        "distribution": distribution,
        "tier": tier,
        "order": order,
        "originalPath": source_path(path),
        "sha256": sha256_file(path),
        "query": {
            "recordType": "item export",
            "field": "ItemName",
            "operator": "exact",
            "value": name,
        },
        "status": "exact" if matches else "missing",
        "matchCount": len(matches),
        "matches": [
            {
                "itemName": str(row.get("ItemName", "")),
                "itemType": str(row.get("ItemType", "")),
                "requiredClass": str(row.get("ItemRequiredClass", "")),
                "requiredAmount": str(row.get("ItemRequiredAmount", "")),
                "image": str(row.get("ItemImage", "")),
                "crystalShape": str(row.get("ItemShape", "")),
            }
            for row in matches
        ],
        "adopted": False,
    }
    if companion_of:
        evidence["companionOf"] = companion_of
    return evidence


def dotnet_length_prefix(length: int) -> bytes:
    encoded = bytearray()
    remaining = length
    while remaining >= 0x80:
        encoded.append((remaining & 0x7F) | 0x80)
        remaining >>= 7
    encoded.append(remaining)
    return bytes(encoded)


def binary_item_core_matches(
    path: Path,
    name: str,
) -> tuple[dict[str, int], list[dict[str, Any]]]:
    data = path.read_bytes()
    version, custom_version = struct.unpack_from("<ii", data, 0)
    raw_name = name.encode("utf-8")
    needle = dotnet_length_prefix(len(raw_name)) + raw_name
    matches: list[dict[str, Any]] = []
    position = 0
    core_format = "<6Bh3BHHH"
    core_labels = [
        "serviceType",
        "grade",
        "requiredType",
        "requiredClass",
        "requiredGender",
        "set",
        "crystalShape",
        "weight",
        "light",
        "requiredAmount",
        "image",
        "durability",
        "maxStack",
    ]
    while True:
        position = data.find(needle, position)
        if position < 0:
            break
        record_start = position - 4
        core_offset = position + len(needle)
        if record_start >= 0 and core_offset + struct.calcsize(core_format) <= len(data):
            service_index = struct.unpack_from("<i", data, record_start)[0]
            values = struct.unpack_from(core_format, data, core_offset)
            core = dict(zip(core_labels, values))
            if 0 <= service_index < 100000 and int(core["serviceType"]) == 1:
                matches.append({
                    "serviceIndex": service_index,
                    "serviceName": name,
                    "recordOffset": record_start,
                    **{key: int(value) for key, value in core.items()},
                })
        position += 1
    return {
        "version": int(version),
        "customVersion": int(custom_version),
    }, matches


def binary_item_query_evidence(
    path: Path,
    distribution: str,
    tier: str,
    order: int,
    name: str,
) -> dict[str, Any]:
    database_info, matches = binary_item_core_matches(path, name)
    return {
        "lane": "server_data",
        "distribution": distribution,
        "tier": tier,
        "order": order,
        "originalPath": source_path(path),
        "sha256": sha256_file(path),
        "databaseVersion": database_info["version"],
        "databaseCustomVersion": database_info["customVersion"],
        "query": {
            "recordType": "ItemInfo",
            "field": "serviceName",
            "operator": "exact",
            "value": name,
        },
        "status": "exact" if matches else "missing",
        "matchCount": len(matches),
        "matches": matches,
        "adopted": False,
    }


def luosha_complete_fallback_evidence(
    formal_item: dict[str, Any],
    primary_state_image_count: int,
) -> dict[str, Any]:
    target_name = "罗刹"
    auxiliary_1 = [
        csv_item_query_evidence(
            AUXILIARY_1_FULL_ITEMS,
            "server.angelk727_full",
            "auxiliary_1",
            1,
            target_name,
        ),
        csv_item_query_evidence(
            AUXILIARY_1_EXPORT_ITEMS,
            "server.angelk727_exports",
            "auxiliary_1",
            1,
            target_name,
            companion_of="server.angelk727_full",
        ),
        csv_item_query_evidence(
            AUXILIARY_1_REFERENCE_ITEMS,
            "server_reference.angelk727",
            "auxiliary_1",
            1,
            target_name,
            companion_of="server.angelk727_full",
        ),
    ]
    auxiliary_2 = binary_item_query_evidence(
        AUXILIARY_2_DB,
        "server.crystal.Jev",
        "auxiliary_2",
        2,
        target_name,
    )
    auxiliary_3 = binary_item_query_evidence(
        AUXILIARY_3_DB,
        "server.crystal.Daneo1989",
        "auxiliary_3",
        3,
        target_name,
    )
    rejected_aliases = []
    for path, distribution, tier, order in (
        (
            AUXILIARY_2_DB,
            "server.crystal.Jev",
            "auxiliary_2",
            2,
        ),
        (
            AUXILIARY_3_DB,
            "server.crystal.Daneo1989",
            "auxiliary_3",
            3,
        ),
    ):
        alias_query = binary_item_query_evidence(
            path,
            distribution,
            tier,
            order,
            "HellYamaBlade",
        )
        matches = alias_query["matches"]
        mismatch = {
            "requiredAmount": {
                "formal": int(formal_item["reqLevel"]),
                "candidate": (
                    int(matches[0]["requiredAmount"]) if matches else None
                ),
            },
            "weight": {
                "formal": int(formal_item["weight"]),
                "candidate": int(matches[0]["weight"]) if matches else None,
            },
            "durability": {
                "formalServerScale": int(formal_item["durability"]) * 1000,
                "candidate": (
                    int(matches[0]["durability"]) if matches else None
                ),
            },
            "primaryStateItemCapacity": {
                "imageCount": primary_state_image_count,
                "candidateImage": (
                    int(matches[0]["image"]) if matches else None
                ),
                "candidateWithinPrimaryLibrary": (
                    bool(matches)
                    and int(matches[0]["image"]) < primary_state_image_count
                ),
            },
        }
        rejected_aliases.append({
            **alias_query,
            "candidateReason": (
                "semantic Yama/Rakshasa resemblance was checked only as "
                "an alias candidate"
            ),
            "compatibility": mismatch,
            "status": "rejected_incompatible_identity",
            "rejectionReason": (
                "the record is a level-52 later-distribution weapon with "
                "Image 1153, not the level-15 formal 罗刹; it cannot join "
                "the primary StateItem library and no field is adopted"
            ),
        })
    if any(row["status"] != "missing" for row in auxiliary_1):
        raise AssertionError("罗刹 unexpectedly resolved in auxiliary_1")
    if auxiliary_2["status"] != "missing":
        raise AssertionError("罗刹 unexpectedly resolved in auxiliary_2")
    if auxiliary_3["status"] != "missing":
        raise AssertionError("罗刹 unexpectedly resolved in auxiliary_3")
    return {
        "entered": True,
        "lane": "server_data",
        "target": target_name,
        "adopted": False,
        "configuredChainExhausted": True,
        "queriesInPolicyOrder": [
            *auxiliary_1,
            auxiliary_2,
            auxiliary_3,
        ],
        "rejectedAliases": rejected_aliases,
        "result": (
            "missing in every configured server_data source; no lower-tier "
            "server value or unconfigured database is adopted"
        ),
    }


def main() -> None:
    required_paths = [
        FORMAL_CATALOG,
        SOURCE_POLICY,
        PRIMARY_DB,
        STATE_ITEM,
        WEAPON,
        CLIENT_RULE,
        SERVER_RULE,
        AUXILIARY_1_FULL_ITEMS,
        AUXILIARY_1_EXPORT_ITEMS,
        AUXILIARY_1_REFERENCE_ITEMS,
        AUXILIARY_2_DB,
        AUXILIARY_3_DB,
    ]
    for path in required_paths:
        if not path.exists():
            raise FileNotFoundError(f"missing weapon compatibility input: {path}")

    policy = json.loads(SOURCE_POLICY.read_text(encoding="utf-8"))
    lanes = policy.get("lanes", {})
    expected_primaries = {
        "server_data": PRIMARY_SERVER_DISTRIBUTION,
        "client_assets": PRIMARY_CLIENT_DISTRIBUTION,
        "client_rules": PRIMARY_CLIENT_RULE_DISTRIBUTION,
        "server_rules": PRIMARY_SERVER_RULE_DISTRIBUTION,
    }
    for lane, expected in expected_primaries.items():
        sources = lanes.get(lane, {}).get("sources", [])
        if (
            not sources
            or sources[0].get("tier") != "primary"
            or sources[0].get("distribution") != expected
        ):
            raise ValueError(f"{lane} primary source changed")
    server_sources = lanes.get("server_data", {}).get("sources", [])
    configured_server_chain = [
        (
            str(source.get("distribution", "")),
            str(source.get("tier", "")),
            int(source.get("order", -1)),
        )
        for source in server_sources
        if source.get("tier") in {
            "primary",
            "auxiliary_1",
            "auxiliary_2",
            "auxiliary_3",
        }
    ]
    if configured_server_chain != [
        ("server.crystal.cjlaaa", "primary", 0),
        ("server.angelk727_full", "auxiliary_1", 1),
        ("server.crystal.Jev", "auxiliary_2", 2),
        ("server.crystal.Daneo1989", "auxiliary_3", 3),
    ]:
        raise ValueError(
            "server_data configured source order changed; fallback evidence "
            "must be re-reviewed before generation"
        )
    if set(server_sources[1].get("companions", [])) != {
        "server.angelk727_exports",
        "server_reference.angelk727",
    }:
        raise ValueError("server_data auxiliary_1 companions changed")

    formal_items = [
        item
        for item in json.loads(
            FORMAL_CATALOG.read_text(encoding="utf-8")
        ).get("records", [])
        if item.get("category") == "武器"
    ]
    formal_items.sort(key=lambda item: int(item["itemId"]))
    if len(formal_items) != 37:
        raise AssertionError(
            f"expected 37 formal weapons, got {len(formal_items)}"
        )
    if {int(item["itemId"]) for item in formal_items} != set(PROFESSIONS):
        raise AssertionError("formal weapon item-id roster changed")
    for item in formal_items:
        item_id = int(item["itemId"])
        if str(item.get("profession", "")) != PROFESSIONS[item_id]:
            raise AssertionError(
                f"profession taxonomy changed for {item_id} {item['name']}"
            )

    database_info, database_records = parse_primary_items()
    weapon_records = [
        record
        for record in database_records
        if int(record["serviceType"]) == 1
    ]
    by_name: dict[str, list[dict[str, Any]]] = {}
    for record in weapon_records:
        by_name.setdefault(str(record["serviceName"]), []).append(record)

    state_library = read_library(STATE_ITEM)
    weapon_library = read_library(WEAPON)
    if int(state_library[3]["image_count"]) <= 71:
        raise AssertionError("primary StateItem no longer contains weapon range")
    if len(weapon_library[2]) // 600 != 68:
        raise AssertionError("primary Weapon.wil feature count changed")

    database_hash = sha256_file(PRIMARY_DB)
    state_hashes = {
        "wil": sha256_file(STATE_ITEM),
        "wix": sha256_file(STATE_ITEM.with_suffix(".wix")),
    }
    weapon_hashes = {
        "wil": sha256_file(WEAPON),
        "wix": sha256_file(WEAPON.with_suffix(".wix")),
    }
    items_by_id: dict[str, dict[str, Any]] = {}
    resolved_ids: list[int] = []
    unresolved_ids: list[int] = []
    divergent_shape_ids: list[int] = []
    shared_primary_appearance_ids: list[int] = []

    for item in formal_items:
        item_id = int(item["itemId"])
        name = str(item["name"])
        profession = PROFESSIONS[item_id]
        target_query = query_result(name, by_name)
        alias = PRIMARY_ALIASES.get(name)
        adopted_name = str(alias["name"]) if alias else name
        adopted_query = query_result(adopted_name, by_name)
        compatibility = PIXEL_COMPATIBILITY.get(name)

        base_record: dict[str, Any] = {
            "itemId": item_id,
            "itemName": name,
            "profession": profession,
            "professionAxis": {
                "value": profession,
                "role": "gameplay eligibility/progression semantics",
                "independentFrom": "visualWeaponClass",
            },
            "primaryServerQuery": {
                "lane": "server_data",
                "distribution": PRIMARY_SERVER_DISTRIBUTION,
                "tier": "primary",
                "order": 0,
                "originalPath": source_path(PRIMARY_DB),
                "sha256": database_hash,
                "databaseVersion": int(database_info["version"]),
                "targetNameResult": target_query,
            },
        }
        if alias:
            base_record["primaryServerQuery"]["aliasResult"] = adopted_query
            base_record["primaryServerQuery"]["aliasReason"] = str(
                alias["reason"]
            )

        if compatibility is None:
            if name not in UNRESOLVED_NAMES:
                raise AssertionError(
                    f"unreviewed primary compatibility gap: {item_id} {name}"
                )
            if target_query["status"] != "missing":
                raise AssertionError(
                    f"{name} became available in primary; review is required"
                )
            base_record.update({
                "status": "unresolved",
                "visualWeaponClass": "unresolved",
                "mappingPolicy": (
                    "draw no weapon layer; never infer a Weapon feature"
                ),
                "missingEvidence": {
                    "primary": target_query,
                    "fallback": (
                        luosha_complete_fallback_evidence(
                            item,
                            int(state_library[3]["image_count"]),
                        )
                        if name == "罗刹"
                        else {
                            "entered": False,
                            "reason": (
                                "no lower-tier value is adopted by this "
                                "primary compatibility repair"
                            ),
                        }
                    ),
                },
            })
            items_by_id[str(item_id)] = base_record
            unresolved_ids.append(item_id)
            continue

        shared_appearance = INTEGRATION_SHARED_PRIMARY_APPEARANCE.get(name)
        source_record: dict[str, Any] | None
        if shared_appearance:
            if target_query["status"] != "missing":
                raise AssertionError(
                    f"{name} became available in primary; integration "
                    "shared appearance must be re-reviewed"
                )
            if alias:
                raise AssertionError(
                    f"{name} cannot combine a DB alias and integration "
                    "shared appearance"
                )
            source_record = None
            base_record["fallbackEvidence"] = (
                luosha_complete_fallback_evidence(
                    item,
                    int(state_library[3]["image_count"]),
                )
            )
            base_record["mappingType"] = str(
                shared_appearance["mappingType"]
            )
            base_record["integrationDecision"] = shared_appearance
            shared_primary_appearance_ids.append(item_id)
        else:
            if adopted_query["status"] != "exact":
                raise AssertionError(
                    f"resolved mapping lacks primary record: {item_id} {name}"
                )
            if adopted_query["matchCount"] != 1:
                raise AssertionError(
                    f"resolved primary query is ambiguous: {item_id} {name}"
                )
            source_record = by_name[adopted_name][0]
            base_record["mappingType"] = (
                "primary_server_image_to_primary_client_pixels"
            )

        state_index, classic_shape, visual_class, review_note = compatibility
        if source_record is not None:
            if int(source_record["image"]) != int(state_index):
                raise AssertionError(
                    f"primary Image changed for {item_id} {name}: "
                    f"{source_record['image']} != {state_index}"
                )
        else:
            if (
                int(shared_appearance["stateItemIndex"]) != int(state_index)
                or int(shared_appearance["classicWeaponShape"])
                != int(classic_shape)
                or str(shared_appearance["visualWeaponClass"])
                != visual_class
            ):
                raise AssertionError(
                    f"integration shared appearance changed: "
                    f"{item_id} {name}"
                )
        feature = int(classic_shape) * 2
        if feature <= 0 or feature >= 68 or feature % 2 != 0:
            raise AssertionError(
                f"invalid male classic feature for {item_id} {name}: {feature}"
            )

        state_sprite = sprite_evidence(state_library, int(state_index))
        weapon_frames = [
            sprite_evidence(
                weapon_library,
                feature * 600 + 200 + direction * 8,
            )
            for direction in range(8)
        ]
        crystal_shape = (
            int(source_record["crystalShape"])
            if source_record is not None
            else None
        )
        if (
            crystal_shape is not None
            and crystal_shape != int(classic_shape)
        ):
            divergent_shape_ids.append(item_id)
        base_record.update({
            "status": "resolved_primary_pixels",
            "visualWeaponClass": visual_class,
            "visualClassAxis": {
                "value": visual_class,
                "role": "physical silhouette/rendering identity",
                "independentFrom": "profession",
                "userConfirmed": name in USER_CONFIRMED_CLASSIFICATION,
            },
            "crystalShape": crystal_shape,
            "crystalShapeStatus": (
                "primary_server_evidence_only"
                if crystal_shape is not None
                else (
                    "missing_after_complete_configured_fallback; "
                    "integration mapping is primary-client-only"
                )
            ),
            "classicWeaponShape": int(classic_shape),
            "maleFeature": feature,
            "crystalShapeUsedAsClassicShape": False,
            "stateItemEvidence": {
                "lane": "client_assets",
                "distribution": PRIMARY_CLIENT_DISTRIBUTION,
                "tier": "primary",
                "originalPath": source_path(STATE_ITEM),
                "librarySha256": state_hashes,
                **state_sprite,
            },
            "weaponEvidence": {
                "lane": "client_assets",
                "distribution": PRIMARY_CLIENT_DISTRIBUTION,
                "tier": "primary",
                "originalPath": source_path(WEAPON),
                "librarySha256": weapon_hashes,
                "classicShape": int(classic_shape),
                "maleFeature": feature,
                "reviewMethod": (
                    "manual primary StateItem silhouette/material to primary "
                    "Weapon.wil eight-direction attack-frame compatibility"
                ),
                "reviewResult": review_note,
                "attackDirectionFrame0": weapon_frames,
            },
        })
        items_by_id[str(item_id)] = base_record
        resolved_ids.append(item_id)

    for name, expected in USER_CONFIRMED_CLASSIFICATION.items():
        record = next(
            value
            for value in items_by_id.values()
            if value["itemName"] == name
        )
        if (
            record["profession"],
            record["visualWeaponClass"],
        ) != expected:
            raise AssertionError(f"user classification regressed: {name}")

    required_visibility = {}
    for name in sorted(USER_REQUIRED_VISIBLE):
        record = next(
            value
            for value in items_by_id.values()
            if value["itemName"] == name
        )
        required_visibility[name] = (
            str(record.get("mappingType", "resolved_primary_pixels"))
            if record["status"] == "resolved_primary_pixels"
            else "unresolved_after_complete_configured_fallback"
        )

    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "policyId": str(policy.get("policyId", "")),
        "sourcePolicyPath": "res://assets/data/source_priority_policy.json",
        "axisPolicy": {
            "profession": (
                "gameplay profession semantics; never inferred from pixels"
            ),
            "visualWeaponClass": (
                "physical weapon silhouette; never inferred from profession"
            ),
        },
        "primarySources": {
            "serverData": {
                "distribution": PRIMARY_SERVER_DISTRIBUTION,
                "tier": "primary",
                "path": source_path(PRIMARY_DB),
                "sha256": database_hash,
                **database_info,
            },
            "clientAssetsStateItem": {
                "distribution": PRIMARY_CLIENT_DISTRIBUTION,
                "tier": "primary",
                "path": source_path(STATE_ITEM),
                "sha256": state_hashes,
                "imageCount": int(state_library[3]["image_count"]),
            },
            "clientAssetsWeapon": {
                "distribution": PRIMARY_CLIENT_DISTRIBUTION,
                "tier": "primary",
                "path": source_path(WEAPON),
                "sha256": weapon_hashes,
                "imageCount": int(weapon_library[3]["image_count"]),
                "blockFrames": 600,
            },
            "clientRules": {
                "distribution": PRIMARY_CLIENT_RULE_DISTRIBUTION,
                "tier": "primary",
                "path": source_path(CLIENT_RULE),
                "sha256": sha256_file(CLIENT_RULE),
                "queryResult": (
                    "HUMANFRAME=600; m_nWeaponOffset="
                    "HUMANFRAME*m_btWeapon"
                ),
            },
            "serverRules": {
                "distribution": PRIMARY_SERVER_RULE_DISTRIBUTION,
                "tier": "primary",
                "path": source_path(SERVER_RULE),
                "sha256": sha256_file(SERVER_RULE),
                "queryResult": (
                    "classic StdItem.Shape is encoded as Shape*2+gender; "
                    "this rule is applied only after pixel compatibility"
                ),
            },
        },
        "coverage": {
            "formalWeapons": len(formal_items),
            "resolvedPrimaryPixels": len(resolved_ids),
            "integrationSharedPrimaryAppearance": len(
                shared_primary_appearance_ids
            ),
            "unresolved": len(unresolved_ids),
            "crystalShapeDiffersFromClassicShape": len(divergent_shape_ids),
            "directCrystalShapeMultiplication": 0,
            "lowerTierValuesAdopted": 0,
        },
        "classification": {
            "resolved": resolved_ids,
            "integrationSharedPrimaryAppearance": (
                shared_primary_appearance_ids
            ),
            "unresolved": unresolved_ids,
            "crystalShapeDivergence": divergent_shape_ids,
        },
        "acceptance": {
            "requiredWorldAppearance": required_visibility,
            "userConfirmedClassification": {
                name: {
                    "profession": values[0],
                    "visualWeaponClass": values[1],
                }
                for name, values in USER_CONFIRMED_CLASSIFICATION.items()
            },
            "allResolvedMappingsUsePrimaryPixels": True,
            "noCrystalShapeDirectMapping": True,
            "unresolvedNeverBorrowsFeature": True,
        },
        "itemsById": items_by_id,
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "PRIMARY_WEAPON_COMPATIBILITY_PASS "
        f"formal={len(formal_items)} resolved={len(resolved_ids)} "
        f"unresolved={len(unresolved_ids)} "
        f"shape_divergence={len(divergent_shape_ids)}"
    )


if __name__ == "__main__":
    main()
