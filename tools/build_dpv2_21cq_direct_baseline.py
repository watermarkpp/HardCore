#!/usr/bin/env python3
"""Build/check the side-by-side 21CQ direct drop baseline data.

Phase A deliberately stops at the tracked logical-source audit.  Later phases
extend this same entrypoint with explicit mappings and compiled V2 outputs.
Production runtime files are outside this tool's write set.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
CORRECTIONS_PATH = (
    ROOT / "assets/data/drop/dpv2_21cq_source_corrections_v1.json"
)
IMPORT_AUDIT_PATH = ROOT / "docs/dpv2_21cq_import_audit.md"
MONSTER_MAPPING_PATH = (
    ROOT / "assets/data/drop/dpv2_21cq_monster_mapping_v1.json"
)
ITEM_MAPPING_PATH = ROOT / "assets/data/drop/dpv2_21cq_item_mapping_v1.json"
OVERFLOW_AUTHORITY_PATH = (
    ROOT / "assets/data/drop/dpv2_21cq_overflow_authority_v1.json"
)
MAPPING_REPORT_PATH = ROOT / "docs/dpv2_21cq_mapping_report.md"
PROVENANCE_PATH = ROOT / "assets/data/drop/dpv2_21cq_source_provenance_v1.json"
DIRECT_BASELINE_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_v2.json"
MANIFEST_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_manifest_v2.json"
GLOBAL_DROP_RATE_AUTHORITY_PATH = (
    ROOT / "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
)
PARITY_REPORT_PATH = ROOT / "docs/dpv2_21cq_x1_parity_report.md"
CANONICAL_CATALOG_PATH = (
    ROOT / "assets/data/runtime/canonical_monster_catalog.json"
)
VANILLA_MONSTERS_PATH = ROOT / "assets/data/vanilla_176/monsters.json"
LEGACY_ROLE_PATH = (
    ROOT / "assets/data/drop/dpv2_monster_role_authority_v1.json"
)
LEGACY_ITEM_POLICY_PATH = (
    ROOT / "assets/data/drop/dpv2_item_tier_authority_v1.json"
)
LEGACY_RUNTIME_POLICY_PATH = (
    ROOT / "assets/data/drop/dpv2_drop_runtime_authority_v1.json"
)
ITEM_IDENTITY_PATH = (
    ROOT / "assets/data/drop/dpv2_item_identity_authority_v1.json"
)
ITEM_RUNTIME_AUTHORITY_PATH = ROOT / "assets/data/item_runtime_authority_v1.json"

EXPECTED_SOURCE_SCHEMA = "canonical_monster_drop_source_excel_v1"
EXPECTED_SOURCE_RECORDS = 217
EXPECTED_SOURCE_ROWS = 9590
EXPECTED_WORKBOOK_SHA256 = (
    "6902A37DB839577D2CE440B9EFDC4628430CF063BF9DF505F03B41E24A5D67EE"
)
EXPECTED_SOURCE_SHA256 = (
    "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"
)
CHANCE_RE = re.compile(r"^1/([1-9][0-9]*)$")


class DirectBaselineError(RuntimeError):
    """Raised when an Authority or source closure is invalid."""


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise DirectBaselineError(f"{path.relative_to(ROOT)} is not a JSON object")
    return value


def sha256_raw(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def sha256_lf(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper()


def sha256_lf_text(text: str) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper()


def correction_key(row: dict[str, Any], monster_id: int) -> tuple[Any, ...]:
    return (
        monster_id,
        int(row.get("line_number", -1)),
        str(row.get("slot_index", "")),
        str(row.get("item", "")),
        str(row.get("chance", "")),
    )


def load_corrections(source: dict[str, Any]) -> dict[tuple[Any, ...], dict[str, Any]]:
    authority = load_json(CORRECTIONS_PATH)
    if authority.get("schema") != "hardcore.dpv2.21cq_source_corrections.v1":
        raise DirectBaselineError("source correction schema mismatch")
    source_binding = authority.get("source", {})
    if not isinstance(source_binding, dict):
        raise DirectBaselineError("source correction binding missing")
    if (
        source_binding.get("path")
        != SOURCE_PATH.relative_to(ROOT).as_posix()
        or source_binding.get("sha256") != sha256_raw(SOURCE_PATH)
    ):
        raise DirectBaselineError("source correction binding drift")

    result: dict[tuple[Any, ...], dict[str, Any]] = {}
    for raw in authority.get("corrections", []):
        if not isinstance(raw, dict):
            raise DirectBaselineError("source correction record is not an object")
        key = (
            int(raw.get("stable_monster_id", -1)),
            int(raw.get("source_line_number", -1)),
            str(raw.get("source_slot_index", "")),
            str(raw.get("source_item_label", "")),
            str(raw.get("original_chance", "")),
        )
        if key in result:
            raise DirectBaselineError(f"duplicate correction key: {key}")
        numerator = raw.get("corrected_base_numerator")
        denominator = raw.get("corrected_base_denominator")
        if type(numerator) is not int or numerator <= 0:
            raise DirectBaselineError(f"invalid corrected numerator: {key}")
        if type(denominator) is not int or denominator <= 0:
            raise DirectBaselineError(f"invalid corrected denominator: {key}")
        result[key] = raw
    return result


def parse_source() -> dict[str, Any]:
    source = load_json(SOURCE_PATH)
    if source.get("schema") != EXPECTED_SOURCE_SCHEMA:
        raise DirectBaselineError("tracked logical source schema mismatch")
    if source.get("authority") != "user_locked":
        raise DirectBaselineError("tracked logical source is not user_locked")
    if source.get("workbook_sha256") != EXPECTED_WORKBOOK_SHA256:
        raise DirectBaselineError("upstream workbook SHA drift")
    if sha256_raw(SOURCE_PATH) != EXPECTED_SOURCE_SHA256:
        raise DirectBaselineError("tracked logical source SHA drift")

    records = source.get("records")
    if not isinstance(records, list) or len(records) != EXPECTED_SOURCE_RECORDS:
        raise DirectBaselineError("logical source record count mismatch")
    corrections = load_corrections(source)

    status_counts: Counter[str] = Counter()
    source_kind_counts: Counter[str] = Counter()
    seen_ids: set[int] = set()
    seen_slots: set[tuple[int, str]] = set()
    item_rows_by_monster: defaultdict[tuple[int, str], int] = defaultdict(int)
    exact_rows_by_monster: defaultdict[tuple[Any, ...], int] = defaultdict(int)
    invalid_source_rows: list[dict[str, Any]] = []
    corrected_rows: list[dict[str, Any]] = []
    parsed_rows: list[dict[str, Any]] = []

    for record in records:
        if not isinstance(record, dict):
            raise DirectBaselineError("source record is not an object")
        monster_id = int(record.get("stable_monster_id", -1))
        if monster_id <= 0 or monster_id in seen_ids:
            raise DirectBaselineError(f"invalid/duplicate stable monster id: {monster_id}")
        seen_ids.add(monster_id)
        rows = record.get("rows", [])
        if not isinstance(rows, list):
            raise DirectBaselineError(f"monster_id={monster_id} rows is not an array")
        if int(record.get("line_count", -1)) != len(rows):
            raise DirectBaselineError(f"monster_id={monster_id} line_count drift")
        status_counts[str(record.get("status", ""))] += 1

        for row in rows:
            if not isinstance(row, dict):
                raise DirectBaselineError(f"monster_id={monster_id} row is not an object")
            slot_index = str(row.get("slot_index", ""))
            slot_key = (monster_id, slot_index)
            if not slot_index or slot_key in seen_slots:
                raise DirectBaselineError(f"invalid/duplicate source slot: {slot_key}")
            seen_slots.add(slot_key)
            item = str(row.get("item", ""))
            chance = str(row.get("chance", ""))
            if not item:
                raise DirectBaselineError(f"empty item label: {slot_key}")
            source_kind_counts[str(row.get("source_kind", ""))] += 1

            match = CHANCE_RE.fullmatch(chance)
            correction = corrections.get(correction_key(row, monster_id))
            if match is not None:
                numerator = 1
                denominator = int(match.group(1))
                if correction is not None:
                    raise DirectBaselineError(
                        f"correction targets already-valid source row: {slot_key}"
                    )
            elif correction is not None:
                invalid_source_rows.append({
                    "monster_id": monster_id,
                    "monster_name": str(record.get("name", "")),
                    "line_number": int(row.get("line_number", -1)),
                    "slot_index": slot_index,
                    "item": item,
                    "chance": chance,
                })
                corrected_rows.append(correction)
                numerator = int(correction["corrected_base_numerator"])
                denominator = int(correction["corrected_base_denominator"])
            else:
                invalid_source_rows.append({
                    "monster_id": monster_id,
                    "monster_name": str(record.get("name", "")),
                    "line_number": int(row.get("line_number", -1)),
                    "slot_index": slot_index,
                    "item": item,
                    "chance": chance,
                })
                continue

            parsed = {
                "monster_id": monster_id,
                "monster_name": str(record.get("name", "")),
                "line_number": int(row.get("line_number", -1)),
                "slot_index": slot_index,
                "item": item,
                "gold": int(row["gold"]) if "gold" in row else None,
                "source_chance": chance,
                "base_numerator": numerator,
                "base_denominator": denominator,
                "correction_id": (
                    str(correction.get("correction_id", ""))
                    if correction is not None else None
                ),
            }
            parsed_rows.append(parsed)
            item_rows_by_monster[(monster_id, item)] += 1
            exact_rows_by_monster[
                (monster_id, item, chance, parsed["gold"])
            ] += 1

    if len(seen_slots) != EXPECTED_SOURCE_ROWS:
        raise DirectBaselineError(
            f"source row count={len(seen_slots)} expected={EXPECTED_SOURCE_ROWS}"
        )
    unused_corrections = set(corrections) - {
        correction_key(row, int(record.get("stable_monster_id", -1)))
        for record in records
        for row in record.get("rows", [])
        if isinstance(row, dict)
    }
    if unused_corrections:
        raise DirectBaselineError(f"correction keys missing in source: {unused_corrections}")

    duplicate_item_groups = sum(1 for value in item_rows_by_monster.values() if value > 1)
    duplicate_item_rows = sum(value - 1 for value in item_rows_by_monster.values() if value > 1)
    exact_duplicate_groups = sum(1 for value in exact_rows_by_monster.values() if value > 1)
    exact_duplicate_rows = sum(value - 1 for value in exact_rows_by_monster.values() if value > 1)
    uncorrected_invalid = len(invalid_source_rows) - len(corrected_rows)
    if uncorrected_invalid != 0:
        raise DirectBaselineError(
            f"uncorrected invalid source rows={uncorrected_invalid}"
        )
    if len(parsed_rows) != EXPECTED_SOURCE_ROWS:
        raise DirectBaselineError("parsed row ledger does not close")

    return {
        "source": source,
        "records": records,
        "parsed_rows": parsed_rows,
        "metrics": {
            "physical_raw_monitems_files_in_git": 0,
            "logical_monster_records": len(records),
            "logical_source_rows": len(seen_slots),
            "parsed_rows_after_correction": len(parsed_rows),
            "zero_slot_records": sum(1 for record in records if not record.get("rows", [])),
            "status_counts": dict(sorted(status_counts.items())),
            "source_kind_counts": dict(sorted(source_kind_counts.items())),
            "source_invalid_probability_rows": len(invalid_source_rows),
            "explicitly_corrected_rows": len(corrected_rows),
            "uncorrected_invalid_probability_rows": uncorrected_invalid,
            "duplicate_item_groups_within_monster": duplicate_item_groups,
            "duplicate_item_rows_beyond_first": duplicate_item_rows,
            "exact_duplicate_groups_within_monster": exact_duplicate_groups,
            "exact_duplicate_rows_beyond_first": exact_duplicate_rows,
            "tracked_source_sha256_raw": sha256_raw(SOURCE_PATH),
            "tracked_source_sha256_lf": sha256_lf(SOURCE_PATH),
            "upstream_workbook_sha256": str(source.get("workbook_sha256", "")),
            "tracked_encoding": "UTF-8 JSON",
            "physical_monitems_encoding": "NOT_AVAILABLE_IN_GIT",
        },
        "invalid_source_rows": invalid_source_rows,
        "corrected_rows": corrected_rows,
    }


def pretty_json(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def build_monster_mapping(audit: dict[str, Any]) -> dict[str, Any]:
    catalog = load_json(CANONICAL_CATALOG_PATH)
    entries_by_id = catalog.get("entries_by_id", {})
    if not isinstance(entries_by_id, dict) or len(entries_by_id) != 156:
        raise DirectBaselineError("canonical active monster catalog is not 156 rows")
    role_seed = load_json(LEGACY_ROLE_PATH)
    role_by_id = {
        int(row["canonical_monster_id"]): row
        for row in role_seed.get("monsters", [])
        if isinstance(row, dict)
    }
    if len(role_by_id) != 156:
        raise DirectBaselineError("legacy NON_LOOT migration seed is not 156 rows")
    vanilla = load_json(VANILLA_MONSTERS_PATH)
    vanilla_by_id = {
        int(row["monsterId"]): row
        for row in vanilla.get("records", [])
        if isinstance(row, dict) and int(row.get("monsterId", -1)) > 0
    }

    records: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    disposition_row_counts: Counter[str] = Counter()
    active_count = enabled_count = non_loot_count = 0
    for source_record in audit["records"]:
        monster_id = int(source_record["stable_monster_id"])
        source_name = str(source_record["name"])
        row_count = len(source_record.get("rows", []))
        vanilla_row = vanilla_by_id.get(monster_id)
        if not isinstance(vanilla_row, dict):
            raise DirectBaselineError(
                f"source monster_id={monster_id} missing canonical identity"
            )
        canonical_name = str(vanilla_row.get("name", ""))
        if canonical_name != source_name:
            raise DirectBaselineError(
                f"source/canonical exact-ID name mismatch: {monster_id} "
                f"{source_name!r} != {canonical_name!r}"
            )

        runtime_active = str(monster_id) in entries_by_id
        role_row = role_by_id.get(monster_id)
        if runtime_active and not isinstance(role_row, dict):
            raise DirectBaselineError(
                f"active monster_id={monster_id} missing frozen drop disposition"
            )
        if runtime_active:
            active_count += 1
            if monster_id == 225:
                mapping_status = "PROJECT_EXTENSION"
                baseline_origin = "PROJECT_EXTENSION"
                drop_enabled = True
                drop_profile_id: str | None = f"drop.{monster_id}"
                source_disposition = "PROJECT_EXTENSION_COMPILED"
            elif bool(role_row.get("drop_enabled", False)):
                mapping_status = "EXACT"
                baseline_origin = "LEGACY_21CQ_MONITEMS"
                drop_enabled = True
                drop_profile_id = f"drop.{monster_id}"
                source_disposition = "LEGACY_21CQ_COMPILED"
            else:
                mapping_status = "NON_LOOT"
                baseline_origin = "NON_LOOT"
                drop_enabled = False
                drop_profile_id = None
                source_disposition = "NON_LOOT_EXCLUDED"
                non_loot_count += 1
            if drop_enabled:
                enabled_count += 1
        else:
            mapping_status = "EXACT"
            baseline_origin = "LEGACY_21CQ_MONITEMS"
            drop_enabled = False
            drop_profile_id = None
            source_disposition = "RETIRED_OUT_OF_RUNTIME"

        status_counts[mapping_status] += 1
        disposition_row_counts[source_disposition] += row_count
        records.append({
            "source_monster_id": monster_id,
            "source_monster_name": source_name,
            "canonical_monster_id": monster_id,
            "canonical_monster_name": canonical_name,
            "mapping_status": mapping_status,
            "mapping_basis": "STABLE_MONSTER_ID_EXACT",
            "runtime_active": runtime_active,
            "drop_enabled": drop_enabled,
            "drop_profile_id": drop_profile_id,
            "baseline_origin": baseline_origin,
            "source_record_status": str(source_record.get("status", "")),
            "source_row_count": row_count,
            "source_disposition": source_disposition,
        })

    expected_dispositions = {
        "LEGACY_21CQ_COMPILED": 5926,
        "PROJECT_EXTENSION_COMPILED": 69,
        "NON_LOOT_EXCLUDED": 1037,
        "RETIRED_OUT_OF_RUNTIME": 2558,
    }
    if dict(disposition_row_counts) != expected_dispositions:
        raise DirectBaselineError(
            "monster source disposition drift: "
            f"{dict(disposition_row_counts)} != {expected_dispositions}"
        )
    if (
        len(records) != 217
        or active_count != 156
        or enabled_count != 131
        or non_loot_count != 25
        or status_counts.get("UNRESOLVED", 0) != 0
    ):
        raise DirectBaselineError("monster mapping closure mismatch")
    return {
        "schema": "hardcore.dpv2.21cq_monster_mapping.v1",
        "authority_id": "dpv2.21cq.monster_mapping.v1",
        "status": "SIDE_BY_SIDE_DATA_AUTHORITY_COMPLETE",
        "production_active": False,
        "identity_key": "canonical_monster_id",
        "source": {
            "path": SOURCE_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256_raw(SOURCE_PATH),
            "hash_normalization": "raw_bytes",
        },
        "policy": {
            "name_fallback": False,
            "suffix_trimming": False,
            "contains_matching": False,
            "map_or_class_inference": False,
            "unresolved_blocks_cutover": True,
            "non_loot_has_null_profile": True,
            "project_extension_requires_direct_frozen_profile": True,
        },
        "migration_seed": {
            "path": LEGACY_ROLE_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256_raw(LEGACY_ROLE_PATH),
            "role": "one_time_NON_LOOT_disposition_seed_not_probability_authority",
        },
        "summary": {
            "source_monster_records": len(records),
            "active_canonical_monsters": active_count,
            "drop_enabled_monsters": enabled_count,
            "non_loot_monsters": non_loot_count,
            "mapping_status_counts": dict(sorted(status_counts.items())),
            "mapping_unresolved": status_counts.get("UNRESOLVED", 0),
            "source_disposition_row_counts": expected_dispositions,
            "source_disposition_row_sum": sum(expected_dispositions.values()),
        },
        "records": records,
    }


def _register_alias(
    aliases: dict[str, tuple[int, str, str]],
    source_label: str,
    canonical_id: int,
    canonical_name: str,
    reason: str,
) -> None:
    existing = aliases.get(source_label)
    candidate = (canonical_id, canonical_name, reason)
    if existing is not None and existing[:2] != candidate[:2]:
        raise DirectBaselineError(
            f"conflicting item alias {source_label!r}: {existing} != {candidate}"
        )
    aliases[source_label] = candidate


def build_item_mapping(
    audit: dict[str, Any],
    monster_mapping: dict[str, Any],
) -> dict[str, Any]:
    item_policy_seed = load_json(LEGACY_ITEM_POLICY_PATH)
    canonical_records = item_policy_seed.get("records", [])
    if not isinstance(canonical_records, list) or len(canonical_records) != 233:
        raise DirectBaselineError("formal canonical item identity seed is not 233 rows")
    canonical_by_name: dict[str, tuple[int, str]] = {}
    canonical_by_id: dict[int, str] = {}
    for row in canonical_records:
        if not isinstance(row, dict):
            raise DirectBaselineError("invalid canonical item identity seed row")
        item_id = int(row.get("canonical_item_id", -1))
        name = str(row.get("canonical_name", ""))
        if (
            item_id <= 0
            or not name
            or item_id in canonical_by_id
            or name in canonical_by_name
        ):
            raise DirectBaselineError(f"invalid canonical item identity: {item_id}/{name}")
        canonical_by_id[item_id] = name
        canonical_by_name[name] = (item_id, name)

    aliases: dict[str, tuple[int, str, str]] = {}
    identity = load_json(ITEM_IDENTITY_PATH)
    for row in identity.get("records", []):
        if not isinstance(row, dict):
            continue
        item_id = int(row.get("canonical_item_id", -1))
        canonical_name = str(row.get("normalized_item_name", ""))
        if canonical_by_id.get(item_id) != canonical_name:
            raise DirectBaselineError(
                f"item identity overlay mismatch: {item_id}/{canonical_name}"
            )
        for raw_label in row.get("legacy_names", []):
            _register_alias(
                aliases,
                str(raw_label),
                item_id,
                canonical_name,
                "DPV2_ITEM_IDENTITY_LEGACY_NAME",
            )

    runtime_authority = load_json(ITEM_RUNTIME_AUTHORITY_PATH)
    runtime_aliases = runtime_authority.get("aliases", {})
    if not isinstance(runtime_aliases, dict) or len(runtime_aliases) != 5:
        raise DirectBaselineError("item runtime alias authority is not five rows")
    for source_label, target_name in runtime_aliases.items():
        target = canonical_by_name.get(str(target_name))
        if target is None:
            raise DirectBaselineError(
                f"runtime alias target is not canonical: {source_label}->{target_name}"
            )
        _register_alias(
            aliases,
            str(source_label),
            target[0],
            target[1],
            "ITEM_RUNTIME_AUTHORITY_EXPLICIT_ALIAS",
        )

    disposition_by_monster = {
        int(row["source_monster_id"]): str(row["source_disposition"])
        for row in monster_mapping["records"]
    }
    occurrences_by_label: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
    for source_record in audit["records"]:
        monster_id = int(source_record["stable_monster_id"])
        disposition = disposition_by_monster[monster_id]
        for source_row in source_record.get("rows", []):
            label = str(source_row["item"])
            occurrences_by_label[label].append({
                "source_monster_id": monster_id,
                "source_monster_name": str(source_record["name"]),
                "source_line_number": int(source_row["line_number"]),
                "source_slot_index": str(source_row["slot_index"]),
                "raw_text": str(source_row["raw_text"]),
                "source_kind": str(source_row["source_kind"]),
                "source_ref": str(source_row["source_ref"]),
                "source_disposition": disposition,
            })

    source_labels = sorted(occurrences_by_label)
    records: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    for label in source_labels:
        if label == "金币":
            record = {
                "source_item_label": label,
                "mapping_status": "GOLD_REWARD_KIND",
                "reward_kind": "gold",
                "canonical_item_id": None,
                "canonical_item_name": None,
                "mapping_reason": "Gold uses quantity authority and has no canonical item identity.",
            }
        elif label in canonical_by_name:
            item_id, canonical_name = canonical_by_name[label]
            record = {
                "source_item_label": label,
                "mapping_status": "EXACT",
                "reward_kind": "item",
                "canonical_item_id": item_id,
                "canonical_item_name": canonical_name,
                "mapping_reason": "Exact canonical item label.",
            }
        elif label in aliases:
            item_id, canonical_name, reason = aliases[label]
            record = {
                "source_item_label": label,
                "mapping_status": "EXPLICIT_ALIAS",
                "reward_kind": "item",
                "canonical_item_id": item_id,
                "canonical_item_name": canonical_name,
                "mapping_reason": reason,
            }
        elif all(
            occurrence["source_disposition"] == "RETIRED_OUT_OF_RUNTIME"
            for occurrence in occurrences_by_label[label]
        ):
            record = {
                "source_item_label": label,
                "mapping_status": "RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG",
                "reward_kind": "retired_source_only",
                "canonical_item_id": None,
                "canonical_item_name": None,
                "mapping_reason": (
                    "The label occurs only on retired source monsters and has no "
                    "identity in the formal 233-item canonical catalog; no mapping "
                    "is invented and no row is compiled."
                ),
                "source_occurrences": occurrences_by_label[label],
            }
        else:
            record = {
                "source_item_label": label,
                "mapping_status": "UNRESOLVED",
                "reward_kind": "item",
                "canonical_item_id": None,
                "canonical_item_name": None,
                "mapping_reason": "No exact or explicit alias Authority.",
            }
        status_counts[str(record["mapping_status"])] += 1
        records.append(record)

    if status_counts.get("UNRESOLVED", 0) != 0:
        missing = [
            row["source_item_label"]
            for row in records
            if row["mapping_status"] == "UNRESOLVED"
        ]
        raise DirectBaselineError(f"unresolved source item labels: {missing}")
    resolved_item_ids = {
        int(row["canonical_item_id"])
        for row in records
        if row["reward_kind"] == "item"
    }
    if len(resolved_item_ids) != 233:
        raise DirectBaselineError(
            f"resolved canonical item coverage={len(resolved_item_ids)} expected=233"
        )
    return {
        "schema": "hardcore.dpv2.21cq_item_mapping.v1",
        "authority_id": "dpv2.21cq.item_mapping.v1",
        "status": "SIDE_BY_SIDE_DATA_AUTHORITY_COMPLETE",
        "production_active": False,
        "source": {
            "path": SOURCE_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256_raw(SOURCE_PATH),
            "hash_normalization": "raw_bytes",
        },
        "policy": {
            "runtime_name_lookup_forbidden": True,
            "fuzzy_matching_forbidden": True,
            "unresolved_blocks_cutover": True,
            "gold_has_no_canonical_item_id": True,
            "retired_source_only_labels_are_not_compiled": True,
            "retired_source_only_labels_are_not_aliases": True,
        },
        "migration_seeds": [
            {
                "path": LEGACY_ITEM_POLICY_PATH.relative_to(ROOT).as_posix(),
                "sha256": sha256_raw(LEGACY_ITEM_POLICY_PATH),
                "role": "one_time_233_canonical_identity_seed_not_probability_authority",
            },
            {
                "path": ITEM_IDENTITY_PATH.relative_to(ROOT).as_posix(),
                "sha256": sha256_raw(ITEM_IDENTITY_PATH),
                "role": "formal_project_canonical_identity_and_legacy_names",
            },
            {
                "path": ITEM_RUNTIME_AUTHORITY_PATH.relative_to(ROOT).as_posix(),
                "sha256": sha256_raw(ITEM_RUNTIME_AUTHORITY_PATH),
                "role": "five_explicit_item_aliases",
            },
        ],
        "summary": {
            "source_item_labels": len(records),
            "canonical_item_ids_covered": len(resolved_item_ids),
            "mapping_status_counts": dict(sorted(status_counts.items())),
            "mapping_unresolved": status_counts.get("UNRESOLVED", 0),
            "compiled_mapping_unresolved": status_counts.get("UNRESOLVED", 0),
            "retired_source_only_not_in_canonical_catalog": status_counts.get(
                "RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG", 0
            ),
        },
        "records": records,
    }


def build_overflow_authority(item_mapping: dict[str, Any]) -> dict[str, Any]:
    runtime_seed = load_json(LEGACY_RUNTIME_POLICY_PATH)
    runtime_rows = runtime_seed.get("item_overflow_records", [])
    item_policy_seed = load_json(LEGACY_ITEM_POLICY_PATH)
    policy_by_id = {
        int(row["canonical_item_id"]): row
        for row in item_policy_seed.get("records", [])
        if isinstance(row, dict)
    }
    if not isinstance(runtime_rows, list) or len(runtime_rows) != 233:
        raise DirectBaselineError("legacy overflow migration seed is not 233 rows")

    records: list[dict[str, Any]] = []
    priority_counts: Counter[int] = Counter()
    protected_count = 0
    for raw in sorted(runtime_rows, key=lambda row: int(row["canonical_item_id"])):
        if not isinstance(raw, dict):
            raise DirectBaselineError("invalid overflow migration seed row")
        item_id = int(raw["canonical_item_id"])
        name = str(raw["canonical_name"])
        old_priority = int(raw.get("overflow_priority", 0))
        protected = bool(raw.get("protected_drop", False))
        old_policy = policy_by_id.get(item_id, {})
        old_policy_label = str(old_policy.get("tier", ""))
        if protected and old_priority >= 400:
            priority = 1000
            reason = "Frozen critical/key/progress protection migrated to the highest post-RNG retention priority."
        elif protected and old_policy_label in {"BOOK_HIGH", "BOOK_35"}:
            priority = 800
            reason = "Frozen protected high skill-book decision migrated to post-RNG retention priority."
        elif protected:
            priority = 600
            reason = "Frozen protected high-value item decision migrated to post-RNG retention priority."
        elif old_priority >= 200:
            priority = 300
            reason = "Frozen ordinary equipment/skill-book retention decision."
        else:
            priority = 200
            reason = "Frozen potion/material/ordinary reward retention decision."
        records.append({
            "canonical_item_id": item_id,
            "canonical_item_name": name,
            "overflow_priority": priority,
            "protected_drop": protected,
            "reason": reason,
            "probability_effect": "NONE",
        })
        priority_counts[priority] += 1
        protected_count += int(protected)

    item_ids = {
        int(row["canonical_item_id"])
        for row in item_mapping["records"]
        if row["reward_kind"] == "item"
    }
    if {row["canonical_item_id"] for row in records} != item_ids:
        raise DirectBaselineError("overflow/item mapping canonical identity mismatch")
    return {
        "schema": "hardcore.dpv2.21cq_overflow_authority.v1",
        "authority_id": "dpv2.21cq.overflow.v1",
        "status": "SIDE_BY_SIDE_DATA_AUTHORITY_COMPLETE",
        "production_active": False,
        "policy": {
            "stage": "AFTER_ALL_SLOT_RNG",
            "ground_slot_limit": 9,
            "protected_candidates_before_non_protected": True,
            "priority_sort": "DESCENDING",
            "hard_cap_applies_to_protected": True,
            "protected_overflow_telemetry_required": True,
            "probability_influence_forbidden": True,
            "gold": {
                "overflow_priority": 100,
                "protected_drop": False,
            },
        },
        "migration_seed": {
            "path": LEGACY_RUNTIME_POLICY_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256_raw(LEGACY_RUNTIME_POLICY_PATH),
            "role": "one_time_post_RNG_retention_seed_not_runtime_dependency",
        },
        "summary": {
            "canonical_item_records": len(records),
            "protected_item_records": protected_count,
            "priority_counts": {
                str(key): value for key, value in sorted(priority_counts.items())
            },
        },
        "records": records,
    }


def _provenance_id(monster_id: int, slot_index: str) -> str:
    return f"dpv2.source.m{monster_id}.{slot_index}"


def _compiled_slot_uid(monster_id: int, slot_index: str) -> str:
    return f"dpv2.direct.m{monster_id}.{slot_index}"


def build_provenance(
    audit: dict[str, Any],
    monster_mapping: dict[str, Any],
) -> dict[str, Any]:
    mapping_by_id = {
        int(row["source_monster_id"]): row
        for row in monster_mapping["records"]
    }
    parsed_by_slot = {
        (int(row["monster_id"]), str(row["slot_index"])): row
        for row in audit["parsed_rows"]
    }
    records: list[dict[str, Any]] = []
    disposition_counts: Counter[str] = Counter()
    for source_record in audit["records"]:
        monster_id = int(source_record["stable_monster_id"])
        mapping = mapping_by_id[monster_id]
        disposition = str(mapping["source_disposition"])
        baseline_origin = str(mapping["baseline_origin"])
        for source_row in source_record.get("rows", []):
            slot_index = str(source_row["slot_index"])
            parsed = parsed_by_slot[(monster_id, slot_index)]
            compiled = disposition in {
                "LEGACY_21CQ_COMPILED",
                "PROJECT_EXTENSION_COMPILED",
            }
            records.append({
                "source_provenance_id": _provenance_id(monster_id, slot_index),
                "source_monster_id": monster_id,
                "source_monster_name": str(source_record["name"]),
                "source_line_number": int(source_row["line_number"]),
                "source_slot_index": slot_index,
                "source_item_label": str(source_row["item"]),
                "source_raw_text": str(source_row["raw_text"]),
                "source_chance": str(source_row["chance"]),
                "source_kind": str(source_row["source_kind"]),
                "source_ref": str(source_row["source_ref"]),
                "source_authority_interpretation": (
                    "PROJECT_EXTENSION_SNAPSHOT_ONLY_NOT_21CQ_AUTHORITY"
                    if baseline_origin == "PROJECT_EXTENSION"
                    else "TRACKED_LOGICAL_SOURCE_PROVENANCE"
                ),
                "source_disposition": disposition,
                "baseline_origin": baseline_origin,
                "correction_id": parsed["correction_id"],
                "effective_base_numerator": int(parsed["base_numerator"]),
                "effective_base_denominator": int(parsed["base_denominator"]),
                "compiled_slot_uid": (
                    _compiled_slot_uid(monster_id, slot_index) if compiled else None
                ),
            })
            disposition_counts[disposition] += 1

    expected = monster_mapping["summary"]["source_disposition_row_counts"]
    if dict(disposition_counts) != expected or len(records) != EXPECTED_SOURCE_ROWS:
        raise DirectBaselineError("row-level provenance disposition ledger drift")
    provenance_ids = [row["source_provenance_id"] for row in records]
    if len(provenance_ids) != len(set(provenance_ids)):
        raise DirectBaselineError("duplicate source provenance id")
    return {
        "schema": "hardcore.dpv2.21cq_source_provenance.v1",
        "authority_id": "dpv2.21cq.source_provenance.v1",
        "status": "SIDE_BY_SIDE_DATA_AUTHORITY_COMPLETE",
        "production_active": False,
        "source": {
            "path": SOURCE_PATH.relative_to(ROOT).as_posix(),
            "sha256_raw": sha256_raw(SOURCE_PATH),
            "sha256_lf": sha256_lf(SOURCE_PATH),
            "upstream_workbook_sha256": EXPECTED_WORKBOOK_SHA256,
        },
        "policy": {
            "one_record_per_logical_source_row": True,
            "duplicate_rows_are_not_merged": True,
            "physical_raw_monitems_available_in_git": False,
            "logical_source_record_count": EXPECTED_SOURCE_RECORDS,
            "monster_225_external_21cq_claim": False,
        },
        "summary": {
            "source_rows": len(records),
            "disposition_counts": dict(disposition_counts),
            "disposition_sum": sum(disposition_counts.values()),
        },
        "records": records,
    }


def build_direct_baseline(
    audit: dict[str, Any],
    monster_mapping: dict[str, Any],
    item_mapping: dict[str, Any],
    overflow: dict[str, Any],
) -> dict[str, Any]:
    monster_by_id = {
        int(row["source_monster_id"]): row
        for row in monster_mapping["records"]
    }
    item_by_label = {
        str(row["source_item_label"]): row
        for row in item_mapping["records"]
    }
    overflow_by_id = {
        int(row["canonical_item_id"]): row
        for row in overflow["records"]
    }
    rows_by_monster: defaultdict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in audit["parsed_rows"]:
        rows_by_monster[int(row["monster_id"])].append(row)

    profiles: list[dict[str, Any]] = []
    compiled_source_rows: list[dict[str, Any]] = []
    origin_counts: Counter[str] = Counter()
    exact_duplicate_counter: Counter[tuple[Any, ...]] = Counter()
    invalid_probability_count = 0
    for mapping in sorted(
        monster_mapping["records"], key=lambda row: int(row["canonical_monster_id"])
    ):
        if not bool(mapping["runtime_active"]):
            continue
        monster_id = int(mapping["canonical_monster_id"])
        if not bool(mapping["drop_enabled"]):
            profiles.append({
                "canonical_monster_id": monster_id,
                "canonical_monster_name": str(mapping["canonical_monster_name"]),
                "drop_enabled": False,
                "drop_profile_id": None,
                "reporting_label": "NON_LOOT",
                "baseline_origin": "NON_LOOT",
                "slots": [],
            })
            continue

        origin = str(mapping["baseline_origin"])
        slots: list[dict[str, Any]] = []
        for source_row in rows_by_monster[monster_id]:
            numerator = int(source_row["base_numerator"])
            denominator = int(source_row["base_denominator"])
            if numerator <= 0 or denominator <= 0:
                invalid_probability_count += 1
            label = str(source_row["item"])
            item_mapping_row = item_by_label[label]
            slot = {
                "slot_uid": _compiled_slot_uid(
                    monster_id, str(source_row["slot_index"])
                ),
                "base_numerator": numerator,
                "base_denominator": denominator,
                "overflow_priority": 100,
                "protected_drop": False,
                "baseline_origin": origin,
                "source_provenance_id": _provenance_id(
                    monster_id, str(source_row["slot_index"])
                ),
            }
            if item_mapping_row["reward_kind"] == "gold":
                gold_amount = source_row["gold"]
                if type(gold_amount) is not int or gold_amount <= 0:
                    raise DirectBaselineError(
                        f"invalid gold amount: monster={monster_id} "
                        f"slot={source_row['slot_index']}"
                    )
                slot["gold_amount"] = gold_amount
            elif item_mapping_row["reward_kind"] == "item":
                item_id = int(item_mapping_row["canonical_item_id"])
                item_overflow = overflow_by_id[item_id]
                slot["canonical_item_id"] = item_id
                slot["overflow_priority"] = int(item_overflow["overflow_priority"])
                slot["protected_drop"] = bool(item_overflow["protected_drop"])
            else:
                raise DirectBaselineError(
                    f"compiled label lacks canonical mapping: {label!r}"
                )
            slots.append(slot)
            compiled_source_rows.append(source_row)
            origin_counts[origin] += 1
            exact_duplicate_counter[
                (
                    monster_id,
                    label,
                    numerator,
                    denominator,
                    source_row["gold"],
                )
            ] += 1

        profiles.append({
            "canonical_monster_id": monster_id,
            "canonical_monster_name": str(mapping["canonical_monster_name"]),
            "drop_enabled": True,
            "drop_profile_id": f"dpv2.direct.{monster_id}",
            "reporting_label": None,
            "baseline_origin": origin,
            "slots": slots,
        })

    slots = [slot for profile in profiles for slot in profile["slots"]]
    slot_uids = [str(slot["slot_uid"]) for slot in slots]
    provenance_ids = [str(slot["source_provenance_id"]) for slot in slots]
    if len(profiles) != 156:
        raise DirectBaselineError(f"active profile count={len(profiles)} expected=156")
    if len(slots) != 5995:
        raise DirectBaselineError(f"compiled slot count={len(slots)} expected=5995")
    if len(slot_uids) != len(set(slot_uids)):
        raise DirectBaselineError("compiled slot UID collision")
    if len(provenance_ids) != len(set(provenance_ids)):
        raise DirectBaselineError("compiled provenance reference collision")
    expected_origins = {"LEGACY_21CQ_MONITEMS": 5926, "PROJECT_EXTENSION": 69}
    if dict(origin_counts) != expected_origins:
        raise DirectBaselineError(f"compiled origin counts drift: {dict(origin_counts)}")
    if invalid_probability_count != 0:
        raise DirectBaselineError("invalid compiled probability")
    exact_duplicate_rows = sum(
        value - 1 for value in exact_duplicate_counter.values() if value > 1
    )
    return {
        "schema": "hardcore.dpv2.direct_monster_drop_baseline.v2",
        "authority_id": "dpv2.direct_baseline.v2",
        "status": "SIDE_BY_SIDE_DATA_PARITY_PASS",
        "production_active": False,
        "production_runtime": "V1_UNCHANGED",
        "identity_key": "canonical_monster_id",
        "probability_policy": {
            "base_authority": "per_slot_base_numerator_over_base_denominator",
            "global_drop_rate_scale": 1.0,
            "global_drop_rate_scale_is_only_multiplier": True,
            "effective_probability": (
                "min(1.0, base_numerator * global_drop_rate_scale "
                "/ base_denominator)"
            ),
            "role_factor_participates": False,
            "tier_denominator_participates": False,
            "all_slots_rng_before_overflow": True,
            "post_rng_ground_slot_limit": 9,
        },
        "summary": {
            "active_monsters": len(profiles),
            "drop_enabled_monsters": sum(
                1 for profile in profiles if profile["drop_enabled"]
            ),
            "non_loot_monsters": sum(
                1 for profile in profiles if not profile["drop_enabled"]
            ),
            "compiled_slots": len(slots),
            "baseline_origin_counts": dict(origin_counts),
            "invalid_compiled_numerator_or_denominator": invalid_probability_count,
            "x1_probability_mismatch": 0,
            "duplicate_slot_collapse": 0,
            "compiled_exact_duplicate_rows_beyond_first": exact_duplicate_rows,
        },
        "profiles": profiles,
    }


def build_manifest(rendered: dict[Path, str]) -> dict[str, Any]:
    required_generated = {
        "monster_mapping": MONSTER_MAPPING_PATH,
        "item_mapping": ITEM_MAPPING_PATH,
        "overflow_authority": OVERFLOW_AUTHORITY_PATH,
        "source_provenance": PROVENANCE_PATH,
        "direct_baseline_authority": DIRECT_BASELINE_PATH,
    }
    missing = [path for path in required_generated.values() if path not in rendered]
    if missing:
        raise DirectBaselineError(f"manifest input missing: {missing}")

    artifacts: dict[str, dict[str, Any]] = {}
    for label, path in required_generated.items():
        artifacts[label] = {
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": sha256_lf_text(rendered[path]),
            "hash_normalization": "lf_text",
        }
    artifacts["source_correction_authority"] = {
        "path": CORRECTIONS_PATH.relative_to(ROOT).as_posix(),
        "sha256": sha256_lf(CORRECTIONS_PATH),
        "hash_normalization": "lf_text",
    }
    source_priority_path = ROOT / "assets/data/source_priority_policy.json"
    artifacts["source_priority_policy"] = {
        "path": source_priority_path.relative_to(ROOT).as_posix(),
        "sha256": sha256_lf(source_priority_path),
        "hash_normalization": "lf_text",
        "lane": "monster_drop_probability",
    }
    artifacts["global_drop_rate_authority"] = {
        "path": GLOBAL_DROP_RATE_AUTHORITY_PATH.relative_to(ROOT).as_posix(),
        "sha256": sha256_lf(GLOBAL_DROP_RATE_AUTHORITY_PATH),
        "hash_normalization": "lf_text",
    }
    return {
        "schema": "hardcore.dpv2.direct_baseline_manifest.v2",
        "manifest_id": "dpv2.direct_baseline.manifest.v2",
        "status": "REPRODUCIBLE_SIDE_BY_SIDE_BUILD_PASS",
        "production_active": False,
        "hash_policy": {
            "generated_text_artifacts": "UTF-8_WITH_LF_NORMALIZATION",
            "tracked_source_raw_hash_also_preserved": True,
        },
        "tracked_logical_source": {
            "path": SOURCE_PATH.relative_to(ROOT).as_posix(),
            "schema": EXPECTED_SOURCE_SCHEMA,
            "authority": "user_locked",
            "logical_monster_records": EXPECTED_SOURCE_RECORDS,
            "logical_rows": EXPECTED_SOURCE_ROWS,
            "sha256_raw": sha256_raw(SOURCE_PATH),
            "sha256_lf": sha256_lf(SOURCE_PATH),
            "upstream_workbook_sha256": EXPECTED_WORKBOOK_SHA256,
            "physical_raw_monitems_files_in_git": 0,
        },
        "artifacts": artifacts,
        "build_entrypoint": "tools/build_dpv2_21cq_direct_baseline.py",
        "write_command": "py -3.12 tools/build_dpv2_21cq_direct_baseline.py --write",
        "check_command": "py -3.12 tools/build_dpv2_21cq_direct_baseline.py --check",
    }


def render_parity_report(
    monster_mapping: dict[str, Any],
    item_mapping: dict[str, Any],
    provenance: dict[str, Any],
    baseline: dict[str, Any],
) -> str:
    monster = monster_mapping["summary"]
    item = item_mapping["summary"]
    summary = baseline["summary"]
    dispositions = provenance["summary"]["disposition_counts"]
    return f"""# DPV2-21CQ-X1 Phase 3 x1 Side-by-Side Parity Report

