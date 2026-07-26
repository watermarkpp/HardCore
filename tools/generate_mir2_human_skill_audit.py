#!/usr/bin/env python3
"""Generate the first-pass, read-only MIR2 human skill system audit.

This tool only reads the current repository and local reference sources.  It
does not change gameplay data, formulas, actions, cooldowns, or visual assets.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import struct
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
DOCS = ROOT / "docs" / "audit"
TEST_LOGS = ROOT / "outputs" / "skill_audit_20260724"

SKILLS_PATH = ROOT / "assets/data/vanilla_176/skills.json"
MAGIC_INFO_PATH = ROOT / "assets/data/vanilla_176/profession_magic_info.json"
GROWTH_PATH = ROOT / "assets/data/vanilla_176/profession_growth.json"
COMBAT_RULES_PATH = ROOT / "assets/data/vanilla_176/profession_combat_rules.json"
VISUALS_PATH = ROOT / "assets/data/caster_skill_visuals.json"
WARRIOR_ICONS_PATH = ROOT / "assets/ui/gothic_hud/v2/runtime/skill_icons/skill_icon_manifest.json"
PARADOX_MAGIC_PATH = (
    ROOT
    / "dev_art_sources/reference/mir2_database_candidates"
    / "mylgd_mir2server_176/Mud2/DB/Magic.DB"
)

AUDIT_DATE = date(2026, 7, 24).isoformat()
AUDIT_ID = "MIR2-HUMAN-SKILL-SYSTEM-AUDIT-V1.0"
CURRENT_RUNTIME = "HardCore offline Godot runtime"

CLASSIFICATIONS = {
    "warrior.basic_swordsmanship": "passive_skill",
    "warrior.slaying_swordsmanship": "warrior_attack_modifier",
    "warrior.thrusting": "warrior_attack_modifier",
    "warrior.half_moon": "warrior_attack_modifier",
    "warrior.wild_rush": "movement_skill",
    "warrior.fire_sword": "warrior_attack_modifier",
    "wizard.fireball": "projectile_spell",
    "wizard.repulsion_ring": "movement_skill",
    "wizard.temptation_light": "special_scripted_skill",
    "wizard.hellfire": "line_spell",
    "wizard.lightning": "instant_target_spell",
    "wizard.teleport": "teleport",
    "wizard.great_fireball": "projectile_spell",
    "wizard.exploding_flame": "area_spell",
    "wizard.fire_wall": "ground_target_spell",
    "wizard.laser": "line_spell",
    "wizard.hell_lightning": "area_spell",
    "wizard.magic_shield": "buff",
    "wizard.holy_word": "instant_target_spell",
    "wizard.ice_storm": "ground_target_spell",
    "taoist.healing": "healing",
    "taoist.spiritual_warfare": "passive_skill",
    "taoist.poison": "debuff",
    "taoist.soul_fire_talisman": "projectile_spell",
    "taoist.summon_skeleton": "summon",
    "taoist.invisibility": "buff",
    "taoist.mass_invisibility": "buff",
    "taoist.magic_defense": "buff",
    "taoist.defense": "buff",
    "taoist.revelation": "instant_target_spell",
    "taoist.entrapment": "debuff",
    "taoist.mass_healing": "healing",
    "taoist.summon_divine_beast": "summon",
}

CAST_TO_SHAPE = {
    "passive": "self",
    "melee": "single_actor",
    "line": "line",
    "area": "circle",
    "dash": "line",
    "projectile": "single_actor",
    "execute": "single_actor",
    "ground_dot": "cross",
    "poison": "single_actor",
    "control": "single_actor",
    "knockback": "around_caster",
    "teleport": "line",
    "heal": "self",
    "heal_area": "around_caster",
    "shield": "self",
    "stealth": "self",
    "stealth_area": "around_caster",
    "magic_defense_buff": "around_caster",
    "defense_buff": "around_caster",
    "summon": "around_caster",
    "inspect": "single_actor",
    "root_area": "around_target",
}

CAST_FILTERS = {
    "passive": "self",
    "melee": "hostile_actor",
    "line": "hostile_actor",
    "area": "hostile_actor",
    "dash": "walkable_direction_and_pushable_actor",
    "projectile": "hostile_actor",
    "execute": "hostile_undead_actor",
    "ground_dot": "hostile_actor_on_effect_cells",
    "poison": "hostile_actor",
    "control": "hostile_non_player_actor",
    "knockback": "hostile_lower_level_actor",
    "teleport": "validated_map_position",
    "heal": "self_in_current_runtime",
    "heal_area": "allied_player_actor",
    "shield": "self",
    "stealth": "self",
    "stealth_area": "allied_player_actor",
    "magic_defense_buff": "allied_player_actor",
    "defense_buff": "allied_player_actor",
    "summon": "self_owner",
    "inspect": "hostile_actor",
    "root_area": "hostile_actor",
}

WARRIOR_SOURCE = {
    "warrior.basic_swordsmanship": ("passive_accuracy", "M2Server/ObjBase.pas RecalcHitSpeed"),
    "warrior.slaying_swordsmanship": ("attack_proc", "M2Server/ObjBase.pas attack path"),
    "warrior.thrusting": ("attack_line_modifier", "M2Server/ObjBase.pas attack path"),
    "warrior.half_moon": ("attack_area_modifier", "M2Server/ObjBase.pas attack path"),
    "warrior.wild_rush": ("movement_attack", "M2Server/ObjBase.pas rush path"),
    "warrior.fire_sword": ("armed_next_attack", "M2Server/ObjBase.pas fire-sword path"),
}

WARRIOR_FORMAL_VISUALS = {
    "warrior.slaying_swordsmanship": "assets/art/characters/warrior/effects/power_hit.png",
    "warrior.thrusting": "assets/art/characters/warrior/effects/long_hit.png",
    "warrior.half_moon": "assets/art/characters/warrior/effects/wide_hit.png",
    "warrior.fire_sword": "assets/art/characters/warrior/effects/fire_hit_d0_f0.png",
}

STATUS_BY_SKILL = {
    "wizard.temptation_light": ("charm", "replace_or_refresh"),
    "wizard.magic_shield": ("magic_shield", "max_duration_and_max_reduction"),
    "taoist.poison": ("green_health_poison_or_red_armor_poison", "current_runtime_health_poison=max_power/max_duration; red requires adapter"),
    "taoist.invisibility": ("stealth", "max_duration"),
    "taoist.mass_invisibility": ("stealth", "max_duration"),
    "taoist.magic_defense": ("magic_defense_buff", "current runtime merges into generic defense_buff"),
    "taoist.defense": ("physical_defense_buff", "current runtime merges into generic defense_buff"),
    "taoist.entrapment": ("root_control", "max_duration"),
    "wizard.repulsion_ring": ("knockback", "instant"),
}

REQUESTED_TESTS = {
    "test_skill_database_import": ["profession_magic_info_test", "profession_skill_id_test"],
    "test_skill_definition_instance_separation": [
        "multi_character_save_test",
        "test_character_full_skill_profiles_test",
        "skill_loadout_rules_test",
    ],
    "test_skill_protocol_roundtrip": [],
    "test_server_authoritative_damage": [],
    "test_mp_consumption": ["wizard_profession_package_test", "taoist_profession_package_test"],
    "test_item_consumption": ["taoist_profession_package_test"],
    "test_cast_range": ["skill_combat_profile_test", "caster_skill_runtime_test"],
    "test_target_filter": ["caster_skill_behavior_test", "caster_skill_runtime_test"],
    "test_damage_formula_golden_cases": ["caster_combat_math_test"],
    "test_heal_formula": ["caster_combat_math_test"],
    "test_status_duration": ["caster_skill_behavior_test"],
    "test_status_stack_policy": [],
    "test_cast_action_binding": ["player_attack_interrupt_consistency_test"],
    "test_effect_resource_binding": ["caster_skill_visual_test"],
    "test_effect_spawn_frame": [],
    "test_cooldown_server_client_sync": [],
    "test_skill_interrupt": ["player_attack_interrupt_consistency_test"],
    "test_skill_proficiency": [],
    "test_skill_persistence": ["multi_character_save_test"],
    "test_no_duplicate_damage": ["player_attack_interrupt_consistency_test"],
    "test_no_unapproved_skill_patches": [],
}

KNOWN_FAILED_RUNS = {
    "caster_full_skill_entry_avatar_independence_test": "Godot child exited without PASS marker",
    "class_combat_test": "Godot child exited without PASS marker",
    "skill_runtime_integration_test": "Godot child exited without PASS marker",
    "warrior_skill_state_machine_test": "Godot child exited without PASS marker",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True, encoding="utf-8").strip()


def dump(name: str, payload: Any) -> None:
    path = REPORTS / name
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_ref(path: str, lines: str, finding: str) -> dict[str, str]:
    return {"path": path, "lines": lines, "finding": finding}


def read_paradox_magic_db() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    payload = PARADOX_MAGIC_PATH.read_bytes()
    record_size = int.from_bytes(payload[0:2], "little")
    header_size = int.from_bytes(payload[2:4], "little")
    record_count = int.from_bytes(payload[6:10], "little")
    field_count = payload[0x21]
    fields = []
    name_cursor = 0x295
    for index in range(field_count):
        name_end = payload.index(0, name_cursor)
        name = payload[name_cursor:name_end].decode("ascii")
        name_cursor = name_end + 1
        fields.append((name, payload[0x78 + 2 * index], payload[0x79 + 2 * index]))
    if sum(size for _, _, size in fields) != record_size:
        raise ValueError("Paradox Magic.DB field sizes do not match record size")

    def decode(raw: bytes, field_type: int) -> Any:
        if field_type == 1:
            return raw.split(b"\0", 1)[0].decode("gbk")
        if field_type not in {3, 4}:
            raise ValueError(f"unsupported Paradox field type {field_type}")
        ordered = bytearray(raw)
        ordered[0] ^= 0x80
        return int.from_bytes(ordered, "big", signed=True)

    rows = []
    block_size = payload[5] * 1024
    for block_start in range(header_size, len(payload), block_size):
        block_rows = int.from_bytes(payload[block_start + 4:block_start + 6], "little") // record_size + 1
        for row_index in range(block_rows):
            record_start = block_start + 6 + row_index * record_size
            raw_record = payload[record_start:record_start + record_size]
            row: dict[str, Any] = {}
            field_cursor = 0
            for name, field_type, size in fields:
                row[name] = decode(raw_record[field_cursor:field_cursor + size], field_type)
                field_cursor += size
            rows.append(row)
    if len(rows) != record_count:
        raise ValueError(f"Paradox Magic.DB expected {record_count} rows, decoded {len(rows)}")
    return rows, {
        "path": str(PARADOX_MAGIC_PATH.relative_to(ROOT)).replace("\\", "/"),
        "sha256": sha256(PARADOX_MAGIC_PATH),
        "record_size": record_size,
        "header_size": header_size,
        "record_count": record_count,
        "field_count": field_count,
        "fields": [{"name": name, "type": field_type, "size": size} for name, field_type, size in fields],
        "classification": "B/C-classic-structure-candidate",
        "warning": "Candidate directory, no import manifest, and includes extended skill MagID 41.",
    }


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)

    skills_payload = read_json(SKILLS_PATH)
    magic_payload = read_json(MAGIC_INFO_PATH)
    growth = read_json(GROWTH_PATH)
    rules = read_json(COMBAT_RULES_PATH)
    visuals = read_json(VISUALS_PATH)
    warrior_icons = read_json(WARRIOR_ICONS_PATH)
    paradox_rows, paradox_source = read_paradox_magic_db()

    level_rows = list(skills_payload["records"])
    base_rows = {row["skill_id"]: row for row in level_rows if int(row["skillLevel"]) == 0}
    magic_rows = {row["skill_id"]: row for row in magic_payload["records"]}
    paradox_by_name = {row["MagName"]: row for row in paradox_rows if int(row["MagID"]) <= 33}
    skill_ids = sorted(base_rows)
    assert len(skill_ids) == 33

    current_commit = git("rev-parse", "HEAD")
    common = {
        "audit_id": AUDIT_ID,
        "audit_date": AUDIT_DATE,
        "git_commit": current_commit,
        "scope": "first read-only execution",
        "runtime": CURRENT_RUNTIME,
    }

    assert set(paradox_by_name) == {base_rows[skill_id]["display_name"] for skill_id in skill_ids}
    schema = build_schema(common, magic_payload, paradox_source)
    catalog = build_catalog(
        common, skill_ids, base_rows, level_rows, magic_rows, paradox_by_name, paradox_source
    )
    instances = build_instances(common, skill_ids, base_rows)
    classifications = build_classification(common, skill_ids, base_rows, growth)
    protocol = build_protocol(common, skill_ids, base_rows, growth, paradox_by_name)
    formulas = build_formulas(common, skill_ids, base_rows, magic_rows, rules)
    targeting = build_targeting(common, skill_ids, base_rows, growth)
    consumption = build_consumption(common, skill_ids, base_rows, magic_rows, rules)
    actions = build_actions(common, skill_ids, base_rows, growth)
    visual_bindings = build_visuals(
        common, skill_ids, base_rows, magic_rows, paradox_by_name, visuals, warrior_icons
    )
    status_effects = build_statuses(common, skill_ids, base_rows, rules)
    cooldowns = build_cooldowns(common, skill_ids, base_rows, magic_rows, growth)
    proficiency = build_proficiency(common, skill_ids, base_rows)
    magic_numbers = build_magic_numbers(common)
    tests = build_test_results(common)
    unresolved = build_unresolved(common, skill_ids, base_rows, visual_bindings, consumption)
    comparison_rows = build_comparison_rows(
        skill_ids, base_rows, classifications, protocol, formulas, targeting,
        consumption, actions, visual_bindings, cooldowns, proficiency
    )

    dump("server_skill_schema.json", schema)
    dump("server_skill_catalog.json", catalog)
    dump("player_skill_instance_audit.json", instances)
    dump("skill_classification.json", classifications)
    dump("skill_protocol_matrix.json", protocol)
    dump("skill_formula_catalog.json", formulas)
    dump("skill_targeting_catalog.json", targeting)
    dump("skill_resource_consumption.json", consumption)
    dump("skill_action_binding.json", actions)
    dump("skill_visual_binding.json", visual_bindings)
    dump("skill_status_effect_catalog.json", status_effects)
    dump("skill_cooldown_audit.json", cooldowns)
    dump("skill_proficiency_audit.json", proficiency)
    dump("skill_magic_number_inventory.json", magic_numbers)
    dump("skill_test_results.json", tests)
    dump("unresolved_skill_bindings.json", unresolved)
    write_comparison_csv(comparison_rows)
    write_markdown_report(
        common, schema, catalog, instances, protocol, formulas, targeting,
        consumption, actions, visual_bindings, status_effects, cooldowns,
        proficiency, magic_numbers, tests, unresolved, comparison_rows
    )
    print(f"SKILL_AUDIT_REPORTS_GENERATED=18 skills={len(skill_ids)} commit={current_commit[:12]}")


def build_schema(
    common: dict[str, Any],
    magic_payload: dict[str, Any],
    paradox_source: dict[str, Any],
) -> dict[str, Any]:
    return {
        **common,
        "verdict": "candidate_schema_not_classic_magic_db",
        "current_primary_candidate": magic_payload["source"],
        "reader_contract": magic_payload["reader_contract"],
        "classic_structure_candidate": {
            **paradox_source,
            "match_result": "33/33 project skills match uniquely by display_name == MagName; extra record MagID 41 is excluded",
            "selection_status": "not selected as authenticated user current table",
        },
        "classic_expected_source": {
            "type": "BDE/DBF Magic.DB",
            "status": "not present in the current evidence set",
            "reader": "dev_art_sources/reference/original_gameofmir/M2Server/LocalDB.pas",
            "expected_fields": [
                "MagicId", "MagicName", "EffectType", "Effect", "Spell",
                "Power", "MaxPower", "Job", "NeedL1", "NeedL2", "NeedL3",
                "L1Train", "L2Train", "L3Train", "Delay", "DefSpell",
                "DefPower", "DefMaxPower", "Descr",
            ],
        },
        "current_crystal_candidate_fields": {
            "binary_layout": "ReadString + 7B + 3H + 2I + 4H + B + 2f",
            "decoded_fields": [
                "Name", "Spell", "BaseManaCost", "LevelManaCost", "Icon",
                "Level1", "Level2", "Level3", "Need1", "Need2", "Need3",
                "DelayBase", "DelayReduction", "PowerBase", "PowerBonus",
                "MagicPowerBase", "MagicPowerBonus", "RangeCells",
                "MultiplierBase", "MultiplierBonus",
            ],
            "not_field_equivalent_to_classic": [
                "EffectType", "Effect", "Power/MaxPower", "DefSpell",
                "DefPower/DefMaxPower", "Job", "Descr",
            ],
        },
        "errors": [
            {
                "classification": "SKILL_DATABASE_ERROR",
                "severity": "critical",
                "finding": "The 33 current records are extracted from Crystal Server.MirDB version 105, not from the classic Magic.DB consumed by the audited Magic.pas/LocalDB.pas server.",
            },
            {
                "classification": "MISSING_SOURCE_EVIDENCE",
                "severity": "critical",
                "finding": "No authenticated user import manifest or same-distribution database + server code + client code tuple proves all classic fields and semantics end to end. A complete Paradox candidate exists but is not version-certified.",
            },
        ],
    }


def build_catalog(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    level_rows: list[dict[str, Any]],
    magic_rows: dict[str, Any],
    paradox_by_name: dict[str, Any],
    paradox_source: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        base = base_rows[skill_id]
        magic = magic_rows[skill_id]
        classic = paradox_by_name[base["display_name"]]
        levels = sorted(
            (row for row in level_rows if row["skill_id"] == skill_id),
            key=lambda row: int(row["skillLevel"]),
        )
        records.append({
            "skill_id": classic["MagID"],
            "stable_skill_id": skill_id,
            "name": base["display_name"],
            "job": classic["Job"],
            "effect_type": classic["EffectType"],
            "effect": classic["Effect"],
            "spell": classic["Spell"],
            "power": classic["Power"],
            "max_power": classic["MaxPower"],
            "def_spell": classic["DefSpell"],
            "def_power": classic["DefPower"],
            "def_max_power": classic["DefMaxPower"],
            "delay": classic["Delay"],
            "train_levels": [classic["NeedL1"], classic["NeedL2"], classic["NeedL3"]],
            "max_train": [classic["L1Train"], classic["L2Train"], classic["L3Train"]],
            "description": classic["Descr"],
            "classic_extended_levels": [
                {
                    "level": level,
                    "need_character_level": classic[f"NeedL{level}"],
                    "max_train": classic[f"L{level}Train"],
                }
                for level in range(4, 16)
            ],
            "project_level_rows": [
                {
                    "level": int(row["skillLevel"]),
                    "required_character_level": row["requiredCharacterLevel"],
                    "training_points": row["trainingPoints"],
                    "mana_cost": row["manaCost"],
                    "delay": row["delay"],
                }
                for row in levels
            ],
            "source": {
                "classification": paradox_source["classification"],
                "database": "mylgd Paradox Magic.DB",
                "database_path": paradox_source["path"],
                "database_sha256": paradox_source["sha256"],
                "record_semantics": "Complete classic field structure candidate; not authenticated as user's current table or same build as audited source code.",
                "project_static_source": "assets/data/vanilla_176/skills.json",
            },
            "current_runtime_crystal_candidate": {
                "classification": magic["classification"],
                "database": "Server.MirDB",
                "database_sha256": magic_payload_hash(),
                "spell": magic["service_spell_id"],
                "base_mana_cost": magic["base_mana_cost"],
                "level_mana_cost": magic["level_mana_cost"],
                "icon": magic["icon"],
                "power_base": magic["power_base"],
                "power_bonus": magic["power_bonus"],
                "magic_power_base": magic["magic_power_base"],
                "magic_power_bonus": magic["magic_power_bonus"],
                "range_cells": magic["range_cells"],
                "cooldown_ms_by_level": magic["cooldown_ms_by_level"],
                "warning": "Crystal Spell is not classic MagID and fields must not be silently merged.",
            },
            "errors": ["MISSING_SOURCE_EVIDENCE", "SKILL_DATABASE_ERROR"],
        })
    return {
        **common,
        "record_count": len(records),
        "provenance_verdict": "33_complete_classic_structure_candidates_plus_33_current_Crystal_runtime_candidates_but_no_authenticated_user_current_table",
        "selection_rule": "Top-level classic fields come from the Paradox candidate and are never silently merged with Crystal values; current runtime candidates are nested separately.",
        "records": records,
    }


def magic_payload_hash() -> str:
    return sha256(
        ROOT / "dev_art_sources/reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa/Server.MirDB"
    )


def build_instances(
    common: dict[str, Any], skill_ids: list[str], base_rows: dict[str, Any]
) -> dict[str, Any]:
    return {
        **common,
        "verdict": "partially_separated_but_incomplete",
        "static_definition": "assets/data/vanilla_176/skills.json, profession_growth.json, profession_combat_rules.json",
        "player_instance": {
            "representation": "PlayerState.learned_skills Dictionary keyed by Chinese display name with integer level value",
            "per_character_persistence": True,
            "saved_fields": ["learned level", "quick slots", "warrior toggles", "fire-sword remaining cooldown"],
            "missing_fields": [
                "proficiency/experience", "general enabled state", "general current cooldown",
                "last cast sequence/idempotency token", "buff/debuff persistence",
            ],
            "evidence": [
                source_ref("scripts/player_state.gd", "46-48", "instance dictionaries"),
                source_ref("scripts/player_state.gd", "906-971", "save/load learned_skills and quick_slots"),
                source_ref("scripts/player_state.gd", "1025-1051", "warrior-only runtime state"),
            ],
        },
        "records": [
            {
                "skill_id": skill_id,
                "name": base_rows[skill_id]["display_name"],
                "definition_key": skill_id,
                "instance_key": base_rows[skill_id]["display_name"],
                "level_saved": True,
                "proficiency_saved": False,
                "quick_slot_saved": True,
                "enabled_saved": skill_id in {
                    "warrior.thrusting", "warrior.half_moon", "warrior.fire_sword"
                },
                "cooldown_saved": skill_id == "warrior.fire_sword",
                "errors": ["PROFICIENCY_ERROR"] + (
                    ["SKILL_INSTANCE_ERROR"] if skill_id not in {
                        "warrior.thrusting", "warrior.half_moon", "warrior.fire_sword"
                    } else []
                ),
            }
            for skill_id in skill_ids
        ],
    }


def build_classification(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    growth: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        profile = growth["skillProfiles"][name]
        records.append({
            "skill_id": skill_id,
            "name": name,
            "profession_id": base_rows[skill_id]["profession_id"],
            "audit_classification": CLASSIFICATIONS[skill_id],
            "current_cast_type": profile["cast_type"],
            "current_runtime_path": (
                "PlayerCharacter.request_attack/_build_warrior_attack_context"
                if skill_id.startswith("warrior.") and skill_id != "warrior.wild_rush"
                else "PlayerCharacter.request_skill -> game_root._on_player_skill legacy Chinese-name/local dispatch"
                if not skill_id.startswith("warrior.")
                else "PlayerCharacter.request_skill movement branch"
            ),
            "classification_status": "correct_family" if (
                not skill_id.startswith("warrior.") or skill_id in WARRIOR_SOURCE
            ) else "review",
        })
    return {**common, "records": records, "counts": dict(Counter(r["audit_classification"] for r in records))}


def resolved_profile(growth: dict[str, Any], name: str) -> dict[str, Any]:
    profile = dict(growth["skillProfiles"][name])
    defaults = growth["castDefaults"].get(profile["cast_type"], {})
    for key, value in defaults.items():
        profile.setdefault(key, value)
    profile.update(growth.get("skillTimingOverrides", {}).get(name, {}))
    return profile


def build_protocol(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    growth: dict[str, Any],
    paradox_by_name: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        profile = resolved_profile(growth, name)
        classic = paradox_by_name[name]
        records.append({
            "skill_id": skill_id,
            "name": name,
            "transport": "in_process_signal_no_network_protocol",
            "client_request_message": "PlayerCharacter.request_skill(String display_name)",
            "request_skill_identifier": "Chinese display-name String",
            "target_actor": "local Node reference selected in game_root/caster runtime",
            "target_coordinates": "local Godot Vector2 world coordinates",
            "direction": "local normalized Vector2",
            "skill_level": "read locally from PlayerState; no server verification",
            "server_response_message": None,
            "damage_or_status_message": "player.skill_requested signal -> game_root direct local method call",
            "client_effect_message": "game_root direct local projectile/ground/summon node spawn",
            "failure_message": "boolean false or failure_reason Dictionary; no protocol packet",
            "id_width_or_truncation": "not applicable to current String-based local call",
            "duplicate_prevention": "local pending action_id only; no network idempotency token",
            "target_mode": profile.get("target_mode"),
            "classic_reference_protocol": {
                "client_request": "CM_SPELL=3017",
                "magic_id": classic["MagID"],
                "magic_id_encoding": "TDefaultMessage.Tag Word (16-bit)",
                "target_coordinates": "Recog=MakeLong(x,y), each coordinate 16-bit",
                "target_actor": "Param=LowWord(actor), Series=HiWord(actor), combined 32-bit",
                "direction": "server derives from coordinates; EffectType=0 warrior path overloads target-x as direction",
                "client_skill_level": "not sent; server resolves TUserMagic",
                "server_cast_response": "SM_SPELL=17",
                "effect_response": "SM_MAGICFIRE=638 or SM_MAGICFIREFAIL=639",
                "damage_response": "SM_STRUCK=31",
                "effect_type": classic["EffectType"],
                "effect": classic["Effect"],
                "replay_protection": "queue replaces older CM_SPELL plus server cast interval; no nonce/request id",
            },
            "errors": ["SKILL_PROTOCOL_ERROR", "SERVER_AUTHORITY_ERROR"],
        })
    return {
        **common,
        "verdict": "no_client_server_skill_protocol_in_current_runtime",
        "classic_reference_verdict": "classic protocol is server-authoritative but uses 16-bit skill/coordinate fields and has interval-and-queue replay suppression only",
        "classic_reference_evidence": [
            source_ref("dev_art_sources/reference/original_gameofmir/Common/Grobal2.pas", "175-206,497-504", "message IDs and TDefaultMessage widths"),
            source_ref("dev_art_sources/reference/original_gameofmir/MirClient/ClMain.pas", "3586-3594", "CM_SPELL request packing"),
            source_ref("dev_art_sources/reference/original_gameofmir/M2Server/UsrEngn.pas", "1646-1669", "server request decode"),
            source_ref("dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas", "4565-4581", "delayed server hit and damage"),
        ],
        "records": records,
        "evidence": [
            source_ref("scripts/player.gd", "237-266", "local request and pre-cast MP deduction"),
            source_ref("scripts/player.gd", "327-341", "local delayed signal commit"),
            source_ref("scripts/game_root.gd", "1455-1527", "active legacy local dispatch and direct result application"),
            source_ref("assets/data/profession_integration_requirements.json", "19-45", "stable-ID caster runtime and formula dispatch are still integration requirements"),
        ],
    }


def rule_for(skill_id: str, rules: dict[str, Any]) -> dict[str, Any]:
    profession = "wizard" if skill_id.startswith("wizard.") else "taoist"
    return rules.get(profession, {}).get("skills", {}).get(skill_id, {})


def build_formulas(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    magic_rows: dict[str, Any],
    rules: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        magic = magic_rows[skill_id]
        if skill_id in WARRIOR_SOURCE:
            formula_group, source_anchor = WARRIOR_SOURCE[skill_id]
            current_formula = {
                "warrior.basic_swordsmanship": "accuracy_bonus = 3 * skill_level",
                "warrior.slaying_swordsmanship": "attack proc cycle and added DC damage in WarriorCombatMath",
                "warrior.thrusting": "base attack plus second-cell modifier in warrior attack context",
                "warrior.half_moon": "base attack plus directional area modifier",
                "warrior.wild_rush": "movement/push success; damage adapter is project-local",
                "warrior.fire_sword": "base attack plus level-scaled fire modifier",
            }[skill_id]
            status = "classic_source_reconstruction_with_project_adapter"
        else:
            rule = rule_for(skill_id, rules)
            formula_group = rule.get("formula_group", "missing")
            source_anchor = rule.get("source_anchor", "")
            current_formula = (
                rules["formulaContracts"]["healing"]
                if formula_group == "classic_healing"
                else rules["formulaContracts"]["magic_damage"]
                if formula_group == "classic_magic_damage"
                else "special formula fields in profession_combat_rules.json"
            )
            status = rule.get("source_status", "missing")
        records.append({
            "skill_id": skill_id,
            "name": base_rows[skill_id]["display_name"],
            "formula_group": formula_group,
            "source_formula": current_formula,
            "source_anchor": source_anchor,
            "input_attributes": (
                ["DC range", "accuracy", "luck", "target agility/defense"]
                if skill_id.startswith("warrior.")
                else ["MC roll", "skill power roll", "target defense/resistance"]
                if skill_id.startswith("wizard.")
                else ["SC roll", "skill power roll", "target defense/resistance"]
            ),
            "random_interval": "runtime roll path exists; deterministic compatibility helpers use candidate lower bounds",
            "skill_level_coefficient": "level clamped to 0..3",
            "target_resistance": "partly applied by target.take_damage; not represented in a server protocol",
            "rounding": rules["formulaContracts"]["rounding"],
            "lower_bound": 1 if formula_group in {"classic_magic_damage", "classic_healing"} else None,
            "upper_bound": None,
            "candidate_values": {
                "power_base": magic["power_base"],
                "power_bonus": magic["power_bonus"],
                "magic_power_base": magic["magic_power_base"],
                "magic_power_bonus": magic["magic_power_bonus"],
                "multiplier_base": magic["multiplier_base"],
                "multiplier_bonus": magic["multiplier_bonus"],
            },
            "source_status": status,
            "active_runtime_formula": (
                "WarriorCombatMath attack-path formula"
                if skill_id.startswith("warrior.")
                else "generic locally rolled profession stat damage multiplied by profession_growth multiplier"
            ),
            "source_formula_integrated_in_active_runtime": skill_id.startswith("warrior."),
            "errors": ["MISSING_SOURCE_EVIDENCE"] + (
                ["FORMULA_ERROR"] if (
                    not skill_id.startswith("warrior.") or skill_id == "warrior.wild_rush"
                ) else []
            ),
        })
    return {
        **common,
        "verdict": "server_source_reconstruction_is_not_same_distribution_as_candidate_database_and_caster_formula_package_is_not_in_active_game_path",
        "formula_contracts": rules["formulaContracts"],
        "records": records,
    }


def build_targeting(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    growth: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        profile = resolved_profile(growth, name)
        cast_type = profile["cast_type"]
        records.append({
            "skill_id": skill_id,
            "name": name,
            "target_mode": profile.get("target_mode"),
            "target_filter": CAST_FILTERS.get(cast_type, "unresolved"),
            "range_shape": CAST_TO_SHAPE.get(cast_type, "unresolved"),
            "cast_range": profile.get("range", 0.0),
            "effect_range": profile.get("area_radius", 0.0),
            "line_of_sight": "not explicitly modeled in the common skill profile",
            "friendly_fire": "not explicitly modeled",
            "max_targets": "not explicitly bounded; context array driven",
            "target_sort_policy": "not explicitly modeled",
            "coordinate_system": "Godot local world pixels, not MIR2 map-cell protocol coordinates",
            "errors": ["TARGETING_ERROR", "RANGE_ERROR"],
        })
    return {**common, "verdict": "basic_shapes_exist_but_legality_contract_is_incomplete", "records": records}


def build_consumption(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    magic_rows: dict[str, Any],
    rules: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        magic = magic_rows[skill_id]
        rule = rule_for(skill_id, rules)
        amulet_cost = int(rule.get("amulet_cost", 0))
        if skill_id == "taoist.poison":
            item_requirement = "poison item/amulet shape required by classic source"
        elif amulet_cost:
            item_requirement = f"amulet x{amulet_cost}"
        else:
            item_requirement = None
        records.append({
            "skill_id": skill_id,
            "name": base_rows[skill_id]["display_name"],
            "base_mp": magic["base_mana_cost"],
            "level_mp_delta": magic["level_mana_cost"],
            "mp_by_level": magic["mana_cost_by_level"],
            "continuous_cost": None,
            "item_requirement": item_requirement,
            "item_consumption_runtime": "candidate_package_only_not_removed_by_active_game_path" if item_requirement else "not_required_or_not_modeled",
            "weapon_durability": "1/30 random on request_skill, independent of success",
            "summon_limit": rule.get("default_count") if skill_id.startswith("taoist.summon_") else None,
            "failed_cast_mp_policy": "MP is deducted before downstream plan/target/special success validation",
            "interrupted_cast_refund": "no refund path",
            "errors": (
                ["RESOURCE_CONSUMPTION_ERROR"] if item_requirement else []
            ) + ["CAST_VALIDATION_ERROR"],
        })
    return {
        **common,
        "verdict": "mp_is_candidate_based_and_item_consumption_is_not_enforced",
        "records": records,
        "evidence": [
            source_ref("scripts/player.gd", "237-266", "MP deducted before local skill dispatch"),
            source_ref("scripts/game_root.gd", "1455-1527", "active legacy dispatch does not validate or remove skill materials"),
            source_ref("scripts/caster_profession_package.gd", "210-319", "candidate package has validate-before-consume material logic but is not integrated"),
        ],
    }


def build_actions(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    growth: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        profile = resolved_profile(growth, name)
        warrior = skill_id.startswith("warrior.")
        records.append({
            "skill_id": skill_id,
            "name": name,
            "cast_action": name if warrior else "cast",
            "attack_action": name if warrior else None,
            "ready_action": "fire_sword_auto_toggle" if skill_id == "warrior.fire_sword" else None,
            "release_frame": profile.get("hit_frame"),
            "effect_spawn_frame": None,
            "runtime_release_seconds": profile.get("windup"),
            "recovery_action": "shared PlayerVisual returns to idle",
            "unified_character_action_system": True,
            "active_caster_action_resolution": "PlayerVisual uses the shared cast action key and the integration branch has formal cast textures; release timing is still windup-based",
            "direct_sprite_frame_mutation_by_skill_runtime": False,
            "timing_status": "windup timer drives commit; hit_frame is metadata and is not the scheduling authority",
            "interrupt_status": "pending action commits once; struck reaction queues after current action",
            "errors": ["EVENT_TIMING_ERROR"],
        })
    return {
        **common,
        "verdict": "unified_visual_action_is_used_but_frame_binding_is_not_proven",
        "records": records,
    }


def build_visuals(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    magic_rows: dict[str, Any],
    paradox_by_name: dict[str, Any],
    visuals: dict[str, Any],
    warrior_icons: dict[str, Any],
) -> dict[str, Any]:
    icon_by_name = {entry["skillName"]: entry for entry in warrior_icons["icons"]}
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        candidate_icon = magic_rows[skill_id]["icon"]
        classic_effect = int(paradox_by_name[name]["Effect"])
        coverage = visuals.get("skillCoverage", {}).get(skill_id, {})
        asset = visuals.get("assets", {}).get(coverage.get("asset_id", ""), {})
        warrior_icon = icon_by_name.get(name)
        warrior_visual = WARRIOR_FORMAL_VISUALS.get(skill_id)
        role = asset.get("role")
        source_library = asset.get("original_path")
        source_index = asset.get("source_index")
        if role == "projectile":
            cast_library, flight_library = None, source_library
            cast_start, flight_start = None, source_index
        else:
            cast_library, flight_library = source_library, None
            cast_start, flight_start = source_index, None
        icon_status = (
            "runtime_effect_crop_not_MagIcon" if warrior_icon
            else "candidate_MagIcon_pair_valid_but_not_bound_to_runtime"
        )
        visual_status = coverage.get("status")
        if not visual_status:
            if warrior_visual:
                visual_status = "formal_primary_client_warrior_action_effect"
            elif skill_id == "warrior.basic_swordsmanship":
                visual_status = "no_runtime_visual_passive"
            elif skill_id == "warrior.wild_rush":
                visual_status = "missing_formal_skill_effect"
            else:
                visual_status = "missing_catalog_entry"
        records.append({
            "skill_id": skill_id,
            "name": name,
            "icon_library": "Data/MagIcon.wil",
            "classic_effect_candidate": classic_effect,
            "icon_index": classic_effect * 2,
            "icon_pressed_index": classic_effect * 2 + 1,
            "icon_mapping_rule": "original client draws Effect*2 and Effect*2+1",
            "crystal_icon_candidate": candidate_icon,
            "icon_library_image_count": 72,
            "icon_library_sha256": "22109b4327adbef871eb0008e4fff928d60020c400b43441a7522abf33656a02",
            "icon_pair_in_bounds": classic_effect * 2 + 1 < 72,
            "icon_binding_status": icon_status,
            "runtime_icon_path": warrior_icon.get("output") if warrior_icon else None,
            "warrior_action_effect_path": warrior_visual,
            "cast_effect_library": cast_library,
            "cast_effect_start": cast_start,
            "flight_effect_library": flight_library,
            "flight_effect_start": flight_start,
            "impact_effect_library": None,
            "impact_effect_start": None,
            "direction_count": None,
            "frame_count": None,
            "frame_time": None,
            "blend_mode": "current Godot default/visual-effect code; not catalogued per skill",
            "draw_layer": "runtime node type dependent; not catalogued per skill",
            "anchor": asset.get("source_draw_offset"),
            "visual_status": visual_status,
            "mapping_rule": asset.get("mapping_rule"),
            "mapping_confidence": asset.get("mapping_confidence"),
            "effect_type_verified": bool(asset.get("mapping_rule")),
            "active_runtime_passes_stable_source_skill_id": False if not skill_id.startswith("warrior.") else None,
            "active_runtime_inference": (
                "projectile/ground/summon nodes infer a profession-wide or display-name skill ID"
                if not skill_id.startswith("warrior.") else "warrior action path"
            ),
            "errors": ["EFFECT_BINDING_ERROR"] + (
                ["MISSING_SOURCE_EVIDENCE"] if not asset else []
            ),
        })
    return {
        **common,
        "verdict": "all_33_candidate_MagIcon_pairs_are_in_bounds_but_not_consumed_by_runtime; 30_have_formal_static_visual_bindings_while_active_game_path_only_uses_9_correct_effect_families",
        "counts": {
            "skills": 33,
            "formal_primary_client_caster_visuals": sum(
                r["visual_status"] == "formal_primary_client_pixel" for r in records
            ),
            "formal_primary_client_warrior_visuals": sum(
                r["visual_status"] == "formal_primary_client_warrior_action_effect" for r in records
            ),
            "formal_static_visual_bindings_total": 30,
            "passive_no_cast_visual": 2,
            "missing_formal_visual": 1,
            "active_runtime_correct_effect_family": 9,
            "active_runtime_wrong_effect_family": 4,
            "active_runtime_missing_formal_effect": 18,
            "active_runtime_passive_no_effect": 2,
            "runtime_icons_from_effect_crops": sum(r["icon_binding_status"] == "runtime_effect_crop_not_MagIcon" for r in records),
            "runtime_MagIcon_bindings_verified": 0,
            "candidate_MagIcon_pairs_in_bounds": sum(r["icon_pair_in_bounds"] for r in records),
        },
        "source_policy": visuals.get("sourcePolicy"),
        "mapping_sources": visuals.get("mappingSources"),
        "records": records,
    }


def build_statuses(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    rules: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id, (status_id, stack_policy) in STATUS_BY_SKILL.items():
        rule = rule_for(skill_id, rules)
        records.append({
            "status_id": status_id,
            "source_skill": skill_id,
            "source_skill_name": base_rows[skill_id]["display_name"],
            "duration": rule.get("duration_formula", "runtime plan value"),
            "stack_policy": stack_policy,
            "refresh_policy": "max/current runtime method dependent",
            "tick_interval": rule.get("green_damage_interval_ms") or rule.get("tick_interval_ms"),
            "max_stack": 1,
            "dispel_policy": "not modeled",
            "attribute_modifier": rule.get("buff_power_formula") or rule.get("red_armor_rate_tenths"),
            "visual_effect": skill_id,
            "server_authority": False,
            "persistence_policy": "not saved; runtime timers",
            "active_runtime_duration": {
                "wizard.magic_shield": "12 seconds hard-coded",
                "taoist.poison": "8 seconds hard-coded",
                "taoist.invisibility": "10 seconds hard-coded",
                "taoist.mass_invisibility": "10 seconds hard-coded",
                "taoist.magic_defense": "15 seconds hard-coded",
                "taoist.defense": "15 seconds hard-coded",
                "taoist.entrapment": "5 seconds hard-coded",
                "wizard.temptation_light": "6 seconds hard-coded",
            }.get(skill_id, "instant/local runtime"),
            "death_policy": "not explicitly centralized per status",
            "map_change_policy": "not explicitly catalogued",
            "errors": ["STATUS_EFFECT_ERROR", "SERVER_AUTHORITY_ERROR", "PERSISTENCE_ERROR"],
        })
    return {
        **common,
        "verdict": "local_timer_states_exist_but_no_authoritative_status_contract",
        "records": records,
        "notable_collision": "magic defense and physical defense both call PlayerCharacter.apply_defense_buff and share defense_buff_time/defense_buff; formula-backed status dispatcher is not integrated",
    }


def build_cooldowns(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    magic_rows: dict[str, Any],
    growth: dict[str, Any],
) -> dict[str, Any]:
    records = []
    for skill_id in skill_ids:
        name = base_rows[skill_id]["display_name"]
        profile = resolved_profile(growth, name)
        magic = magic_rows[skill_id]
        runtime = float(profile.get("cooldown", 0.0))
        server_candidate = [value / 1000.0 for value in magic["cooldown_ms_by_level"]]
        records.append({
            "skill_id": skill_id,
            "name": name,
            "server_delay_candidate_seconds": server_candidate,
            "runtime_skill_cooldown_seconds": runtime,
            "public_cast_interval": "PlayerCharacter._attack_timer",
            "attack_interval": "attack_cooldown / attack_speed",
            "animation_recovery": profile.get("action_duration", runtime),
            "button_cooldown_display": "no general authoritative cooldown state",
            "persisted": skill_id == "warrior.fire_sword",
            "matches_server_candidate": all(abs(runtime - value) < 0.0001 for value in server_candidate),
            "errors": ["COOLDOWN_ERROR"] if not all(
                abs(runtime - value) < 0.0001 for value in server_candidate
            ) else [],
        })
    return {
        **common,
        "verdict": "runtime_animation_style_cooldowns_do_not_match_candidate_server_delay_for_most_skills",
        "records": records,
        "mismatch_count": sum(not record["matches_server_candidate"] for record in records),
    }


def build_proficiency(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
) -> dict[str, Any]:
    return {
        **common,
        "verdict": "missing",
        "records": [
            {
                "skill_id": skill_id,
                "name": base_rows[skill_id]["display_name"],
                "learning_level": "static level rows exist",
                "current_skill_level": "integer saved per character",
                "proficiency": None,
                "upgrade_threshold": "static trainingPoints exists but runtime does not consume it",
                "max_level": 3,
                "increase_condition": None,
                "failed_cast_increases": False,
                "hit_only_or_cast": "not implemented",
                "upgrade_message": None,
                "persistence": "level only",
                "errors": ["PROFICIENCY_ERROR", "PERSISTENCE_ERROR"],
            }
            for skill_id in skill_ids
        ],
    }


def build_magic_numbers(common: dict[str, Any]) -> dict[str, Any]:
    terms = [
        "skill_damage", "magic_damage", "spell_delay", "effect_offset",
        "magic_offset", "cast_frame", "hit_frame", "skill_id",
        "effect_id", "special_skill",
    ]
    tracked = git("ls-files").splitlines()
    allowed_prefixes = ("scripts/", "assets/data/", "assets/ui/", "tools/", "tests/")
    allowed_suffixes = {".gd", ".json", ".py", ".cs", ".pas", ".md"}
    inventory = []
    for rel in tracked:
        normalized = rel.replace("\\", "/")
        path = ROOT / rel
        if not normalized.startswith(allowed_prefixes) or path.suffix.lower() not in allowed_suffixes:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            lower = line.lower()
            for term in terms:
                if term in lower:
                    inventory.append({
                        "path": normalized,
                        "line": line_number,
                        "term": term,
                        "snippet": line.strip()[:240],
                        "classification": "MAGIC_PATCH" if any(
                            token in lower for token in ("override", "special", "compat", "candidate")
                        ) else "REVIEW_REQUIRED",
                    })
    name_branches = []
    patterns = [
        re.compile(r'\bif\s+.*skill_name'),
        re.compile(r'\bmatch\s+skill_name'),
        re.compile(r'\bif\s+.*magic_name'),
        re.compile(r'\bmatch\s+magic_name'),
    ]
    for item in inventory:
        snippet = item["snippet"].lower()
        if any(pattern.search(snippet) for pattern in patterns):
            name_branches.append(item)
    return {
        **common,
        "search_terms": terms + ["if skill_name", "if magic_name"],
        "occurrence_count": len(inventory),
        "name_branch_count": len(name_branches),
        "name_branches": name_branches,
        "inventory": inventory,
    }


def test_marker(name: str) -> tuple[str, str | None]:
    candidates = sorted(TEST_LOGS.glob(f"{name}*.stdout.log"), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in candidates:
        raw = path.read_bytes()
        if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
            text = raw.decode("utf-16", errors="replace")
        else:
            text = raw.decode("utf-8", errors="replace")
        match = re.search(r"([A-Z0-9_]+_PASS[^\r\n]*)", text)
        if match:
            return "pass", match.group(1)
    if name in KNOWN_FAILED_RUNS:
        return "fail", KNOWN_FAILED_RUNS[name]
    return "not_run", None


def build_test_results(common: dict[str, Any]) -> dict[str, Any]:
    executed_names = sorted({
        equivalent for equivalents in REQUESTED_TESTS.values() for equivalent in equivalents
    } | set(KNOWN_FAILED_RUNS))
    executed = []
    for name in executed_names:
        status, detail = test_marker(name)
        executed.append({
            "test": name,
            "scene": f"tests/{name}.tscn",
            "status": status,
            "detail": detail,
            "log_directory": str(TEST_LOGS.relative_to(ROOT)).replace("\\", "/"),
        })
    requested = []
    executed_by_name = {row["test"]: row for row in executed}
    for requested_name, equivalents in REQUESTED_TESTS.items():
        statuses = [executed_by_name[name]["status"] for name in equivalents]
        if not equivalents:
            status = "missing_existing_test"
        elif all(value == "pass" for value in statuses):
            status = "covered_by_existing_tests"
        elif any(value == "fail" for value in statuses):
            status = "existing_equivalent_failed"
        else:
            status = "not_fully_executed"
        requested.append({
            "requested_test": requested_name,
            "status": status,
            "existing_equivalents": equivalents,
        })
    counts = Counter(row["status"] for row in executed)
    return {
        **common,
        "command_pattern": "tools/godot-4.7/Godot_v4.7-stable_win64_console.exe --headless --log-file <new audit log> --path . <scene>",
        "executed": executed,
        "executed_counts": dict(counts),
        "requested_coverage": requested,
        "conclusion": "Passing local tests do not establish a client/server protocol or server authority.",
    }


def build_unresolved(
    common: dict[str, Any],
    skill_ids: list[str],
    base_rows: dict[str, Any],
    visuals: dict[str, Any],
    consumption: dict[str, Any],
) -> dict[str, Any]:
    visual_by_id = {row["skill_id"]: row for row in visuals["records"]}
    consumption_by_id = {row["skill_id"]: row for row in consumption["records"]}
    records = []
    for skill_id in skill_ids:
        issues = [
            "same-distribution classic Magic.DB record is missing",
            "no current client/server request-response protocol",
            "no server-authoritative hit/damage boundary",
            "no proficiency state or training path",
            "MagIcon runtime binding is not verified",
        ]
        if consumption_by_id[skill_id]["item_requirement"]:
            issues.append("required item/amulet is metadata-only and is not consumed")
        if visual_by_id[skill_id]["visual_status"] not in {
            "formal_primary_client_pixel", "no_runtime_visual"
        }:
            issues.append("formal per-skill visual binding is absent")
        records.append({
            "skill_id": skill_id,
            "name": base_rows[skill_id]["display_name"],
            "issues": issues,
            "error_classes": sorted({
                "MISSING_SOURCE_EVIDENCE", "SKILL_PROTOCOL_ERROR",
                "SERVER_AUTHORITY_ERROR", "PROFICIENCY_ERROR",
                "EFFECT_BINDING_ERROR",
            } | ({"RESOURCE_CONSUMPTION_ERROR"} if consumption_by_id[skill_id]["item_requirement"] else set())),
        })
    return {**common, "unresolved_skill_count": len(records), "records": records}


def build_comparison_rows(
    skill_ids: list[str],
    base_rows: dict[str, Any],
    classifications: dict[str, Any],
    protocol: dict[str, Any],
    formulas: dict[str, Any],
    targeting: dict[str, Any],
    consumption: dict[str, Any],
    actions: dict[str, Any],
    visuals: dict[str, Any],
    cooldowns: dict[str, Any],
    proficiency: dict[str, Any],
) -> list[dict[str, Any]]:
    def index(payload: dict[str, Any]) -> dict[str, Any]:
        return {row["skill_id"]: row for row in payload["records"]}
    c, p, f, t = map(index, (classifications, protocol, formulas, targeting))
    r, a, v, cd, pr = map(index, (consumption, actions, visuals, cooldowns, proficiency))
    rows = []
    for skill_id in skill_ids:
        passive = c[skill_id]["audit_classification"] == "passive_skill"
        disposition = (
            "retain_definition_repair_instance"
            if passive else "retain_definition_rebuild_shared_authority_path"
        )
        rows.append({
            "skill_id": skill_id,
            "name": base_rows[skill_id]["display_name"],
            "profession": base_rows[skill_id]["profession_id"],
            "classification": c[skill_id]["audit_classification"],
            "database_source": "Crystal Server.MirDB B/C candidate",
            "instance_separation": "partial",
            "protocol": p[skill_id]["transport"],
            "server_authority": "absent",
            "formula": f[skill_id]["source_status"],
            "targeting": "incomplete_contract",
            "mp": "candidate_applied_before_validation",
            "item_consumption": r[skill_id]["item_consumption_runtime"],
            "action_binding": "shared_action_system_timing_unproven",
            "visual": v[skill_id]["visual_status"],
            "icon": v[skill_id]["icon_binding_status"],
            "cooldown_match": cd[skill_id]["matches_server_candidate"],
            "proficiency": pr[skill_id]["proficiency"],
            "disposition": disposition,
        })
    return rows


def write_comparison_csv(rows: list[dict[str, Any]]) -> None:
    path = REPORTS / "skill_comparison_matrix.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_markdown_report(
    common: dict[str, Any],
    schema: dict[str, Any],
    catalog: dict[str, Any],
    instances: dict[str, Any],
    protocol: dict[str, Any],
    formulas: dict[str, Any],
    targeting: dict[str, Any],
    consumption: dict[str, Any],
    actions: dict[str, Any],
    visuals: dict[str, Any],
    statuses: dict[str, Any],
    cooldowns: dict[str, Any],
    proficiency: dict[str, Any],
    magic_numbers: dict[str, Any],
    tests: dict[str, Any],
    unresolved: dict[str, Any],
    comparison: list[dict[str, Any]],
) -> None:
    test_counts = tests["executed_counts"]
    item_skills = sum(row["item_requirement"] is not None for row in consumption["records"])
    dispositions = Counter(row["disposition"] for row in comparison)
    report = f"""# MIR2 人物技能系统全面审计报告

