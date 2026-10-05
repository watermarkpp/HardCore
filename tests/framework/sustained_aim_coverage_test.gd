extends "res://tests/framework/natural_sustained_chain_test.gd"

## A controlled counterexample for the test driver, not a combat/performance gate.
## One real release creates the active ActorRefs. Only the driver's historical
## peak counter is controlled; no production state, clock or pump is replaced.
const SCENE_ID := "sustained_aim_coverage_test"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"aim-driver counterexample owns isolated production-profile data")
	PlayerState.begin_startup_save_upgrade()
	var started: bool = PlayerState.finish_startup_save_upgrade()
	var reason: String = PlayerState.create_character("持续瞄准覆盖", "hc.profession.wizard") if started else "startup"
	check(started and reason.is_empty(), "real profile starts: " + reason)
	if not failures.is_empty(): _finish(); return
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm": 3}
	PlayerState.equipment["hc.slot.weapon"] = Drop.create_instance(GameData.get_item_record({"item_id": 85}), "aim:weapon")
	PlayerState.recalculate_stats(false)
	check(await ContentLayers.reload_feature_catalog_async("res://assets/data/features/validation/resource_natural_registry.json"),
		"same default-off natural source prepares through its production service")
	if not failures.is_empty(): _finish(); return
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 15000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "real mapped Root reaches READY")
	if not failures.is_empty(): _finish(); return
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5)))
	var points: Array[Vector2] = [Vector2(40.5, 12.2), Vector2(41.22, 12.2), Vector2(44.1, 14.76)]
	for index in points.size():
		var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19),
			game._canonical_ground_gu_to_screen_px(points[index]), false, -1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:aim:%d" % index})
		check(actor != null and actor._hc_point_walkable(points[index]), "formal walkable receiver %d" % index)
		if actor == null: _finish(); return
		actor.max_hp = 100000
		actor.current_hp = actor.max_hp
		actor.set_physics_process(false)
		targets.append(actor)
	check(_current_aim_target() == targets[0], "before effects, equally uncovered targets prefer the denser legal footprint")
	game._set_magic_locked_target(targets[0], true)
	var accepted: StringName = game._try_release_skill("hc.skill.wizard.ice_storm", false)
	check(accepted == &"accepted", "one actual Root release owns the real windup, planner and effects")
	deadline = Time.get_ticks_msec() + 5000
	var own_active := {}
	while Time.get_ticks_msec() < deadline:
		runtime = game._feature_effect_runtime
		own_active.clear()
		if runtime != null:
			for state: Dictionary in runtime._states.values():
				var receiver: Node = state.target.resolve()
				if receiver in targets: own_active[receiver.get_instance_id()] = true
		if own_active.has(targets[0].get_instance_id()) and own_active.has(targets[1].get_instance_id()): break
		await get_tree().process_frame
	check(own_active.size() == 2 and not own_active.has(targets[2].get_instance_id()),
		"real committed effects cover the dense pair and leave the separated third receiver uncovered")
	if not failures.is_empty(): _finish(); return
	round_peak_states = 89
	var before_peak: EnemyActor = _current_aim_target()
	check(before_peak == targets[2], "uncovered edge receiver is selected while the historical peak is below ninety")
	round_peak_states = 90
	var after_peak: EnemyActor = _current_aim_target()
	check(after_peak == targets[2], "the same uncovered receiver retains priority after the historical peak reaches ninety")
	var metrics_before: Dictionary = runtime.metrics()
	for repetition in 50:
		_current_aim_target()
	check(runtime.metrics() == metrics_before and targets[2].current_hp == targets[2].max_hp,
		"repeated driver queries submit no damage, effects, clock changes or new actions")
	print("SUSTAINED_AIM_COVERAGE_TRACE ", JSON.stringify({
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scene_id": SCENE_ID, "points": points,
		"covered_receivers": own_active.keys(), "edge_receiver": targets[2].get_instance_id(),
		"before_peak_selected": before_peak.get_instance_id(), "after_peak_selected": after_peak.get_instance_id(),
		"historical_counter_controlled_by_fixture": true,
		"scope": "test-driver coverage counterexample with one real production release; stationary three-receiver setup is not natural movement/performance acceptance"
	}))
	game.queue_free()
	await get_tree().process_frame
	runtime = null
	targets.clear()
	check(ContentLayers.reload_feature_catalog(), "retired world withdraws its prepared default-off source")
	_finish()

func _finish() -> void:
	observing = false
	if is_instance_valid(game): game.queue_free()
	var written := proof.write_receipt(SCENE_ID, checks, failures.size())
	print("SUSTAINED_AIM_COVERAGE_", "PASS" if written and failures.is_empty() else "FAIL", " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
