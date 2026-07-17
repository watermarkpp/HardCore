#!/usr/bin/env python3
"""Build stable monsterId region spawn rules for the single-player runtime."""

from __future__ import annotations

import hashlib
import json
import math
import struct
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MONSTERS_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
LEGACY_SPAWNS_PATH = ROOT / "assets/data/vanilla_176/spawn_rules.json"
MAP_CONTENT_PATH = ROOT / "assets/data/vanilla_176/map_content.json"
BICH_CROSSCHECK_PATH = ROOT / "assets/data/bich_public_database_crosscheck.json"
SERVICE_RUNTIME_PATH = ROOT / "assets/data/service_monster_runtime_catalog.json"
PRIMARY_SERVER_DB_PATH = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates/"
    "suprcode_crystal_database/cjlaaa/Server.MirDB"
)
OUTPUT_PATH = ROOT / "assets/data/runtime/region_spawn_runtime_catalog.json"

DEFAULT_NORMAL_RESPAWN_SECONDS = 180.0


class BinaryReader:
    def __init__(self, payload: bytes, offset: int = 0):
        self.payload = payload
        self.offset = offset

    def _read(self, fmt: str) -> Any:
        value = struct.unpack_from(fmt, self.payload, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def read_i32(self) -> int:
        return int(self._read("<i"))

    def read_u16(self) -> int:
        return int(self._read("<H"))

    def read_u8(self) -> int:
        return int(self._read("<B"))

    def read_bool(self) -> bool:
        return self.read_u8() != 0

    def read_7bit_int(self) -> int:
        result = 0
        shift = 0
        while True:
            byte = self.read_u8()
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0:
                return result
            shift += 7
            if shift >= 35:
                raise ValueError("invalid .NET 7-bit encoded integer")

    def read_string(self) -> str:
        byte_count = self.read_7bit_int()
        end = self.offset + byte_count
        value = self.payload[self.offset:end].decode("utf-8")
        self.offset = end
        return value


def monster_index() -> dict[str, int]:
    records = json.loads(MONSTERS_PATH.read_text(encoding="utf-8"))["records"]
    result: dict[str, int] = {}
    for record in sorted(records, key=lambda row: int(row["monsterId"])):
        for name in (str(record.get("name", "")), str(record.get("baseName", ""))):
            if name:
                result.setdefault(name, int(record["monsterId"]))
    return result


def map_codes_by_runtime_id(
    primary_map_files_by_title: dict[str, list[str]],
) -> dict[int, str]:
    payload = json.loads(MAP_CONTENT_PATH.read_text(encoding="utf-8"))
    result: dict[int, str] = {}
    for record in payload.get("records", []):
        content = record.get("content", {})
        source_map = str(content.get("source_map", ""))
        if not source_map:
            matching_files = primary_map_files_by_title.get(
                str(content.get("name", "")).casefold(), []
            )
            if len(matching_files) == 1:
                source_map = matching_files[0]
        result[int(record["mapId"])] = source_map
    return result


def service_indices_by_monster_id() -> dict[int, int]:
    payload = json.loads(SERVICE_RUNTIME_PATH.read_text(encoding="utf-8"))
    result: dict[int, int] = {}
    for raw_id, row in payload.get("runtimeByMonsterId", {}).items():
        service_record = row.get("serviceRecord")
        if isinstance(service_record, dict) and "serviceIndex" in service_record:
            result[int(raw_id)] = int(service_record["serviceIndex"])
    return result


def distance_squared(source: dict[str, Any], candidate: dict[str, Any]) -> float:
    coordinate = source.get("source_coordinate", {}).get("$vector2")
    if not isinstance(coordinate, list) or len(coordinate) < 2:
        return 0.0
    return math.pow(float(coordinate[0]) - float(candidate["x"]), 2) + math.pow(
        float(coordinate[1]) - float(candidate["y"]), 2
    )


def primary_server_timing_candidates() -> tuple[
    dict[tuple[str, int], list[dict[str, Any]]],
    dict[str, int],
    dict[str, list[str]],
]:
    payload = PRIMARY_SERVER_DB_PATH.read_bytes()
    if len(payload) < 44:
        raise ValueError("primary Server.MirDB is truncated")
    (
        version,
        custom_version,
        _map_index,
        max_item_index,
        _monster_index,
        _npc_index,
        _quest_index,
        _game_shop_index,
        _conquest_index,
        _respawn_index,
    ) = struct.unpack_from("<10i", payload, 0)
    if version != 105:
        raise ValueError(f"unsupported Server.MirDB version: {version}")

    reader = BinaryReader(payload, 40)
    map_count = reader.read_i32()
    result: dict[tuple[str, int], list[dict[str, Any]]] = {}
    map_files_by_title: dict[str, list[str]] = {}
    respawn_count = 0
    for _ in range(map_count):
        _map_index = reader.read_i32()
        map_file = reader.read_string()
        title = reader.read_string()
        map_files_by_title.setdefault(title.casefold(), []).append(map_file)
        reader.read_u16()  # MiniMap
        reader.read_u8()  # Light
        reader.read_u16()  # BigMap

        safe_zone_count = reader.read_i32()
        for _ in range(safe_zone_count):
            reader.read_i32()
            reader.read_i32()
            reader.read_u16()
            reader.read_bool()

        map_respawn_count = reader.read_i32()
        for _ in range(map_respawn_count):
            monster_index = reader.read_i32()
            x = reader.read_i32()
            y = reader.read_i32()
            count = reader.read_u16()
            spread = reader.read_u16()
            delay_minutes = reader.read_u16()
            direction = reader.read_u8()
            route_path = reader.read_string()
            random_delay_minutes = reader.read_u16()
            respawn_index = reader.read_i32()
            save_respawn_time = reader.read_bool()
            respawn_ticks = reader.read_u16()
            candidate = {
                "mapFile": map_file,
                "monsterIndex": monster_index,
                "x": x,
                "y": y,
                "count": count,
                "spread": spread,
                "delayMinutes": delay_minutes,
                "randomDelayMinutes": random_delay_minutes,
                "direction": direction,
                "routePath": route_path,
                "respawnIndex": respawn_index,
                "saveRespawnTime": save_respawn_time,
                "respawnTicks": respawn_ticks,
            }
            result.setdefault((map_file.casefold(), monster_index), []).append(candidate)
            respawn_count += 1

        movement_count = reader.read_i32()
        for _ in range(movement_count):
            for _ in range(5):
                reader.read_i32()
            reader.read_bool()
            reader.read_bool()
            reader.read_i32()
            reader.read_bool()
            reader.read_i32()

        reader.read_bool()  # NoTeleport
        reader.read_bool()  # NoReconnect
        reader.read_string()  # NoReconnectMap
        for _ in range(10):
            reader.read_bool()
        reader.read_bool()  # Fire
        reader.read_i32()  # FireDamage
        reader.read_bool()  # Lightning
        reader.read_i32()  # LightningDamage
        reader.read_u8()  # MapDarkLight

        mine_zone_count = reader.read_i32()
        for _ in range(mine_zone_count):
            reader.read_i32()
            reader.read_i32()
            reader.read_u16()
            reader.read_u8()
        reader.read_u8()  # MineIndex
        reader.read_bool()  # NoMount
        reader.read_bool()  # NeedBridle
        reader.read_bool()  # NoFight
        reader.read_u16()  # Music
        reader.read_bool()  # NoTownTeleport
        reader.read_bool()  # NoReincarnation

    item_list_offset = reader.offset
    item_count = struct.unpack_from("<i", payload, item_list_offset)[0]
    if item_count != max_item_index + 1:
        raise ValueError(
            f"Server.MirDB item count {item_count} does not follow max item index {max_item_index}"
        )
    return (
        result,
        {
            "databaseVersion": version,
            "customVersion": custom_version,
            "mapCount": map_count,
            "respawnRowCount": respawn_count,
            "itemListOffset": item_list_offset,
            "itemCount": item_count,
            "sha256": hashlib.sha256(payload).hexdigest(),
        },
        map_files_by_title,
    )


def select_primary_timing(
    entry: dict[str, Any], candidates: list[dict[str, Any]]
) -> dict[str, Any]:
    coordinate = entry.get("source_coordinate", {}).get("$vector2")
    if isinstance(coordinate, list) and len(coordinate) >= 2:
        return min(
            candidates,
            key=lambda candidate: (
                distance_squared(entry, candidate),
                int(candidate["delayMinutes"]),
                int(candidate["x"]),
                int(candidate["y"]),
            ),
        )

    delay_counts = Counter(int(row["delayMinutes"]) for row in candidates)
    representative_delay = min(
        delay_counts,
        key=lambda delay: (-delay_counts[delay], delay),
    )
    return min(
        (row for row in candidates if int(row["delayMinutes"]) == representative_delay),
        key=lambda row: (int(row["x"]), int(row["y"]), int(row["randomDelayMinutes"])),
    )


def timing_candidates() -> dict[tuple[str, str], list[dict[str, Any]]]:
    crosscheck = json.loads(BICH_CROSSCHECK_PATH.read_text(encoding="utf-8"))
    result: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in crosscheck.get("spawns", []):
        key = (str(row.get("mapCode", "")), str(row.get("monsterName", "")))
        result.setdefault(key, []).append(row)
    return result


def enrich(
    entry: dict[str, Any],
    map_id: int,
    index: int,
    kind: str,
    ids_by_name: dict[str, int],
    map_codes: dict[int, str],
    service_indices: dict[int, int],
    primary_timings: dict[tuple[str, int], list[dict[str, Any]]],
    timings: dict[tuple[str, str], list[dict[str, Any]]],
) -> dict[str, Any]:
    result = json.loads(json.dumps(entry, ensure_ascii=False))
    name = str(result.get("name", ""))
    if name not in ids_by_name:
        raise ValueError(f"unresolved monster name map={map_id} kind={kind} name={name!r}")
    monster_id = ids_by_name[name]
    result["monsterId"] = monster_id
    result["spawnGroupId"] = f"map:{map_id}:{kind}:{index}:monster:{monster_id}"
    result["identityKey"] = "monsterId"
    result["legacyNameCompatibility"] = name
    result.setdefault("count", 1)
    result.setdefault("max_alive", int(result["count"]))

    if float(result.get("respawn_seconds", 0.0)) > 0.0:
        result["respawnEvidence"] = {
            "status": "authored_boss_rule",
            "confidence": "B",
            "source": "vanilla_176/spawn_rules.json",
        }
        return result

    map_code = map_codes.get(map_id, "")
    service_index = service_indices.get(monster_id)
    primary_candidates = (
        primary_timings.get((map_code.casefold(), service_index), [])
        if service_index is not None
        else []
    )
    if primary_candidates:
        selected = select_primary_timing(result, primary_candidates)
        delay_minutes = int(selected["delayMinutes"])
        random_delay_minutes = int(selected["randomDelayMinutes"])
        result["respawn_seconds"] = float(delay_minutes) * 60.0
        result["respawn_random_seconds"] = float(random_delay_minutes) * 60.0
        result["respawnEvidence"] = {
            "status": "primary_server_mirdb",
            "confidence": "B",
            "source": "server.crystal.cjlaaa/Server.MirDB",
            "mapFile": map_code,
            "serviceMonsterIndex": service_index,
            "delayMinutes": delay_minutes,
            "randomDelayMinutes": random_delay_minutes,
            "sourceCoordinate": [int(selected["x"]), int(selected["y"])],
        }
        return result

    candidates = timings.get((map_code, name), [])
    if candidates:
        selected = min(candidates, key=lambda candidate: distance_squared(result, candidate))
        result["respawn_seconds"] = float(selected["respawnMinutes"]) * 60.0
        result["respawn_random_seconds"] = 0.0
        result["respawnEvidence"] = {
            "status": "community_mongen_crosscheck",
            "confidence": "B",
            "source": "bich_public_database_crosscheck.json",
            "mapCode": map_code,
            "respawnMinutes": int(selected["respawnMinutes"]),
        }
    else:
        result["respawn_seconds"] = DEFAULT_NORMAL_RESPAWN_SECONDS
        result["respawn_random_seconds"] = 0.0
        result["respawnEvidence"] = {
            "status": "single_player_normal_fallback",
            "confidence": "POLICY",
            "source": "runtime_policy",
            "reason": "No accepted MonGen interval exists; replaces the obsolete 7-second prototype respawn.",
        }
    return result


def build_catalog() -> dict[str, Any]:
    legacy = json.loads(LEGACY_SPAWNS_PATH.read_text(encoding="utf-8"))
    ids_by_name = monster_index()
    service_indices = service_indices_by_monster_id()
    primary_timings, primary_metadata, primary_map_files_by_title = (
        primary_server_timing_candidates()
    )
    map_codes = map_codes_by_runtime_id(primary_map_files_by_title)
    timings = timing_candidates()
    records = []
    status_counts: dict[str, int] = {}
    entry_count = 0

    for map_record in legacy.get("records", []):
        map_id = int(map_record["mapId"])
        output_record = {"mapId": map_id, "spawns": [], "bosses": []}
        for kind in ("spawns", "bosses"):
            singular = "spawn" if kind == "spawns" else "boss"
            for index, entry in enumerate(map_record.get(kind, [])):
                enriched = enrich(
                    entry,
                    map_id,
                    index,
                    singular,
                    ids_by_name,
                    map_codes,
                    service_indices,
                    primary_timings,
                    timings,
                )
                output_record[kind].append(enriched)
                status = str(enriched["respawnEvidence"]["status"])
                status_counts[status] = status_counts.get(status, 0) + 1
                entry_count += 1
        records.append(output_record)

    return {
        "schemaVersion": 1,
        "layer": "runtime_services",
        "table": "region_spawn_runtime",
        "identityKey": "monsterId",
        "compatibilityKey": "name",
        "runtimeMode": "single_player",
        "policy": {
            "normalFallbackSeconds": DEFAULT_NORMAL_RESPAWN_SECONDS,
            "legacyPrototypeSecondsRejected": [7, 18],
            "animationStatusUnchanged": True,
        },
        "sources": {
            "identity": "vanilla_176/monsters.json",
            "legacyPositions": "vanilla_176/spawn_rules.json",
            "mapSourceCodes": "vanilla_176/map_content.json",
            "serviceMonsterResolution": "service_monster_runtime_catalog.json",
            "primaryServerRespawns": {
                "distribution": "server.crystal.cjlaaa",
                "path": (
                    "dev_art_sources/reference/mir2_database_candidates/"
                    "suprcode_crystal_database/cjlaaa/Server.MirDB"
                ),
                **primary_metadata,
                "runtimeSemanticsReference": (
                    "dev_art_sources/reference/mir2_sources/suprcode_crystal/"
                    "Server/MirEnvir/Map.cs"
                ),
            },
            "acceptedBichTimingEvidence": "bich_public_database_crosscheck.json",
        },
        "summary": {
            "mapCount": len(records),
            "entryCount": entry_count,
            "resolvedMonsterIdCount": entry_count,
            "unresolvedMonsterIdCount": 0,
            "respawnStatusCounts": status_counts,
        },
        "records": records,
    }


def main() -> None:
    payload = build_catalog()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("REGION_SPAWN_RUNTIME_BUILT", json.dumps(payload["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
