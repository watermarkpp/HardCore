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
RUNTIME_AUTHORITY = ROOT / "assets/data/drop/dpv2_drop_runtime_authority_v1.json"
GLOBAL_AUTHORITY = ROOT / "assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
CATALOG = ROOT / "assets/data/runtime/canonical_monster_catalog.json"
SPECIAL_NORMAL_AUTHORITY = ROOT / "assets/data/special_normal_monster_spawn_authority_v1.json"

EXPECTED_FILE_HASHES = {
    "assets/data/canonical_monster_drop_source_v2.json": "59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013",
    "project.godot": "6C2187CF476B347238B7E37CBEF43DEBE9EF61E35B163931A696ED1361463490",
}
EXPECTED_TREE_HASHES = {
    # Map-editor catalog code is an authorized post-A0.7 consumer of the
    # orthogonal special_normal spawn Authority; A0.7 continues to freeze the
    # actual map data and all 7032 drop inputs, not future catalog UI code.
    "assets/data/runtime/map_editor": "38f20933766ad82ed4a386d9c61badd682b73446",
    "map_editor_workspace": "c50ef3d8c5b56184a1277fd7187703437fc7285a",
    "assets/maps": "c46ea4b3146096113ae793236a87e4ceceb7812d",
}
DECISION_SHA256 = "FDEEAAD95AC824E8CBDB98D4D7D8CD58844AB822DFF912F8F5B54E6FF9235EDC"
SOURCE_SLOT_PROJECTION_SHA256 = "9481DAB12C3D6B0EAA279493242BD6FC523BA819750276487A4D8825B4CFB24B"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def sha256_lf(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest().upper()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def git_tree_hash(relative: str) -> str:
    return subprocess.check_output(
        ["git", "rev-parse", f"HEAD:{relative}"], cwd=ROOT, text=True
    ).strip()


def source_slot_projection_sha256(catalog: dict) -> str:
    rows = [
        {"profile": profile_id, "entry": entry}
        for profile_id in sorted(catalog["drop_profiles"])
        for entry in catalog["drop_profiles"][profile_id]["entries"]
    ]
    encoded = json.dumps(
        rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest().upper()


def main() -> int:
    item = load(ITEM_AUTHORITY)
    role = load(ROLE_AUTHORITY)
    snapshot = load(SNAPSHOT)
    runtime = load(RUNTIME_AUTHORITY)
    global_scale = load(GLOBAL_AUTHORITY)
    catalog = load(CATALOG)
    special_normal = load(SPECIAL_NORMAL_AUTHORITY)

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

    expected_special_provenance = {
        "item_tier_sha": sha256_lf(ITEM_AUTHORITY),
        "monster_role_sha": sha256_lf(ROLE_AUTHORITY),
        "global_scale_sha": sha256_lf(GLOBAL_AUTHORITY),
        "hash_normalization": "lf_text",
    }
    special_binding = special_normal.get("drop_binding", {})
    require(
        special_binding.get("authority_provenance") == expected_special_provenance,
        "special_normal DPV2 provenance drift",
    )
    for key in ("item_tier_sha", "monster_role_sha", "global_scale_sha"):
        require(
            special_binding.get(key) == expected_special_provenance[key],
            f"special_normal drop_binding.{key} drift",
        )
    special_sources = {
        str(row.get("path")): row
        for row in special_normal.get("authority", {}).get("sources", [])
        if isinstance(row, dict)
    }
    for relative, key in (
        ("assets/data/drop/dpv2_item_tier_authority_v1.json", "item_tier_sha"),
        ("assets/data/drop/dpv2_monster_role_authority_v1.json", "monster_role_sha"),
        ("assets/data/drop/dpv2_global_drop_rate_authority_v1.json", "global_scale_sha"),
    ):
        require(
            special_sources.get(relative, {}).get("sha256")
            == expected_special_provenance[key],
            f"special_normal source hash drift: {relative}",
        )

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

    require(runtime["schema"] == "hardcore.dpv2.drop_runtime_authority.v1", "runtime Authority schema drift")
    require(runtime["activation"]["production_active"] is True, "runtime Authority inactive")
    require(runtime["ground_overflow_policy"]["maximum_ground_slots"] == 9, "ground slot limit drift")
    require(len(runtime["item_overflow_records"]) == 233, "overflow item coverage drift")
	# Runtime overflow priority is derived from the resolved DPV2 tier, never
	# from item_type or source-array order. Ordinary equipment/books are useful
	# but are not protected telemetry classes.
    progress_tiers = {"BOSS_KEY_ITEM"}
    high_value_tiers = {
        "BOOK_35", "BOOK_HIGH", "REDMOON_SET", "NEW_CLOTHES",
        "LEGENDARY_WEAPON", "SPECIAL_RING", "ZUMA_GEAR",
        "HIGH_CLASS_WEAPON", "EXPANDED_HIGH_WEAPON", "MYSTERY_SIGNATURE",
        "PRAYER_MEMORY", "MAGICBLOOD_RAINBOW", "RARE_CONSUMABLE",
        "FUNCTIONAL_SPECIAL", "SOLAR_CONSUMABLE",
    }
    standard_equipment_tiers = {
        "EQUIP_LOW", "EQUIP_MID", "EQUIP_HIGH_MID", "WOOMA_GEAR",
    }
    standard_book_tiers = {"BOOK_LOW", "BOOK_MID"}
    expected_runtime_policy = {}
    for tier_name in progress_tiers:
        expected_runtime_policy[tier_name] = ("PROTECTED_PROGRESS", True, 400)
    for tier_name in high_value_tiers:
        expected_runtime_policy[tier_name] = ("PROTECTED_HIGH_VALUE", True, 300)
    for tier_name in standard_equipment_tiers:
        expected_runtime_policy[tier_name] = ("EQUIPMENT_STANDARD", False, 200)
    for tier_name in standard_book_tiers:
        expected_runtime_policy[tier_name] = ("BOOK_STANDARD", False, 200)
    for raw_record in runtime["item_overflow_records"]:
        tier_name = str(raw_record.get("tier", ""))
        expected_class, expected_protected, expected_priority = expected_runtime_policy.get(
            tier_name, ("ORDINARY_CONSUMABLE", False, 100)
        )
        require(
            (raw_record.get("overflow_class"), raw_record.get("protected_drop"), raw_record.get("overflow_priority"))
            == (expected_class, expected_protected, expected_priority),
            f"runtime tier overflow policy drift: {tier_name}",
        )
    require(global_scale["active_preset"] == "1x", "global drop scale drift")

    source_contract = runtime["source_slot_contract"]
    expected_gate = {
        "canonical_source_slots": 7032,
        "drop_enabled_source_slots": 5995,
        "drop_disabled_source_slots": 1037,
        "reward_resolved_enabled_slots": 5995,
        "probability_resolved_enabled_slots": 5995,
        "rng_eligible_slots": 5995,
        "rng_roll_count": 5995,
    }
    for key, expected in expected_gate.items():
        require(source_contract.get(key) == expected, f"runtime source gate drift: {key}")
        require(snapshot["summary"].get(key) == expected, f"snapshot source gate drift: {key}")
        require(snapshot["authority"].get("source_slot_gate", {}).get(key) == expected, f"snapshot authority source gate drift: {key}")
    require(
        source_contract["canonical_source_slots"]
        == source_contract["drop_enabled_source_slots"]
        + source_contract["drop_disabled_source_slots"],
        "runtime source gate partition does not close",
    )
    require(
        source_contract["all_enabled_resolved_slots_rng_before_overflow"] is True
        and source_contract["overflow_stage"] == "after_all_probability_rolls",
        "runtime source gate does not prove pre-overflow RNG coverage",
    )
    slots = snapshot.get("slots", [])
    require(len(slots) == 7032, "snapshot slot rows drift")
    observed_gate = {
        "canonical_source_slots": len(slots),
        "drop_enabled_source_slots": sum(bool(row.get("drop_enabled")) for row in slots),
        "drop_disabled_source_slots": sum(not bool(row.get("drop_enabled")) for row in slots),
        "reward_resolved_enabled_slots": sum(bool(row.get("reward_resolved_enabled")) for row in slots),
        "probability_resolved_enabled_slots": sum(bool(row.get("probability_resolved_enabled")) for row in slots),
        "rng_eligible_slots": sum(bool(row.get("rng_eligible")) for row in slots),
        "rng_roll_count": sum(bool(row.get("rng_eligible_before_overflow")) for row in slots),
    }
    require(observed_gate == expected_gate, f"snapshot row gate recomputation drift: {observed_gate}")
    require(snapshot["summary"].get("rng_roll_count") == 5995, "snapshot RNG roll-stage count drift")
    require(snapshot["summary"].get("all_enabled_resolved_slots_rng_before_overflow") is True, "snapshot pre-overflow gate drift")

    catalog_special = catalog.get("special_normal_spawn_authority", {})
    require(
        catalog_special.get("authority_provenance") == expected_special_provenance,
        "catalog special_normal DPV2 provenance drift",
    )
    for monster_id in special_normal.get("scope", {}).get("canonical_monster_ids", []):
        entry = catalog.get("entries_by_id", {}).get(str(monster_id), {})
        spawn = entry.get("spawn_authority", {})
        binding = spawn.get("drop_binding", {})
        require(
            binding.get("authority_provenance") == expected_special_provenance,
            f"catalog monster {monster_id} special_normal provenance drift",
        )
    require(
        [row["preset"] for row in global_scale["presets"]]
        == ["0.5x", "0.8x", "1x", "1.5x", "2x"],
        "global drop presets drift",
    )
    require(
        source_slot_projection_sha256(catalog) == SOURCE_SLOT_PROJECTION_SHA256,
        "7032 source slot projection changed",
    )

    for relative, expected in EXPECTED_FILE_HASHES.items():
        require(sha256(ROOT / relative) == expected, f"protected file changed: {relative}")
    for relative, expected in EXPECTED_TREE_HASHES.items():
        require(git_tree_hash(relative) == expected, f"protected tree changed: {relative}")

    print(
        "DPV2_A07_HUMAN_AUTHORITY_FREEZE_PASS: items=233/233 tiers_unresolved=0 "
        "monsters=156 enabled=131 non_loot=25 role_unresolved=0 veteran=0 "
        "clothes=6x6 cow225=ENDGAME_BOSS@16 slots=7032 source_slots_unchanged=1 "
        "runtime_binding=ACTIVE ground_slots=9 global=1x"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
