#!/usr/bin/env python3
"""Build/check the M00R per-monster movement source authority.

This is an offline authority builder. Runtime consumers use stable monster_id
records only and never perform a name lookup.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import math
import struct
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/data/monster_movement_source_master_v1.json"
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
AUTHORITY_PATH = ROOT / "assets/data/monster_runtime_authority_v1.json"
SERVICE_PATH = ROOT / "assets/data/service_monster_runtime_catalog.json"
COMBAT_PATH = ROOT / "assets/data/canonical_monster_combat_source_v1.json"
BEHAVIOR_PATH = ROOT / "assets/data/monster_behavior_profiles.json"
POLICY_PATH = ROOT / "assets/data/source_priority_policy.json"
DETAIL_SOURCE_PATH = ROOT / "assets/data/monster_21cq_detail_source_v1.json"
M00_SHA = "1945a5eceaf6efc49ddf4e5da4298834bf15c864"
PRE_21CQ_AUTHORITY_COMMIT = "29692163b72664600a027e76a3e4ab3bf74ae089"

CRYSTAL_ROOT = ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database"
PRIMARY_DB = CRYSTAL_ROOT / "cjlaaa/Server.MirDB"
AUX2_DB = CRYSTAL_ROOT / "Jev/Server.MirDB"
AUX3_DB = CRYSTAL_ROOT / "Daneo1989/Server.MirDB"
AUX1_CSV = ROOT / "dev_art_sources/reference/mir2_database_candidates/angelk727_full/Exports/3_怪物数据.csv"
LOCAL_176_DB = ROOT / "dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/Mud2/DB/Monster.DB"
LOCAL_176_README = ROOT / "dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/README.md"
CRYSTAL_README = CRYSTAL_ROOT / "README.md"

EXPECTED_HASHES = {
    "server.crystal.cjlaaa": "ace4fa6a70e18db7f8454350326d611ce6c56826b9f9a4f214797a3f8a5f69d0",
    "server.angelk727_full": "7850ea794b7e34ce27d1b03407ae64d5144379941e5c33e2122445b78bbf7284",
    "server.crystal.Jev": "37358b0d95eafe458b060c1db2ebc0524757fe524fb93125ccb98d9b4a8ef78b",
    "server.crystal.Daneo1989": "6781323b7ae5fdbbe0b48db21b35420f732a6c30cc663ab75f7ca5a6d056ead5",
    "candidate.mylgd_mir2server_176": "a8a2919b2f05f95459c01a67c9326f3d86fb954ecdc5dbb095e96cba237515b0",
}

ALLOWED_SOURCE_STATUSES = {"LOCKED", "ACCEPTED_CANDIDATE", "COMPATIBILITY_HOLD"}
CONFLICT_CLASSES = {
    "SAME_VERSION_DATA_CONFLICT",
    "VERSION_DIFFERENCE",
    "CANONICAL_PROJECT_TUNING",
    "ID_BINDING_MISMATCH",
    "SOURCE_ROW_MISSING",
    "SPECIAL_CLASS_OVERRIDE",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_pre_21cq_authority() -> dict[str, Any]:
    """Load the pre-override candidate snapshot for conflict classification.

    The current runtime authority is regenerated from this source master, so
    reading it directly would make a rebuild compare the new output with
    itself.  The task baseline is fixed by the integration handoff; retaining
    that candidate snapshot only preserves historical conflict classes and
    never supplies a runtime value.
    """
    relative = "assets/data/monster_runtime_authority_v1.json"
    try:
        raw = subprocess.check_output(
            ["git", "show", f"{PRE_21CQ_AUTHORITY_COMMIT}:{relative}"],
            cwd=ROOT,
        )
        return json.loads(raw.decode("utf-8"))
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError, json.JSONDecodeError):
        return read_json(AUTHORITY_PATH)


def load_local_rows() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    module_path = ROOT / "tools/build_complete_monster_client_art.py"
    spec = importlib.util.spec_from_file_location("m00r_monster_db_reader", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load local 1.76 Monster.DB reader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.read_monster_db()


def crystal_header(path: Path) -> tuple[int, int]:
    return struct.unpack_from("<ii", path.read_bytes(), 0)


def collection_count_before_first_archer(path: Path) -> int:
    data = path.read_bytes()
    name = b"ArcherGuard"
    marker = bytes([len(name)]) + name
    position = data.find(marker)
    if position < 8:
        raise ValueError(f"ArcherGuard first-record marker missing: {path}")
    service_index = struct.unpack_from("<i", data, position - 4)[0]
    count = struct.unpack_from("<i", data, position - 8)[0]
    if service_index != 1 or count <= 0:
        raise ValueError(f"invalid Crystal monster collection boundary: {path}")
    return count


def audit_sources(canonical_names: set[str], service: dict[str, Any]) -> list[dict[str, Any]]:
    policy = read_json(POLICY_PATH)
    lane = policy["lanes"]["server_data"]["sources"]
    lane_by_distribution = {str(item["distribution"]): item for item in lane}
    primary_meta = service["sources"]["serverData"]
    aux1_rows = list(csv.DictReader(AUX1_CSV.open(encoding="utf-8-sig", newline="")))
    aux1_names = {str(row.get("MonsterName", "")) for row in aux1_rows}
    crystal_readme_hash = sha256(CRYSTAL_README)

    def policy_fields(distribution: str) -> dict[str, Any]:
        item = lane_by_distribution[distribution]
        return {
            "distribution": distribution,
            "tier": item["tier"],
            "order": int(item["order"]),
            "path": str(item["rootPrefix"]),
        }

    primary = {
        **policy_fields("server.crystal.cjlaaa"),
        "file": source_path(PRIMARY_DB),
        "sha256": sha256(PRIMARY_DB),
        "version_evidence": {
            "database_version": int(primary_meta["databaseVersion"]),
            "distribution_dates": "2017-11-04 through 2022-06-24",
            "readme": source_path(CRYSTAL_README),
            "readme_sha256": crystal_readme_hash,
        },
        "monster_record_count": int(primary_meta["monsterCount"]),
        "walk_spd_coverage": int(primary_meta["monsterCount"]),
        "walk_step_coverage": 0,
        "walk_wait_coverage": 0,
        "canonical_exact_binding_coverage": int(service["summary"]["exactServiceName"]),
        "canonical_missing": 156 - int(service["summary"]["exactServiceName"]),
        "conflicts": "modern Crystal movement interval is retained only as current compatibility evidence",
        "decision": "SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH",
        "rejection_reason": "modern Crystal distribution is not authenticated classic 1.76 and its schema has no WalkStep/WalkWait",
    }

    aux1 = {
        **policy_fields("server.angelk727_full"),
        "file": source_path(AUX1_CSV),
        "sha256": sha256(AUX1_CSV),
        "version_evidence": {
            "repository_commit": "16c49ad53f3bc2ff6f9f584117e61b5b9fe4970f",
            "commit_date": "2024-04-06T17:34:37+08:00",
            "schema_markers": ["AssassinClone", "critical rate fields", "mount-era Crystal export"],
        },
        "monster_record_count": len(aux1_rows),
        "walk_spd_coverage": sum(bool(str(row.get("MonsterMoveSpeed", "")).strip()) for row in aux1_rows),
        "walk_step_coverage": sum(bool(str(row.get("WalkStep", "")).strip()) for row in aux1_rows),
        "walk_wait_coverage": sum(bool(str(row.get("WalkWait", "")).strip()) for row in aux1_rows),
        "canonical_exact_binding_coverage": len(canonical_names & aux1_names),
        "canonical_missing": 156 - len(canonical_names & aux1_names),
        "conflicts": "later Crystal export cannot certify classic cadence rows",
        "decision": "SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH",
        "rejection_reason": "2024 modern Crystal export and no WalkStep/WalkWait",
    }

    audits = [primary, aux1]
    for distribution, path, dates in (
        ("server.crystal.Jev", AUX2_DB, "2020-07-23 through present"),
        ("server.crystal.Daneo1989", AUX3_DB, "2014-11-27 through 2015-10-31"),
    ):
        version, custom_version = crystal_header(path)
        count = collection_count_before_first_archer(path)
        raw = path.read_bytes()
        exact = sum(
            (bytes([len(name.encode("utf-8"))]) + name.encode("utf-8")) in raw
            for name in canonical_names
            if len(name.encode("utf-8")) < 128
        )
        audits.append({
            **policy_fields(distribution),
            "file": source_path(path),
            "sha256": sha256(path),
            "version_evidence": {
                "database_version": version,
                "custom_version": custom_version,
                "distribution_dates": dates,
                "readme": source_path(CRYSTAL_README),
                "readme_sha256": crystal_readme_hash,
            },
            "monster_record_count": count,
            "walk_spd_coverage": count,
            "walk_step_coverage": 0,
            "walk_wait_coverage": 0,
            "canonical_exact_binding_coverage": exact,
            "canonical_missing": 156 - exact,
            "conflicts": "Crystal schema/version differs from classic Paradox 1.76",
            "decision": "SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH",
            "rejection_reason": "later Crystal database and no WalkStep/WalkWait",
        })
    return audits


def classify_interval_conflict(
    record: dict[str, Any],
    old_movement: dict[str, Any],
    classic: dict[str, Any],
) -> str | None:
    canonical = old_movement["current_canonical_candidate"]
    canonical_interval = canonical.get("walk_interval_ms")
    classic_interval = classic.get("walk_interval_raw_ms")
    if canonical_interval is None or int(canonical_interval) == int(classic_interval):
        return None
    if bool(old_movement.get("stationary", False)):
        return "SPECIAL_CLASS_OVERRIDE"
    if str(record.get("classification", "")) == "version_difference":
        return "VERSION_DIFFERENCE"
    if (
        str(classic.get("source", {}).get("binding", "")) == "explicit_override"
        or str(canonical.get("resolution_status", "")) == "base_name_fallback"
    ):
        return "ID_BINDING_MISMATCH"
    if str(canonical.get("distribution", "")) == "project.single_player_fallback":
        return "CANONICAL_PROJECT_TUNING"
    return "VERSION_DIFFERENCE"


def build_payload() -> dict[str, Any]:
    catalog = read_json(CATALOG_PATH)
    detail_source = read_json(DETAIL_SOURCE_PATH)
    if detail_source.get("authority") != "user_authoritative_override":
        raise ValueError("21CQ detail source is not user-authoritative")
    detail_by_id = {
        int(row["monster_id"]): row
        for row in detail_source.get("records", [])
        if isinstance(row, dict)
    }
    if len(detail_by_id) != 217:
        raise ValueError("21CQ detail source must contain 217 rows")
    old_authority = load_pre_21cq_authority()
    service = read_json(SERVICE_PATH)
    combat = read_json(COMBAT_PATH)
    behavior = read_json(BEHAVIOR_PATH)
    local_rows, local_meta = load_local_rows()
    local_by_name = {str(row["Name"]): (index, row) for index, row in enumerate(local_rows)}
    old_by_id = {int(row["monster_id"]): row for row in old_authority["records"]}
    service_by_id = {int(key): value for key, value in service["runtimeByMonsterId"].items()}
    combat_by_id = {int(key): value for key, value in combat["records_by_monster_id"].items()}
    profile_by_id = {int(key): value for key, value in behavior["profileByMonsterId"].items()}
    canonical_names = {str(row["canonical_name"]) for row in catalog["entries"]}
    source_audits = audit_sources(canonical_names, service)

    records: list[dict[str, Any]] = []
    conflict_rows: list[dict[str, Any]] = []
    for canonical in sorted(catalog["entries"], key=lambda item: int(item["monster_id"])):
        monster_id = int(canonical["monster_id"])
        old = old_by_id[monster_id]
        old_movement = old["movement"]
        detail_row = detail_by_id.get(monster_id)
        if not isinstance(detail_row, dict):
            raise ValueError(f"21CQ detail source missing monster_id={monster_id}")
        combat_row = combat_by_id.get(monster_id)
        exact = combat_row is not None
        source_name = str(combat_row.get("source_name", "")) if exact else ""
        binding_kind = str(combat_row.get("binding", "")) if exact else ""
        if exact:
            ordinal, source_row = local_by_name[source_name]
            binding_status = "EXACT_SOURCE_ROW"
        else:
            base_name = str(service_by_id[monster_id].get("projectBaseName", ""))
            if base_name not in local_by_name:
                raise ValueError(f"monster_id={monster_id} has no exact or explicit base compatibility row")
            ordinal, source_row = local_by_name[base_name]
            source_name = base_name
            binding_kind = "explicit_stable_id_to_base_row"
            binding_status = "SOURCE_ROW_MISSING"

        stationary = bool(old_movement["stationary"])
        detail_interval_raw_ms = int(detail_row["move_interval_ms"])
        if stationary:
            status = "LOCKED"
            movement_enabled = False
            walk_interval_ms = 0
            walk_step = 0
            walk_wait_ms = 0
            decision_reason = "source-locked stationary class/state: no movement grant"
        elif exact:
            status = "ACCEPTED_CANDIDATE"
            movement_enabled = True
            # 21CQ is authoritative for the interval value.  The existing
            # server cadence contract still enforces its 200ms effective
            # minimum; keep the raw website value in the evidence below.
            walk_interval_ms = max(200, detail_interval_raw_ms)
            walk_step = max(1, int(source_row["WalkStep"] or 0))
            walk_wait_ms = int(source_row["WaLkWait"] or 0)
            decision_reason = "21CQ authoritative move interval with audited 1.76 step/wait cadence candidate"
        else:
            status = "COMPATIBILITY_HOLD"
            movement_enabled = True
            walk_interval_ms = max(200, detail_interval_raw_ms)
            walk_step = max(1, int(source_row["WalkStep"] or 0))
            walk_wait_ms = int(source_row["WaLkWait"] or 0)
            decision_reason = "21CQ authoritative move interval with explicit stable-ID compatibility step/wait binding"

        classic = old_movement.get("classic_176_non_routed_candidate")
        conflict_class = None
        if exact and classic is not None:
            conflict_class = classify_interval_conflict(old, old_movement, classic)
        elif not exact:
            conflict_class = "SOURCE_ROW_MISSING"
        if conflict_class:
            conflict = {
                "monster_id": monster_id,
                "classification": conflict_class,
                "canonical_interval_ms": old_movement["current_canonical_candidate"].get("walk_interval_ms"),
                "selected_interval_ms": walk_interval_ms,
                "binding_status": binding_status,
                "resolution": status,
            }
            conflict_rows.append(conflict)
        else:
            conflict = None

        profile_id = str(profile_by_id.get(monster_id, "")) or None
        record = {
            "monster_id": monster_id,
            "canonical_name": str(canonical["canonical_name"]),
            "classification": str(canonical["classification"]),
            "runtime_allowed": bool(canonical["runtime_allowed"]),
            "movement_source_status": status,
            "movement_enabled": movement_enabled,
            "walk_interval_ms": walk_interval_ms,
            "walk_step": walk_step,
            "walk_wait_ms": walk_wait_ms,
            "decision_reason": decision_reason,
            "source_binding": {
                "runtime_lookup": "monster_id_only",
                "binding_status": binding_status,
                "source_row_ordinal_zero_based": ordinal,
                "source_name_audit_only": source_name,
                "source_binding_kind": binding_kind,
                "source": "candidate.mylgd_mir2server_176",
                "path": source_path(LOCAL_176_DB),
                "sha256": sha256(LOCAL_176_DB),
            },
            "interval_authority": {
                "authority": "user_authoritative_override",
                "distribution": str(detail_source.get("distribution", "")),
                "source": source_path(DETAIL_SOURCE_PATH),
                "sha256": sha256(DETAIL_SOURCE_PATH),
                "source_url": str(detail_row.get("source_url", "")),
                "raw_html_sha256": str(detail_row.get("raw_html_sha256", "")),
                "field": "move_interval_ms",
                "raw_interval_ms": detail_interval_raw_ms,
                "effective_interval_ms": walk_interval_ms,
                "minimum_contract_ms": 200,
            },
            "source_row": {
                "WALK_SPD": int(source_row["WALK_SPD"] or 0),
                "WalkStep": int(source_row["WalkStep"] or 0),
                "WalkWait": int(source_row["WaLkWait"] or 0),
                "Race": int(source_row["Race"] or 0),
                "RaceImg": int(source_row["RaceImg"] or 0),
                "Appr": int(source_row["Appr"] or 0),
            },
            "server_class_binding": {
                "status": status,
                "server_race": int(source_row["Race"] or 0),
                "server_race_img": int(source_row["RaceImg"] or 0),
                "appearance": int(source_row["Appr"] or 0),
                "behavior_family": profile_id or f"race_{int(source_row['Race'] or 0)}",
                "runtime_name_lookup": False,
            },
            "interval_conflict": conflict,
        }
        records.append(record)

    status_counts = Counter(str(row["movement_source_status"]) for row in records)
    exact_count = sum(row["source_binding"]["binding_status"] == "EXACT_SOURCE_ROW" for row in records)
    missing_count = len(records) - exact_count
    interval_conflicts = [row for row in conflict_rows if row["classification"] != "SOURCE_ROW_MISSING"]
    conflict_counts = Counter(str(row["classification"]) for row in interval_conflicts)
    holds = [int(row["monster_id"]) for row in records if row["movement_source_status"] == "COMPATIBILITY_HOLD"]

    return {
        "schema_version": 1,
        "authority_id": "monster.movement.source.master.v1",
        "stage": "M00R_M01_RELEASE_SOURCE_CLOSURE",
        "identity_key": "monster_id",
        "m00_final_sha": M00_SHA,
        "generated_date": "2026-08-24",
        "rule_sources": {
            "field_semantics": {
                "distribution": "source.original_gameofmir.server_suite",
                "lane": "server_rules",
                "status": "A_LOCKED",
                "rule": "WALK_SPD is millisecond cadence with 200ms minimum",
            },
            "cadence_algorithm": {
                "distribution": "source.original_gameofmir.server_suite",
                "lane": "server_rules",
                "status": "A_LOCKED",
                "rule": "WalkStep grants then WalkWait locks; semantics are not re-arbitrated in M00R",
            },
        },
        "server_data_source_audit": source_audits,
        "selected_value_source": {
            "distribution": "candidate.mylgd_mir2server_176",
            "tier": "explicit_user_requested_candidate_after_routed_source_exhaustion",
            "order": 4,
            "path": source_path(LOCAL_176_DB),
            "sha256": sha256(LOCAL_176_DB),
            "schema": {
                "field_count": int(local_meta["fieldCount"]),
                "record_size": int(local_meta["recordSize"]),
                "decoded_row_count": int(local_meta["decodedRowCount"]),
                "required_fields": ["Name", "Race", "RaceImg", "Appr", "WALK_SPD", "WalkStep", "WaLkWait"],
            },
            "version_evidence": {
                "readme": source_path(LOCAL_176_README),
                "readme_sha256": sha256(LOCAL_176_README),
                "declared_version": "1.76",
                "declared_engine": "GEE",
                "authenticity_limit": "third-party learning package; accepted candidate, not official classic truth",
            },
            "decision": "ACCEPTED_CANDIDATE_FOR_EXACT_ROWS",
            "reason": "all formally routed server_data sources are version-scope mismatches and omit WalkStep/WalkWait",
            "exact_bindings": exact_count,
            "missing_exact_bindings": missing_count,
            "interval_conflicts": len(interval_conflicts),
        },
        "interval_value_authority": {
            "authority": "user_authoritative_override",
            "distribution": str(detail_source.get("distribution", "")),
            "source": source_path(DETAIL_SOURCE_PATH),
            "sha256": sha256(DETAIL_SOURCE_PATH),
            "field": "move_interval_ms",
            "raw_value_policy": "exact_21cq_detail_value",
            "effective_value_policy": "existing_strict_cadence_minimum_200ms_for_nonstationary_runtime",
            "excluded": ["spawn", "respawn", "map", "quantity", "drops", "drop_probability"],
        },
        "conflict_policy": {
            "allowed_classes": sorted(CONFLICT_CLASSES),
            "interval_conflict_count": len(interval_conflicts),
            "interval_conflict_classification": dict(sorted(conflict_counts.items())),
            "source_row_missing_count": sum(row["classification"] == "SOURCE_ROW_MISSING" for row in conflict_rows),
            "records": conflict_rows,
        },
        "temporary_cell_contract": {
            "status": "LOCKED",
            "persistent_position": "runtime_map_absolute_ground_gu",
            "temporary_only": True,
            "ground_gu_to_cell": "Vector2i(floor(position_ground_gu.x), floor(position_ground_gu.y))",
            "cell_to_center_ground_gu": "Vector2(cell)+Vector2(0.5,0.5)",
            "neighbor_target_ground_gu": "Vector2(cell + neighbor)+Vector2(0.5,0.5)",
            "neighbor_set": [[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]],
            "axis_neighbor_gu": 1.0,
            "diagonal_neighbor_gu": math.sqrt(2.0),
            "movement_grants_per_neighbor": 1,
            "persistent_cell_forbidden": True,
            "evidence": "scripts/layers/runtime/map_editor_runtime_bridge.gd cell center conversion; pure boundary/round-trip checks in this builder",
        },
        "summary": {
            "canonical_monsters": len(records),
            "locked_count": status_counts["LOCKED"],
            "accepted_candidate_count": status_counts["ACCEPTED_CANDIDATE"],
            "compatibility_hold_count": status_counts["COMPATIBILITY_HOLD"],
            "hold_monster_ids": holds,
            "server_class_binding_coverage": len(records),
            "temporary_cell_quantization": "LOCKED",
            "data_hold_count": 0,
        },
        "records": records,
    }


def validate_quantization(contract: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    values = [-2.000001, -2.0, -1.999999, -1.000001, -1.0, -0.999999, -0.000001, 0.0, 0.000001, 0.999999, 1.0, 1.000001, 2.0]
    for x in values:
        for y in values:
            cell = (math.floor(x), math.floor(y))
            center = (cell[0] + 0.5, cell[1] + 0.5)
            if (math.floor(center[0]), math.floor(center[1])) != cell:
                errors.append(f"cell center round-trip failed for {(x, y)}")
    neighbors = [tuple(value) for value in contract["neighbor_set"]]
    if len(neighbors) != 8 or len(set(neighbors)) != 8:
        errors.append("neighbor set must contain eight unique deltas")
    for dx, dy in neighbors:
        if dx == 0 and dy == 0 or abs(dx) > 1 or abs(dy) > 1:
            errors.append(f"invalid neighbor {(dx, dy)}")
        expected = 1.0 if dx == 0 or dy == 0 else math.sqrt(2.0)
        if not math.isclose(math.hypot(dx, dy), expected, rel_tol=0.0, abs_tol=1e-12):
            errors.append(f"neighbor distance mismatch {(dx, dy)}")
    return errors


def validate(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    catalog = read_json(CATALOG_PATH)
    detail_source = read_json(DETAIL_SOURCE_PATH)
    detail_by_id = {
        int(item["monster_id"]): item
        for item in detail_source.get("records", [])
        if isinstance(item, dict)
    }
    if detail_source.get("authority") != "user_authoritative_override" or len(detail_by_id) != 217:
        errors.append("21CQ detail source authority/coverage invalid")
    canonical = {int(row["monster_id"]): row for row in catalog["entries"]}
    records = payload.get("records", [])
    seen: set[int] = set()
    for row in records:
        monster_id = int(row.get("monster_id", -1))
        if monster_id in seen or monster_id not in canonical:
            errors.append(f"duplicate/unknown monster_id={monster_id}")
            continue
        seen.add(monster_id)
        if row.get("canonical_name") != canonical[monster_id].get("canonical_name"):
            errors.append(f"monster_id={monster_id} canonical_name drift")
        status = str(row.get("movement_source_status", ""))
        if status not in ALLOWED_SOURCE_STATUSES:
            errors.append(f"monster_id={monster_id} invalid movement status={status}")
        detail_row = detail_by_id.get(monster_id, {})
        interval_authority = dict(row.get("interval_authority", {}))
        expected_raw_interval = detail_row.get("move_interval_ms")
        expected_effective_interval = (
            0
            if bool(row.get("movement_enabled", False)) is False
            else max(200, int(expected_raw_interval or 0))
        )
        if interval_authority.get("authority") != "user_authoritative_override":
            errors.append(f"monster_id={monster_id} move interval lacks 21CQ authority")
        if interval_authority.get("raw_interval_ms") != expected_raw_interval:
            errors.append(f"monster_id={monster_id} raw 21CQ move interval mismatch")
        if int(row.get("walk_interval_ms", -1)) != expected_effective_interval:
            errors.append(f"monster_id={monster_id} effective 21CQ move interval mismatch")
        if status != "LOCKED" and (
            int(row.get("walk_interval_ms", 0)) < 200
            or int(row.get("walk_step", 0)) < 1
            or int(row.get("walk_wait_ms", -1)) < 0
        ):
            errors.append(f"monster_id={monster_id} invalid cadence values")
        binding = row.get("source_binding", {})
        if binding.get("runtime_lookup") != "monster_id_only":
            errors.append(f"monster_id={monster_id} runtime binding is not ID-only")
        server_class = row.get("server_class_binding", {})
        if bool(server_class.get("runtime_name_lookup", True)):
            errors.append(f"monster_id={monster_id} server class enables name lookup")
        conflict = row.get("interval_conflict")
        if conflict is not None and conflict.get("classification") not in CONFLICT_CLASSES:
            errors.append(f"monster_id={monster_id} invalid conflict class")
    if seen != set(canonical):
        errors.append("monster_id set differs from canonical catalog")
    summary = payload.get("summary", {})
    if summary.get("locked_count") != 6:
        errors.append("stationary LOCKED count must be 6")
    if summary.get("accepted_candidate_count") != 138:
        errors.append("accepted candidate count must be 138")
    if summary.get("compatibility_hold_count") != 12:
        errors.append("compatibility hold count must be 12")
    if summary.get("data_hold_count") != 0:
        errors.append("M01 movement source cannot contain DATA_HOLD")
    if payload.get("selected_value_source", {}).get("exact_bindings") != 144:
        errors.append("local 1.76 exact binding count must be 144")
    if payload.get("conflict_policy", {}).get("interval_conflict_count") != 75:
        errors.append("interval conflict count must be 75")
    if payload.get("interval_value_authority", {}).get("authority") != "user_authoritative_override":
        errors.append("top-level move interval authority is not 21CQ")
    for audit in payload.get("server_data_source_audit", []):
        if sha256(ROOT / audit["file"]) != EXPECTED_HASHES[audit["distribution"]]:
            errors.append(f"source hash drift: {audit['distribution']}")
        if audit.get("decision") != "SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH":
            errors.append(f"routed source silently adopted: {audit['distribution']}")
    if sha256(LOCAL_176_DB) != EXPECTED_HASHES["candidate.mylgd_mir2server_176"]:
        errors.append("local 1.76 candidate hash drift")
    errors.extend(validate_quantization(payload.get("temporary_cell_contract", {})))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = build_payload()
    if args.check:
        if not OUTPUT.exists():
            print("MONSTER_MOVEMENT_SOURCE_MASTER_CHECK_FAIL output missing")
            return 1
        actual = read_json(OUTPUT)
        errors = validate(actual)
        if actual != expected:
            errors.append("movement source master is stale; rebuild required")
        if errors:
            for error in errors:
                print(f"ERROR: {error}")
            print(f"MONSTER_MOVEMENT_SOURCE_MASTER_CHECK_FAIL errors={len(errors)}")
            return 1
        summary = actual["summary"]
        print(
            "MONSTER_MOVEMENT_SOURCE_MASTER_CHECK_PASS "
            f"records={summary['canonical_monsters']} locked={summary['locked_count']} "
            f"accepted={summary['accepted_candidate_count']} holds={summary['compatibility_hold_count']}"
        )
        return 0
    errors = validate(expected)
    if errors:
        raise RuntimeError("; ".join(errors))
    OUTPUT.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MONSTER_MOVEMENT_SOURCE_MASTER_BUILD_PASS output={OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
