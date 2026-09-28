extends Node

const Rollout := preload("res://scripts/layers/rules/equipment_skill_level_affix_rollout.gd")


func _ready() -> void:
	assert(not Rollout.generate(42, 0, 0).generated)
	var policy := {
		"contract_id": Rollout.CONTRACT_ID,
		"enabled": true,
		"eligible_item_ids": [42],
		"gate": {"numerator": 1, "denominator": 4},
		"weighted_affixes": [
			{"scope": "all", "value": 1, "weight": 2},
			{"scope": "skill:warrior.fire_sword", "value": 2, "weight": 1},
		],
	}
	assert(Rollout.generate(42, 0, 0, policy).modifier.scope == "all")
	assert(Rollout.generate(42, 0, 2, policy).modifier.scope == "skill:warrior.fire_sword")
	assert(Rollout.generate(42, 1, 0, policy).reason == "gate_miss")
	assert(Rollout.generate(43, 0, 0, policy).reason == "ineligible_item")
	policy.weighted_affixes[1].scope = "skill:wizard.magic_shield"
	assert(Rollout.generate(42, 0, 0, policy).reason == "invalid_affix")
	print("EQUIPMENT_SKILL_LEVEL_AFFIX_ROLLOUT_PASS")
	get_tree().quit(0)