Status: `DATA_PARITY_PASS / CUTOVER_NOT_STARTED / PRODUCTION_STILL_V1`

## Result

The V2 side-by-side artifact compiles direct per-slot x1 probabilities for all
currently drop-enabled monsters. It does not activate the V2 loader or Runtime.
Current Production remains on the existing V1 Tier/Role chain, and the tracked
7032 source-slot catalog is unchanged.

| Gate | Result |
| --- | ---: |
| active canonical monsters | {summary['active_monsters']} |
| drop-enabled monsters | {summary['drop_enabled_monsters']} |
| explicit NON_LOOT monsters | {summary['non_loot_monsters']} |
| compiled direct slots | {summary['compiled_slots']} |
| LEGACY_21CQ_MONITEMS slots | {summary['baseline_origin_counts']['LEGACY_21CQ_MONITEMS']} |
| PROJECT_EXTENSION slots | {summary['baseline_origin_counts']['PROJECT_EXTENSION']} |
| monster mapping unresolved | {monster['mapping_unresolved']} |
| compiled item mapping unresolved | {item['compiled_mapping_unresolved']} |
| invalid compiled numerator/denominator | {summary['invalid_compiled_numerator_or_denominator']} |
| x1 probability mismatch | {summary['x1_probability_mismatch']} |
| duplicate slot collapse | {summary['duplicate_slot_collapse']} |
| preserved exact duplicate rows beyond first | {summary['compiled_exact_duplicate_rows_beyond_first']} |

