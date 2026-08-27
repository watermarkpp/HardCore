#!/usr/bin/env python3
"""Build-time validator for the non-runtime DPV2 A0.7 monster-role authority."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY_PATH = ROOT / "assets/data/drop/dpv2_monster_role_authority_v1.json"
CATALOG_PATH = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
DESIGN_PATH = ROOT / "assets/data/drop/dpv2_drop_role_design_authority_v1.json"
DECISION_PATH = ROOT / "docs/drop/DPV2_A07_HUMAN_AUTHORITY_DECISION.md"
A06_PACKAGE_DOC_PATH = ROOT / "docs/drop/DPV2_A06_MONSTER_ROLE_DECISION_PACKAGE.md"
SEED_PATH = ROOT / "outputs/drop/dpv2_monster_role_seed_candidate.json"
CONFLICT_PACKAGE_PATH = ROOT / "outputs/drop/dpv2_monster_role_conflicts_32.json"

SCHEMA = "hardcore.dpv2.monster_role_authority.v1"
STATUS = "A0_7_FORMAL_AUTHORITY_COMPLETE_PHASE_1_FORBIDDEN"
DECISION_SHA256 = "FDEEAAD95AC824E8CBDB98D4D7D8CD58844AB822DFF912F8F5B54E6FF9235EDC"
CATALOG_SHA256 = "742C939875DD4CB14203C03056C386B1AD57FF9A9359F92B996160E07BA9E32D"
DESIGN_SHA256 = "30FE94845CF44298F3F054AEF14142B591FB4AAD727EFACEC6489E2C053E42C3"
A06_PACKAGE_DOC_SHA256 = "424CEAE8948D4C2B465FEDF32E3167C73D487B4C81F4737456B66A9D76D951CC"
SEED_SHA256 = "9A5B3689CB78ED74DE6E0F5E3C35E10A52ABD04B83FCCB1B935ED4F4A247E8D5"
CONFLICT_PACKAGE_SHA256 = "72018CFAB46EC92A7ED635F15F0D85C8E52498E6CA66ADD72637AA561C051D35"

LEGAL_ROLE_FACTORS: dict[str, int | float] = {
    "COMMON": 1,
    "STRONG_COMMON": 1.5,
    "ELITE": 3,
    "OFFICIAL_JP": 4,
    "OFFICIAL_SUPER_JP": 5,
    "MINOR_BOSS": 6,
    "BOSS": 8,
    "MAJOR_BOSS": 12,
    "ENDGAME_BOSS": 16,
    "NEW_CLOTHES_BOSS": 16,
}
FORBIDDEN_PROBABILITY_ROLES = {
    "VETERAN",
    "UNIQUE_GEAR_BOSS",
    "PRESENTATION",
    "SYSTEM",
    "NON_LOOT",
}
ZERO_STATE_SOURCE_ROLES = {"PRESENTATION", "SYSTEM", "NON_LOOT"}
RECONCILIATION_CODE = "A0_7_ZERO_ROLE_TO_DISABLED_NON_LOOT"

EXPECTED_ROLE_COUNTS = {
    "BOSS": 4,
    "COMMON": 41,
    "ELITE": 16,
    "ENDGAME_BOSS": 4,
    "MAJOR_BOSS": 8,
    "MINOR_BOSS": 13,
    "NEW_CLOTHES_BOSS": 6,
    "OFFICIAL_JP": 6,
    "OFFICIAL_SUPER_JP": 1,
    "STRONG_COMMON": 32,
}

# A0.6 recommendation parity is explicit here so validation does not depend on
# ignored outputs remaining present in a future checkout.
EXPECTED_A06_CONFLICT_RECOMMENDATIONS: dict[int, tuple[str, int | float]] = {
    39: ("STRONG_COMMON", 1.5),
    41: ("ELITE", 3),
    55: ("ELITE", 3),
    57: ("MINOR_BOSS", 6),
    59: ("NON_LOOT", 0),
    74: ("ELITE", 3),
    75: ("ELITE", 3),
    77: ("NON_LOOT", 0),
    78: ("NON_LOOT", 0),
    90: ("MINOR_BOSS", 6),
    91: ("ELITE", 3),
    121: ("MINOR_BOSS", 6),
    122: ("ELITE", 3),
    123: ("ELITE", 3),
    131: ("OFFICIAL_JP", 4),
    133: ("STRONG_COMMON", 1.5),
    134: ("OFFICIAL_JP", 4),
    136: ("ELITE", 3),
    137: ("NON_LOOT", 0),
    140: ("OFFICIAL_JP", 4),
    142: ("NON_LOOT", 0),
    152: ("OFFICIAL_JP", 4),
    155: ("OFFICIAL_JP", 4),
    157: ("ELITE", 3),
    158: ("OFFICIAL_JP", 4),
    159: ("OFFICIAL_SUPER_JP", 5),
    161: ("NON_LOOT", 0),
    189: ("ELITE", 3),
    190: ("ELITE", 3),
    192: ("ELITE", 3),
    199: ("BOSS", 8),
    209: ("MAJOR_BOSS", 12),
}
HUMAN_FROZEN_OVERRIDES: dict[int, tuple[str, int | float]] = {
    77: ("MAJOR_BOSS", 12),
    137: ("ELITE", 3),
    142: ("MINOR_BOSS", 6),
}
NEW_CLOTHES_BIJECTION: dict[int, int] = {
    235: 140,
    236: 144,
    237: 142,
    238: 141,
    239: 145,
    240: 143,
}


class AuthorityValidationError(ValueError):
    """Raised when the A0.7 authority violates a frozen contract."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AuthorityValidationError(message)


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _source_record(path: Path, digest: str, role: str) -> dict[str, Any]:
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "sha256": digest,
        "role": role,
    }


