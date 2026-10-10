extends Node

## RED contract fixture for equipment-only ring skills.
##
## This intentionally references the not-yet-landed rules/registry overlay. It
## must remain RED until production wiring is released and the native test is
## scheduled by the root owner.
const EntityRegistry := preload("res://scripts/identity/entity_registry.gd")
const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")

const EXPECTED := {
	254: {
		"skill_id": "hc.skill.equipment.ring_teleport",
		"effect_id": "safe_teleport",
		"parent_skill_id": "wizard.teleport",
		"mana_cost": 0,
	},
	255: {
		"skill_id": "hc.skill.equipment.ring_healing",
		"effect_id": "grant_healing_skill",
		"parent_skill_id": "taoist.healing",
		"mana_cost": 5,
	},
	259: {
		"skill_id": "hc.skill.equipment.ring_fireball",
		"effect_id": "grant_fireball_skill",
		"parent_skill_id": "wizard.fireball",
		"mana_cost": 5,
	},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var seen_skills := {}
	for item_id: int in EXPECTED:
		var expected: Dictionary = EXPECTED[item_id]
		assert(not seen_skills.has(expected.skill_id))
		seen_skills[expected.skill_id] = true
		# RED business assertions: the current registry and vanilla loader must
		# reject these IDs until the explicit equipment overlay is generated.
		assert(not EntityRegistry.resolve(expected.skill_id, "skill").is_empty(),
			"missing generated equipment skill identity: %s" % expected.skill_id)
		var base_definition := SkillDataLoader.skill(expected.skill_id)
		assert(not base_definition.is_empty(),
			"equipment skill must be visible through the loader overlay: %s" % expected.skill_id)
		assert(bool(base_definition.get("equipment_granted", false)))
		assert(str(base_definition.get("effect_id", "")) == expected.effect_id)
		assert(str(base_definition.get("parent_skill_id", "")) == expected.parent_skill_id)
		assert(str(base_definition.get("activation", "")) == "click")
		assert(int(base_definition.get("mana_cost", -1)) == int(expected.mana_cost))
		var grant_rules_path := "res://scripts/equipment_granted_skill_rules.gd"
		if FileAccess.file_exists(grant_rules_path):
			var grant_script: Variant = load(grant_rules_path)
			var grant_rules: Variant = grant_script.new()
			assert(bool(grant_rules.ensure_loaded()))
			assert(grant_rules.skill_id_for_item(item_id) == expected.skill_id)
			assert(grant_rules.item_id_for_skill(expected.skill_id) == item_id)
			assert(grant_rules.effect_id_for_skill(expected.skill_id) == expected.effect_id)
	assert(seen_skills.size() == 3)
	assert(SkillDataLoader.skill("hc.skill.equipment.ring_teleport").is_empty() == false)
	assert(SkillDataLoader.skill("hc.skill.equipment.ring_teleport") != SkillDataLoader.skill("hc.skill.equipment.ring_healing"))
	assert(SkillDataLoader.skill("hc.skill.equipment.ring_healing") != SkillDataLoader.skill("hc.skill.equipment.ring_fireball"))
	print("EQUIPMENT_GRANTED_SKILL_IDENTITY_PASS skills=3 teleport_mp=0 healing_mp=5 fireball_mp=5")
	get_tree().quit()