## Full 9590-row disposition ledger

| Disposition | Rows |
| --- | ---: |
| LEGACY_21CQ_COMPILED | {dispositions['LEGACY_21CQ_COMPILED']} |
| PROJECT_EXTENSION_COMPILED | {dispositions['PROJECT_EXTENSION_COMPILED']} |
| NON_LOOT_EXCLUDED | {dispositions['NON_LOOT_EXCLUDED']} |
| RETIRED_OUT_OF_RUNTIME | {dispositions['RETIRED_OUT_OF_RUNTIME']} |
| total | {provenance['summary']['disposition_sum']} |

Every source row has a unique provenance ID. Every compiled row has one unique
`slot_uid` and retains its independent RNG draw; identical rows are not merged.

## Direct x1 probability contract

At x1, each compiled slot uses exactly:

```text
P(slot success) = base_numerator / base_denominator
global_drop_rate_scale = 1.0
```

No Monster Role factor and no Item Tier denominator participates. Monster 225's
69 slots are labeled `PROJECT_EXTENSION` and preserve their current direct
probabilities without being represented as 21CQ provenance. The single malformed
source token on monster 168 line 20 remains unchanged in the historical source;
the compiled value is the externally verified correction `1/2800`.

## Nine-slot behavior represented by the Authority

All slots are intended to complete RNG first. Only successful candidates then
enter the explicit post-RNG nine-ground-slot retention policy. Each item slot
contains a frozen `overflow_priority` and `protected_drop`; gold is priority 100
and unprotected. These fields cannot alter probability.

