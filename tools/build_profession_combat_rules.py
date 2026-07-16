#!/usr/bin/env python3
"""Build caster rule descriptors from Magic.pas and extracted MagicInfo values."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAGIC = ROOT / "dev_art_sources/reference/original_gameofmir/M2Server/Magic.pas"
SETUP = ROOT / "dev_art_sources/reference/original_gameofmir/MirServer/Mir200/!Setup.txt"
CATALOG = ROOT / "assets/data/vanilla_176/profession_magic_info.json"
OUTPUT = ROOT / "assets/data/vanilla_176/profession_combat_rules.json"

DAMAGE = {
    "wizard.fireball",
    "wizard.great_fireball",
    "wizard.hellfire",
    "wizard.lightning",
    "wizard.exploding_flame",
    "wizard.fire_wall",
    "wizard.laser",
    "wizard.hell_lightning",
    "wizard.ice_storm",
    "taoist.soul_fire_talisman",
}
HEAL = {"taoist.healing", "taoist.mass_healing"}

ANCHORS = {
    "wizard.fireball": "TMagicManager.DoSpell/SKILL_FIREBALL",
    "wizard.repulsion_ring": "TMagicManager.DoSpell/SKILL_FIREWIND",
    "wizard.temptation_light": "TMagicManager.MagTamming",
    "wizard.hellfire": "TMagicManager.DoSpell/SKILL_FIRE",
    "wizard.lightning": "TMagicManager.DoSpell/SKILL_LIGHTENING",
    "wizard.teleport": "TMagicManager.DoSpell/SKILL_SPACEMOVE",
    "wizard.great_fireball": "TMagicManager.DoSpell/SKILL_FIREBALL2",
    "wizard.exploding_flame": "TMagicManager.DoSpell/SKILL_FIREBOOM",
    "wizard.fire_wall": "TMagicManager.DoSpell/SKILL_EARTHFIRE + MagMakeFireCross",
    "wizard.laser": "TMagicManager.DoSpell/SKILL_SHOOTLIGHTEN",
    "wizard.hell_lightning": "TMagicManager.DoSpell/SKILL_LIGHTFLOWER",
    "wizard.magic_shield": "TMagicManager.DoSpell/SKILL_SHIELD + MagBubbleDefenceUp",
    "wizard.holy_word": "TMagicManager.DoSpell/SKILL_KILLUNDEAD",
    "wizard.ice_storm": "TMagicManager.DoSpell/SKILL_SNOWWIND",
    "taoist.healing": "TMagicManager.DoSpell/SKILL_HEALLING",
    "taoist.spiritual_warfare": "TMagicManager.DoSpell/SKILL_SPIRIT",
    "taoist.poison": "TMagicManager.DoSpell/SKILL_AMYOUNSUL",
    "taoist.soul_fire_talisman": "TMagicManager.DoSpell/SKILL_FIRECHARM",
    "taoist.summon_skeleton": "TMagicManager.MagMakeSlave",
    "taoist.invisibility": "TMagicManager.MagMakePrivateTransparent",
    "taoist.mass_invisibility": "TMagicManager.MagMakeGroupTransparent",
    "taoist.magic_defense": "TMagicManager.DoSpell/SKILL_HANGMAJINBUB",
    "taoist.defense": "TMagicManager.DoSpell/SKILL_DEJIWONHO",
    "taoist.revelation": "TMagicManager.DoSpell/SKILL_SHOWHP",
    "taoist.entrapment": "TMagicManager.MagMakeHolyCurtain",
    "taoist.mass_healing": "TMagicManager.DoSpell/SKILL_BIGHEALLING",
    "taoist.summon_divine_beast": "TMagicManager.MagMakeSinSuSlave",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def formula_group(skill_id: str) -> str:
    if skill_id in DAMAGE:
        return "classic_magic_damage"
    if skill_id in HEAL:
        return "classic_healing"
    if skill_id.startswith("taoist.summon_"):
        return "classic_summon"
    return "classic_special"


def special_fields(skill_id: str) -> dict:
    fields: dict = {}
    if skill_id == "wizard.lightning":
        fields["undead_damage_multiplier"] = 1.5
    elif skill_id == "wizard.hell_lightning":
        fields.update({"undead_damage_divisor": 1, "living_damage_divisor": 10})
    elif skill_id == "wizard.repulsion_ring":
        fields.update({"push_cells_formula": "1 + max(0, skill_level - 1) + random(2)", "success_random_bound": 20})
    elif skill_id == "wizard.teleport":
        fields.update({"success_formula": "random(11) < skill_level * 2 + 4"})
    elif skill_id == "wizard.fire_wall":
        fields.update({"shape": "five_cell_cross", "duration_formula": "get_power(10) + floor(mc_roll / 2)"})
    elif skill_id == "wizard.magic_shield":
        fields.update({"shield_power_formula": "get_power(mc_roll + 15)"})
    elif skill_id == "wizard.holy_word":
        fields.update({"undead_only": True, "success_formula": "random(100) < skill_level*7 + 15 + caster_level-target_level"})
    elif skill_id == "taoist.poison":
        fields.update({"green_power_formula": "get_power13(40) + sc_roll*2", "red_power_formula": "get_power13(30) + sc_roll*2", "duration_formula": "round(skill_level/3 * power/20)", "poison_interval_ms": 1000, "amy_ounsul_point": 20})
    elif skill_id in {"taoist.invisibility", "taoist.mass_invisibility"}:
        fields.update({"duration_formula": "get_power13(30) + sc_roll*3", "area_radius_cells": 1 if skill_id.endswith("mass_invisibility") else 0})
    elif skill_id == "taoist.entrapment":
        fields.update({"duration_formula": "get_power13(40) + sc_roll*3", "ring_event_count": 8})
    elif skill_id == "taoist.revelation":
        fields.update({"duration_formula": "get_power13(sc_roll*2 + 30)", "success_formula": "random(6) <= skill_level + 3"})
    elif skill_id in {"taoist.magic_defense", "taoist.defense"}:
        fields.update({"buff_power_formula": "get_power13(60) + sc_roll*10", "area_radius_cells": 3})
    elif skill_id.startswith("taoist.summon_"):
        fields.update({
            "attack_type": "fire" if skill_id.endswith("divine_beast") else "physical",
            "lifetime_seconds_by_level": [864000, 864000, 864000, 864000],
            "summon_level_equals_skill_level": True,
            "summon_exp_level_equals_skill_level": True,
            "default_count": 1,
            "reject_when_owner_has_slave": True,
            "recall_existing_on_create_failure": skill_id.endswith("divine_beast"),
            "leash_range": 560,
            "teleport_range": 900,
            "spatial_state_machine_status": "project_adapter_C_candidate",
            "amulet_cost": 5 if skill_id.endswith("divine_beast") else 1,
        })
    if skill_id in {
        "taoist.soul_fire_talisman", "taoist.magic_defense", "taoist.defense",
        "taoist.entrapment", "taoist.summon_skeleton", "taoist.invisibility",
        "taoist.mass_invisibility",
    }:
        fields["amulet_cost"] = 1
    return fields


def main() -> None:
    magic_text = MAGIC.read_text(encoding="gbk", errors="replace")
    setup_text = SETUP.read_text(encoding="gbk", errors="replace")
    required_evidence = [
        "function GetPower(nPower:Integer;UserMagic:pTUserMagic):Integer;",
        "function GetPower13(nInt:Integer;UserMagic:pTUserMagic):Integer;",
        "dwRoyaltySec:=10 * 24 * 60 * 60;",
        "SKILL_SINSU{30}",
    ]
    if any(item not in magic_text for item in required_evidence) or "AmyOunsulPoint=20" not in setup_text:
        raise RuntimeError("classic Magic.pas/!Setup.txt evidence changed or is incomplete")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    output = {
        "schemaVersion": 2,
        "layer": "vanilla_core",
        "sourcePolicy": "classic M2Server rule source first; Crystal MagicInfo values remain B/C candidates",
        "classicRuleSource": {
            "distribution_id": "source.original_gameofmir.server_suite",
            "source_priority": {"lane": "server_rules", "tier": "primary", "order": 0, "weight": 100},
            "original_path": "M2Server/Magic.pas",
            "workspace_path": str(MAGIC.relative_to(ROOT)).replace("\\", "/"),
            "sha256": digest(MAGIC),
            "confidence": "A-source-code-reconstruction",
        },
        "classicConfigSource": {
            "distribution_id": "source.original_gameofmir.server_suite",
            "source_priority": {"lane": "server_rules", "tier": "primary", "order": 0, "weight": 100},
            "original_path": "MirServer/Mir200/!Setup.txt",
            "workspace_path": str(SETUP.relative_to(ROOT)).replace("\\", "/"),
            "sha256": digest(SETUP),
        },
        "formulaContracts": {
            "get_power": "round(power_roll/(train_level+1)*(skill_level+1)) + def_power_roll",
            "get_power13": "round((input-input/3)/(train_level+1)*(skill_level+1) + input/3 + def_power_roll)",
            "magic_damage": "stat_roll + get_power(magic_power_roll)",
            "healing": "get_power(magic_power_roll) + sc_roll*2",
            "train_level": 3,
        },
        "wizard": {"skills": {}},
        "taoist": {"skills": {}},
    }
    for record in catalog["records"]:
        skill_id = record["skill_id"]
        if record["profession_id"] not in {"wizard", "taoist"}:
            continue
        rule = {
            "formula_group": formula_group(skill_id),
            "source_anchor": ANCHORS[skill_id],
            "source_status": "classic_rule_with_crystal_value_candidate",
            "confidence": "B/C",
            "train_level": 3,
            "power_base": record["power_base"],
            "power_bonus": record["power_bonus"],
            "magic_power_base": record["magic_power_base"],
            "magic_power_bonus": record["magic_power_bonus"],
            "multiplier_by_level": [record["multiplier_base"] + record["multiplier_bonus"] * level for level in range(4)],
            "cooldown_by_level": [value / 1000.0 for value in record["cooldown_ms_by_level"]],
            "service_spell_id": record["service_spell_id"],
            **special_fields(skill_id),
        }
        output[record["profession_id"]]["skills"][skill_id] = rule
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PROFESSION_COMBAT_RULES_BUILT=27")


if __name__ == "__main__":
    main()
