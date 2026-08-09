extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	PlayerState.test_mode = true
	TaoistCombatMath.clear_cache_for_tests()
	assert(
		TaoistCombatMath.summon_baseline_contract_id()
		== "skills.taoist_summon.original_database_binary_verified.v1"
	)
	var expected_skeleton_hp := [140, 196, 280, 392, 532, 700, 896, 1120]
	var expected_skeleton_dc_max := [23, 24, 26, 28, 31, 35, 39, 44]
	var expected_divine_hp := [300, 420, 600, 840, 1140, 1500, 1920, 2400]
	var expected_divine_dc_max := [30, 31, 33, 35, 38, 42, 46, 51]
	for pet_level: int in range(8):
		var skeleton_stats := TaoistCombatMath.summon_stats("skeleton", pet_level)
		var divine_stats := TaoistCombatMath.summon_stats("divine_beast", pet_level)
		assert(skeleton_stats.max_hp == expected_skeleton_hp[pet_level])
		assert(skeleton_stats.dc_min == 12 and skeleton_stats.dc_max == expected_skeleton_dc_max[pet_level])
		assert(skeleton_stats.ac_min == 2 and skeleton_stats.ac_max == 4)
		assert(skeleton_stats.mac_min == 3 and skeleton_stats.mac_max == 6)
		assert(skeleton_stats.accuracy == 20 and skeleton_stats.agility == 20)
		assert(divine_stats.max_hp == expected_divine_hp[pet_level])
		assert(divine_stats.dc_min == 20 and divine_stats.dc_max == expected_divine_dc_max[pet_level])
		assert(divine_stats.ac_min == 8 and divine_stats.ac_max == 8)
		assert(divine_stats.mac_min == 5 and divine_stats.mac_max == 5)
		assert(divine_stats.accuracy == 17 and divine_stats.agility == 25)

	assert(TaoistCombatMath.maximum_summon_pet_level(0) == 1)
	assert(TaoistCombatMath.maximum_summon_pet_level(1) == 3)
	assert(TaoistCombatMath.maximum_summon_pet_level(2) == 5)
	assert(TaoistCombatMath.maximum_summon_pet_level(3) == 7)
	assert(TaoistCombatMath.summon_growth_threshold("skeleton", 0) == 325)
	assert(TaoistCombatMath.summon_growth_threshold("divine_beast", 0) == 580)
	assert(TaoistCombatMath.effective_summon_attack_interval_ms("skeleton", 3) == 1200)
	assert(TaoistCombatMath.effective_summon_move_interval_ms("skeleton", 3) == 450)
	assert(TaoistCombatMath.effective_summon_attack_interval_ms("divine_beast", 3) == 1200)
	assert(TaoistCombatMath.effective_summon_move_interval_ms("divine_beast", 3) == 350)

	var owner := PlayerCharacter.new()
	owner.current_hp = 100
	var skeleton := SummonActor.new()
	skeleton.setup(owner, "变异骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	add_child(skeleton)
	assert(skeleton.max_hp == 140 and skeleton.maximum_pet_level == 1)
	skeleton.current_hp = 100
	assert(not skeleton.gain_growth_from_kill(325), "原始严格大于阈值被错误实现为大于等于")
	assert(skeleton.summon_exp_level == 0 and skeleton.pet_growth_exp == 325)
	assert(skeleton.gain_growth_from_kill(1), "超过阈值后未升级")
	assert(skeleton.summon_exp_level == 1 and skeleton.pet_growth_exp == 1)
	assert(skeleton.max_hp == 196 and skeleton.current_hp == 100, "升级错误治疗了召唤物")
	assert(not skeleton.gain_growth_from_kill(9999), "技能等级上限未阻止继续升级")

	var level_three := SummonActor.new()
	level_three.setup(owner, "变异骷髅", 1, 3, "taoist.summon_skeleton", 26, 7)
	add_child(level_three)
	assert(level_three.gain_growth_from_kill(10000))
	assert(level_three.summon_exp_level == 4, "一次击杀经验错误连续提升多级")
	assert(level_three.pet_growth_exp == 10000 - 425, "升级余数没有保留")
	assert(level_three.growth_contract_snapshot().persistence == "transient_non_permanent_pet")

	var killer := SummonActor.new()
	killer.setup(owner, "变异骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	killer.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen"),
		GroundUnit.screen_delta_px_to_ground_delta_gu
	)
	add_child(killer)
	killer.pet_growth_exp = TaoistCombatMath.summon_growth_threshold("skeleton", 0)
	var enemy := EnemyActor.new()
	enemy.setup({"name": "growth-credit-target", "hp": 1, "level": 1, "attackMin": 1, "attackMax": 1}, owner, false)
	enemy.control_time = 60.0
	enemy.global_position = killer.global_position
	add_child(enemy)
	killer._current_target = enemy
	killer._physics_process(0.016)
	assert(enemy.current_hp == 1 and killer._pending_attack_target == enemy)
	assert(
		killer.attack_release_snapshot_intersects_target(killer._pending_attack_snapshot, enemy),
		"击杀成长测试的释放快照未覆盖同位目标: %s" % JSON.stringify(killer._pending_attack_snapshot)
	)
	killer._release_pending_attack()
	assert(enemy.current_hp == 0, "召唤物命中帧未击杀测试目标")
	assert(killer.summon_exp_level == 1 and killer.pet_growth_exp == 1, "击杀者没有获得怪物等级成长值")

	owner.free()
	print("TAOIST_SUMMON_GROWTH_CONTRACT_PASS: verified baselines, strict threshold, one-level growth, cap and HP preservation")
	get_tree().quit(0)
