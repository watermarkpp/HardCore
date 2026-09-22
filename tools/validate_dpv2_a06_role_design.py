#!/usr/bin/env python3
"""Validate the non-runtime DPV2 A0.6 role-design authority."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "assets/data/drop/dpv2_drop_role_design_authority_v1.json"
CATALOG = ROOT / "assets/data/runtime/canonical_monster_catalog.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    authority = load(AUTHORITY)
    catalog = load(CATALOG)
    catalog_by_id = {int(row["monster_id"]): row for row in catalog["entries"]}

    formal_roles = authority["formal_roles"]
    formal_names = [row["role"] for row in formal_roles]
    require(len(formal_names) == len(set(formal_names)), "formal role names must be unique")
    require("VETERAN" not in formal_names, "VETERAN remains in formal role taxonomy")
    require("UNIQUE_GEAR_BOSS" not in formal_names, "UNIQUE_GEAR_BOSS remains formal")
    require("NEW_CLOTHES_BOSS" in formal_names, "NEW_CLOTHES_BOSS missing")
    removed = {row["role"] for row in authority["removed_roles"]}
    require({"VETERAN", "UNIQUE_GEAR_BOSS"} <= removed, "removed-role decisions incomplete")

    mappings = authority["new_clothes_boss_authority"]["mappings"]
    boss_ids = [int(row["canonical_monster_id"]) for row in mappings]
    item_ids = [int(row["canonical_item_id"]) for row in mappings]
    require(len(mappings) == 6, "new-clothes mapping count must be six")
    require(len(set(boss_ids)) == 6, "new-clothes bosses are not one-to-one")
    require(len(set(item_ids)) == 6, "new-clothes items are not one-to-one")
    for row in mappings:
        monster_id = int(row["canonical_monster_id"])
        require(monster_id in catalog_by_id, f"unknown new-clothes monster {monster_id}")
        require(catalog_by_id[monster_id]["canonical_name"] == row["canonical_monster_name"], f"name drift for monster {monster_id}")

    frozen = authority["frozen_overrides"]
    require(len(frozen) == 1, "unexpected frozen override count")
    cow = frozen[0]
    require(int(cow["canonical_monster_id"]) == 225, "dark cow ID drift")
    require(cow["role"] == "ENDGAME_BOSS" and float(cow["factor"]) == 16, "dark cow role drift")
    require(cow["new_clothes_eligible"] is False, "dark cow gained clothes eligibility")
    require(225 not in set(boss_ids), "dark cow entered six-clothes mapping")
    require(catalog_by_id[225]["canonical_name"] == "暗之牛魔王", "dark cow canonical identity drift")

    counts = authority["accepted_candidate_counts"]
    require(counts == {"canonical_monsters": 156, "runtime_allowed": 153, "accepted_without_conflict": 124, "waiting_human_role_decision": 32}, "A0.6 candidate counts drift")
    require(authority["activation"] == {"production_active": False, "phase_1_allowed": False, "runtime_consumer": None}, "A0.6 activation boundary drift")

    print("DPV2_A06_ROLE_DESIGN_PASS: formal_roles=%d veteran=0 new_clothes=6 conflicts=32 dark_cow=ENDGAME_BOSS@16" % len(formal_roles))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