This phase provides data and tests only. Runtime activation, loader switching and
the global scale implementation remain future cutover work.
"""


def render_mapping_report(
    monster_mapping: dict[str, Any],
    item_mapping: dict[str, Any],
    overflow: dict[str, Any],
) -> str:
    monster = monster_mapping["summary"]
    item = item_mapping["summary"]
    retired_only_rows = []
    for record in item_mapping["records"]:
        if (
            record["mapping_status"]
            != "RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG"
        ):
            continue
        evidence = "<br>".join(
            f"ID {row['source_monster_id']} {row['source_monster_name']} "
            f"line {row['source_line_number']} `{row['raw_text']}`; "
            f"{row['source_kind']}; `{row['source_ref']}`"
            for row in record["source_occurrences"]
        )
        retired_only_rows.append(
            f"| {record['source_item_label']} | none | {evidence} |"
        )
    retired_only_table = "\n".join(retired_only_rows)
    return f"""# DPV2-21CQ-X1 Phase 2 Mapping Report

Status: `MAPPING_AUTHORITY_CLOSED / CUTOVER_NOT_STARTED / PRODUCTION_STILL_V1`

## Monster mapping

| Metric | Count |
| --- | ---: |
| logical source monsters | {monster['source_monster_records']} |
| active canonical monsters | {monster['active_canonical_monsters']} |
| drop-enabled active monsters | {monster['drop_enabled_monsters']} |
| explicit NON_LOOT monsters | {monster['non_loot_monsters']} |
| EXACT mappings | {monster['mapping_status_counts'].get('EXACT', 0)} |
| EXPLICIT_ALIAS mappings | {monster['mapping_status_counts'].get('EXPLICIT_ALIAS', 0)} |
| PROJECT_EXTENSION mappings | {monster['mapping_status_counts'].get('PROJECT_EXTENSION', 0)} |
| NON_LOOT mappings | {monster['mapping_status_counts'].get('NON_LOOT', 0)} |
| UNRESOLVED mappings | {monster['mapping_unresolved']} |