审计编号：`{AUDIT_ID}`<br>
审计日期：`{AUDIT_DATE}`<br>
审计基线：`{common["git_commit"]}`<br>
执行边界：首次只读审计；未修改伤害、冷却、特效、动作、图标或技能实现。

## 结论先行

当前 33 技能能够在 HardCore 离线 Godot 场景中运行，但尚不能证明“严格复现同一套 MIR2 服务端数据库、服务端规则、客户端协议和客户端资源”。最高风险不是某一个伤害数字，而是证据链与权威边界：

1. 当前运行时技能数据来自 Crystal `Server.MirDB` version 105 的 33 条候选记录，全部标为 `B/C-candidate`；经典规则来自另一份 `original_gameofmir` 的 `Magic.pas`。另发现一份可完整解析、与 33 个技能名称全部匹配的 Paradox `Magic.DB` 候选，但它位于候选目录、没有导入清单且包含扩展技能“狮子吼”，不能认证为用户当前真实表或与规则源码同版。
2. 当前是单进程离线运行时，没有技能请求/响应网络协议，也没有独立服务端裁决；正式主场景仍使用中文名/`cast_type` 通用分派并直接结算伤害、治疗、Buff、Debuff 和移动。已经准备好的稳定 ID `CasterSkillRuntime` 尚未接入正式主链。
3. 玩家技能实例只保存“中文技能名 → 等级整数”、快捷槽，以及少量战士开关/烈火冷却；没有熟练度和升级训练状态。
4. MP 在目标/行为最终验证之前扣除；{item_skills} 个需要护身符或毒物的技能仅携带消耗元数据，没有从背包实际扣除。失败与中断也没有统一返还规则。
5. 26 个法师/道士主动技能已有按客户端源码映射到 `Magic.wil` 的正式像素；但正式主链未把稳定 `skill_id` 传给投射物、地效和召唤物，仍按职业/显示名猜测。33 个技能的运行时图标也都未从 `MagIcon.wil` 建立可证明绑定，现有 4 个战士快捷图标来自技能效果截图裁切。
6. 33 个技能均缺少完整的 LOS、友伤、最大目标数、目标排序和同地图/安全区/禁用地图契约。冷却候选与当前动画式冷却有 {cooldowns["mismatch_count"]} 项不一致。

