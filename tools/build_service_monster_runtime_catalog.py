#!/usr/bin/env python3
"""Build the single-player monster runtime catalog keyed by stable monsterId.

Project monster identity comes from vanilla_176/monsters.json.  Service timing
and AI metadata are read from the selected primary Crystal Server.MirDB.
Unmatched project records remain loadable through an explicit project fallback;
they are never presented as service-derived facts.
"""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa/Server.MirDB"
PROJECT_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
OUTPUT_PATH = ROOT / "assets/data/service_monster_runtime_catalog.json"

EXPECTED_DATABASE_VERSION = 105
EXPECTED_ITEM_COUNT = 1349
EXPECTED_MONSTER_COUNT = 544

SERVER_DATA_DISTRIBUTION = "server.crystal.cjlaaa"
PRIMARY_RULE_DISTRIBUTION = "source.original_gameofmir.server_suite"
DATABASE_FORMAT_REFERENCE_DISTRIBUTION = "source.suprcode_crystal.server"
PROJECT_DISTRIBUTION = "vanilla_176"


class Reader:
    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    def take(self, fmt: str) -> Any:
        size = struct.calcsize(fmt)
        if self.pos + size > len(self.data):
            raise ValueError("unexpected end of database")
        values = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return values[0] if len(values) == 1 else values

    def string(self) -> str:
        length = 0
        shift = 0
        for _ in range(5):
            value = self.take("<B")
            length |= (value & 0x7F) << shift
            if not value & 0x80:
                break
            shift += 7
        if self.pos + length > len(self.data):
            raise ValueError("invalid .NET string length")
        raw = self.data[self.pos:self.pos + length]
        self.pos += length
        return raw.decode("utf-8")


def read_stats(reader: Reader) -> dict[str, int]:
    count = reader.take("<i")
    if count < 0 or count > 256:
        raise ValueError(f"invalid stat count {count}")
    stats: dict[str, int] = {}
    for _ in range(count):
        stat = reader.take("<B")
        stats[str(stat)] = reader.take("<i")
    return stats


def skip_item(reader: Reader) -> None:
    reader.take("<i")
    reader.string()
    reader.take("<B")
    reader.take("<B")
    reader.take("<B")
    reader.take("<B")
    reader.take("<B")
    reader.take("<B")
    reader.take("<h")
    reader.take("<B")
    reader.take("<B")
    reader.take("<B")
    reader.take("<H")
    reader.take("<H")
    reader.take("<H")
    reader.take("<I")
    reader.take("<?")
    reader.take("<B")
    reader.take("<B")
    reader.take("<h")
    reader.take("<h")
    reader.take("<B")
    reader.take("<?")
    reader.take("<?")
    reader.take("<B")
    read_stats(reader)
    if reader.take("<?"):
        reader.string()


def parse_monster(reader: Reader) -> dict[str, Any]:
    record = {
        "serviceIndex": reader.take("<i"),
        "serviceName": reader.string(),
        "image": reader.take("<H"),
        "aiCode": reader.take("<B"),
        "effect": reader.take("<B"),
        "level": reader.take("<H"),
        "viewRange": reader.take("<B"),
        "coolEye": reader.take("<B"),
        "stats": read_stats(reader),
        "light": reader.take("<B"),
        "attackIntervalMs": reader.take("<H"),
        "moveIntervalMs": reader.take("<H"),
        "experience": reader.take("<I"),
        "canPush": bool(reader.take("<?")),
        "canTame": bool(reader.take("<?")),
        "autoRevive": bool(reader.take("<?")),
        "undead": bool(reader.take("<?")),
        "dropPath": reader.string(),
    }
    return record


