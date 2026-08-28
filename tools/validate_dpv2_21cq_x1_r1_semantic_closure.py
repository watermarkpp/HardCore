#!/usr/bin/env python3
"""Cross-authority validator for the DPV2-21CQ-X1-R1 semantic closure.

This gate deliberately treats the canonical monster catalog as the only
runtime-eligibility source.  The semantic authority supplies the explicit
human dispositions, the logical source supplies independent slot rows, and
the generated mapping/baseline/provenance artifacts must agree with all three.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json"
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
SOURCE_PATH = ROOT / "assets/data/canonical_monster_drop_source_v2.json"
CORRECTIONS_PATH = ROOT / "assets/data/drop/dpv2_21cq_source_corrections_v1.json"
MAPPING_PATH = ROOT / "assets/data/drop/dpv2_21cq_monster_mapping_v1.json"
BASELINE_PATH = ROOT / "assets/data/drop/dpv2_direct_baseline_v2.json"
PROVENANCE_PATH = ROOT / "assets/data/drop/dpv2_21cq_source_provenance_v1.json"

SOURCE_SCHEMA = "canonical_monster_drop_source_excel_v1"
EXPECTED_SOURCE_RECORDS = 217
EXPECTED_SOURCE_ROWS = 9590
EXPECTED_SOURCE_SHA256 = (
    "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"
)
EXPECTED_CATALOG_RUNTIME_ALLOWED = 153
EXPECTED_CATALOG_PROFILES = 156
EXPECTED_DROP_ENABLED = 144
EXPECTED_EXPLICIT_NON_LOOT = frozenset(
    {59, 78, 145, 146, 147, 161, 186, 187, 194}
)
EXPECTED_RUNTIME_DISABLED = frozenset({33, 183, 241})
EXPECTED_PROJECT_EXTENSION = 225
EXPECTED_DIRECT_OVERRIDES = {
    79: 59,
    81: 60,
    83: 59,
    85: 59,
    87: 59,
    226: 1,
    227: 36,
    228: 51,
    229: 36,
    230: 64,
    231: 57,
    232: 95,
    233: 96,
    234: 82,
}
EXPECTED_DIRECT_FROZEN_IDS = frozenset(EXPECTED_DIRECT_OVERRIDES)
EXPECTED_RESTORED_SLOT_COUNT = sum(EXPECTED_DIRECT_OVERRIDES.values())
EXPECTED_EXPLICIT_ROWS = {145: 74, 146: 78, 147: 71}
EXPECTED_ACCOUNTING = {
    "LEGACY_21CQ_COMPILED": 6740,
    "PROJECT_EXTENSION_COMPILED": 69,
    "EXPLICIT_NON_LOOT_EXCLUDED": 223,
    "RETIRED_OUT_OF_RUNTIME": 2558,
}
BASELINE_FREEZE_SHA = "c1cfe8cf809d5047344060e9fe3ea06a9b9799f8"
BASELINE_FREEZE_SLOT_COUNT = 5995
BASELINE_FREEZE_SLOT_SHA256 = (
    "2D70FB2A279BA4E9EA471BDAFA2A777AA4B899BFA70A76A3FE8055BFA4941A14"
)
BASELINE_RELATIVE = "assets/data/drop/dpv2_direct_baseline_v2.json"
CHANCE_RE = re.compile(r"^1/([1-9][0-9]*)$")


class SemanticClosureValidationError(ValueError):
    """Raised when one of the semantic closure authorities disagrees."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SemanticClosureValidationError(message)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SemanticClosureValidationError(f"cannot read JSON: {path}") from exc
    _require(isinstance(value, dict), f"{path} is not a JSON object")
    return value