因此，本轮结论是：保留 33 个稳定 `skill_id` 和已建立的源码追溯；不要重平衡。应先补齐同源数据库证据、玩家技能实例、共享权威执行边界和协议，再逐技能修复消费、目标、公式、动作、视觉和状态。

## 证据边界

| 证据层 | 当前来源 | 结论 |
|---|---|---|
| 技能静态数据 | Crystal `Server.MirDB` + mylgd Paradox `Magic.DB` + 项目 JSON | 两套均可复现解析；前者是当前治理候选，后者有完整经典字段，但都没有用户正式导入清单 |
| 服务端规则 | `dev_art_sources/reference/original_gameofmir/M2Server/Magic.pas` 等 | 可作为经典规则重建证据，但与 Crystal 数据库不同源 |
| 客户端规则 | `MirClient/magiceff.pas`、`PlayScn.pas`、`Actor.pas` | 可证明部分 EffectBase/动作映射；未形成当前协议闭环 |
| 客户端资源 | `Magic.wil` 等正式像素 | 26 个法/道主动视觉已绑定；MagIcon 运行时绑定未完成 |
| 当前运行时 | Godot GDScript | 单机本地执行；不是客户端/服务端双层架构 |

## 二十个必须直接回答的问题

1. **当前技能列表是否来自真实服务端技能表？** 否。`import_server_data/` 没有用户正式 `import_manifest.json` 或技能表。Crystal `Server.MirDB` 与 Paradox `Magic.DB` 都是可解析候选；后者 33/33 名称匹配并提供完整字段，但版本/发行链未认证。
2. **静态定义与玩家实例是否分离？** 部分分离。静态 JSON 与每角色 `learned_skills` 分开，但实例结构过薄且以中文名为键。
3. **等级和熟练度是否独立保存？** 等级按角色保存；熟练度不存在。
4. **战士技能与普通施法路径是否正确？** 大部分战士技能进入普通攻击上下文，方向基本正确；法/道正式主链仍走 `game_root` 的旧通用中文名分派，尚未进入已经准备好的 `CasterSkillRuntime`。
5. **服务端是否为命中和伤害最终裁决者？** 否。当前无独立服务端，Godot 本地场景直接裁决。
6. **威力公式是否来自服务端源码？** 独立公式包的规则骨架来自经典 `Magic.pas`/`ObjBase.pas`，输入数值来自不同发行版的 Crystal 候选；更关键的是正式法/道主链仍使用“本地属性随机值 × 通用 multiplier”，没有调用该公式包。
7. **MP 和道具消耗是否正确？** MP 使用候选值并在验证前扣除；护身符/毒物没有实际扣除，故不完整。
8. **失败时是否错误消耗资源？** 是，存在风险：先扣 MP，后续特殊行为或目标适配可能失败；无统一返还。
9. **目标和范围是否正确？** 有基本形状和像素距离，但正式主链主要依靠 `distance <= range` 与方向点积；群疗和群体 Buff 退化为只作用施法者，完整合法性、LOS、友伤、上限和排序缺失。
10. **动作是否调用统一人物动作系统？** 是，调用 `PlayerVisual.play_action`，集成分支已有正式 `cast` 动作纹理；缺口是释放仍按独立 `windup` 计时，而不是按动作释放帧提交。
11. **释放帧与效果生成时点是否一致？** 未证明。实际以 `windup` 定时器提交，`hit_frame` 只是元数据。
12. **EffectType/Effect 是否经客户端代码验证？** 部分。26 个法/道主动视觉有客户端源码映射规则；经典表字段本身缺失，且正式节点创建没有传稳定技能 ID，不能对 33 个技能的实际表现链全部证明。
13. **图标是否来自正确 MagIcon 索引？** 当前运行时否。经典候选 `Effect*2/+1` 的 33 对索引均可在 72 帧 `MagIcon.wil` 解码，但 UI 尚未消费；4 个战士图标来自效果图裁切，其余使用技能书图标或无快捷图标。
14. **Buff/Debuff 是否服务器权威？** 否，本地计时器状态。
15. **持续时间和叠加规则是否正确？** 有部分 `max duration/max value` 行为，但无统一状态契约；魔防和物防还合并到同一字段。
16. **冷却与动画时长是否混淆？** 是。当前 `castDefaults`/动作时长驱动公共 `_attack_timer`，与候选服务端 Delay 大量不一致。
17. **熟练度和升级逻辑是否完整？** 否，未实现。
18. **网络延迟是否可能重复施法/伤害？** 当前无网络；本地 action_id 防止同一待提交动作重复，但未来网络层没有幂等键，不能保证。
19. **多少技能依赖名称或人工猜测绑定？** 正式路径 33/33 玩家实例和主入口依赖中文技能名；至少 7 个投射物技能的视觉 ID 由职业猜测，地效与召唤也存在职业/显示名猜测；4 个现有快捷图标不是 MagIcon，而是效果图裁切。26 个法/道素材映射本身有源码证据，不计作人工猜测。
20. **哪些技能保留、修复或重建？** 33 个稳定定义都保留；2 个被动技能修复实例/熟练度；其余 31 个保留定义并接入重建后的共享权威执行层。重建对象是一次共享协议/权威架构，不是擅自重做 31 份数值或美术。

