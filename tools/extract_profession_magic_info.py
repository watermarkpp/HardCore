#!/usr/bin/env python3
"""Reproducibly extract the 33 project skills from the primary Server.MirDB.

The database is a Crystal candidate rather than an official 1.76 Magic.DB.  The
generated records therefore remain explicitly labelled B/C candidates and never
silently replace the project's display names or stable IDs.
"""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa/Server.MirDB"
PARSER_SOURCE = ROOT / "dev_art_sources/reference/mir2_sources/minipizza_mir2/Server/MirDatabase/MagicInfo.cs"
PRIMARY_RULE_SOURCE = ROOT / "dev_art_sources/reference/original_gameofmir/M2Server/LocalDB.pas"
SKILLS = ROOT / "assets/data/vanilla_176/skills.json"
OUTPUT = ROOT / "assets/data/vanilla_176/profession_magic_info.json"

DB_DISTRIBUTION = "server.crystal.cjlaaa"
DB_ORIGINAL_PATH = "Server.MirDB"
PARSER_DISTRIBUTION = "source.minipizza_mir2.server"
PARSER_ORIGINAL_PATH = "Server/MirDatabase/MagicInfo.cs"
DATABASE_VERSION = 105
RECORD_TAIL = struct.Struct("<7B3H2I4HB2f")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_7bit_int(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    for _ in range(5):
        if offset >= len(data):
            raise ValueError("truncated 7-bit length")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
    raise ValueError("invalid 7-bit length")


def read_dotnet_string(data: bytes, offset: int) -> tuple[str, int]:
    length, offset = read_7bit_int(data, offset)
    if not 0 < length <= 128 or offset + length > len(data):
        raise ValueError("invalid MagicInfo name length")
    return data[offset : offset + length].decode("utf-8"), offset + length


def parse_record(data: bytes, offset: int) -> tuple[dict, int]:
    name, offset = read_dotnet_string(data, offset)
    if offset + RECORD_TAIL.size > len(data):
        raise ValueError("truncated MagicInfo record")
    values = RECORD_TAIL.unpack_from(data, offset)
    offset += RECORD_TAIL.size
    (
        spell,
        base_cost,
        level_cost,
        icon,
        level1,
        level2,
        level3,
        need1,
        need2,
        need3,
        delay_base,
        delay_reduction,
        power_base,
        power_bonus,
        mpower_base,
        mpower_bonus,
        range_cells,
        multiplier_base,
        multiplier_bonus,
    ) = values
    if spell == 0 or delay_base > 3_600_000 or range_cells > 64:
        raise ValueError("implausible MagicInfo values")
    return {
        "server_name": name,
        "service_spell_id": spell,
        "base_mana_cost": base_cost,
        "level_mana_cost": level_cost,
        "icon": icon,
        "required_character_levels": [level1, level2, level3],
        "training_points": [need1, need2, need3],
        "cooldown_base_ms": delay_base,
        "cooldown_reduction_ms": delay_reduction,
        "power_base": power_base,
        "power_bonus": power_bonus,
        "magic_power_base": mpower_base,
        "magic_power_bonus": mpower_bonus,
        "range_cells": range_cells,
        "multiplier_base": multiplier_base,
        "multiplier_bonus": multiplier_bonus,
        "mana_cost_by_level": [base_cost + level_cost * level for level in range(4)],
        "cooldown_ms_by_level": [max(0, delay_base - delay_reduction * level) for level in range(4)],
    }, offset


def target_catalog() -> dict[str, dict]:
    payload = json.loads(SKILLS.read_text(encoding="utf-8"))
    targets: dict[str, dict] = {}
    for row in payload["records"]:
        if int(row["skillLevel"]) != 0:
            continue
        name = str(row["display_name"])
        targets[name] = {
            "skill_id": str(row["skill_id"]),
            "profession_id": str(row["profession_id"]),
            "display_name": name,
        }
    if len(targets) != 33:
        raise RuntimeError(f"expected 33 stable skills, found {len(targets)}")
    return targets


def find_magic_info_block(data: bytes, target_names: set[str]) -> tuple[int, list[dict], int]:
    matches: list[tuple[int, list[dict], int]] = []
    for offset in range(0, len(data) - 4):
        count = struct.unpack_from("<i", data, offset)[0]
        if not 50 <= count <= 300:
            continue
        cursor = offset + 4
        records: list[dict] = []
        try:
            for _ in range(count):
                record, cursor = parse_record(data, cursor)
                records.append(record)
        except (UnicodeDecodeError, ValueError, struct.error):
            continue
        names = {record["server_name"] for record in records}
        if target_names <= names:
            matches.append((offset, records, cursor))
    if len(matches) != 1:
        raise RuntimeError(f"expected one MagicInfo block, found {len(matches)}")
    return matches[0]


def update_skills(extracted: dict[str, dict]) -> None:
    payload = json.loads(SKILLS.read_text(encoding="utf-8"))
    for row in payload["records"]:
        candidate = extracted[str(row["skill_id"])]
        level = int(row["skillLevel"])
        service_level = max(0, level - 1)
        if level == 0:
            required_candidate = candidate["required_character_levels"][0]
            training_candidate = None
        else:
            required_candidate = candidate["required_character_levels"][service_level]
            training_candidate = candidate["training_points"][service_level]
        row["manaCost"] = candidate["mana_cost_by_level"][level]
        row["service_candidate"] = {
            "classification": "B/C-candidate",
            "service_spell_id": candidate["service_spell_id"],
            "required_character_level": required_candidate,
            "training_points": training_candidate,
            "mana_cost": candidate["mana_cost_by_level"][level],
            "cooldown_ms": candidate["cooldown_ms_by_level"][level],
        }
        trace = row.setdefault("source_trace", {})
        for key, field, value in (
            ("required_character_level", "requiredCharacterLevel", required_candidate),
            ("training_points", "trainingPoints", training_candidate),
            ("mana_cost", "manaCost", candidate["mana_cost_by_level"][level]),
            ("server_cooldown", "service_candidate.cooldown_ms", candidate["cooldown_ms_by_level"][level]),
        ):
            trace[key] = {
                "field": field,
                "selected_value": row.get(field) if "." not in field else value,
                "service_candidate_value": value,
                "status": "selected_service_candidate" if key == "mana_cost" else "comparison_candidate",
                "classification": "B/C-candidate",
                "distribution_id": DB_DISTRIBUTION,
                "original_path": DB_ORIGINAL_PATH,
                "sha256": sha256(DB),
            }
    SKILLS.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if not DB.is_file() or not PARSER_SOURCE.is_file():
        raise FileNotFoundError("primary Server.MirDB or its matching MagicInfo reader is missing")
    targets = target_catalog()
    data = DB.read_bytes()
    block_offset, records, block_end = find_magic_info_block(data, set(targets))
    selected: dict[str, dict] = {}
    for record in records:
        target = targets.get(record["server_name"])
        if target is None:
            continue
        merged = {**target, **record, "classification": "B/C-candidate"}
        selected[target["skill_id"]] = merged
    if len(selected) != 33:
        raise RuntimeError(f"expected 33 extracted skills, found {len(selected)}")

    payload = {
        "schema_version": 1,
        "record_type": "MagicInfo extraction candidate",
        "classification": "B/C-candidate",
        "selection_policy": "main full-scan source priority",
        "warning": "Crystal Server.MirDB is the primary available service database, not proof of official 1.76 values.",
        "source": {
            "distribution_id": DB_DISTRIBUTION,
            "source_priority": {"lane": "server_data", "tier": "primary", "order": 0, "weight": 100},
            "original_path": DB_ORIGINAL_PATH,
            "workspace_path": str(DB.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha256(DB),
            "database_version": DATABASE_VERSION,
            "magic_info_block_offset": block_offset,
            "magic_info_block_end": block_end,
            "magic_info_record_count": len(records),
        },
        "reader_contract": {
            "distribution_id": PARSER_DISTRIBUTION,
            "source_priority": {"lane": "server_rules", "tier": "auxiliary_1", "order": 1, "weight": 70},
            "original_path": PARSER_ORIGINAL_PATH,
            "workspace_path": str(PARSER_SOURCE.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha256(PARSER_SOURCE),
            "binary_layout": "BinaryReader.ReadString + 7B + 3H + 2I + 4H + B + 2f (version > 70)",
        },
        "primary_missing_evidence": [
            {
                "lane": "server_rules",
                "distribution_id": "source.original_gameofmir.server_suite",
                "status": "incompatible",
                "original_path": "M2Server/LocalDB.pas",
                "workspace_path": str(PRIMARY_RULE_SOURCE.relative_to(ROOT)).replace("\\", "/"),
                "sha256": sha256(PRIMARY_RULE_SOURCE),
                "reason": "The primary classic reader loads BDE/DBF Magic.DB fields; it does not define Crystal Server.MirDB BinaryReader framing.",
            }
        ],
        "records": [selected[key] for key in sorted(selected)],
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_skills(selected)
    print(f"MAGIC_INFO_EXTRACTED={len(selected)} block={block_offset} records={len(records)}")


if __name__ == "__main__":
    main()
