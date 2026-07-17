#!/usr/bin/env python3
"""Add stable profession/skill identifiers and traceability to vanilla skill data."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS_PATH = ROOT / "assets/data/vanilla_176/skills.json"
GROWTH_PATH = ROOT / "assets/data/vanilla_176/profession_growth.json"
RULES_PATH = ROOT / "assets/data/vanilla_176/profession_combat_rules.json"

PROFESSIONS = {
    "战士": "warrior",
    "法师": "wizard",
    "道士": "taoist",
}

SKILLS = {
    "基本剑术": "warrior.basic_swordsmanship",
    "攻杀剑术": "warrior.slaying_swordsmanship",
    "刺杀剑术": "warrior.thrusting",
    "半月弯刀": "warrior.half_moon",
    "野蛮冲撞": "warrior.wild_rush",
    "烈火剑法": "warrior.fire_sword",
    "火球术": "wizard.fireball",
    "抗拒火环": "wizard.repulsion_ring",
    "诱惑之光": "wizard.temptation_light",
    "地狱火": "wizard.hellfire",
    "雷电术": "wizard.lightning",
    "瞬息移动": "wizard.teleport",
    "大火球": "wizard.great_fireball",
    "爆裂火焰": "wizard.exploding_flame",
    "火墙": "wizard.fire_wall",
    "疾光电影": "wizard.laser",
    "地狱雷光": "wizard.hell_lightning",
    "魔法盾": "wizard.magic_shield",
    "圣言术": "wizard.holy_word",
    "冰咆哮": "wizard.ice_storm",
    "治愈术": "taoist.healing",
    "精神力战法": "taoist.spiritual_warfare",
    "施毒术": "taoist.poison",
    "灵魂火符": "taoist.soul_fire_talisman",
    "召唤骷髅": "taoist.summon_skeleton",
    "隐身术": "taoist.invisibility",
    "集体隐身术": "taoist.mass_invisibility",
    "幽灵盾": "taoist.magic_defense",
    "神圣战甲术": "taoist.defense",
    "心灵启示": "taoist.revelation",
    "困魔咒": "taoist.entrapment",
    "群体治疗术": "taoist.mass_healing",
    "召唤神兽": "taoist.summon_divine_beast",
}


def trace(row: dict, field: str, status: str = "sourced_candidate") -> dict:
    return {
        "field": field,
        "status": status,
        "source_url": row.get("sourceUrl", ""),
        "secondary_source_url": row.get("secondarySourceUrl", ""),
        "source_date": row.get("sourceDate", ""),
        "confidence": row.get("confidence", "B"),
        "verification": row.get("verification", ""),
    }


def build_skill_rows() -> None:
    payload = json.loads(SKILLS_PATH.read_text(encoding="utf-8"))
    payload["schemaVersion"] = 2
    for row in payload["records"]:
        name = row["skillName"]
        profession = row["profession"]
        row["profession_id"] = PROFESSIONS[profession]
        row["skill_id"] = SKILLS[name]
        row["display_name"] = name
        row["source_trace"] = {
            "required_character_level": trace(row, "requiredCharacterLevel"),
            "training_points": trace(
                row,
                "trainingPoints",
                "not_applicable" if row.get("trainingPoints") is None and int(row.get("skillLevel", 0)) == 0 else "sourced_candidate",
            ),
            "mana_cost": {
                "field": "manaCost",
                "status": "unresolved" if row.get("manaCost") is None else "sourced_candidate",
                "required_source": "Magic.DB wSpell + btDefSpell",
                "confidence": "unknown" if row.get("manaCost") is None else row.get("confidence", "B"),
            },
            "server_delay": trace(row, "delay"),
        }
    SKILLS_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_growth() -> None:
    payload = json.loads(GROWTH_PATH.read_text(encoding="utf-8"))
    payload["schemaVersion"] = 2
    payload["professionCatalog"] = {
        profession_id: {
            "profession_id": profession_id,
            "display_name": display_name,
        }
        for display_name, profession_id in PROFESSIONS.items()
    }
    payload["skillCatalog"] = {
        skill_id: {
            "skill_id": skill_id,
            "profession_id": PROFESSIONS[payload["skillProfiles"][display_name]["profession"]],
            "display_name": display_name,
        }
        for display_name, skill_id in SKILLS.items()
    }
    for display_name, profile in payload["skillProfiles"].items():
        profile["profession_id"] = PROFESSIONS[profile["profession"]]
        profile["skill_id"] = SKILLS[display_name]
        profile["display_name"] = display_name
        profile["formula_id"] = f"{SKILLS[display_name]}.v1"
        profile["source_trace"] = {
            "runtime_profile": {
                "source": "legacy_verified_adapter",
                "confidence": "A" if profile["profession"] == "战士" else "B",
            },
            "cooldown": {
                "source": "Client/Actor.pas" if profile["profession"] == "战士" else "mobile_runtime_candidate",
                "confidence": "A" if profile["profession"] == "战士" else "B",
            },
            "status_duration": {
                "source": "profession_combat_rules.json",
                "confidence": "B" if profile["profession"] != "战士" else "not_applicable",
            },
        }
    payload["sourcePolicy"] = {
        "identity": "stable English IDs are authoritative; Chinese names are display/legacy aliases",
        "character_presentation": "male_only",
        "service_values": "Magic.DB and server source take priority",
        "client_timing": "original client source takes priority",
        "candidate_values": "must remain explicitly marked until replaced by source-backed values",
    }
    GROWTH_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_combat_rules() -> None:
    rules = {
        "schemaVersion": 1,
        "layer": "vanilla_core",
        "sourcePolicy": {
            "baseline": "2003 official 1.76 behavior where local source is available",
            "server_source": "dev_art_sources/reference/original_gameofmir/MirServer",
            "client_source": "dev_art_sources/reference/original_gameofmir/MirClient/Actor.pas",
            "missing_database": "Magic.DB wSpell/btDefSpell is not present",
            "candidate_notice": "B/C values are replaceable runtime candidates, not claimed as exact official values",
        },
        "wizard": {
            "profession_id": "wizard",
            "formula_source": "WizardCombatMath",
            "skills": wizard_rules(),
        },
        "taoist": {
            "profession_id": "taoist",
            "formula_source": "TaoistCombatMath",
            "skills": taoist_rules(),
        },
    }
    RULES_PATH.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def wizard_rules() -> dict:
    return {
        "wizard.fireball": damage_rule([0.85, 1.0, 1.15, 1.3], [0.72] * 4),
        "wizard.repulsion_ring": status_rule("knockback_distance", [50, 65, 80, 95], [0.8] * 4),
        "wizard.temptation_light": status_rule("status_duration", [3, 4, 5, 6], [0.9] * 4),
        "wizard.hellfire": damage_rule([1.0, 1.15, 1.3, 1.45], [0.62] * 4),
        "wizard.lightning": damage_rule([1.15, 1.35, 1.55, 1.75], [0.72] * 4),
        "wizard.teleport": status_rule("travel_range", [160, 180, 200, 220], [1.0] * 4),
        "wizard.great_fireball": damage_rule([1.2, 1.45, 1.7, 1.95], [0.78] * 4),
        "wizard.exploding_flame": damage_rule([1.05, 1.25, 1.45, 1.65], [0.78] * 4),
        "wizard.fire_wall": {
            **damage_rule([0.45, 0.55, 0.65, 0.75], [0.85] * 4),
            "status_duration_by_level": [4, 5, 6, 7],
            "tick_interval": 0.8,
        },
        "wizard.laser": damage_rule([1.35, 1.55, 1.75, 1.95], [0.82] * 4),
        "wizard.hell_lightning": damage_rule([0.95, 1.1, 1.25, 1.4], [0.78] * 4),
        "wizard.magic_shield": {
            **status_rule("status_duration", [8, 10, 12, 14], [0.9] * 4),
            "damage_reduction_by_level": [0.25, 0.3, 0.35, 0.4],
        },
        "wizard.holy_word": {
            **damage_rule([0.8, 0.9, 1.0, 1.1], [0.9] * 4),
            "execute_level_margin_by_level": [4, 5, 6, 7],
        },
        "wizard.ice_storm": damage_rule([1.5, 1.7, 1.9, 2.1], [0.95] * 4),
    }


def taoist_rules() -> dict:
    return {
        "taoist.healing": {
            **damage_rule([0.9, 1.0, 1.1, 1.2], [0.75] * 4),
            "flat_power_by_level": [6, 8, 10, 12],
        },
        "taoist.spiritual_warfare": status_rule("accuracy_bonus", [0, 1, 2, 3], [0.0] * 4),
        "taoist.poison": {
            **damage_rule([0.3, 0.35, 0.4, 0.45], [0.72] * 4),
            "status_duration_by_level": [6, 7, 8, 9],
            "tick_interval": 1.0,
        },
        "taoist.soul_fire_talisman": damage_rule([1.05, 1.15, 1.25, 1.35], [0.72] * 4),
        "taoist.summon_skeleton": summon_rule("physical", [180, 240, 300, 360]),
        "taoist.invisibility": status_rule("status_duration", [7, 8, 9, 10], [0.9] * 4),
        "taoist.mass_invisibility": status_rule("status_duration", [6, 7, 8, 9], [1.0] * 4),
        "taoist.magic_defense": {
            **status_rule("status_duration", [12, 13, 14, 15], [0.9] * 4),
            "buff_power_by_level": [1, 2, 3, 4],
        },
        "taoist.defense": {
            **status_rule("status_duration", [12, 13, 14, 15], [0.9] * 4),
            "buff_power_by_level": [1, 2, 3, 4],
        },
        "taoist.revelation": status_rule("status_duration", [3, 4, 5, 6], [0.55] * 4),
        "taoist.entrapment": status_rule("status_duration", [3, 4, 5, 6], [1.0] * 4),
        "taoist.mass_healing": {
            **damage_rule([0.75, 0.85, 0.95, 1.05], [1.0] * 4),
            "flat_power_by_level": [4, 6, 8, 10],
        },
        "taoist.summon_divine_beast": summon_rule("fire", [300, 360, 420, 480]),
    }


def damage_rule(multiplier: list[float], cooldown: list[float]) -> dict:
    return {
        "multiplier_by_level": multiplier,
        "cooldown_by_level": cooldown,
        "confidence": "B",
        "source_status": "runtime_candidate_from_legacy_profile",
    }


def status_rule(field: str, values: list[float], cooldown: list[float]) -> dict:
    return {
        f"{field}_by_level": values,
        "cooldown_by_level": cooldown,
        "confidence": "B",
        "source_status": "runtime_candidate_from_legacy_profile",
    }


def summon_rule(attack_type: str, lifetime: list[int]) -> dict:
    return {
        "attack_type": attack_type,
        "lifetime_seconds_by_level": lifetime,
        "leash_range": 560,
        "teleport_range": 900,
        "confidence": "C",
        "source_status": "project_state_machine_candidate",
    }


def main() -> None:
    build_skill_rows()
    build_growth()
    # Rebuild traceable service candidates and source-backed Magic.pas rules.
    # The legacy multiplier builder above remains only for migration history.
    from extract_profession_magic_info import main as extract_magic_info
    from build_profession_combat_rules import main as build_classic_rules

    extract_magic_info()
    build_classic_rules()
    print(f"PROFESSION_SKILL_CATALOG_PASS professions={len(PROFESSIONS)} skills={len(SKILLS)}")


if __name__ == "__main__":
    main()