## 关键问题分级

### Critical

- `SKILL_DATABASE_ERROR`：数据库候选与规则源码不同源。
- `SKILL_PROTOCOL_ERROR` / `SERVER_AUTHORITY_ERROR`：没有客户端—服务端技能协议与服务端裁决。
- `PROFICIENCY_ERROR`：33 技能无熟练度/升级训练路径。

### High

- `RESOURCE_CONSUMPTION_ERROR`：道具消耗不执行，MP 先扣后验。
- `TARGETING_ERROR` / `RANGE_ERROR`：完整目标合法性契约缺失。
- `COOLDOWN_ERROR`：候选 Delay 与运行时动作式冷却分离且未同步。
- `EFFECT_BINDING_ERROR`：MagIcon 未绑定，EffectType/Effect 只完成部分客户端映射。
- `STATUS_EFFECT_ERROR`：状态无统一权威、叠加、驱散和持久化规则。

### Medium

- `EVENT_TIMING_ERROR`：`hit_frame` 未作为调度来源。
- `PERSISTENCE_ERROR`：通用开关、冷却和状态未保存。
- `MAGIC_PATCH`：当前项目仍有名称分派、兼容入口和候选数值，需要在权威链建成后逐项清点。

## 测试结果

本轮使用独立的新日志目录 `outputs/skill_audit_20260724/`，没有复用或删除既有日志。现有专项执行统计：通过 {test_counts.get("pass", 0)}，失败/无 PASS 标记 {test_counts.get("fail", 0)}，未运行 {test_counts.get("not_run", 0)}。通过项证明当前本地实现的 ID、公式辅助函数、27 个法/道计划、视觉、快捷槽、存档和一次提交行为；它们不能证明服务端权威或网络协议。

