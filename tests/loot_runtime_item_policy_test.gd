extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)

const FEMALE_TO_MALE_DROP_NAMES := {
	117: "布衣(男)",
	119: "轻型盔甲(男)",
	121: "中型盔甲(男)",
	123: "重盔甲(男)",
	125: "魔法长袍(男)",
	127: "灵魂战衣(男)",
	129: "战神盔甲(男)",
	131: "恶魔长袍(男)",
	133: "幽灵战衣(男)",
	141: "天魔神甲",
	143: "法神披风",
	145: "天尊道袍",
}


func _ready() -> void:
	assert(GameData.ensure_loaded(), GameData.load_error)
	var service := LootRuntimeScript.new()
	_test_female_equipment_output(service)
	_test_small_monster_probability(service)
	_test_prewarm_uses_output_identity(service)
	_test_lean_runtime_cache_stays_hot(service)
	print("LOOT_RUNTIME_ITEM_POLICY_PASS female_pairs=12 small_monster=ordinary")
	get_tree().quit(0)


func _test_female_equipment_output(service: Node) -> void:
	for source_id: int in FEMALE_TO_MALE_DROP_NAMES:
		var expected_name := str(FEMALE_TO_MALE_DROP_NAMES[source_id])
		assert(
			service._drop_output_item_name(source_id, "female-source") == expected_name,
			"female drop replacement failed: %d" % source_id,
		)
		var target := GameData.get_item_record(expected_name)
		assert(not target.is_empty(), "male drop target missing: %s" % expected_name)
		assert(str(target.get("kind", "")) == "equipment", str(target))
	assert(service._drop_output_item_name(116, "布衣(男)") == "布衣(男)")


func _test_small_monster_probability(service: Node) -> void:
	assert(GameData.canonical_monster_classification(19) == "ordinary")
	assert(GameData.canonical_monster_classification(31) == "elite")
	assert(GameData.canonical_monster_classification(76) == "boss")
	var equipment_probability := {
		"canonical_item_id": 116,
		"final_numerator": 1,
		"final_denominator": 20,
		"final_probability": 0.05,
	}
	var equipment_adjusted: Dictionary = service._apply_small_monster_probability_policy(
		equipment_probability,
		"ordinary",
	)
	assert(int(equipment_adjusted.final_numerator) == 1)
	assert(int(equipment_adjusted.final_denominator) == 60)
	assert(int(equipment_adjusted.small_monster_denominator_multiplier) == 3)
	assert(int(equipment_probability.final_denominator) == 20)

	var shenshui_probability := {
		"canonical_item_id": 910001,
		"final_numerator": 1,
		"final_denominator": 20,
		"final_probability": 0.05,
	}
	var shenshui_adjusted: Dictionary = service._apply_small_monster_probability_policy(
		shenshui_probability,
		"ordinary",
	)
	assert(int(shenshui_adjusted.final_denominator) == 120)
	assert(int(shenshui_adjusted.small_monster_denominator_multiplier) == 6)

	var elite_unchanged: Dictionary = service._apply_small_monster_probability_policy(
		equipment_probability,
		"elite",
	)
	var boss_unchanged: Dictionary = service._apply_small_monster_probability_policy(
		shenshui_probability,
		"boss",
	)
	assert(elite_unchanged == equipment_probability)
	assert(boss_unchanged == shenshui_probability)

	var ordinary_gold := {
		"canonical_item_id": -1,
		"final_numerator": 1,
		"final_denominator": 4,
		"final_probability": 0.25,
	}
	assert(
		service._apply_small_monster_probability_policy(ordinary_gold, "ordinary")
		== ordinary_gold
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 19003176
	var ordinary_roll: Dictionary = service.roll_monster_drops(19, rng)
	assert(bool(ordinary_roll.get("configured", false)), str(ordinary_roll))
	for attempt: Dictionary in ordinary_roll.get("attempts", []):
		var attempt_item_id := int(attempt.get("canonical_item_id", -1))
		if attempt_item_id in [910001, 910003, 910004]:
			assert(int(attempt.get("small_monster_denominator_multiplier", 1)) == 6)
		elif GameData.canonical_item_kind(attempt_item_id) == "equipment":
			assert(int(attempt.get("small_monster_denominator_multiplier", 1)) == 3)

	rng.seed = 76001931
	var boss_roll: Dictionary = service.roll_monster_drops(76, rng)
	assert(bool(boss_roll.get("configured", false)), str(boss_roll))
	for attempt: Dictionary in boss_roll.get("attempts", []):
		assert(int(attempt.get("small_monster_denominator_multiplier", 1)) == 1)


func _test_prewarm_uses_output_identity(service: Node) -> void:
	var names: Array[String] = service.possible_item_names_for_monster_ids([19])
	assert(names.has("布衣(男)"), str(names))
	assert(not names.has("布衣(女)"), str(names))


func _test_lean_runtime_cache_stays_hot(service: Node) -> void:
	service.clear_runtime_resolution_cache_for_test()
	service.possible_item_names_for_monster_ids([19])
	var warmed: Dictionary = service.runtime_resolution_cache_debug_snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026090317
	for _index: int in range(512):
		var roll: Dictionary = service.roll_monster_drops(19, rng, false)
		assert(bool(roll.get("configured", false)), str(roll))
	var after: Dictionary = service.runtime_resolution_cache_debug_snapshot()
	assert(after.get("misses", {}) == warmed.get("misses", {}), str(after))
	assert(int(after.get("profile_count", 0)) == int(warmed.get("profile_count", -1)))
	assert(int(after.get("probability_count", 0)) == int(warmed.get("probability_count", -1)))
	assert(int(after.get("reward_count", 0)) == int(warmed.get("reward_count", -1)))
