extends RefCounted
## Complete canonical-ID coverage. No display-name lookup. No default DIRECT.
## This table describes the primary route; summons/status subevents keep their
## own source message contracts. Do not classify pet damage as SUMMON feedback.
const FAMILIES := {
    "warrior.basic_swordsmanship": &"PASSIVE",
    "warrior.slaying_swordsmanship": &"PHYSICAL_MODIFIER",
    "warrior.thrusting": &"PHYSICAL",
    "warrior.half_moon": &"PHYSICAL",
    "warrior.fire_sword": &"PHYSICAL",
    "warrior.wild_rush": &"PUSH",
    "wizard.fireball": &"DIRECT",
    "wizard.great_fireball": &"DIRECT",
    "wizard.repulsion_ring": &"PUSH",
    "wizard.temptation_light": &"CONTROL",
    "wizard.hellfire": &"DIRECT",
    "wizard.lightning": &"DIRECT",
    "wizard.teleport": &"SELF_UTILITY",
    "wizard.exploding_flame": &"DIRECT",
    "wizard.fire_wall": &"MINE",
    "wizard.laser": &"DIRECT",
    "wizard.hell_lightning": &"DIRECT",
    "wizard.magic_shield": &"BUFF",
    "wizard.holy_word": &"INSTANT_KILL",
    "wizard.ice_storm": &"DIRECT",
    "taoist.healing": &"HEAL",
    "taoist.spiritual_warfare": &"PASSIVE",
    "taoist.poison": &"POISON",
    "taoist.soul_fire_talisman": &"DIRECT",
    "taoist.summon_skeleton": &"SUMMON",
    "taoist.invisibility": &"BUFF",
    "taoist.mass_invisibility": &"BUFF",
    "taoist.magic_defense": &"BUFF",
    "taoist.defense": &"BUFF",
    "taoist.revelation": &"UTILITY",
    "taoist.entrapment": &"CONTROL",
    "taoist.mass_healing": &"HEAL",
    "taoist.summon_divine_beast": &"SUMMON",
}

static func family(skill_id: String) -> StringName:
    return StringName(FAMILIES.get(skill_id, &"UNKNOWN"))

static func validate_ids(actual_ids: PackedStringArray) -> PackedStringArray:
    var errors := PackedStringArray()
    var seen: Dictionary = {}
    for skill_id: String in actual_ids:
        if seen.has(skill_id):
            errors.append("duplicate_skill_id:" + skill_id)
        seen[skill_id] = true
        if not FAMILIES.has(skill_id):
            errors.append("unmapped_skill_id:" + skill_id)
    for skill_id: String in FAMILIES:
        if not seen.has(skill_id):
            errors.append("missing_skill_id:" + skill_id)
    return errors