附件要求的理想测试中，协议往返、服务端权威伤害、状态叠加、效果生成帧、冷却双端同步、熟练度和未批准补丁清理目前没有同名或等价的现有自动测试。详见 `reports/skill_test_results.json`。

## 保留、修复与重建顺序

1. 保留全部 33 个稳定 `skill_id`、当前源哈希和已证明的 26 个法/道视觉映射。
2. 先认证目标发行版的经典 `Magic.DB`（或明确批准继续采用哪一套候选），为数据库、规则源码和客户端建立同源证据闭环。
3. 将玩家实例升级为稳定 ID 键，加入等级、熟练度、快捷键、启用状态、冷却和迁移规则。
4. 重建一次共享的权威技能命令/结果层：请求 ID、目标/坐标、序列号、验证、消费、结算、结果事件、幂等。
5. 逐技能接入分类、合法性、消费、目标、公式、动作、视觉、状态和冷却；在此之前不改数值平衡。
6. 最后处理旧名称分派和魔法数字，保留兼容迁移而不是直接删除。

## 产物完整性

本轮生成附件要求的 18 个交付物（1 份 Markdown 总报告、16 份 JSON、1 份 CSV）。目录中的其他未跟踪审计文件未被覆盖或删除。未解技能绑定数：{unresolved["unresolved_skill_count"]}；魔法数字/补丁搜索命中：{magic_numbers["occurrence_count"]}；名称条件分支：{magic_numbers["name_branch_count"]}。

处置统计：

- `retain_definition_repair_instance`：{dispositions.get("retain_definition_repair_instance", 0)}
- `retain_definition_rebuild_shared_authority_path`：{dispositions.get("retain_definition_rebuild_shared_authority_path", 0)}
"""
    (DOCS / "MIR2_HUMAN_SKILL_SYSTEM_AUDIT_REPORT.md").write_text(report, encoding="utf-8")


if __name__ == "__main__":
    main()