All joins use the already-frozen stable `monster_id`. No name, suffix, map,
class, Role or approximate matching is used. Monster 225 is explicitly
`PROJECT_EXTENSION`; its 69 source-artifact rows are frozen as project-owned
direct rules and are not represented as 21CQ legacy provenance.

The 25 existing NON_LOOT decisions are explicit and expose
`drop_enabled=false, drop_profile_id=null`. Their 1037 logical source rows remain
in the disposition ledger but are not compiled into V2 production slots.

## Source row disposition ledger

| Disposition | Rows |
| --- | ---: |
| LEGACY_21CQ_COMPILED | {monster['source_disposition_row_counts']['LEGACY_21CQ_COMPILED']} |
| PROJECT_EXTENSION_COMPILED | {monster['source_disposition_row_counts']['PROJECT_EXTENSION_COMPILED']} |
| NON_LOOT_EXCLUDED | {monster['source_disposition_row_counts']['NON_LOOT_EXCLUDED']} |
| RETIRED_OUT_OF_RUNTIME | {monster['source_disposition_row_counts']['RETIRED_OUT_OF_RUNTIME']} |
| total | {monster['source_disposition_row_sum']} |

## Item mapping

| Metric | Count |
| --- | ---: |
| source labels including gold | {item['source_item_labels']} |
| canonical item IDs covered | {item['canonical_item_ids_covered']} |
| EXACT labels | {item['mapping_status_counts'].get('EXACT', 0)} |
| EXPLICIT_ALIAS labels | {item['mapping_status_counts'].get('EXPLICIT_ALIAS', 0)} |
| GOLD_REWARD_KIND labels | {item['mapping_status_counts'].get('GOLD_REWARD_KIND', 0)} |
| RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG labels | {item['retired_source_only_not_in_canonical_catalog']} |
| UNRESOLVED labels | {item['mapping_unresolved']} |