def _relative(repo_root: Path, relative: str) -> Path:
    return repo_root / relative.replace("/", "\\")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _sha256_lf(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    return hashlib.sha256(
        text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    ).hexdigest().upper()


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _slot_hash(slots: list[dict[str, Any]]) -> str:
    ordered = sorted(slots, key=lambda row: str(row.get("slot_uid", "")))
    return hashlib.sha256(_canonical_json(ordered).encode("utf-8")).hexdigest().upper()


def _flatten_slots(baseline: dict[str, Any]) -> list[dict[str, Any]]:
    profiles = baseline.get("profiles")
    _require(isinstance(profiles, list), "baseline profiles are not an array")
    slots: list[dict[str, Any]] = []
    for profile in profiles:
        _require(isinstance(profile, dict), "baseline profile is not an object")
        profile_slots = profile.get("slots")
        _require(isinstance(profile_slots, list), "baseline profile slots are not an array")
        for slot in profile_slots:
            _require(isinstance(slot, dict), "baseline slot is not an object")
            slots.append(slot)
    return slots


def _load_frozen_slots(repo_root: Path) -> list[dict[str, Any]]:
    try:
        encoded = subprocess.check_output(
            ["git", "show", f"{BASELINE_FREEZE_SHA}:{BASELINE_RELATIVE}"],
            cwd=repo_root,
            stderr=subprocess.STDOUT,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SemanticClosureValidationError(
            f"cannot load BASE_SHA baseline {BASELINE_FREEZE_SHA}"
        ) from exc
    try:
        frozen = json.loads(encoded.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SemanticClosureValidationError("BASE_SHA baseline is invalid JSON") from exc
    _require(isinstance(frozen, dict), "BASE_SHA baseline is not an object")
    slots = _flatten_slots(frozen)
    _require(
        len(slots) == BASELINE_FREEZE_SLOT_COUNT,
        f"BASE_SHA slot count={len(slots)} expected={BASELINE_FREEZE_SLOT_COUNT}",
    )
    _require(
        _slot_hash(slots) == BASELINE_FREEZE_SLOT_SHA256,
        "BASE_SHA slot hash drift",
    )
    return slots


def _parse_source(repo_root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, tuple[int, int]]]:
    source_path = _relative(repo_root, "assets/data/canonical_monster_drop_source_v2.json")
    corrections_path = _relative(
        repo_root, "assets/data/drop/dpv2_21cq_source_corrections_v1.json"
    )
    source = _read_json(source_path)
    _require(source.get("schema") == SOURCE_SCHEMA, "logical source schema mismatch")
    _require(source.get("authority") == "user_locked", "logical source is not user_locked")
    _require(_sha256(source_path) == EXPECTED_SOURCE_SHA256, "logical source SHA drift")
    records = source.get("records")
    _require(
        isinstance(records, list) and len(records) == EXPECTED_SOURCE_RECORDS,
        "logical source record count drift",
    )
    corrections = _read_json(corrections_path)
    _require(
        corrections.get("source", {}).get("path")
        == "assets/data/canonical_monster_drop_source_v2.json",
        "source correction path binding drift",
    )
    _require(
        corrections.get("source", {}).get("sha256") == _sha256(source_path),
        "source correction SHA binding drift",
    )
    correction_by_key: dict[tuple[Any, ...], dict[str, Any]] = {}
    for correction in corrections.get("corrections", []):
        _require(isinstance(correction, dict), "invalid source correction row")
        key = (
            int(correction.get("stable_monster_id", -1)),
            int(correction.get("source_line_number", -1)),
            str(correction.get("source_slot_index", "")),
            str(correction.get("source_item_label", "")),
            str(correction.get("original_chance", "")),
        )
        _require(key not in correction_by_key, f"duplicate correction key: {key}")
        correction_by_key[key] = correction

    source_by_id: dict[str, dict[str, Any]] = {}
    probabilities: dict[str, tuple[int, int]] = {}
    slot_keys: set[tuple[int, str]] = set()
    for raw_record in records:
        _require(isinstance(raw_record, dict), "source record is not an object")
        monster_id = int(raw_record.get("stable_monster_id", -1))
        _require(monster_id > 0 and str(monster_id) not in source_by_id, "source ID drift")
        rows = raw_record.get("rows", [])
        _require(isinstance(rows, list), f"source rows invalid: {monster_id}")
        _require(
            int(raw_record.get("line_count", -1)) == len(rows),
            f"source line count drift: {monster_id}",
        )
        source_by_id[str(monster_id)] = raw_record
        for raw_row in rows:
            _require(isinstance(raw_row, dict), f"source row invalid: {monster_id}")
            slot_index = str(raw_row.get("slot_index", ""))
            slot_key = (monster_id, slot_index)
            _require(slot_index and slot_key not in slot_keys, f"source slot drift: {slot_key}")
            slot_keys.add(slot_key)
            chance = str(raw_row.get("chance", ""))
            match = CHANCE_RE.fullmatch(chance)
            if match is not None:
                numerator, denominator = 1, int(match.group(1))
            else:
                correction_key = (
                    monster_id,
                    int(raw_row.get("line_number", -1)),
                    slot_index,
                    str(raw_row.get("item", "")),
                    chance,
                )
                correction = correction_by_key.get(correction_key)
                _require(correction is not None, f"uncorrected source chance: {correction_key}")
                numerator = int(correction["corrected_base_numerator"])
                denominator = int(correction["corrected_base_denominator"])
            _require(numerator > 0 and denominator > 0, f"invalid source probability: {slot_key}")
            probabilities[f"dpv2.direct.m{monster_id}.{slot_index}"] = (numerator, denominator)
    _require(len(slot_keys) == EXPECTED_SOURCE_ROWS, "logical source row count drift")
    return source_by_id, probabilities


def _catalog(repo_root: Path) -> tuple[dict[str, Any], dict[int, dict[str, Any]]]:
    catalog = _read_json(_relative(repo_root, "assets/data/runtime/canonical_monster_catalog.json"))
    entries = catalog.get("entries")
    _require(
        isinstance(entries, list) and len(entries) == EXPECTED_CATALOG_PROFILES,
        "canonical catalog profile count drift",
    )
    by_id: dict[int, dict[str, Any]] = {}
    for raw in entries:
        _require(isinstance(raw, dict), "catalog row is not an object")
        monster_id = int(raw.get("monster_id", -1))
        _require(monster_id > 0 and monster_id not in by_id, "canonical catalog ID drift")
        _require(type(raw.get("runtime_allowed")) is bool, f"catalog runtime_allowed invalid: {monster_id}")
        placement = raw.get("editor_placement")
        _require(isinstance(placement, dict), f"catalog placement missing: {monster_id}")
        _require(type(placement.get("allowed")) is bool, f"catalog placement allowed invalid: {monster_id}")
        _require(isinstance(raw.get("classification"), str) and raw["classification"], f"catalog classification missing: {monster_id}")
        capability = raw.get("runtime_capability")
        _require(isinstance(capability, dict), f"catalog runtime capability missing: {monster_id}")
        _require(type(capability.get("allowed")) is bool, f"catalog capability invalid: {monster_id}")
        by_id[monster_id] = raw
    entries_by_id = catalog.get("entries_by_id")
    _require(isinstance(entries_by_id, dict), "catalog entries_by_id missing")
    _require({int(key) for key in entries_by_id} == set(by_id), "catalog entries_by_id ID drift")
    for monster_id, raw in by_id.items():
        mirror = entries_by_id.get(str(monster_id))
        _require(isinstance(mirror, dict), f"catalog entries_by_id row missing: {monster_id}")
        _require(mirror.get("runtime_allowed") is raw["runtime_allowed"], f"catalog runtime mirror drift: {monster_id}")
    return catalog, by_id


def _expected_semantic_status(monster_id: int, runtime_allowed: bool) -> str:
    if not runtime_allowed:
        return "RUNTIME_DISABLED"
    if monster_id == EXPECTED_PROJECT_EXTENSION:
        return "PROJECT_EXTENSION"
    if monster_id in EXPECTED_EXPLICIT_NON_LOOT:
        return "EXPLICIT_NON_LOOT"
    return "DIRECT_21CQ"


def _expected_reason_and_freeze(
    monster_id: int,
    semantic_status: str,
) -> tuple[str, bool]:
    if semantic_status == "RUNTIME_DISABLED":
        return "RUNTIME_DISABLED", True
    if semantic_status == "PROJECT_EXTENSION":
        return "PROJECT_EXTENSION", True
    if semantic_status == "EXPLICIT_NON_LOOT":
        if monster_id in {145, 146, 147}:
            return "SUMMON_OR_EVENT_COMBAT_ENTITY", True
        if monster_id in {59, 78, 161}:
            return "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE", True
        if monster_id in {186, 187}:
            return "TAMEABLE_CURRENT_EXEMPTION", True
        if monster_id == 194:
            return "GUARD_SCRIPT_CURRENT_EXEMPTION", True
        raise SemanticClosureValidationError(
            f"unknown explicit non-loot identity: {monster_id}"
        )
    if semantic_status == "DIRECT_21CQ":
        if monster_id in EXPECTED_DIRECT_FROZEN_IDS:
            return "HUMAN_FROZEN_DIRECT_21CQ", True
        return "DIRECT_CATALOG_SOURCE_EXACT", False
    raise SemanticClosureValidationError(
        f"unknown semantic status: {semantic_status}"
    )


def validate_authority(
    authority: dict[str, Any] | None = None,
    *,
    repo_root: Path = ROOT,
) -> dict[str, Any]:
    """Validate the checked-in semantic authority and all generated consumers."""

    if authority is None:
        authority = _read_json(_relative(repo_root, "assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json"))
    catalog, catalog_by_id = _catalog(repo_root)
    source_by_id, source_probabilities = _parse_source(repo_root)
    mapping = _read_json(_relative(repo_root, "assets/data/drop/dpv2_21cq_monster_mapping_v1.json"))
    baseline = _read_json(_relative(repo_root, "assets/data/drop/dpv2_direct_baseline_v2.json"))
    provenance = _read_json(_relative(repo_root, "assets/data/drop/dpv2_21cq_source_provenance_v1.json"))

    _require(
        authority.get("schema") == "hardcore.dpv2.monster_drop_semantic_authority.v1",
        "semantic authority schema mismatch",
    )
    _require(authority.get("status") == "SEMANTIC_AUTHORITY_COMPLETE", "semantic authority status mismatch")
    _require(authority.get("production_active") is True, "semantic authority activation drift")
    semantic_text = json.dumps(authority, ensure_ascii=False)
    for forbidden in (
        "tier",
        "role",
        "factor",
        "a0.7",
        "a07",
        "a0_7",
        "legacy_role",
        "drop_role",
        "role_factor",
    ):
        _require(forbidden not in semantic_text.lower(), f"semantic authority contains forbidden {forbidden}")
    source_binding = authority.get("source")
    _require(isinstance(source_binding, dict), "semantic authority source binding missing")
    catalog_binding = source_binding.get("canonical_catalog")
    logical_binding = source_binding.get("logical_drop_source")
    _require(isinstance(catalog_binding, dict) and isinstance(logical_binding, dict), "semantic authority source binding invalid")
    catalog_path = _relative(repo_root, "assets/data/runtime/canonical_monster_catalog.json")
    source_path = _relative(repo_root, "assets/data/canonical_monster_drop_source_v2.json")
    _require(catalog_binding.get("path") == "assets/data/runtime/canonical_monster_catalog.json", "semantic catalog path drift")
    _require(catalog_binding.get("sha256") == _sha256_lf(catalog_path), "semantic catalog hash drift")
    _require(logical_binding.get("path") == "assets/data/canonical_monster_drop_source_v2.json", "semantic source path drift")
    _require(logical_binding.get("sha256") == _sha256(source_path), "semantic source hash drift")

    semantic_records = authority.get("records")
    _require(isinstance(semantic_records, list) and len(semantic_records) == EXPECTED_CATALOG_PROFILES, "semantic record count drift")
    semantic_by_id: dict[int, dict[str, Any]] = {}
    for raw in semantic_records:
        _require(isinstance(raw, dict), "semantic record is not an object")
        monster_id = int(raw.get("canonical_monster_id", -1))
        _require(monster_id in catalog_by_id and monster_id not in semantic_by_id, f"semantic ID drift: {monster_id}")
        catalog_row = catalog_by_id[monster_id]
        _require(raw.get("canonical_monster_name") == catalog_row.get("canonical_name"), f"semantic name drift: {monster_id}")
        _require(raw.get("runtime_allowed") is catalog_row.get("runtime_allowed"), f"semantic runtime_allowed drift: {monster_id}")
        expected_status = _expected_semantic_status(monster_id, bool(catalog_row["runtime_allowed"]))
        _require(raw.get("semantic_status") == expected_status, f"semantic status drift: {monster_id}")
        _require(raw.get("drop_semantic_state") == expected_status, f"semantic state drift: {monster_id}")
        expected_reason, expected_human_frozen = _expected_reason_and_freeze(
            monster_id,
            expected_status,
        )
        _require(
            isinstance(raw.get("reason_code"), str)
            and bool(raw.get("reason_code")),
            f"semantic reason missing: {monster_id}",
        )
        _require(raw.get("reason_code") == expected_reason, f"semantic reason drift: {monster_id}")
        _require(type(raw.get("human_frozen")) is bool, f"semantic human_frozen type drift: {monster_id}")
        _require(raw.get("human_frozen") is expected_human_frozen, f"semantic human_frozen drift: {monster_id}")
        _require(int(raw.get("source_row_count", -1)) == len(source_by_id[str(monster_id)].get("rows", [])), f"semantic source row count drift: {monster_id}")
        evidence = raw.get("evidence")
        _require(isinstance(evidence, dict) and bool(evidence), f"semantic evidence missing: {monster_id}")
        catalog_path = "assets/data/runtime/canonical_monster_catalog.json"
        source_path = "assets/data/canonical_monster_drop_source_v2.json"
        catalog_selector = f"entries[monster_id={monster_id}]"
        source_selector = f"records[stable_monster_id={monster_id}]"
        expected_classification_path = f"{catalog_path}#{catalog_selector}.classification"
        expected_source_row_path = f"{source_path}#{source_selector}.rows"
        _require(
            isinstance(evidence.get("current_user_decision"), str)
            and bool(evidence.get("current_user_decision")),
            f"semantic current decision evidence missing: {monster_id}",
        )
        _require(evidence.get("catalog_path") == catalog_path, f"semantic catalog evidence drift: {monster_id}")
        _require(evidence.get("classification_path") == expected_classification_path, f"semantic classification evidence drift: {monster_id}")
        _require(evidence.get("classification") == catalog_row.get("classification"), f"semantic classification value drift: {monster_id}")
        _require(evidence.get("source_row_path") == expected_source_row_path, f"semantic source evidence drift: {monster_id}")
        source_evidence = evidence.get("source_row")
        _require(isinstance(source_evidence, dict), f"semantic source row evidence missing: {monster_id}")
        _require(source_evidence.get("path") == source_path, f"semantic source path drift: {monster_id}")
        _require(source_evidence.get("selector") == source_selector, f"semantic source selector drift: {monster_id}")
        _require(source_evidence.get("count") == raw.get("source_row_count"), f"semantic source evidence count drift: {monster_id}")
        catalog_evidence = evidence.get("catalog")
        _require(isinstance(catalog_evidence, dict), f"semantic catalog evidence missing: {monster_id}")
        _require(catalog_evidence.get("path") == catalog_path, f"semantic catalog path evidence drift: {monster_id}")
        _require(catalog_evidence.get("selector") == catalog_selector, f"semantic catalog selector drift: {monster_id}")
        _require(catalog_evidence.get("runtime_allowed") is catalog_row["runtime_allowed"], f"semantic catalog runtime evidence drift: {monster_id}")
        if expected_status == "RUNTIME_DISABLED":
            runtime_evidence = evidence.get("runtime_evidence")
            _require(isinstance(runtime_evidence, dict), f"runtime-disabled evidence missing: {monster_id}")
            _require(runtime_evidence.get("runtime_allowed") is False, f"runtime-disabled evidence enabled: {monster_id}")
            for key in ("script_path", "effect_path", "runtime_path"):
                _require(isinstance(runtime_evidence.get(key), str) and bool(runtime_evidence.get(key)), f"runtime-disabled evidence {key} missing: {monster_id}")
        else:
            if expected_status in {"DIRECT_21CQ", "PROJECT_EXTENSION"}:
                _require("runtime_evidence" not in evidence, f"unexpected runtime evidence: {monster_id}")
        semantic_by_id[monster_id] = raw
        if expected_status == "EXPLICIT_NON_LOOT":
            exemption = raw.get("exemption")
            _require(isinstance(exemption, dict) and exemption.get("required") is True, f"missing explicit exemption: {monster_id}")
            _require(exemption.get("kind") == "EXPLICIT_NON_LOOT", f"explicit exemption kind drift: {monster_id}")
            _require(exemption.get("reason_code") == expected_reason, f"explicit exemption reason drift: {monster_id}")
        else:
            _require(raw.get("exemption") is None, f"unexpected semantic exemption: {monster_id}")
    _require(set(semantic_by_id) == set(catalog_by_id), "semantic/catalog ID set drift")

    expected_runtime_disabled = {monster_id for monster_id, row in catalog_by_id.items() if row["runtime_allowed"] is False}
    _require(expected_runtime_disabled == set(EXPECTED_RUNTIME_DISABLED), "catalog runtime-disabled set drift")
    _require(sum(int(row["runtime_allowed"]) for row in semantic_records) == EXPECTED_CATALOG_RUNTIME_ALLOWED, "runtime_allowed count drift")
    semantic_counts = Counter(str(row["semantic_status"]) for row in semantic_records)
    _require(semantic_counts == Counter({"DIRECT_21CQ": 143, "PROJECT_EXTENSION": 1, "EXPLICIT_NON_LOOT": 9, "RUNTIME_DISABLED": 3}), "semantic partition count drift")
    semantic_summary = authority.get("summary", {})
    _require(semantic_summary.get("canonical_monsters") == EXPECTED_CATALOG_PROFILES, "semantic profile summary drift")
    _require(semantic_summary.get("runtime_allowed") == EXPECTED_CATALOG_RUNTIME_ALLOWED, "semantic runtime summary drift")
    _require(semantic_summary.get("drop_enabled") == EXPECTED_DROP_ENABLED, "semantic drop summary drift")
    _require(semantic_summary.get("explicit_non_loot") == len(EXPECTED_EXPLICIT_NON_LOOT), "semantic explicit summary drift")
    _require(semantic_summary.get("runtime_disabled") == len(EXPECTED_RUNTIME_DISABLED), "semantic runtime-disabled summary drift")
    _require(semantic_summary.get("production_slots") == 6809, "semantic production slot summary drift")
    _require(semantic_summary.get("source_accounting") == EXPECTED_ACCOUNTING, "semantic source accounting drift")

    frozen = authority.get("frozen_decisions")
    _require(isinstance(frozen, dict), "semantic frozen decisions missing")
    direct_rows = frozen.get("direct_21cq")
    _require(isinstance(direct_rows, list), "direct frozen decisions missing")
    direct_by_id = {int(row["canonical_monster_id"]): int(row["source_row_count"]) for row in direct_rows if isinstance(row, dict)}
    _require(direct_by_id == EXPECTED_DIRECT_OVERRIDES, "direct frozen ID/count decisions drift")
    _require(
        direct_by_id
        == {
            monster_id: len(source_by_id[str(monster_id)].get("rows", []))
            for monster_id in EXPECTED_DIRECT_OVERRIDES
        },
        "direct frozen source row counts drift",
    )
    explicit_rows = frozen.get("explicit_non_loot")
    _require(isinstance(explicit_rows, list), "explicit frozen decisions missing")
    explicit_by_id = {int(row["canonical_monster_id"]): int(row["source_row_count"]) for row in explicit_rows if isinstance(row, dict)}
    expected_explicit_counts = {monster_id: len(source_by_id[str(monster_id)].get("rows", [])) for monster_id in EXPECTED_EXPLICIT_NON_LOOT}
    _require(explicit_by_id == expected_explicit_counts, "explicit frozen ID/count decisions drift")
    _require(set(frozen.get("runtime_disabled", [])) == set(EXPECTED_RUNTIME_DISABLED), "runtime-disabled frozen decisions drift")
    project = frozen.get("project_extension")
    _require(isinstance(project, dict) and project.get("canonical_monster_id") == EXPECTED_PROJECT_EXTENSION and project.get("source_row_count") == 69, "project extension frozen decision drift")
    _require(
        len(source_by_id[str(EXPECTED_PROJECT_EXTENSION)].get("rows", [])) == 69,
        "project extension source row count drift",
    )
    _require(EXPECTED_EXPLICIT_ROWS == {monster_id: len(source_by_id[str(monster_id)].get("rows", [])) for monster_id in EXPECTED_EXPLICIT_ROWS}, "explicit source rows drift")

    # The source ledger is partitioned by semantic state, while source-only IDs
    # remain retired.  Runtime-disabled identities have no source rows and do
    # not manufacture an extra accounting bucket.
    accounting: Counter[str] = Counter()
    for raw in source_by_id.values():
        monster_id = int(raw["stable_monster_id"])
        row_count = len(raw.get("rows", []))
        if monster_id not in catalog_by_id:
            disposition = "RETIRED_OUT_OF_RUNTIME"
        else:
            status = semantic_by_id[monster_id]["semantic_status"]
            disposition = {
                "DIRECT_21CQ": "LEGACY_21CQ_COMPILED",
                "PROJECT_EXTENSION": "PROJECT_EXTENSION_COMPILED",
                "EXPLICIT_NON_LOOT": "EXPLICIT_NON_LOOT_EXCLUDED",
                "RUNTIME_DISABLED": "RUNTIME_DISABLED",
            }[status]
        if row_count:
            accounting[disposition] += row_count
        if disposition == "RUNTIME_DISABLED":
            _require(row_count == 0, f"runtime-disabled source rows present: {monster_id}")
    _require(dict(accounting) == EXPECTED_ACCOUNTING, f"source accounting drift: {dict(accounting)}")

    mapping_records = mapping.get("records")
    _require(isinstance(mapping_records, list) and len(mapping_records) == EXPECTED_SOURCE_RECORDS, "monster mapping record count drift")
    mapping_by_source_id = {int(row["source_monster_id"]): row for row in mapping_records if isinstance(row, dict)}
    _require(set(mapping_by_source_id) == {int(key) for key in source_by_id}, "monster mapping source ID drift")
    for monster_id, raw in mapping_by_source_id.items():
        catalog_row = catalog_by_id.get(monster_id)
        if catalog_row is None:
            expected_status = "RETIRED_OUT_OF_RUNTIME"
            expected_enabled = False
            expected_runtime = False
            expected_origin = "LEGACY_21CQ_MONITEMS"
            expected_disposition = "RETIRED_OUT_OF_RUNTIME"
        else:
            expected_status = semantic_by_id[monster_id]["semantic_status"]
            expected_enabled = expected_status in {"DIRECT_21CQ", "PROJECT_EXTENSION"}
            expected_runtime = bool(catalog_row["runtime_allowed"])
            expected_origin = {
                "DIRECT_21CQ": "LEGACY_21CQ_MONITEMS",
                "PROJECT_EXTENSION": "PROJECT_EXTENSION",
                "EXPLICIT_NON_LOOT": "EXPLICIT_NON_LOOT",
                "RUNTIME_DISABLED": "RUNTIME_DISABLED",
            }[expected_status]
            expected_disposition = {
                "DIRECT_21CQ": "LEGACY_21CQ_COMPILED",
                "PROJECT_EXTENSION": "PROJECT_EXTENSION_COMPILED",
                "EXPLICIT_NON_LOOT": "EXPLICIT_NON_LOOT_EXCLUDED",
                "RUNTIME_DISABLED": "RUNTIME_DISABLED",
            }[expected_status]
        _require(raw.get("mapping_status") == expected_status and raw.get("semantic_status") == expected_status, f"monster mapping semantic drift: {monster_id}")
        _require(raw.get("runtime_allowed") is expected_runtime and raw.get("runtime_active") is expected_runtime, f"monster mapping runtime drift: {monster_id}")
        _require(raw.get("drop_enabled") is expected_enabled, f"monster mapping enabled drift: {monster_id}")
        _require(raw.get("baseline_origin") == expected_origin and raw.get("source_disposition") == expected_disposition, f"monster mapping disposition drift: {monster_id}")
        _require(int(raw.get("source_row_count", -1)) == len(source_by_id[str(monster_id)].get("rows", [])), f"monster mapping row count drift: {monster_id}")
    mapping_summary = mapping.get("summary", {})
    _require(mapping_summary.get("canonical_profiles") == EXPECTED_CATALOG_PROFILES, "mapping canonical profile count drift")
    _require(mapping_summary.get("active_canonical_monsters") == EXPECTED_CATALOG_RUNTIME_ALLOWED, "mapping runtime profile count drift")
    _require(mapping_summary.get("drop_enabled_monsters") == EXPECTED_DROP_ENABLED, "mapping drop-enabled count drift")
    _require(mapping_summary.get("explicit_non_loot_monsters") == len(EXPECTED_EXPLICIT_NON_LOOT), "mapping explicit count drift")
    _require(mapping_summary.get("runtime_disabled_monsters") == len(EXPECTED_RUNTIME_DISABLED), "mapping runtime-disabled count drift")
    _require(mapping_summary.get("source_disposition_row_counts") == EXPECTED_ACCOUNTING, "mapping accounting drift")

    _require(baseline.get("schema") == "hardcore.dpv2.direct_monster_drop_baseline.v2", "baseline schema mismatch")
    _require(baseline.get("production_active") is True and baseline.get("production_runtime") == "V2_DIRECT_BASELINE", "baseline production status drift")
    profiles = baseline.get("profiles")
    _require(isinstance(profiles, list) and len(profiles) == EXPECTED_CATALOG_PROFILES, "baseline profile count drift")
    profile_by_id = {int(row["canonical_monster_id"]): row for row in profiles if isinstance(row, dict)}
    _require(set(profile_by_id) == set(catalog_by_id), "baseline profile ID drift")
    compiled_slots: list[dict[str, Any]] = []
    source_compiled_uids: set[str] = set()
    expected_compiled_uids: set[str] = set()
    exact_counter: Counter[tuple[Any, ...]] = Counter()
    restored_counter: Counter[tuple[Any, ...]] = Counter()
    frozen_slots = _load_frozen_slots(repo_root)
    frozen_uids = {str(slot["slot_uid"]) for slot in frozen_slots}
    for monster_id, semantic_row in semantic_by_id.items():
        profile = profile_by_id[monster_id]
        status = str(semantic_row["semantic_status"])
        should_compile = status in {"DIRECT_21CQ", "PROJECT_EXTENSION"}
        _require(profile.get("semantic_status") == status, f"baseline semantic profile drift: {monster_id}")
        _require(profile.get("runtime_allowed") is bool(semantic_row["runtime_allowed"]), f"baseline runtime profile drift: {monster_id}")
        _require(profile.get("drop_enabled") is should_compile, f"baseline enabled profile drift: {monster_id}")
        slots = profile.get("slots")
        _require(isinstance(slots, list), f"baseline profile slots invalid: {monster_id}")
        expected_source_rows = source_by_id[str(monster_id)].get("rows", [])
        if not should_compile:
            _require(slots == [], f"excluded profile has production slots: {monster_id}")
            _require(profile.get("drop_profile_id") is None and profile.get("reporting_label") == "NON_LOOT", f"excluded profile contract drift: {monster_id}")
            continue
        _require(len(slots) == len(expected_source_rows), f"baseline slot count drift: {monster_id}")
        for source_row, slot in zip(expected_source_rows, slots):
            slot_uid = f"dpv2.direct.m{monster_id}.{source_row['slot_index']}"
            expected_compiled_uids.add(slot_uid)
            _require(slot.get("slot_uid") == slot_uid, f"baseline slot UID drift: {slot_uid}")
            _require(slot_uid in source_probabilities, f"baseline source probability missing: {slot_uid}")
            expected_probability = source_probabilities[slot_uid]
            _require((slot.get("base_numerator"), slot.get("base_denominator")) == expected_probability, f"baseline x1 probability drift: {slot_uid}")
            reward_keys = int("canonical_item_id" in slot) + int("gold_amount" in slot)
            _require(reward_keys == 1, f"baseline reward key drift: {slot_uid}")
            compiled_slots.append(slot)
            source_compiled_uids.add(slot_uid)
            exact_counter[(monster_id, source_row.get("item"), *expected_probability, source_row.get("gold"))] += 1
            if slot_uid not in frozen_uids:
                restored_counter[(slot.get("canonical_item_id"), slot.get("gold_amount"), *expected_probability)] += 1
    _require(source_compiled_uids == expected_compiled_uids, "baseline/source compiled UID set drift")
    _require(len(compiled_slots) == 6809, "baseline compiled slot count drift")
    _require(len({str(slot["slot_uid"]) for slot in compiled_slots}) == 6809, "baseline duplicate slot UID")
    _require(len({str(slot["source_provenance_id"]) for slot in compiled_slots}) == 6809, "baseline duplicate provenance ID")
    exact_duplicate_rows = sum(value - 1 for value in exact_counter.values() if value > 1)
    restored_duplicate_rows = sum(value - 1 for value in restored_counter.values() if value > 1)
    _require(exact_duplicate_rows == baseline["summary"].get("compiled_exact_duplicate_rows_beyond_first"), "baseline final duplicate metric drift")
    _require(restored_duplicate_rows == baseline["summary"].get("restored_exact_duplicate_rows_beyond_first"), "baseline restored duplicate metric drift")
    _require(len(compiled_slots) - len(source_compiled_uids) == baseline["summary"].get("duplicate_slot_collapse") == 0, "baseline duplicate collapse drift")
    current_by_uid = {str(slot["slot_uid"]): slot for slot in compiled_slots}
    frozen_by_uid = {str(slot["slot_uid"]): slot for slot in frozen_slots}
    _require(set(frozen_by_uid).issubset(current_by_uid), "existing BASE_SHA slots missing")
    existing_drift = sum(current_by_uid[uid] != slot for uid, slot in frozen_by_uid.items())
    _require(existing_drift == 0, f"existing BASE_SHA slot drift={existing_drift}")
    restored_uids = set(current_by_uid) - set(frozen_by_uid)
    _require(
        len(restored_uids) == EXPECTED_RESTORED_SLOT_COUNT,
        "restored slot count drift",
    )
    restored_expected = {f"dpv2.direct.m{monster_id}.slot_{index:03d}" for monster_id, count in EXPECTED_DIRECT_OVERRIDES.items() for index in range(1, count + 1)}
    _require(restored_uids == restored_expected, "restored direct UID set drift")
    summary = baseline.get("summary", {})
    _require(summary.get("active_monsters") == 156 and summary.get("runtime_allowed_monsters") == 153, "baseline profile summary drift")
    _require(summary.get("drop_enabled_monsters") == 144 and summary.get("explicit_non_loot_monsters") == 9 and summary.get("runtime_disabled_monsters") == 3, "baseline semantic summary drift")
    _require(summary.get("compiled_slots") == 6809, "baseline production slot summary drift")
    _require(summary.get("baseline_origin_counts") == {"LEGACY_21CQ_MONITEMS": 6740, "PROJECT_EXTENSION": 69}, "baseline origin summary drift")
    _require(summary.get("x1_probability_mismatch") == 0 and summary.get("restored_x1_probability_mismatch") == 0, "baseline x1 mismatch drift")
    _require(summary.get("restored_existing_slots") == 814 and summary.get("existing_slot_drift") == 0, "baseline preservation summary drift")
    baseline_freeze = baseline.get("baseline_freeze")
    _require(isinstance(baseline_freeze, dict), "baseline freeze metadata missing")
    _require(baseline_freeze.get("base_sha") == BASELINE_FREEZE_SHA and baseline_freeze.get("base_slot_count") == BASELINE_FREEZE_SLOT_COUNT and baseline_freeze.get("base_slot_sha256") == BASELINE_FREEZE_SLOT_SHA256 and baseline_freeze.get("existing_slot_drift") == 0, "baseline freeze metadata drift")

    provenance_records = provenance.get("records")
    _require(isinstance(provenance_records, list) and len(provenance_records) == EXPECTED_SOURCE_ROWS, "provenance row count drift")
    provenance_ids = [str(row.get("source_provenance_id")) for row in provenance_records if isinstance(row, dict)]
    _require(len(provenance_ids) == len(set(provenance_ids)), "duplicate provenance IDs")
    provenance_by_key = {(int(row["source_monster_id"]), str(row["source_slot_index"])): row for row in provenance_records if isinstance(row, dict)}
    _require(len(provenance_by_key) == EXPECTED_SOURCE_ROWS, "provenance source key drift")
    for monster_id, raw in source_by_id.items():
        numeric_id = int(monster_id)
        status = semantic_by_id[numeric_id]["semantic_status"] if numeric_id in semantic_by_id else "RETIRED_OUT_OF_RUNTIME"
        compiled = status in {"DIRECT_21CQ", "PROJECT_EXTENSION"}
        disposition = {
            "DIRECT_21CQ": "LEGACY_21CQ_COMPILED",
            "PROJECT_EXTENSION": "PROJECT_EXTENSION_COMPILED",
            "EXPLICIT_NON_LOOT": "EXPLICIT_NON_LOOT_EXCLUDED",
            "RUNTIME_DISABLED": "RUNTIME_DISABLED",
            "RETIRED_OUT_OF_RUNTIME": "RETIRED_OUT_OF_RUNTIME",
        }[status]
        for source_row in raw.get("rows", []):
            key = (numeric_id, str(source_row["slot_index"]))
            row = provenance_by_key[key]
            _require(row.get("source_disposition") == disposition, f"provenance disposition drift: {key}")
            _require((row.get("compiled_slot_uid") is not None) is compiled, f"provenance compiled flag drift: {key}")
            if compiled:
                _require(row.get("compiled_slot_uid") in source_compiled_uids, f"provenance compiled UID missing: {key}")
    _require(provenance.get("summary", {}).get("disposition_counts") == EXPECTED_ACCOUNTING, "provenance accounting drift")
    _require(provenance.get("summary", {}).get("disposition_sum") == EXPECTED_SOURCE_ROWS, "provenance disposition sum drift")

    return {
        "status": "PASS",
        "canonical_monsters": EXPECTED_CATALOG_PROFILES,
        "runtime_allowed": EXPECTED_CATALOG_RUNTIME_ALLOWED,
        "drop_enabled": EXPECTED_DROP_ENABLED,
        "explicit_non_loot": len(EXPECTED_EXPLICIT_NON_LOOT),
        "runtime_disabled": len(EXPECTED_RUNTIME_DISABLED),
        "production_slots": len(compiled_slots),
        "restored_slots": len(restored_uids),
        "existing_slot_drift": existing_drift,
        "x1_probability_mismatch": 0,
        "duplicate_slot_collapse": 0,
        "source_accounting": EXPECTED_ACCOUNTING,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate checked-in authorities")
    args = parser.parse_args(argv)
    try:
        result = validate_authority()
        print(
            "DPV2_21CQ_X1_R1_SEMANTIC_CLOSURE_PASS: "
            f"profiles={result['canonical_monsters']} "
            f"runtime_allowed={result['runtime_allowed']} "
            f"drop_enabled={result['drop_enabled']} "
            f"explicit_non_loot={result['explicit_non_loot']} "
            f"runtime_disabled={result['runtime_disabled']} "
            f"production_slots={result['production_slots']} "
            f"restored={result['restored_slots']} "
            f"existing_drift={result['existing_slot_drift']}"
        )
        return 0
    except (SemanticClosureValidationError, KeyError, TypeError, ValueError) as exc:
        print(f"DPV2_21CQ_X1_R1_SEMANTIC_CLOSURE_FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