def parse_database() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data = DB_PATH.read_bytes()
    version, custom_version = struct.unpack_from("<ii", data, 0)
    if version != EXPECTED_DATABASE_VERSION:
        raise ValueError(f"expected database version {EXPECTED_DATABASE_VERSION}, got {version}")

    candidates: list[tuple[int, Reader]] = []
    needle = struct.pack("<i", EXPECTED_ITEM_COUNT)
    offset = 0
    while True:
        offset = data.find(needle, offset)
        if offset < 0:
            break
        try:
            reader = Reader(data, offset + 4)
            for _ in range(EXPECTED_ITEM_COUNT):
                skip_item(reader)
            if reader.take("<i") == EXPECTED_MONSTER_COUNT:
                candidates.append((offset, reader))
        except (UnicodeDecodeError, ValueError, struct.error):
            pass
        offset += 1

    if len(candidates) != 1:
        raise ValueError(f"monster list structural match count={len(candidates)}")

    item_offset, reader = candidates[0]
    monster_offset = reader.pos
    records = [parse_monster(reader) for _ in range(EXPECTED_MONSTER_COUNT)]
    return {
        "databaseVersion": version,
        "customVersion": custom_version,
        "itemListOffset": item_offset,
        "monsterListOffset": monster_offset,
        "monsterCount": len(records),
        "sha256": hashlib.sha256(data).hexdigest(),
    }, records


def service_behavior(record: dict[str, Any], status: str) -> dict[str, Any]:
    confidence = "B" if status == "exact_service_name" else "B/C"
    return {
        "aiCode": record["aiCode"],
        "image": record["image"],
        "effect": record["effect"],
        "viewRange": record["viewRange"],
        "coolEye": record["coolEye"],
        "canPush": record["canPush"],
        "canTame": record["canTame"],
        "autoRevive": record["autoRevive"],
        "undead": record["undead"],
        "confidence": confidence,
        "resolutionStatus": status,
        "sourceDistribution": SERVER_DATA_DISTRIBUTION,
        "primaryRuleDistribution": PRIMARY_RULE_DISTRIBUTION,
        "databaseFormatReferenceDistribution": DATABASE_FORMAT_REFERENCE_DISTRIBUTION,
    }


def fallback_profile() -> dict[str, Any]:
    return {
        "timing": {
            "attackIntervalMs": 2500,
            "moveIntervalMs": 1800,
            "confidence": "C",
            "resolutionStatus": "unresolved_project_fallback",
        },
        "serviceBehavior": {
            "aiCode": 0,
            "image": -1,
            "effect": 0,
            "viewRange": 7,
            "coolEye": 0,
            "canPush": True,
            "canTame": False,
            "autoRevive": True,
            "undead": False,
            "confidence": "C",
            "resolutionStatus": "unresolved_project_fallback",
            "sourceDistribution": "project.single_player_fallback",
        },
    }


def matched_profile(record: dict[str, Any], status: str) -> dict[str, Any]:
    confidence = "B" if status == "exact_service_name" else "B/C"
    return {
        "timing": {
            "attackIntervalMs": record["attackIntervalMs"],
            "moveIntervalMs": record["moveIntervalMs"],
            "confidence": confidence,
            "resolutionStatus": status,
        },
        "serviceBehavior": service_behavior(record, status),
    }