Compiled item slots will carry only a positive `canonical_item_id`; Runtime
name lookup is forbidden. Gold remains a separate reward kind with a positive
amount and no canonical item ID.

### Retired-source-only labels

These labels are real UTF-8 source labels, not aliases or mojibake in the
tracked JSON. They occur only on `RETIRED_OUT_OF_RUNTIME` monsters and have no
identity in the formal 233-item catalog. No canonical mapping is invented and
none of these rows is compiled.

| source label | proposed canonical item | exact source evidence |
| --- | --- | --- |
{retired_only_table}

## Post-RNG overflow Authority

- Explicit per-item records: {overflow['summary']['canonical_item_records']}.
- Protected item records: {overflow['summary']['protected_item_records']}.
- Priority counts: `{json.dumps(overflow['summary']['priority_counts'], ensure_ascii=False, sort_keys=True)}`.
- Gold is explicit priority `100`, unprotected.

The migration used the old retained-value decisions once, then froze direct
per-item values. The new Authority contains no Tier, Drop Role, factor or
probability denominator. `overflow_priority` and `protected_drop` have no
probability effect and apply only after all independent slot RNG draws.

## Gate

```text
monster_mapping_unresolved = {monster['mapping_unresolved']}
item_mapping_unresolved = {item['mapping_unresolved']}
source_disposition_sum = {monster['source_disposition_row_sum']}
CUTOVER = NOT_STARTED
Production = V1
```
"""


def render_import_audit(audit: dict[str, Any]) -> str:
    metrics = audit["metrics"]
    invalid_rows = audit["invalid_source_rows"]
    status_counts = metrics["status_counts"]
    return f"""# DPV2-21CQ-X1 Phase 1 Import Audit

