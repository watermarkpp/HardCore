#!/usr/bin/env python3
"""Validate the non-runtime DPV2 A0.7 item Tier authority.

The A0.7 table is a formal overlay over the A0.5 Tier candidate and the A0.6
item-identity authority.  It is deliberately data-only: validation never
imports Godot/runtime code and never mutates an input or output file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_RELATIVE = "assets/data/drop/dpv2_item_tier_authority_v1.json"
A05_SEED_RELATIVE = "outputs/drop/dpv2_item_tier_seed_candidate.json"
A06_IDENTITY_RELATIVE = "assets/data/drop/dpv2_item_identity_authority_v1.json"
DECISION_DOCUMENT_RELATIVE = "docs/drop/DPV2_A07_HUMAN_AUTHORITY_DECISION.md"

EXPECTED_SCHEMA = "hardcore.dpv2.item_tier_authority.v1"
EXPECTED_BASE_SHA = "041343432ec8e4e7960aded9524a1c146a23241a"
EXPECTED_A05_SCHEMA = "dpv2.item_tier_seed_candidate.a05.v1"
EXPECTED_A06_SCHEMA = "hardcore.dpv2.item_identity_authority.v1"
EXPECTED_A05_SHA256 = "9b6019376606810090d704cd92bcb91ecb42926de423737ba83505d400ef43ba"
EXPECTED_A06_SHA256 = "c2f2f7e2803c7e54c5c096726d14b0e6730cc517dc3d20ee33f0d45bb0e4761c"
EXPECTED_DECISION_SHA256 = "fdeeaad95ac824e8cbdb98d4d7d8cd58844ab822dff912f8f5b54e6ff9235edc"

TIER_DENOMINATORS: dict[str, int] = {
    "POTION_COMMON": 32,
    "POTION_STRONG": 64,
    "SOLAR_CONSUMABLE": 128,
    "RARE_CONSUMABLE": 1024,
    "EQUIP_LOW": 800,
    "EQUIP_MID": 1600,
    "EQUIP_HIGH_MID": 3200,
    "WOOMA_GEAR": 6400,
    "ZUMA_GEAR": 16000,
    "BOOK_LOW": 24,
    "BOOK_MID": 400,
    "BOOK_HIGH": 3200,
    "BOOK_35": 6400,
    "MAGICBLOOD_RAINBOW": 16000,
    "MYSTERY_SIGNATURE": 9600,
    "PRAYER_MEMORY": 8000,
    "REDMOON_SET": 1600,
    "NEW_CLOTHES": 8000,
    "HIGH_CLASS_WEAPON": 48000,
    "EXPANDED_HIGH_WEAPON": 96000,
    "LEGENDARY_WEAPON": 192000,
    "RARE_LEGACY": 48000,
    "FUNCTIONAL_SPECIAL": 14400,
    "SPECIAL_RING": 128000,
    "COLLECTOR_LOW": 1200,
    "BOSS_KEY_ITEM": 32,
    "MONSTER_MATERIAL": 32,
}

NEW_HUMAN_DECISIONS: dict[int, dict[str, Any]] = {
    920023: {
        "name": "沃玛号角",
        "tier": "BOSS_KEY_ITEM",
        "protected_drop": True,
        "overflow_priority": 200,
    },
    920032: {
        "name": "祖玛头像",
        "tier": "BOSS_KEY_ITEM",
        "protected_drop": True,
        "overflow_priority": 200,
    },
    920037: {
        "name": "肉",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
    920038: {
        "name": "蛆卵",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
    920039: {
        "name": "蜘蛛牙",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
    920040: {
        "name": "蝎尾",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
    920049: {
        "name": "食人花叶",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
    920050: {
        "name": "食人花果",
        "tier": "MONSTER_MATERIAL",
        "protected_drop": False,
        "overflow_priority": 100,
    },
}


class AuthorityValidationError(ValueError):
    """Raised when the A0.7 authority or one of its overlays is invalid."""


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise AuthorityValidationError(f"missing JSON: {path}") from exc
    except json.JSONDecodeError as exc:
        raise AuthorityValidationError(f"invalid JSON: {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except FileNotFoundError as exc:
        raise AuthorityValidationError(f"missing provenance file: {path}") from exc


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value > 0 else None
    if isinstance(value, str) and value.strip().isdigit():
        parsed = int(value.strip())
        return parsed if parsed > 0 else None
    return None


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AuthorityValidationError(message)


def _contains_string(value: Any, needle: str) -> bool:
    if isinstance(value, str):
        return value == needle
    if isinstance(value, dict):
        return any(
            _contains_string(key, needle) or _contains_string(child, needle)
            for key, child in value.items()
        )
    if isinstance(value, list):
        return any(_contains_string(child, needle) for child in value)
    return False


def _as_name_map(records: list[dict[str, Any]], label: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for record in records:
        _require(isinstance(record, dict), f"{label} record is not an object")
        name = str(record.get("canonical_name", record.get("item_name", record.get("normalized_item_name", ""))))
        _require(bool(name), f"{label} record has empty name")
        _require(name not in result, f"duplicate {label} name: {name}")
        result[name] = record
    return result


def validate_authority_documents(
    authority: dict[str, Any],
    a05_seed: dict[str, Any],
    a06_identity: dict[str, Any],
    *,
    repo_root: Path,
    authority_path: Path,
    a05_seed_path: Path,
    a06_identity_path: Path,
    decision_document_path: Path,
) -> dict[str, Any]:
    _require(authority.get("schema") == EXPECTED_SCHEMA, "unexpected A0.7 authority schema")
    _require(authority.get("status") == "A0_7_COMPLETE_ITEM_TIER_AUTHORITY", "A0.7 authority is not complete")
    _require(authority.get("base_sha") == EXPECTED_BASE_SHA, "A0.7 base SHA drift")
    _require(a05_seed.get("schema") == EXPECTED_A05_SCHEMA, "A0.5 seed schema drift")
    _require(a06_identity.get("schema") == EXPECTED_A06_SCHEMA, "A0.6 identity schema drift")

    authority_meta = authority.get("authority")
    activation = authority.get("activation")
    provenance = authority.get("source_provenance")
    taxonomy = authority.get("tier_denominators")
    summary = authority.get("summary")
    records = authority.get("records")
    _require(isinstance(authority_meta, dict), "A0.7 authority metadata is missing")
    _require(isinstance(activation, dict), "A0.7 activation boundary is missing")
    _require(isinstance(provenance, dict), "A0.7 source provenance is missing")
    _require(isinstance(taxonomy, dict), "A0.7 Tier taxonomy is missing")
    _require(isinstance(summary, dict), "A0.7 summary is missing")
    _require(isinstance(records, list), "A0.7 records is not an array")
    _require(authority_meta.get("kind") == "user_authoritative_override", "A0.7 authority kind is not explicit")
    _require(authority_meta.get("phase") == "A0.7", "A0.7 phase marker is missing")
    _require(authority_meta.get("decision_document") == DECISION_DOCUMENT_RELATIVE, "A0.7 decision path drift")
    _require(str(authority_meta.get("decision_document_sha256", "")).lower() == EXPECTED_DECISION_SHA256, "A0.7 decision SHA drift")
    _require(authority_meta.get("runtime_consumer") is None, "A0.7 authority has a runtime consumer")
    _require(authority_meta.get("persistence_consumer") is None, "A0.7 authority has a persistence consumer")
    _require(activation == {
        "production_active": False,
        "phase1_allowed": False,
        "runtime_consumer": None,
        "persistence_consumer": None,
    }, "A0.7 activation boundary is not non-runtime")

    _require(
        str(provenance.get("a05_seed_sha256", "")).lower() == EXPECTED_A05_SHA256,
        "A0.5 seed provenance SHA drift",
    )
    _require(
        str(provenance.get("a06_identity_sha256", "")).lower() == EXPECTED_A06_SHA256,
        "A0.6 identity provenance SHA drift",
    )
    _require(
        str(provenance.get("decision_document_sha256", "")).lower() == EXPECTED_DECISION_SHA256,
        "A0.7 decision provenance SHA drift",
    )
    _require(_sha256(a05_seed_path) == EXPECTED_A05_SHA256, "A0.5 seed current SHA does not match authority")
    _require(_sha256(a06_identity_path) == EXPECTED_A06_SHA256, "A0.6 identity current SHA does not match authority")
    _require(_sha256(decision_document_path) == EXPECTED_DECISION_SHA256, "A0.7 decision current SHA does not match authority")

    expected_taxonomy = dict(TIER_DENOMINATORS)
    _require({str(key): int(value) for key, value in taxonomy.items()} == expected_taxonomy, "Tier taxonomy/denominators drift")

    a05_items = a05_seed.get("items")
    a06_records = a06_identity.get("records")
    _require(isinstance(a05_items, list), "A0.5 seed items is not an array")
    _require(isinstance(a06_records, list), "A0.6 identity records is not an array")
    _require(len(a05_items) == 233, "A0.5 seed item count is not 233")
    _require(len(a06_records) == 53, "A0.6 identity record count is not 53")
    _require(a05_seed.get("summary", {}).get("unique_drop_items") == 233, "A0.5 unique item summary drift")
    _require(a05_seed.get("summary", {}).get("tier_deterministically_resolved") == 225, "A0.5 resolved summary drift")
    _require(a05_seed.get("summary", {}).get("tier_unresolved") == 8, "A0.5 unresolved summary drift")

    a05_by_name = _as_name_map(a05_items, "A0.5")
    _require(len(a05_by_name) == 233, "A0.5 names are not unique")
    a06_by_sid: dict[int, dict[str, Any]] = {}
    a06_by_name: dict[str, dict[str, Any]] = {}
    for row in a06_records:
        _require(isinstance(row, dict), "A0.6 record is not an object")
        sid = _positive_int(row.get("legacy_service_index"))
        canonical_id = _positive_int(row.get("canonical_item_id"))
        name = str(row.get("normalized_item_name", ""))
        _require(sid is not None and canonical_id is not None and name, "A0.6 identity record is incomplete")
        _require(sid not in a06_by_sid and name not in a06_by_name, f"A0.6 identity collision: {name}")
        a06_by_sid[sid] = row
        a06_by_name[name] = row
    _require(len(a06_by_sid) == 53 and len(a06_by_name) == 53, "A0.6 identity keys are not unique")

    unresolved_names = {
        str(row.get("item_name", ""))
        for row in a05_items
        if not row.get("candidate_tier")
    }
    _require(len(unresolved_names) == 8, "A0.5 unresolved set is not exactly eight")

    by_name = _as_name_map(records, "A0.7")
    _require(len(records) == 233, "A0.7 authority does not contain exactly 233 records")
    _require(len(by_name) == 233, "A0.7 canonical names are not unique")
    ids: set[int] = set()
    tier_counts: Counter[str] = Counter()
    tier_status_counts: Counter[str] = Counter()
    expected_a05_count = 0
    expected_a07_count = 0

    for source in a05_items:
        source_name = str(source.get("item_name", ""))
        row = by_name.get(source_name)
        _require(row is not None, f"A0.7 record missing A0.5 item: {source_name}")
        canonical_id = _positive_int(row.get("canonical_item_id"))
        _require(canonical_id is not None, f"A0.7 canonical ID is not positive: {source_name}")
        _require(canonical_id not in ids, f"A0.7 canonical ID collision: {canonical_id}")
        ids.add(canonical_id)
        _require(row.get("canonical_name") == source_name, f"A0.7 canonical name drift: {source_name}")
        _require(row.get("tier_status") == "RESOLVED", f"A0.7 Tier is not RESOLVED: {source_name}")
        _require(row.get("authority") == "DPV2_A07_ITEM_TIER_AUTHORITY_V1", f"A0.7 record authority missing: {source_name}")
        _require(row.get("denominator_override") is None, f"per-item denominator override is present: {source_name}")
        _require(row.get("blocker") is None, f"A0.7 blocker remains: {source_name}")
        _require(row.get("source_rate_provenance") == {
            "source_path": "outputs/monster_drop_p1a/monster_drop_p1a_slots.csv",
            "field": "source_rate",
            "role": "provenance_only",
            "used_for_tier": False,
            "used_for_denominator": False,
        }, f"source_rate policy drift: {source_name}")

        source_id = _positive_int(source.get("canonical_item_id"))
        source_sid = _positive_int(source.get("service_index"))
        if source_id is None:
            _require(source_sid is not None, f"A0.5 missing identity has no service index: {source_name}")
            identity = a06_by_sid.get(source_sid)
            _require(identity is not None, f"A0.6 identity missing for service {source_sid}: {source_name}")
            expected_id = _positive_int(identity.get("canonical_item_id"))
            _require(identity.get("normalized_item_name") == source_name, f"A0.6 name parity drift: {source_name}")
            expected_identity_source = "A0_6_ITEM_IDENTITY_AUTHORITY"
            expected_legacy_sid: int | None = source_sid
        else:
            expected_id = source_id
            expected_identity_source = "A0_5_POSITIVE_ITEM_ID"
            expected_legacy_sid = None
        _require(canonical_id == expected_id, f"A0.6/A0.5 canonical ID parity drift: {source_name}")
        _require(row.get("identity_source") == expected_identity_source, f"identity source drift: {source_name}")
        _require(row.get("legacy_service_index") == expected_legacy_sid, f"legacy service identity drift: {source_name}")
        expected_service_role = (
            "legacy_source_locator_plus_provenance_only"
            if expected_legacy_sid is not None
            else "not_applicable_item_master_identity"
        )
        _require(row.get("service_index_role") == expected_service_role, f"service index role drift: {source_name}")

        tier = str(row.get("tier", ""))
        base_denominator = row.get("base_denominator")
        _require(tier in expected_taxonomy, f"unknown Tier: {source_name}")
        _require(base_denominator == expected_taxonomy[tier], f"Tier denominator drift: {source_name}")
        tier_counts[tier] += 1
        tier_status_counts[str(row.get("tier_status"))] += 1

        if source_name in unresolved_names:
            decision = NEW_HUMAN_DECISIONS.get(canonical_id)
            _require(decision is not None, f"unresolved item has no exact A0.7 decision: {source_name}")
            _require(row.get("authority_basis") == "A0_7_HUMAN_AUTHORITY_DECISION", f"A0.7 decision basis drift: {source_name}")
            _require(row.get("source_candidate_tier") is None, f"A0.7 item retains an old candidate Tier: {source_name}")
            _require(row.get("source_mapping_basis") == "DPV2_A07_HUMAN_AUTHORITY", f"A0.7 source basis drift: {source_name}")
            _require(tier == decision["tier"], f"A0.7 human Tier decision drift: {source_name}")
            _require(row.get("protected_drop") is decision["protected_drop"], f"protected_drop drift: {source_name}")
            _require(row.get("overflow_priority") == decision["overflow_priority"], f"overflow priority drift: {source_name}")
            _require(row.get("source_v1_mapping") is None, f"A0.7 material has stale V1 mapping: {source_name}")
            _require(row.get("confidence") == "HUMAN_FROZEN", f"A0.7 confidence drift: {source_name}")
            expected_a07_count += 1
        else:
            candidate = str(source.get("candidate_tier", ""))
            _require(candidate in expected_taxonomy, f"A0.5 candidate Tier missing: {source_name}")
            _require(tier == candidate, f"A0.5 candidate Tier parity drift: {source_name}")
            _require(row.get("authority_basis") == "A0_5_ACCEPTED_TIER_CANDIDATE", f"A0.5 authority basis drift: {source_name}")
            _require(row.get("source_candidate_tier") == candidate, f"A0.5 source candidate drift: {source_name}")
            _require(row.get("source_v1_mapping") == source.get("v1_mapping"), f"A0.5 V1 mapping drift: {source_name}")
            _require(row.get("source_mapping_basis") == source.get("mapping_basis"), f"A0.5 mapping basis drift: {source_name}")
            _require(row.get("confidence") == source.get("confidence"), f"A0.5 confidence drift: {source_name}")
            _require("protected_drop" not in row and "overflow_priority" not in row, f"unexpected A0.7 overflow policy: {source_name}")
            expected_a05_count += 1

    _require(ids and len(ids) == 233, "A0.7 IDs are not 233 unique positive values")
    _require(len(set(by_name)) == 233, "A0.7 names are not 233 unique values")
    _require(expected_a05_count == 225 and expected_a07_count == 8, "A0.5/A0.7 authority split is not 225+8")
    _require(set(NEW_HUMAN_DECISIONS).issubset(ids), "A0.7 human decision IDs are incomplete")
    _require(tier_counts["BOSS_KEY_ITEM"] == 2, "BOSS_KEY_ITEM count is not 2")
    _require(tier_counts["MONSTER_MATERIAL"] == 6, "MONSTER_MATERIAL count is not 6")
    _require(tier_counts == Counter({str(key): int(value) for key, value in summary.get("tier_counts", {}).items()}), "A0.7 tier counts summary drift")
    _require(summary.get("canonical_drop_items") == 233, "A0.7 canonical count summary drift")
    _require(summary.get("resolved_items") == 233, "A0.7 resolved count summary drift")
    _require(summary.get("unresolved_items") == 0, "A0.7 unresolved count is not zero")
    _require(summary.get("tier_status_counts") == {"RESOLVED": 233}, "A0.7 tier status summary drift")
    _require(tier_status_counts == Counter({"RESOLVED": 233}), "A0.7 records contain non-resolved status")

    for needle in ("WAITING_HUMAN_AUTHORITY", "UNRESOLVED"):
        _require(not _contains_string(authority, needle), f"stale {needle} marker remains in A0.7 authority")

    source_rate_policy = authority.get("source_rate_policy")
    _require(source_rate_policy == {
        "source_path": "outputs/monster_drop_p1a/monster_drop_p1a_slots.csv",
        "field": "source_rate",
        "role": "provenance_only",
        "used_for_tier": False,
        "used_for_denominator": False,
    }, "source_rate authority policy is not provenance-only")

    return {
        "status": "PASS",
        "schema": EXPECTED_SCHEMA,
        "authority_records": len(records),
        "unique_canonical_ids": len(ids),
        "unique_canonical_names": len(by_name),
        "resolved_items": summary["resolved_items"],
        "unresolved_items": summary["unresolved_items"],
        "a05_accepted_tiers": expected_a05_count,
        "a07_human_decisions": expected_a07_count,
        "tier_counts": dict(sorted(tier_counts.items())),
        "tier_status_counts": dict(tier_status_counts),
        "source_rate_role": "provenance_only",
        "production_active": False,
        "phase1_allowed": False,
        "runtime_consumer": None,
        "persistence_consumer": None,
        "a06_identity_parity": True,
        "decision_document_sha256": EXPECTED_DECISION_SHA256,
    }


def validate_authority(
    *,
    repo_root: Path = ROOT,
    authority_path: Path | None = None,
    a05_seed_path: Path | None = None,
    a06_identity_path: Path | None = None,
    decision_document_path: Path | None = None,
) -> dict[str, Any]:
    root = repo_root.resolve()
    authority = (authority_path or root / AUTHORITY_RELATIVE).resolve()
    a05_seed = (a05_seed_path or root / A05_SEED_RELATIVE).resolve()
    a06_identity = (a06_identity_path or root / A06_IDENTITY_RELATIVE).resolve()
    decision = (decision_document_path or root / DECISION_DOCUMENT_RELATIVE).resolve()
    return validate_authority_documents(
        _load_json(authority),
        _load_json(a05_seed),
        _load_json(a06_identity),
        repo_root=root,
        authority_path=authority,
        a05_seed_path=a05_seed,
        a06_identity_path=a06_identity,
        decision_document_path=decision,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--authority", type=Path, default=None)
    parser.add_argument("--a05-seed", type=Path, default=None)
    parser.add_argument("--a06-identity", type=Path, default=None)
    parser.add_argument("--decision", type=Path, default=None)
    args = parser.parse_args(argv)
    try:
        result = validate_authority(
            repo_root=args.root,
            authority_path=args.authority,
            a05_seed_path=args.a05_seed,
            a06_identity_path=args.a06_identity,
            decision_document_path=args.decision,
        )
    except AuthorityValidationError as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