def build_catalog() -> dict[str, Any]:
    database, service_records = parse_database()
    project = json.loads(PROJECT_PATH.read_text(encoding="utf-8"))
    project_records = sorted(
        (
            row
            for row in project["records"]
            if row.get("recordStatus") != "retired"
        ),
        key=lambda row: int(row["monsterId"]),
    )
    expected_active_count = 156
    if len(project_records) != expected_active_count:
        raise ValueError(
            "active monster count mismatch: "
            f"expected={expected_active_count} "
            f"actual={len(project_records)}"
        )

    service_by_name: dict[str, list[dict[str, Any]]] = {}
    for record in service_records:
        service_by_name.setdefault(record["serviceName"], []).append(record)
    for matches in service_by_name.values():
        matches.sort(key=lambda row: int(row["serviceIndex"]))

    runtime_by_id: dict[str, dict[str, Any]] = {}
    legacy_name_to_id: dict[str, int] = {}
    counts = {
        "exactServiceName": 0,
        "baseNameFallback": 0,
        "unresolvedProjectFallback": 0,
    }

    for project_record in project_records:
        monster_id = int(project_record["monsterId"])
        name = str(project_record.get("name", ""))
        base_name = str(project_record.get("baseName", ""))
        candidates = service_by_name.get(name, [])
        status = "exact_service_name"
        matched_name = name
        if not candidates and base_name:
            candidates = service_by_name.get(base_name, [])
            status = "base_name_fallback"
            matched_name = base_name

        row: dict[str, Any] = {
            "monsterId": monster_id,
            "projectName": name,
            "projectBaseName": base_name,
        }
        if candidates:
            selected = candidates[0]
            count_key = "exactServiceName" if status == "exact_service_name" else "baseNameFallback"
            counts[count_key] += 1
            row.update({
                "resolutionStatus": status,
                "matchedProjectField": "name" if status == "exact_service_name" else "baseName",
                "matchedName": matched_name,
                "serviceCandidateCount": len(candidates),
                "serviceRecord": selected,
                "behaviorProfile": matched_profile(selected, status),
            })
        else:
            counts["unresolvedProjectFallback"] += 1
            row.update({
                "resolutionStatus": "unresolved_project_fallback",
                "behaviorProfile": fallback_profile(),
            })
        runtime_by_id[str(monster_id)] = row

        for legacy_name in (name, base_name):
            if legacy_name:
                legacy_name_to_id.setdefault(legacy_name, monster_id)

    total = len(project_records)
    if len(runtime_by_id) != total or sum(counts.values()) != total:
        raise ValueError("runtime catalog coverage invariant failed")

    return {
        "schemaVersion": 1,
        "identityKey": "monsterId",
        "compatibilityKey": "name/baseName",
        "runtimeMode": "single_player",
        "evidencePolicy": (
            "Stable project monsterId is authoritative. Service-derived fields only appear on "
            "exact/base-name matches; unresolved rows use an explicit C-confidence project fallback."
        ),
        "sources": {
            "projectIdentity": {
                "distribution": PROJECT_DISTRIBUTION,
                "path": PROJECT_PATH.relative_to(ROOT).as_posix(),
            },
            "serverData": {
                "distribution": SERVER_DATA_DISTRIBUTION,
                "path": DB_PATH.relative_to(ROOT).as_posix(),
                **database,
            },
        "primaryServiceRules": {
            "distribution": PRIMARY_RULE_DISTRIBUTION,
            "path": "dev_art_sources/reference/original_gameofmir/M2Server",
            "references": ["ObjMon.pas", "ObjMon2.pas", "ObjMon3.pas", "ObjAxeMon.pas"],
        },
        "databaseFormatReference": {
            "distribution": DATABASE_FORMAT_REFERENCE_DISTRIBUTION,
            "path": (
                "dev_art_sources/reference/mir2_sources/suprcode_crystal/"
                "Server/MirDatabase/MonsterInfo.cs"
            ),
            "role": "Binary parser layout only; not the primary gameplay rule authority.",
        },
        "auxiliaryAiDispatchReference": {
            "distribution": DATABASE_FORMAT_REFERENCE_DISTRIBUTION,
            "path": (
                "dev_art_sources/reference/mir2_sources/suprcode_crystal/"
                "Server/MirObjects/MonsterObject.cs"
            ),
            "role": "Auxiliary evidence for Crystal aiCode meaning; special behavior still requires primary-rule cross-check.",
        },
        },
        "summary": {
            "projectMonsterCount": total,
            "runtimeEntryCount": len(runtime_by_id),
            "serviceMonsterCount": len(service_records),
            **counts,
        },
        "runtimeByMonsterId": runtime_by_id,
        "legacyNameToMonsterId": legacy_name_to_id,
    }


def main() -> None:
    catalog = build_catalog()
    OUTPUT_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    summary = catalog["summary"]
    print(
        "SERVICE_MONSTER_RUNTIME_CATALOG_BUILT "
        f"total={summary['runtimeEntryCount']} "
        f"exact={summary['exactServiceName']} "
        f"base={summary['baseNameFallback']} "
        f"fallback={summary['unresolvedProjectFallback']}"
    )


if __name__ == "__main__":
    main()