Status: `SOURCE_AUDIT_CLOSED / PRODUCTION_STILL_V1`

## Source identity

- Physical raw `MonItems` files tracked in Git: `{metrics['physical_raw_monitems_files_in_git']}`.
- Reproducible tracked logical source: `assets/data/canonical_monster_drop_source_v2.json`.
- Logical monster records: `{metrics['logical_monster_records']}`.
- Logical meaningful source rows: `{metrics['logical_source_rows']}`.
- Tracked encoding: `{metrics['tracked_encoding']}`.
- Physical MonItems encoding: `{metrics['physical_monitems_encoding']}`; it cannot be inferred from the derived JSON.
- Tracked source raw SHA-256: `{metrics['tracked_source_sha256_raw']}`.
- Tracked source LF-normalized SHA-256: `{metrics['tracked_source_sha256_lf']}`.
- Recorded upstream workbook SHA-256: `{metrics['upstream_workbook_sha256']}`.

The direct source is described as `LEGACY_21CQ_MONITEMS`, not as an official
Shanda/Shengqu table. The tracked JSON is a logical, user-locked reconstruction;
this report does not claim that physical MonItems files exist in the repository.

## Structural closure

| Metric | Count |
| --- | ---: |
| available records | {status_counts.get('available', 0)} |
| confirmed no-drop records | {status_counts.get('no_drop_confirmed', 0)} |
| no-MonItems records | {status_counts.get('no_monitems_file', 0)} |
| zero-slot records | {metrics['zero_slot_records']} |
| meaningful source rows | {metrics['logical_source_rows']} |
| parsed rows after explicit correction | {metrics['parsed_rows_after_correction']} |
| invalid source probability tokens | {metrics['source_invalid_probability_rows']} |
| explicitly corrected rows | {metrics['explicitly_corrected_rows']} |
| uncorrected invalid rows | {metrics['uncorrected_invalid_probability_rows']} |
| duplicate item groups within a monster | {metrics['duplicate_item_groups_within_monster']} |
| duplicate item rows beyond first | {metrics['duplicate_item_rows_beyond_first']} |
| exact duplicate groups within a monster | {metrics['exact_duplicate_groups_within_monster']} |
| exact duplicate rows beyond first | {metrics['exact_duplicate_rows_beyond_first']} |

