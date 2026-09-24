extends Node

const Rules := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")


func _ready() -> void:
	var weapon_best := [8815, 8631, 8447, 7805, 7254, 6703, 6152]
	var armor_best := [5769, 5326, 4882]
	var weapon_chain := 1.0
	var armor_chain := 1.0
	for stage in range(1, 8):
		var quote: Dictionary = Rules.quote_probability("武器", stage, 20, 3, 3, 3)
		assert(int(quote.final_success_bps) == weapon_best[stage - 1])
		assert(Rules.forge_gold_cost("武器", stage) > 0)
		weapon_chain *= float(quote.final_success_bps) / 10000.0
	for stage in range(1, 4):
		var quote: Dictionary = Rules.quote_probability("盔甲", stage, 20, 3, 3, 3)
		assert(int(quote.final_success_bps) == armor_best[stage - 1])
		assert(Rules.quote_probability("头盔", stage, 20, 3, 3, 3) == quote)
		assert(Rules.forge_gold_cost("盔甲", stage) > 0)
		armor_chain *= float(quote.final_success_bps) / 10000.0
	assert(absf(weapon_chain - 0.15) < 0.0002)
	assert(absf(armor_chain - 0.15) < 0.0002)
	assert(Rules.quote_probability("武器", 7, 10, 2, 1, 1).final_success_bps == 3581)
	assert(Rules.quote_probability("武器", 7, 10, 2, 0, 0).final_success_bps == 1377)
	assert(Rules.quote_probability("武器", 7, 9, 2, 2, 2).is_empty())
	assert(Rules.quote_probability("武器", 8, 20, 3, 3, 3).is_empty())
	assert(Rules.forge_gold_cost("武器", 7) == 700000)
	assert(Rules.forge_gold_cost("盔甲", 3) == 500000)
	assert(Rules.forge_attribute_weights({}, {}) == {"attack_max": 1, "magic_max": 1, "tao_max": 1})
	var enhanced := {
		"contract_id": Rules.CONTRACT_ID,
		"forge": {"stage": 2, "history": ["attack_max", "magic_max"], "modifiers": [
			{"stat": "attack_max", "op": "add", "value": 1},
			{"stat": "magic_max", "op": "add", "value": 1},
		]},
	}
	assert(Rules.validate_enhancement(enhanced, "武器"))
	var bad := enhanced.duplicate(true)
	bad.forge.modifiers[0].value = 2
	assert(not Rules.validate_enhancement(bad, "武器"))
	bad = enhanced.duplicate(true)
	bad["socket"] = {}
	assert(not Rules.validate_enhancement(bad, "武器"))
	print("EQUIPMENT_ENHANCEMENT_RULES_PASS")
	get_tree().quit(0)