def build_authority_from_frozen_sources(repo_root: Path = ROOT) -> dict[str, Any]:
    """Reconstruct the checked-in authority from the frozen A0.5/A0.6 inputs."""

    catalog = _read_json(repo_root / CATALOG_PATH.relative_to(ROOT))
    design = _read_json(repo_root / DESIGN_PATH.relative_to(ROOT))
    seed = _read_json(repo_root / SEED_PATH.relative_to(ROOT))
    conflicts = _read_json(repo_root / CONFLICT_PACKAGE_PATH.relative_to(ROOT))

    catalog_entries = sorted(catalog["entries"], key=lambda row: row["monster_id"])
    seed_by_id = {row["canonical_monster_id"]: row for row in seed["monsters"]}
    conflict_by_id = {row["canonical_monster_id"]: row for row in conflicts["conflicts"]}
    _require(len(catalog_entries) == 156, "builder requires exactly 156 catalog entries")
    _require(set(seed_by_id) == {row["monster_id"] for row in catalog_entries}, "seed/catalog ID mismatch")
    _require(set(conflict_by_id) == set(EXPECTED_A06_CONFLICT_RECOMMENDATIONS), "A0.6 conflict ID mismatch")

    design_mappings = design["new_clothes_boss_authority"]["mappings"]
    item_by_boss = {row["canonical_monster_id"]: row["canonical_item_id"] for row in design_mappings}
    _require(item_by_boss == NEW_CLOTHES_BIJECTION, "A0.6 NEW_CLOTHES mapping drift")

    rows: list[dict[str, Any]] = []
    for catalog_row in catalog_entries:
        monster_id = catalog_row["monster_id"]
        seed_row = seed_by_id[monster_id]
        _require(seed_row["canonical_name"] == catalog_row["canonical_name"], f"seed name drift for {monster_id}")
        is_conflict = monster_id in conflict_by_id

        if is_conflict:
            conflict_row = conflict_by_id[monster_id]
            recommendation = conflict_row["recommendation_only"]
            source_role = recommendation["recommended_role"]
            source_factor = recommendation["recommended_factor"]
            _require(
                (source_role, source_factor) == EXPECTED_A06_CONFLICT_RECOMMENDATIONS[monster_id],
                f"A0.6 conflict recommendation drift for {monster_id}",
            )
            if monster_id in HUMAN_FROZEN_OVERRIDES:
                final_role, final_factor = HUMAN_FROZEN_OVERRIDES[monster_id]
                assignment_authority = "HUMAN_FROZEN"
            else:
                final_role, final_factor = source_role, source_factor
                assignment_authority = "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION"
        else:
            source_role = seed_row["candidate_dpv2_role"]
            source_factor = seed_row["candidate_factor"]
            final_role, final_factor = source_role, source_factor
            assignment_authority = "A0_6_DETERMINISTIC_ACCEPTED"

        disabled = final_role in ZERO_STATE_SOURCE_ROLES
        if disabled:
            drop_enabled = False
            drop_role = None
            role_factor = None
            reporting_label = "NON_LOOT"
            reconciliation = RECONCILIATION_CODE
        else:
            drop_enabled = True
            drop_role = final_role
            role_factor = final_factor
            reporting_label = None
            reconciliation = None

        authority_evidence: dict[str, Any] = {
            "decision_document": DECISION_PATH.relative_to(ROOT).as_posix(),
            "decision_document_sha256": DECISION_SHA256,
        }
        if monster_id in HUMAN_FROZEN_OVERRIDES:
            authority_evidence["override_of_a06_recommendation"] = {
                "role": source_role,
                "factor": source_factor,
            }

        rows.append(
            {
                "canonical_monster_id": monster_id,
                "canonical_name": catalog_row["canonical_name"],
                "runtime_allowed": catalog_row["runtime_allowed"],
                "drop_enabled": drop_enabled,
                "drop_role": drop_role,
                "role_factor": role_factor,
                "reporting_label": reporting_label,
                "assignment_authority": assignment_authority,
                "authority_evidence": authority_evidence,
                "a06_source_recommendation": {
                    "role": source_role,
                    "factor": source_factor,
                    "conflict": is_conflict,
                },
                "state_reconciliation": reconciliation,
                "new_clothes_eligible": monster_id in NEW_CLOTHES_BIJECTION,
                "new_clothes_item_id": item_by_boss.get(monster_id),
            }
        )

    role_counts = dict(sorted(Counter(row["drop_role"] for row in rows if row["drop_enabled"]).items()))
    enabled_count = sum(row["drop_enabled"] for row in rows)
    disabled_count = len(rows) - enabled_count
    authority = {
        "schema": SCHEMA,
        "status": STATUS,
        "authority": {
            "kind": "user_authoritative_override",
            "decision_document": DECISION_PATH.relative_to(ROOT).as_posix(),
            "decision_document_sha256": DECISION_SHA256,
            "canonical_identity_authority": CATALOG_PATH.relative_to(ROOT).as_posix(),
            "sources": [
                _source_record(DECISION_PATH, DECISION_SHA256, "A0.7 exhaustive two-state and human override authority"),
                _source_record(CATALOG_PATH, CATALOG_SHA256, "current canonical monster ID/name/runtime authority"),
                _source_record(DESIGN_PATH, DESIGN_SHA256, "A0.6 legal roles and frozen boss mappings"),
                _source_record(A06_PACKAGE_DOC_PATH, A06_PACKAGE_DOC_SHA256, "A0.6 conflict recommendation evidence"),
                _source_record(SEED_PATH, SEED_SHA256, "A0.5 124 deterministic recommendations; construction evidence only"),
                _source_record(CONFLICT_PACKAGE_PATH, CONFLICT_PACKAGE_SHA256, "A0.6 32 conflict recommendations; construction evidence only"),
            ],
        },
        "contract": {
            "exhaustive_state_model": "EXACTLY_ONE_OF_ENABLED_PROBABILITY_ROLE_OR_DISABLED_NON_LOOT",
            "enabled_state": {
                "drop_enabled": True,
                "drop_role": "NON_NULL_FORMAL_ROLE",
                "role_factor": "LEGAL_POSITIVE_FACTOR",
                "reporting_label": None,
            },
            "disabled_state": {
                "drop_enabled": False,
                "drop_role": None,
                "role_factor": None,
                "reporting_label": "NON_LOOT",
            },
            "zero_factor_final_assignment_forbidden": True,
            "reconciliation_code": RECONCILIATION_CODE,
            "reconciliation_reason": (
                "A0.6 PRESENTATION, SYSTEM and NON_LOOT factor-zero recommendations are represented as the exact "
                "disabled NON_LOOT reporting state required by the user's exhaustive A0.7 two-state contract; "
                "this changes probability-state representation only and is not a semantic monster identity rewrite."
            ),
            "semantic_identity_rewrite": False,
        },
        "formal_probability_roles": [
            {"role": role, "factor": factor} for role, factor in LEGAL_ROLE_FACTORS.items()
        ],
        "forbidden_probability_roles": sorted(FORBIDDEN_PROBABILITY_ROLES),
        "summary": {
            "canonical_monsters": len(rows),
            "runtime_allowed": sum(row["runtime_allowed"] for row in rows),
            "enabled": enabled_count,
            "disabled_non_loot": disabled_count,
            "unresolved": 0,
            "waiting_human_authority": 0,
            "a06_non_conflict_accepted": sum(not row["a06_source_recommendation"]["conflict"] for row in rows),
            "a06_conflict_finalized": sum(row["a06_source_recommendation"]["conflict"] for row in rows),
            "a06_conflict_recommendations_accepted": 29,
            "human_frozen_overrides": len(HUMAN_FROZEN_OVERRIDES),
            "veteran_formal_definitions": 0,
            "veteran_assignments": 0,
            "role_distribution": role_counts,
        },
        "new_clothes_boss_authority": {
            "role": "NEW_CLOTHES_BOSS",
            "factor": 16,
            "boss_count": 6,
            "item_count": 6,
            "one_to_one_required": True,
            "mappings": design_mappings,
        },
        "dark_cow_king": {
            "canonical_monster_id": 225,
            "canonical_name": seed_by_id[225]["canonical_name"],
            "drop_role": "ENDGAME_BOSS",
            "role_factor": 16,
            "new_clothes_eligible": False,
        },
        "activation": {
            "production_active": False,
            "runtime_consumer": None,
            "phase_1_allowed": False,
        },
        "monsters": rows,
    }
    validate_authority(authority, repo_root=repo_root, verify_source_hashes=True)
    return authority


