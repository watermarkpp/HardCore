#!/usr/bin/env python3
"""Validate the complete non-runtime DPV2 A0.7 human Authority freeze."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ITEM_AUTHORITY = ROOT / "assets/data/drop/dpv2_item_tier_authority_v1.json"
ROLE_AUTHORITY = ROOT / "assets/data/drop/dpv2_monster_role_authority_v1.json"
DECISION = ROOT / "docs/drop/DPV2_A07_HUMAN_AUTHORITY_DECISION.md"
SNAPSHOT = ROOT / "outputs/monster_drop_p1a/runtime_snapshot.json"

EXPECTED_FILE_HASHES = {
    "assets/data/runtime/canonical_monster_catalog.json": "742C939875DD4CB14203C03056C386B1AD57FF9A9359F92B996160E07BA9E32D",
    "assets/data/canonical_monster_drop_source_v2.json": "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013",
    "outputs/monster_drop_p1a/monster_drop_p1a_slots.csv": "98201CA412873A5E17F6A9141DFD180AE4CA950F6C4718052CC30CBA77D95C0F",
    "scripts/game_data.gd": "66B292ED2B11BD2A8B739D0D60AD7E08A0A70BF19F237B17D79009A1BFCF1347",
    "scripts/game_root.gd": "6C2BAE8BBA8670EEDCCD29265E34514B612A4480FC410B54D20C93A09F3A6A1F",
    "project.godot": "6C2187CF476B347238B7E37CBEF43DEBE9EF61E35B163931A696ED1361463490",
}
EXPECTED_TREE_HASHES = {
    "scripts/map_editor": "4ff5a1acb9b0fd644f34106fd1759104dfdad719",
    "assets/data/runtime/map_editor": "38f20933766ad82ed4a386d9c61badd682b73446",
    "map_editor_workspace": "c50ef3d8c5b56184a1277fd7187703437fc7285a",
    "assets/maps": "c46ea4b3146096113ae793236a87e4ceceb7812d",
}
DECISION_SHA256 = "FDEEAAD95AC824E8CBDB98D4D7D8CD58844AB822DFF912F8F5B54E6FF9235EDC"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def git_tree_hash(relative: str) -> str:
    return subprocess.check_output(
        ["git", "rev-parse", f"HEAD:{relative}"], cwd=ROOT, text=True
    ).strip()


def main() -> int:
    item = load(ITEM_AUTHORITY)
    role = load(ROLE_AUTHORITY)
    snapshot = load(SNAPSHOT)

    require(sha256(DECISION) == DECISION_SHA256, "A0.7 decision hash drift")
    for document in (item, role):
        text = json.dumps(document, ensure_ascii=False)
        require("WAITING_HUMAN_AUTHORITY" not in text, "waiting Authority remains")
        require("UNRESOLVED" not in text, "unresolved Authority remains")
        activation = document["activation"]
        require(activation["production_active"] is False, "Authority became production active")
        require(activation["runtime_consumer"] is None, "Authority gained runtime consumer")
        phase1_allowed = activation.get("phase1_allowed", activation.get("phase_1_allowed"))
        require(phase1_allowed is False, "Phase 1 became allowed")

    item_records = item["records"]
    require(len(item_records) == 233, "item Authority count drift")
    require(len({int(row["canonical_item_id"]) for row in item_records}) == 233, "item IDs are not unique")
    require(all(int(row["canonical_item_id"]) > 0 for row in item_records), "non-positive item ID")
    require(all(row["tier_status"] == "RESOLVED" for row in item_records), "unresolved item Tier")
    require(item["summary"]["resolved_items"] == 233 and item["summary"]["unresolved_items"] == 0, "item summary drift")
    require(item["source_rate_policy"]["role"] == "provenance_only", "source rate became probability Authority")

    boss_keys = {int(row["canonical_item_id"]): row for row in item_records if row["tier"] == "BOSS_KEY_ITEM"}
    materials = {int(row["canonical_item_id"]): row for row in item_records if row["tier"] == "MONSTER_MATERIAL"}
    require(set(boss_keys) == {920023, 920032}, "BOSS_KEY_ITEM membership drift")
    require(set(materials) == {920037, 920038, 920039, 920040, 920049, 920050}, "MONSTER_MATERIAL membership drift")
    for row in boss_keys.values():
        require(row["base_denominator"] == 32 and row["protected_drop"] is True and row["overflow_priority"] == 200, "boss key policy drift")
    for row in materials.values():
        require(row["base_denominator"] == 32 and row["protected_drop"] is False and row["overflow_priority"] == 100, "material policy drift")
    for row in [*boss_keys.values(), *materials.values()]:
        require("per_item_denominator_override" not in row or row["per_item_denominator_override"] is None, "per-item denominator override added")

    monsters = role["monsters"]
    require(len(monsters) == 156, "monster Authority count drift")
    require(len({int(row["canonical_monster_id"]) for row in monsters}) == 156, "monster IDs are not unique")
    enabled = [row for row in monsters if row["drop_enabled"] is True]
    disabled = [row for row in monsters if row["drop_enabled"] is False]
    require(len(enabled) == 131 and len(disabled) == 25, "monster A/B partition drift")
    require(all(row["drop_role"] and float(row["role_factor"]) > 0 and row["reporting_label"] is None for row in enabled), "invalid enabled monster state")
    require(all(row["drop_role"] is None and row["role_factor"] is None and row["reporting_label"] == "NON_LOOT" for row in disabled), "invalid NON_LOOT state")
    require(all(row["role_factor"] != 0 for row in monsters), "factor zero entered final Authority")

    by_id = {int(row["canonical_monster_id"]): row for row in monsters}
    expected_human = {77: ("MAJOR_BOSS", 12), 137: ("ELITE", 3), 142: ("MINOR_BOSS", 6)}
    for monster_id, (expected_role, expected_factor) in expected_human.items():
        row = by_id[monster_id]
        require(row["drop_role"] == expected_role and row["role_factor"] == expected_factor, f"human override drift: {monster_id}")
        require(row["assignment_authority"] == "HUMAN_FROZEN", f"human authority marker drift: {monster_id}")

    require(role["summary"]["veteran_formal_definitions"] == 0, "VETERAN definition returned")
    require(role["summary"]["veteran_assignments"] == 0, "VETERAN assignment returned")
    clothes = role["new_clothes_boss_authority"]
    mappings = clothes["mappings"]
    require(clothes["boss_count"] == 6, "new-clothes boss count drift")
    require(clothes["item_count"] == 6, "new-clothes item count drift")
    violations = (6 - len({int(row["canonical_monster_id"]) for row in mappings})) + (6 - len({int(row["canonical_item_id"]) for row in mappings}))
    require(len(mappings) == 6 and violations == 0, "new-clothes bijection violation")
    cow = by_id[225]
    require(cow["drop_role"] == "ENDGAME_BOSS" and cow["role_factor"] == 16 and cow["new_clothes_eligible"] is False, "monster 225 freeze drift")

    summary = snapshot["summary"]
    require(summary["drop_profile_count"] == 156, "P1A active count drift")
    require(summary["monster_runtime_gate_counts"]["allowed"] == 153, "P1A runtime_allowed drift")
    require(summary["slot_count"] == 7032, "P1A slot count drift")
    require(summary["reward_unresolved_count"] == 0, "P1A reward unresolved drift")

    for relative, expected in EXPECTED_FILE_HASHES.items():
        require(sha256(ROOT / relative) == expected, f"protected file changed: {relative}")
    for relative, expected in EXPECTED_TREE_HASHES.items():
        require(git_tree_hash(relative) == expected, f"protected tree changed: {relative}")

    print(
        "DPV2_A07_HUMAN_AUTHORITY_FREEZE_PASS: items=233/233 tiers_unresolved=0 "
        "monsters=156 enabled=131 non_loot=25 role_unresolved=0 veteran=0 "
        "clothes=6x6 cow225=ENDGAME_BOSS@16 slots=7032 protected_hashes=PASS phase1=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
