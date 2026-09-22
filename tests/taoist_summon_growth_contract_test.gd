extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const MAP_ID := 910001
const TARGET_MONSTER_ID := 38


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _test_screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(value)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
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
	assert(TaoistCombatMath.effective_summon_move_interval_ms("skeleton", 3) == 350)
	assert(TaoistCombatMath.effective_summon_attack_interval_ms("divine_beast", 3) == 1200)
	assert(TaoistCombatMath.effective_summon_move_interval_ms("divine_beast", 3) == 350)

	var owner := PlayerCharacter.new()
	add_child(owner)
	owner.set_physics_process(false)
	owner.current_hp = 100
	var skeleton := SummonActor.new()
	skeleton.setup(owner, "变异骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	add_child(skeleton)
	assert(skeleton.max_hp == 140 and skeleton.maximum_pet_level == 1)
	skeleton.current_hp = 100
	# Project pacing doubles each kill's level credit, while the verified
	# original threshold and strict > comparison stay unchanged. An odd saved
	# remainder is valid across the old/new policy boundary.
	skeleton.pet_growth_exp = 1
	assert(not skeleton.gain_growth_from_kill(162), "原始严格大于阈值被错误实现为大于等于")
	assert(skeleton.summon_exp_level == 0 and skeleton.pet_growth_exp == 325)
	assert(skeleton.gain_growth_from_kill(1), "超过阈值后未升级")
	assert(skeleton.summon_exp_level == 1 and skeleton.pet_growth_exp == 2)
	assert(skeleton.max_hp == 196 and skeleton.current_hp == 100, "升级错误治疗了召唤物")
	assert(not skeleton.gain_growth_from_kill(9999), "技能等级上限未阻止继续升级")
	assert(skeleton.pet_growth_exp == 2, "已达上限的召唤物错误积累击杀成长")

	var level_three := SummonActor.new()
	level_three.setup(owner, "变异骷髅", 1, 3, "taoist.summon_skeleton", 26, 7)
	add_child(level_three)
	assert(level_three.gain_growth_from_kill(10000))
	assert(level_three.summon_exp_level == 4, "一次击杀经验错误连续提升多级")
	assert(level_three.pet_growth_exp == 20000 - 425, "双倍成长积分的升级余数没有保留")
	assert(level_three.growth_contract_snapshot().persistence == "transient_non_permanent_pet")

	var killer := SummonActor.new()
	killer.setup(owner, "变异骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	killer.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_test_ground_to_screen"),
		Callable(self, "_test_screen_to_ground"),
	)
	var spatial_index := RuntimeCombatSpatialIndex.new()
	killer.configure_spatial_index(spatial_index)
	add_child(killer)
	killer.set_physics_process(false)
	killer.pet_growth_exp = TaoistCombatMath.summon_growth_threshold("skeleton", 0)
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(TARGET_MONSTER_ID), owner, false)
	assert(enemy.monster_id == TARGET_MONSTER_ID)
	assert(not bool(enemy.get_meta("canonical_rejected", false)))
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_test_ground_to_screen"),
		Callable(self, "_test_screen_to_ground"),
	)
	enemy.control_time = 60.0
	enemy.global_position = _test_ground_to_screen(Vector2(1.0, 0.0))
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.current_hp = 1
	assert(enemy.can_receive_damage() and enemy.defense == 0)
	var target_level := int(enemy.monster_data.get("level", 0))
	assert(target_level > 0)
	var actor_id := enemy.get_instance_id()
	enemy.configure_spatial_index(spatial_index, actor_id)
	spatial_index.register(
		actor_id, MAP_ID, Vector2(1.0, 0.0), enemy.combat_radius_gu,
		1, enemy, Callable(enemy, "spatial_index_position"),
	)
	assert(killer._current_target == null)
	killer._physics_process(0.016)
	assert(enemy.current_hp == 1 and killer._pending_attack_target == enemy)
	assert(
		killer.attack_release_snapshot_intersects_target(killer._pending_attack_snapshot, enemy),
		"击杀成长测试的释放快照未覆盖真实索引目标: %s" % JSON.stringify(killer._pending_attack_snapshot)
	)
	killer._release_pending_attack()
	assert(enemy.current_hp == 0, "召唤物命中帧未击杀测试目标")
	assert(
		killer.summon_exp_level == 1 and killer.pet_growth_exp == target_level * 2,
		"击杀者没有获得双倍 canonical 怪物等级成长值",
	)
	killer._release_pending_attack()
	assert(killer.pet_growth_exp == target_level * 2, "重复释放错误重复授予击杀成长")

	skeleton.queue_free()
	level_three.queue_free()
	killer.queue_free()
	enemy.queue_free()
	owner.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print("TAOIST_SUMMON_GROWTH_CONTRACT_PASS: verified baselines, doubled kill credit, strict threshold, one-level growth, cap and HP preservation")
	get_tree().quit(0)