def validate_authority(
    authority: dict[str, Any],
    *,
    repo_root: Path = ROOT,
    verify_source_hashes: bool = True,
) -> dict[str, Any]:
    _require(authority.get("schema") == SCHEMA, "schema mismatch")
    _require(authority.get("status") == STATUS, "authority is not complete/non-runtime A0.7")
    authority_meta = authority.get("authority", {})
    _require(authority_meta.get("kind") == "user_authoritative_override", "authority kind mismatch")
    _require(authority_meta.get("decision_document") == DECISION_PATH.relative_to(ROOT).as_posix(), "decision path mismatch")
    _require(authority_meta.get("decision_document_sha256") == DECISION_SHA256, "decision digest mismatch")
    source_by_path = {row.get("path"): row for row in authority_meta.get("sources", [])}
    decision_source = source_by_path.get(DECISION_PATH.relative_to(ROOT).as_posix(), {})
    _require(decision_source.get("sha256") == DECISION_SHA256, "user-authoritative source evidence mismatch")

    if verify_source_hashes:
        pinned_files = {
            DECISION_PATH.relative_to(ROOT): DECISION_SHA256,
            CATALOG_PATH.relative_to(ROOT): CATALOG_SHA256,
            DESIGN_PATH.relative_to(ROOT): DESIGN_SHA256,
            A06_PACKAGE_DOC_PATH.relative_to(ROOT): A06_PACKAGE_DOC_SHA256,
        }
        for relative_path, expected_digest in pinned_files.items():
            actual_path = repo_root / relative_path
            _require(actual_path.is_file(), f"missing pinned authority source: {relative_path.as_posix()}")
            _require(_sha256(actual_path) == expected_digest, f"pinned authority source hash drift: {relative_path.as_posix()}")

    activation = authority.get("activation")
    _require(
        activation == {"production_active": False, "runtime_consumer": None, "phase_1_allowed": False},
        "A0.7 activation boundary mismatch",
    )
    formal_roles = authority.get("formal_probability_roles", [])
    formal_role_map = {row.get("role"): row.get("factor") for row in formal_roles}
    _require(len(formal_roles) == len(LEGAL_ROLE_FACTORS), "duplicate or extra formal role definition")
    _require(formal_role_map == LEGAL_ROLE_FACTORS, "formal probability role/factor set mismatch")
    _require(not (set(formal_role_map) & FORBIDDEN_PROBABILITY_ROLES), "forbidden probability role defined")
    _require(all(factor > 0 for factor in formal_role_map.values()), "formal role factor must be positive")
    _require(
        authority.get("forbidden_probability_roles") == sorted(FORBIDDEN_PROBABILITY_ROLES),
        "forbidden probability role registry mismatch",
    )
    contract = authority.get("contract", {})
    _require(contract.get("zero_factor_final_assignment_forbidden") is True, "factor-zero final guard missing")
    _require(contract.get("reconciliation_code") == RECONCILIATION_CODE, "reconciliation code mismatch")
    _require(contract.get("semantic_identity_rewrite") is False, "two-state reconciliation became an identity rewrite")

    catalog = _read_json(repo_root / CATALOG_PATH.relative_to(ROOT))
    catalog_by_id = {row["monster_id"]: row for row in catalog["entries"]}
    rows = authority.get("monsters", [])
    by_id = {row.get("canonical_monster_id"): row for row in rows}
    _require(len(rows) == 156, "authority must contain exactly 156 rows")
    _require(len(by_id) == 156, "authority monster IDs must be unique")
    _require(set(by_id) == set(catalog_by_id), "authority/catalog monster ID set mismatch")

    authority_counts: Counter[str] = Counter()
    role_counts: Counter[str] = Counter()
    enabled_count = 0
    disabled_count = 0
    conflict_ids: set[int] = set()
    for monster_id, row in by_id.items():
        catalog_row = catalog_by_id[monster_id]
        _require(row.get("canonical_name") == catalog_row["canonical_name"], f"canonical name mismatch for {monster_id}")
        _require(row.get("runtime_allowed") is catalog_row["runtime_allowed"], f"runtime_allowed mismatch for {monster_id}")
        _require(
            row.get("authority_evidence", {}).get("decision_document")
            == DECISION_PATH.relative_to(ROOT).as_posix()
            and row.get("authority_evidence", {}).get("decision_document_sha256") == DECISION_SHA256,
            f"user-authoritative row evidence mismatch for {monster_id}",
        )
        _require(row.get("assignment_authority") in {
            "A0_6_DETERMINISTIC_ACCEPTED",
            "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION",
            "HUMAN_FROZEN",
        }, f"invalid assignment authority for {monster_id}")
        authority_counts[row["assignment_authority"]] += 1

        source = row.get("a06_source_recommendation", {})
        is_conflict = source.get("conflict") is True
        if is_conflict:
            conflict_ids.add(monster_id)
            _require(monster_id in EXPECTED_A06_CONFLICT_RECOMMENDATIONS, f"unexpected conflict ID {monster_id}")
            _require(
                (source.get("role"), source.get("factor")) == EXPECTED_A06_CONFLICT_RECOMMENDATIONS[monster_id],
                f"A0.6 conflict recommendation parity mismatch for {monster_id}",
            )
        else:
            _require(monster_id not in EXPECTED_A06_CONFLICT_RECOMMENDATIONS, f"conflict flag missing for {monster_id}")

        enabled_state = (
            row.get("drop_enabled") is True
            and row.get("drop_role") in LEGAL_ROLE_FACTORS
            and row.get("role_factor") == LEGAL_ROLE_FACTORS.get(row.get("drop_role"))
            and row.get("reporting_label") is None
        )
        disabled_state = (
            row.get("drop_enabled") is False
            and row.get("drop_role") is None
            and row.get("role_factor") is None
            and row.get("reporting_label") == "NON_LOOT"
        )
        _require(enabled_state ^ disabled_state, f"monster {monster_id} violates exact A/B state partition")
        _require(row.get("role_factor") != 0, f"monster {monster_id} exposes factor zero")

        if enabled_state:
            enabled_count += 1
            role_counts[row["drop_role"]] += 1
        else:
            disabled_count += 1

        if monster_id in HUMAN_FROZEN_OVERRIDES:
            expected_role, expected_factor = HUMAN_FROZEN_OVERRIDES[monster_id]
            _require(row["assignment_authority"] == "HUMAN_FROZEN", f"override {monster_id} is not HUMAN_FROZEN")
            _require(row["drop_enabled"] is True, f"override {monster_id} must be enabled")
            _require((row["drop_role"], row["role_factor"]) == (expected_role, expected_factor), f"override mismatch for {monster_id}")
            _require(row.get("state_reconciliation") is None, f"override {monster_id} must not use zero-state reconciliation")
            _require(
                row.get("authority_evidence", {}).get("override_of_a06_recommendation")
                == {"role": "NON_LOOT", "factor": 0},
                f"override evidence mismatch for {monster_id}",
            )
        elif source.get("role") in ZERO_STATE_SOURCE_ROLES:
            _require(disabled_state, f"zero-state recommendation was not disabled for {monster_id}")
            _require(row.get("state_reconciliation") == RECONCILIATION_CODE, f"missing A0.7 reconciliation for {monster_id}")
        else:
            _require(enabled_state, f"positive recommendation was not enabled for {monster_id}")
            _require(
                (row["drop_role"], row["role_factor"]) == (source.get("role"), source.get("factor")),
                f"accepted A0.6 recommendation drift for {monster_id}",
            )
            _require(row.get("state_reconciliation") is None, f"unexpected reconciliation for {monster_id}")

    _require(conflict_ids == set(EXPECTED_A06_CONFLICT_RECOMMENDATIONS), "32-conflict finalization coverage mismatch")
    _require(authority_counts == Counter({
        "A0_6_DETERMINISTIC_ACCEPTED": 124,
        "A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION": 29,
        "HUMAN_FROZEN": 3,
    }), "assignment authority distribution mismatch")
    _require(enabled_count == 131 and disabled_count == 25, "enabled/disabled partition count mismatch")
    _require(dict(sorted(role_counts.items())) == EXPECTED_ROLE_COUNTS, "final role distribution mismatch")

    summary = authority.get("summary", {})
    expected_summary_subset = {
        "canonical_monsters": 156,
        "runtime_allowed": 153,
        "enabled": 131,
        "disabled_non_loot": 25,
        "unresolved": 0,
        "waiting_human_authority": 0,
        "a06_non_conflict_accepted": 124,
        "a06_conflict_finalized": 32,
        "a06_conflict_recommendations_accepted": 29,
        "human_frozen_overrides": 3,
        "veteran_formal_definitions": 0,
        "veteran_assignments": 0,
        "role_distribution": EXPECTED_ROLE_COUNTS,
    }
    _require(summary == expected_summary_subset, "summary mismatch")

    new_clothes_authority = authority.get("new_clothes_boss_authority", {})
    _require(
        {key: new_clothes_authority.get(key) for key in ("role", "factor", "boss_count", "item_count", "one_to_one_required")}
        == {
            "role": "NEW_CLOTHES_BOSS",
            "factor": 16,
            "boss_count": 6,
            "item_count": 6,
            "one_to_one_required": True,
        },
        "NEW_CLOTHES authority header mismatch",
    )
    mappings = new_clothes_authority.get("mappings", [])
    mapping_by_boss = {row.get("canonical_monster_id"): row.get("canonical_item_id") for row in mappings}
    _require(len(mappings) == 6 and mapping_by_boss == NEW_CLOTHES_BIJECTION, "NEW_CLOTHES boss mapping mismatch")
    _require(len(set(mapping_by_boss.values())) == 6, "NEW_CLOTHES item side is not bijective")
    design = _read_json(repo_root / DESIGN_PATH.relative_to(ROOT))
    _require(mappings == design["new_clothes_boss_authority"]["mappings"], "NEW_CLOTHES mapping evidence drift")
    for monster_id, item_id in NEW_CLOTHES_BIJECTION.items():
        row = by_id[monster_id]
        _require(
            row["drop_enabled"] is True
            and row["drop_role"] == "NEW_CLOTHES_BOSS"
            and row["role_factor"] == 16
            and row["new_clothes_eligible"] is True
            and row["new_clothes_item_id"] == item_id,
            f"NEW_CLOTHES row mismatch for {monster_id}",
        )
    _require(sum(row.get("new_clothes_eligible") is True for row in rows) == 6, "NEW_CLOTHES eligibility must be exactly six")
    _require(
        all(
            row.get("new_clothes_item_id") is None
            for row in rows
            if row["canonical_monster_id"] not in NEW_CLOTHES_BIJECTION
        ),
        "non-NEW_CLOTHES monster has a clothing item binding",
    )

    dark_cow = by_id[225]
    _require(
        dark_cow["drop_enabled"] is True
        and dark_cow["drop_role"] == "ENDGAME_BOSS"
        and dark_cow["role_factor"] == 16
        and dark_cow["new_clothes_eligible"] is False
        and dark_cow["new_clothes_item_id"] is None,
        "monster 225 frozen ENDGAME_BOSS decision mismatch",
    )
    _require(
        authority.get("dark_cow_king")
        == {
            "canonical_monster_id": 225,
            "canonical_name": dark_cow["canonical_name"],
            "drop_role": "ENDGAME_BOSS",
            "role_factor": 16,
            "new_clothes_eligible": False,
        },
        "monster 225 top-level frozen record mismatch",
    )
    _require(all(row.get("drop_role") != "VETERAN" for row in rows), "VETERAN assignment found")
    _require(all("DARK_PALACE" not in str(row.get("drop_role")) for row in rows), "unknown-dark-palace role found")
    _require("WAITING_HUMAN_AUTHORITY" not in json.dumps(authority, ensure_ascii=False), "waiting decision remains")

    return {
        "status": "PASS",
        "canonical_monsters": 156,
        "enabled": enabled_count,
        "disabled_non_loot": disabled_count,
        "conflicts_finalized": len(conflict_ids),
        "human_frozen_overrides": len(HUMAN_FROZEN_OVERRIDES),
        "role_distribution": dict(sorted(role_counts.items())),
        "new_clothes_bijection": "6x6",
        "veteran_definitions": 0,
        "veteran_assignments": 0,
        "production_active": False,
    }


def validate_file(path: Path = AUTHORITY_PATH) -> dict[str, Any]:
    return validate_authority(_read_json(path), repo_root=ROOT, verify_source_hashes=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authority", type=Path, default=AUTHORITY_PATH)
    parser.add_argument(
        "--emit-authority",
        action="store_true",
        help="emit the deterministic authority reconstructed from the frozen inputs",
    )
    args = parser.parse_args()
    try:
        if args.emit_authority:
            print(json.dumps(build_authority_from_frozen_sources(), ensure_ascii=True, indent=2) + "\n", end="")
        else:
            print(json.dumps(validate_file(args.authority), ensure_ascii=False, sort_keys=True))
    except (AuthorityValidationError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
