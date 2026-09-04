#!/usr/bin/env python3
"""Cross-check every non-production DPV2 A0.6 authority deliverable."""

from __future__ import annotations

import json
from pathlib import Path

from dpv2_a06_item_identity_validator import validate_authority


ROOT = Path(__file__).resolve().parents[1]


def load(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    identity_result = validate_authority(repo_root=ROOT)
    identity = load("assets/data/drop/dpv2_item_identity_authority_v1.json")
    role_design = load("assets/data/drop/dpv2_drop_role_design_authority_v1.json")
    tier = load("outputs/drop/dpv2_item_tier_unresolved_8.json")
    roles = load("outputs/drop/dpv2_monster_role_conflicts_32.json")
    snapshot = load("outputs/monster_drop_p1a/runtime_snapshot.json")

    require(identity_result["overlay_positive_unique_items"] == 233, "item identity closure is not 233/233")
    identity_by_name = {row["normalized_item_name"]: row for row in identity["records"]}
    tier_items = tier["items"]
    require(len(tier_items) == 8, "Tier decision package must contain eight rows")
    require(len({row["name"] for row in tier_items}) == 8, "Tier decision names are not unique")
    for row in tier_items:
        authority_row = identity_by_name.get(row["name"])
        require(authority_row is not None, f"Tier row missing item authority: {row['name']}")
        require(int(row["canonical_item_id"]) == int(authority_row["canonical_item_id"]), f"Tier canonical ID drift: {row['name']}")
        require(int(row["service_index"]) == int(authority_row["legacy_service_index"]), f"Tier service provenance drift: {row['name']}")
        require(row["mapping_basis"] == "UNRESOLVED", f"Tier was auto-resolved: {row['name']}")
        require(row["authority_disposition"] == "WAITING_HUMAN_AUTHORITY", f"Tier status drift: {row['name']}")
        require(row["v1_denom"] is None and row["dpv2_override"] is None and row["effective_denom"] is None, f"Tier denominator was activated: {row['name']}")
        require(row["v1"]["exact_or_group_hits"] == [], f"unexpected V1 hit: {row['name']}")

    conflicts = roles["conflicts"]
    require(len(conflicts) == 32, "role decision package must contain 32 rows")
    require(len({int(row["canonical_monster_id"]) for row in conflicts}) == 32, "role conflict IDs are not unique")
    for row in conflicts:
        final = row["final_decision"]
        recommendation = row["recommendation_only"]
        require(final == {"status": "WAITING_HUMAN_AUTHORITY", "role": None, "factor": None, "auto_selected": False}, f"role was auto-selected: {row['canonical_monster_id']}")
        require(recommendation["highest_role_wins_used"] is False, f"highest-role-wins used: {row['canonical_monster_id']}")
        require(len(row["v1_candidates"]) >= 2, f"role candidates incomplete: {row['canonical_monster_id']}")

    formal_roles = {row["role"] for row in role_design["formal_roles"]}
    require("VETERAN" not in formal_roles, "VETERAN remains a formal DPV2 role")
    require("UNIQUE_GEAR_BOSS" not in formal_roles, "UNIQUE_GEAR_BOSS remains formal")
    require("NEW_CLOTHES_BOSS" in formal_roles, "NEW_CLOTHES_BOSS missing")
    clothes = role_design["new_clothes_boss_authority"]["mappings"]
    require(len(clothes) == 6, "six-clothes mapping count drift")
    require(len({int(row["canonical_monster_id"]) for row in clothes}) == 6, "six-clothes boss mapping is not one-to-one")
    require(len({int(row["canonical_item_id"]) for row in clothes}) == 6, "six-clothes item mapping is not one-to-one")
    cow = role_design["frozen_overrides"][0]
    require(cow == {"canonical_monster_id": 225, "canonical_name": "暗之牛魔王", "role": "ENDGAME_BOSS", "factor": 16, "new_clothes_eligible": False}, "monster 225 authority drift")

    require(int(snapshot["summary"]["drop_profile_count"]) == 156, "P1A profile count drift")
    require(int(snapshot["summary"]["slot_count"]) == 7032, "P1A slot count drift")
    require(role_design["activation"] == {"production_active": False, "phase_1_allowed": False, "runtime_consumer": None}, "A0.6 activation boundary drift")

    print(
        "DPV2_A06_AUTHORITY_CLOSURE_PASS: items=233/233 legacy53=resolved "
        "tiers=225+8_waiting roles=124+32_waiting veteran=0 clothes=6x6 cow225=ENDGAME_BOSS@16 slots=7032"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
