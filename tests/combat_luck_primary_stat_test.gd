extends Node


func _ready() -> void:
	_run.call_deferred()


func _roll(stat_min: int, stat_max: int, total_luck: int, seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return WarriorCombatMath.roll_primary_stat(stat_min, stat_max, total_luck, rng)


func _assert_player_attack(total_luck: int, expected_damage: int) -> void:
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.computed_stats.merge({
		"attack_min": 4,
		"attack_max": 12,
		"luck": total_luck,
		"critical_chance": 0.0,
	}, true)
	var player := PlayerCharacter.new()
	add_child(player)
	player.attack_hit_windup = 0.0
	var emitted_damage := [-1]
	player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, damage: int) -> void:
		emitted_damage[0] = damage
	)
	assert(player.request_attack(), "总幸运 %+d 的普通攻击未能发起" % total_luck)
	assert(
		emitted_damage[0] == expected_damage,
		"总幸运 %+d 的 DC 普通攻击应为 %d，实际为 %d" % [total_luck, expected_damage, emitted_damage[0]]
	)
	player.free()


func _run() -> void:
	PlayerState.test_mode = true

	# signed total luck reaches deterministic endpoints on every positive span.
	assert(_roll(4, 12, 9, 176) == 12, "总幸运+9没有稳定命中上限")
	assert(_roll(4, 12, -9, 176) == 4, "总幸运-9没有稳定命中下限")
	_assert_player_attack(9, 12)
	_assert_player_attack(-9, 4)

	# Reverse/equal ranges freeze before luck is consulted. Once total max
	# recovers above total min, the same signed luck endpoint bias resumes.
	for total_luck in [-9, 0, 9]:
		assert(_roll(35, 10, total_luck, 176) == 35, "反向区间被幸运/诅咒解除固定端点")
		assert(_roll(35, 35, total_luck, 176) == 35, "零跨度被幸运/诅咒解除固定端点")
	assert(_roll(35, 40, 9, 176) == 40, "恢复正跨度后总幸运+9未恢复上限效果")
	assert(_roll(35, 40, -9, 176) == 35, "恢复正跨度后总幸运-9未恢复下限效果")

	var wizard_low_roll := _roll(4, 12, -9, 176)
	var wizard_high_roll := _roll(4, 12, 9, 176)
	# Q3-C: legacy the legacy resolver was removed; the luck endpoints
	# are asserted through the production formula functions it used.
	assert(
		WizardCombatMath.damage_with_rolls(
			"wizard.fireball", wizard_low_roll, 3, 0, 0, false
		) == 4
		and WizardCombatMath.damage_with_rolls(
			"wizard.fireball", wizard_high_roll, 3, 0, 0, false
		) == 12,
		"MC 幸运端点未进入法师伤害公式"
	)

	var taoist_low_roll := _roll(4, 12, -9, 176)
	var taoist_high_roll := _roll(4, 12, 9, 176)
	assert(
		TaoistCombatMath.damage_with_rolls(
			"taoist.soul_fire_talisman", taoist_low_roll, 3, 0, 0
		) == 4
		and TaoistCombatMath.damage_with_rolls(
			"taoist.soul_fire_talisman", taoist_high_roll, 3, 0, 0
		) == 12,
		"SC 幸运端点未进入道士伤害公式"
	)

	assert(
		TaoistCombatMath.healing_with_rolls(
			"taoist.healing", taoist_low_roll, 3, 0, 0
		) == 8
		and TaoistCombatMath.healing_with_rolls(
			"taoist.healing", taoist_high_roll, 3, 0, 0
		) == 24,
		"SC 幸运端点未进入治愈术公式"
	)

	var holy_word_low := CasterSkillBehavior.resolve("wizard.holy_word", {
		"skill_level": 3,
		"caster_level": 40,
		"target_level": 35,
		"target_is_undead": true,
		"random_0_to_99": 40,
		"magic_stat_roll": wizard_low_roll,
	})
	var holy_word_high := CasterSkillBehavior.resolve("wizard.holy_word", {
		"skill_level": 3,
		"caster_level": 40,
		"target_level": 35,
		"target_is_undead": true,
		"random_0_to_99": 40,
		"magic_stat_roll": wizard_high_roll,
	})
	assert(holy_word_low.success and holy_word_high.success, "固定效果成功率被 MC 幸运端点误影响")

	var poison_low := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": taoist_low_roll,
		"poison_type": "green",
		"target_anti_poison": 5,
		"anti_poison_random": 6,
	})
	var poison_high := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": taoist_high_roll,
		"poison_type": "green",
		"target_anti_poison": 5,
		"anti_poison_random": 6,
	})
	assert(poison_low.success and poison_high.success, "施毒独立成功门被 SC 幸运端点误影响")
	assert(poison_low.power < poison_high.power, "施毒强度没有使用已掷出的 SC 主属性")
	var poison_resisted_low := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": taoist_low_roll,
		"poison_type": "green",
		"target_anti_poison": 5,
		"anti_poison_random": 7,
	})
	var poison_resisted_high := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": taoist_high_roll,
		"poison_type": "green",
		"target_anti_poison": 5,
		"anti_poison_random": 7,
	})
	assert(not poison_resisted_low.success and not poison_resisted_high.success, "施毒抗性失败门被 SC 幸运端点误影响")

	print("COMBAT_LUCK_PRIMARY_STAT_PASS：signed总幸运统一作用于DC/MC/SC，固定效果与施毒成功门保持独立")
	get_tree().quit(0)
