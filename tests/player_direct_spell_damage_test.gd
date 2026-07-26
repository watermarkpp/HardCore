extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.computed_stats.merge({
		"anti_magic_points": 1,
		"magic_evasion_percent": 10,
		"magic_defense_min": 5,
		"magic_defense_max": 5,
		"defense_min": 90,
		"defense_max": 90,
	}, true)
	var player := PlayerCharacter.new()
	add_child(player)
	player.max_hp = 100
	player.current_hp = 100
	player.max_mp = 100
	player.current_mp = 100
	player.defense_min = 90
	player.defense_max = 90
	player.damage_reduction = 0.0

	for skill_id in [
		"wizard.fireball",
		"wizard.great_fireball",
		"wizard.lightning",
		"taoist.soul_fire_talisman",
	]:
		var evaded := player.take_direct_spell_damage(skill_id, 50, 0, 5, false)
		assert(evaded.runtime_contract == PlayerCharacter.DIRECT_SPELL_DAMAGE_RUNTIME_ID)
		assert(
			evaded.magic_evaded
			and not evaded.magic_defense_checked
			and evaded.magic_defense_roll == -1
			and evaded.applied_damage == 0
			and player.current_hp == 100,
			"%s的AntiMagic成功后仍执行MAC或扣血" % skill_id
		)

	var connected := player.take_direct_spell_damage("wizard.lightning", 50, 1, 5, false)
	assert(
		not connected.magic_evaded
		and connected.magic_defense_checked
		and connected.magic_defense_roll == 5
		and connected.final_damage == 45
		and connected.applied_damage == 45
		and player.current_hp == 55,
		"玩家直伤未按AntiMagic→随机MAC→最终扣血结算"
	)
	assert(connected.physical_defense_bypassed, "玩家直伤错误经过物理防御")

	player.current_hp = 100
	PlayerState.computed_stats["magic_defense_min"] = 3
	PlayerState.computed_stats["magic_defense_max"] = 7
	player._rng.seed = 176
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 176
	var expected_mac_roll := expected_rng.randi_range(3, 7)
	var random_mac := player.take_direct_spell_damage("wizard.fireball", 50, 1, -1, false)
	assert(
		random_mac.magic_defense_roll == expected_mac_roll
		and random_mac.final_damage == 50 - expected_mac_roll
		and random_mac.applied_damage == 50 - expected_mac_roll,
		"装备MAC没有在magic_defense_min/max内随机抽取"
	)
	PlayerState.computed_stats["magic_defense_min"] = 5
	PlayerState.computed_stats["magic_defense_max"] = 5

	player.current_hp = 100
	player.damage_reduction = 0.0
	player.take_damage(50, false)
	assert(player.current_hp == 99, "物理受击夹具未消费90点物防")
	player.current_hp = 100
	var magic_bypasses_physical := player.take_direct_spell_damage("wizard.fireball", 50, 1, 5, false)
	assert(
		magic_bypasses_physical.applied_damage == 45 and player.current_hp == 55,
		"直接法术错误复用物理defense_min/max"
	)

	player.current_hp = 100
	player.apply_magic_shield(10.0, 0.5)
	var shielded := player.take_direct_spell_damage("wizard.great_fireball", 50, 1, 5, false)
	assert(
		shielded.player_pipeline_input == 45
		and shielded.applied_damage == 23
		and player.current_hp == 77,
		"直接法术没有复用现有魔法盾减伤管线或发生双算: input=%d applied=%d hp=%d"
		% [shielded.player_pipeline_input, shielded.applied_damage, player.current_hp]
	)

	player.free()
	print("PLAYER_DIRECT_SPELL_DAMAGE_PASS: AntiMagic→MAC→shield/hit pipeline bypasses physical defense")
	get_tree().quit(0)