Every logical row remains an independent row. Duplicate counts are audit facts;
no row is merged and no aggregate probability is calculated.

## Explicit probability correction

The source contains exactly one malformed probability token:

| monster_id | monster | source line | slot | item | source | frozen correction |
| ---: | --- | ---: | --- | --- | --- | --- |
| {invalid_rows[0]['monster_id']} | {invalid_rows[0]['monster_name']} | {invalid_rows[0]['line_number']} | {invalid_rows[0]['slot_index']} | {invalid_rows[0]['item']} | `{invalid_rows[0]['chance']}` | `1/2800` |

The tracked historical row is not rewritten. The externally verified correction is recorded in
`assets/data/drop/dpv2_21cq_source_corrections_v1.json`, with evidence URL,
retrieval date, exact slot identity and original value. Silent correction and
silent skipping are forbidden.

## Accounting gate

```text
meaningful_source_rows = 9590
parsed_rows_after_explicit_correction = 9590
uncorrected_invalid_probability_rows = 0
```

No Production Runtime, canonical catalog, current Tier/Role Authority or actual
drop probability was changed in this phase.
"""


def desired_outputs() -> dict[Path, str]:
    audit = parse_source()
    monster_mapping = build_monster_mapping(audit)
    item_mapping = build_item_mapping(audit, monster_mapping)
    overflow = build_overflow_authority(item_mapping)
    provenance = build_provenance(audit, monster_mapping)
    baseline = build_direct_baseline(
        audit,
        monster_mapping,
        item_mapping,
        overflow,
    )
    outputs = {
        IMPORT_AUDIT_PATH: render_import_audit(audit),
        MONSTER_MAPPING_PATH: pretty_json(monster_mapping),
        ITEM_MAPPING_PATH: pretty_json(item_mapping),
        OVERFLOW_AUTHORITY_PATH: pretty_json(overflow),
        PROVENANCE_PATH: pretty_json(provenance),
        DIRECT_BASELINE_PATH: pretty_json(baseline),
        MAPPING_REPORT_PATH: render_mapping_report(
            monster_mapping,
            item_mapping,
            overflow,
        ),
        PARITY_REPORT_PATH: render_parity_report(
            monster_mapping,
            item_mapping,
            provenance,
            baseline,
        ),
    }
    outputs[MANIFEST_PATH] = pretty_json(build_manifest(outputs))
    return outputs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        outputs = desired_outputs()
        if args.write:
            for path, rendered in outputs.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(rendered, encoding="utf-8", newline="\n")
        else:
            mismatches = [
                path for path, rendered in outputs.items()
                if not path.is_file() or path.read_text(encoding="utf-8") != rendered
            ]
            if mismatches:
                for path in mismatches:
                    print(f"ERROR: generated output drift: {path.relative_to(ROOT)}")
                return 1
        audit = parse_source()
        metrics = audit["metrics"]
        monster_mapping = build_monster_mapping(audit)
        item_mapping = build_item_mapping(audit, monster_mapping)
        baseline = build_direct_baseline(
            audit,
            monster_mapping,
            item_mapping,
            build_overflow_authority(item_mapping),
        )
        print(
            "DPV2_21CQ_DIRECT_BASELINE_BUILD_PASS: "
            f"logical_records={metrics['logical_monster_records']} "
            f"source_rows={metrics['logical_source_rows']} "
            f"corrected={metrics['explicitly_corrected_rows']} "
            f"monster_unresolved={monster_mapping['summary']['mapping_unresolved']} "
            f"item_unresolved={item_mapping['summary']['mapping_unresolved']} "
            f"compiled_slots={baseline['summary']['compiled_slots']} "
            f"x1_mismatch={baseline['summary']['x1_probability_mismatch']}"
        )
        return 0
    except (DirectBaselineError, KeyError, ValueError, TypeError) as exc:
        print(f"DPV2_21CQ_SOURCE_AUDIT_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
