extends Node
const Rules := preload("res://scripts/item_drop_instance_rules.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var catalog := GameData.get_item_record({"item_id": 80})
	var sample: Dictionary = {}
	var applied := 0
	var multiple := 0
	var above_one := 0
	var counts := {"attack_max": 0, "magic_max": 0, "tao_max": 0}
	# Expected independent weapon gates: 0.5 * (1 - (14/15)^3) = 9.348%.
	# Per-stat entry is 1/30; increment has Binomial(12, 1/15) + 1 distribution.
	for i in range(20000):
		var instance := Rules.create_instance(catalog, "jp-v2-sample:%d" % i)
		assert(not instance.is_empty())
		if instance.modifiers.size() > 0: applied += 1
		if instance.modifiers.size() > 1: multiple += 1
		for modifier: Dictionary in instance.modifiers:
			counts[modifier.stat] += 1
			assert(int(modifier.value) >= 1 and int(modifier.value) <= 13)
			if int(modifier.value) > 1: above_one += 1
		if instance.modifiers.size() >= 2 and sample.is_empty(): sample = instance.duplicate(true)
	assert(applied > 1600 and applied < 2150, str(applied))
	assert(multiple > 65 and multiple < 200, str(multiple))
	assert(above_one > 850 and above_one < 1450, str(above_one))
	for stat: String in counts: assert(int(counts[stat]) > 520 and int(counts[stat]) < 820)
	assert(not sample.is_empty())
	PlayerState.equipment["武器"] = {}
	PlayerState.recalculate_stats(false)
	var bare: Dictionary = PlayerState.computed_stats.duplicate(true)
	PlayerState.equipment["武器"] = PlayerState._make_item_instance(str(catalog.name), catalog, 982345)
	PlayerState.recalculate_stats(false)
	var ordinary: Dictionary = PlayerState.computed_stats.duplicate(true)
	PlayerState.equipment["武器"] = sample
	PlayerState.recalculate_stats(false)
	for modifier: Dictionary in sample.modifiers:
		assert(float(PlayerState.computed_stats[modifier.stat]) == float(ordinary[modifier.stat]) + int(modifier.value))
		assert(float(PlayerState.computed_stats[modifier.stat]) > float(bare[modifier.stat]))
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(sample))
	assert(Rules.validate_instance(roundtrip, catalog), "save roundtrip")
	roundtrip.modifiers[0].value += 1
	assert(not Rules.validate_instance(roundtrip, catalog), "forged but in-range modifier rejected")
	for id in Rules._master_by_item_id:
		var item := GameData.get_item_record({"item_id": id})
		assert(not Rules.create_instance(item, "all175:%d" % id).is_empty())
	print("AFFIX_DISTRIBUTION_TEST_PASS sampled=20000 applied=%d multi=%d above_one=%d gates=%s" % [applied, multiple, above_one, counts])
	get_tree().quit(0)
