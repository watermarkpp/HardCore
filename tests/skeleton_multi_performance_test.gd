extends Node

const SAMPLE_FRAMES := 1800
const WARMUP_FRAMES := 300
const FRAME_DELTA := 1.0 / 60.0

var _game: Node
var _player: PlayerCharacter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	var skill_name := ProfessionRules.skill_display_name("taoist.summon_skeleton")
	PlayerState.learned_skills = {skill_name: 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _game.player
	_player.set_physics_process(false)
	_player.global_position = Vector2(240.0, 240.0)
	_player.facing = Vector2.RIGHT
	_player.current_mp = 999
	for raw_enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if raw_enemy is EnemyActor:
			var enemy := raw_enemy as EnemyActor
			enemy.set_combat_position(enemy.global_position + Vector2(5000.0, 5000.0), &"multi_summon_performance_fixture")
			enemy.set_physics_process(false)
	PlayerState.computed_stats["skill_level_affix"] = {"contributions": {"all": 4}, "legacy": {}}
	assert(PlayerState.effective_skill_level(skill_name) == 7)
	for slot_index in range(3):
		var result: Dictionary = _game._execute_canonical_skill(
			skill_name, _player.global_position, _player.facing, 0,
			{"release_id": "multi:perf:%d" % slot_index}
		)
		assert(bool(result.get("accepted", false)), "骷髅性能场景召唤失败：%s" % result)
	var pets: Array = _game._canonical_main_pets("skeleton")
	assert(pets.size() == 3, "7级应生成三只真实骷髅")
	_game.set_physics_process(false)
	for pet: SummonActor in pets:
		pet.set_physics_process(false)
		assert(bool(pet.performance_diagnostics().get("spatial_index_available", false)))

	# Same loaded world and the same three live actors for every sample. Only
	# the number of actors advanced by the measured loop changes.
	for warmup_frame in range(WARMUP_FRAMES):
		for pet: SummonActor in pets:
			pet._physics_process(FRAME_DELTA)
	var samples: Dictionary = {1: [], 2: [], 3: []}
	var scans: Dictionary = {1: [], 2: [], 3: []}
	for count: int in [1, 2, 3, 3, 2, 1]:
		for pet: SummonActor in pets:
			pet.reset_performance_diagnostics_for_tests()
		var started_usec := Time.get_ticks_usec()
		for frame in range(SAMPLE_FRAMES):
			for pet_index in range(count):
				(pets[pet_index] as SummonActor)._physics_process(FRAME_DELTA)
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		var scan_count := 0
		var candidate_count := 0
		for pet_index in range(count):
			var diagnostics: Dictionary = (pets[pet_index] as SummonActor).performance_diagnostics()
			scan_count += int(diagnostics.get("target_scan_count", 0))
			candidate_count += int(diagnostics.get("target_candidate_count", 0))
		assert(scan_count <= count * 130, "索敌次数随骷髅数量异常增长")
		assert(candidate_count == 0, "隔离场景出现非预期的索敌候选")
		(samples[count] as Array).append(elapsed_usec)
		(scans[count] as Array).append(scan_count)
	var one_usec := _average(samples[1] as Array)
	var two_usec := _average(samples[2] as Array)
	var three_usec := _average(samples[3] as Array)
	assert(one_usec > 0.0)
	assert(two_usec <= one_usec * 4.0, "两只骷髅的单帧 CPU 成本异常放大")
	assert(three_usec <= one_usec * 6.0, "三只骷髅的单帧 CPU 成本异常放大")
	print("SKELETON_MULTI_PERFORMANCE_METRICS %s" % JSON.stringify({
		"frames_per_sample": SAMPLE_FRAMES,
		"usec_per_simulated_frame": {"one": one_usec, "two": two_usec, "three": three_usec},
		"scan_count_samples": scans,
		"raw_elapsed_usec": samples,
	}))
	print("SKELETON_MULTI_PERFORMANCE_PASS")
	get_tree().quit(0)


func _average(values: Array) -> float:
	return (float(values[0]) + float(values[1])) / (2.0 * float(SAMPLE_FRAMES))
