extends Node

const Rules := preload("res://scripts/equipment_rules.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var improved := 0
	var cursed := 0
	# Enumerate every draw combination: R=2, lower denominator 8, upper 80.
	for unlucky in range(20):
		for lower in range(8):
			for upper in range(80):
				var outcome := Rules.blessing_outcome(1, 0, 2, 12, unlucky, lower, upper)
				if outcome.result == "improved": improved += 1
				if outcome.result == "cursed": cursed += 1
	assert(improved == 19 * (80 + 7), "original lower-failure fallthrough probability")
	assert(cursed == 8 * 80, "exact 1/20 downside")
	assert(Rules.blessing_outcome(1, 0, 2, 12, 0, 0, 1).luck == 2, "upper-stage success after lower failure")
	assert(Rules.blessing_outcome(4, 1, 2, 12, 1, 0).luck == 2, "legacy net preserved before mutation")
	for luck in range(8):
		for curse in range(11):
			for unlucky in [0, 1]:
				var outcome := Rules.blessing_outcome(luck, curse, 2, 12, unlucky, 1, 1)
				assert(int(outcome.luck) == 0 or int(outcome.curse) == 0, "exclusive new instance state")
	var catalog := GameData.get_item_record({"item_id": 80})
	assert(catalog.kind == "equipment" and catalog.category == "武器")
	var weapon := PlayerState._make_item_instance(str(catalog.name), catalog, 710001)
	for luck in [0, 1, 2, 3, 6, 7]:
		for seed_value in range(64):
			weapon.weapon_luck = luck
			weapon.weapon_curse = 0
			var actual := RandomNumberGenerator.new()
			var reference := RandomNumberGenerator.new()
			actual.seed = seed_value
			reference.seed = seed_value
			var rolls := PlayerState._blessing_oil_rolls(weapon, actual)
			var first := reference.randi_range(0, 19)
			var lower := 0
			var upper := -1
			var r := Rules.blessing_span_factor(int(catalog.attackMin), int(catalog.attackMax))
			if first != 1 and luck >= 1 and luck < 7:
				lower = reference.randi_range(0, (r + 6 if luck < 3 else r * 40) - 1)
				if luck < 3 and lower != 1:
					upper = reference.randi_range(0, r * 40 - 1)
			assert(rolls == {"unlucky_roll":first,"success_roll":lower,"upper_stage_roll":upper})
			assert(actual.state == reference.state, "conditional RNG consumption matches original")
	weapon.weapon_luck = 1
	PlayerState.equipment["武器"] = weapon
	PlayerState.inventory = [{"name":"祝福油", "count":2}]
	var result := PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 0, 1)
	assert(result.ok and PlayerState.equipment["武器"].weapon_luck == 2 and PlayerState.inventory[0].count == 1)
	PlayerState._test_force_atomic_write_failure = true
	result = PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 1, 0)
	PlayerState._test_force_atomic_write_failure = false
	assert(not result.ok and PlayerState.equipment["武器"].weapon_luck == 2 and PlayerState.inventory[0].count == 1, "oil and weapon roll back together")
	for pair in [Vector2i(1,0),Vector2i(0,2),Vector2i(4,1),Vector2i(0,0)]:
		var detail := Detail.format_item(catalog, {"weapon_luck":pair.x,"weapon_curse":pair.y})
		var net := Rules.equipment_luck_contribution(catalog, {"weapon_luck":pair.x,"weapon_curse":pair.y}, true)
		assert(not (detail.contains("幸运 +") and detail.contains("诅咒 +")), "one net attribute only")
		assert(not detail.contains("幸运 +0") and not detail.contains("诅咒 +0"), "zero attributes hidden")
		if net > 0: assert(detail.contains("幸运 +%d" % net), "effective luck displayed")
		if net < 0: assert(detail.contains("诅咒 +%d" % -net), "effective curse displayed")
	print("BLESSING_RULE_V3_PASS exhaustive_draws=12800 rng_sequences=384 transaction_and_display=true")
	get_tree().quit()
