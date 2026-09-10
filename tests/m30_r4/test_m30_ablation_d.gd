extends Node
# Fresh process required for every cold sample. No live coordinator reset.
# CPU factory time, visual-application latency and process cadence are separate.
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Sampler := preload("res://tests/m30_r4_r1/r1_lab_sampler.gd")
const Rules := preload("res://scripts/world_spatial_rules.gd")
var failures: int = 0
var records: Array[Dictionary] = []
var children: Array[EnemyActor] = []
var _sampler: Node

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("M30_ABLATION_D_R1 " + label)

func _spawn_and_wait(game: Node, label: String, key: String) -> bool:
	var radius: float = Rules.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.MONSTER_COLLISION_RADIUS_PX)
	var position: Vector2 = game._find_valid_enemy_landing(game.player.global_position, 1.6, 3.2, radius, null)
	if not position.is_finite() or position == game.player.global_position:
		check(false, label + " no verified landing")
		return false
	var coordinator: MonsterVisualStreamingCoordinator = MonsterVisual.streaming_coordinator()
	var before_requests: int = coordinator.threaded_texture_request_count()
	var before_sync: int = coordinator.sync_load_count()
	var started: int = Time.get_ticks_usec()
	var child: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(127), position, false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:r1_d:%s" % label})
	var returned: int = Time.get_ticks_usec()
	check(is_instance_valid(child), label + " canonical child must be created")
	if not is_instance_valid(child):
		return false
	children.append(child)
	var deadline: int = Time.get_ticks_msec() + 8000
	while not child.visual.uses_final_art() and Time.get_ticks_msec() < deadline:
		await _sampler.after_visual
	check(child.visual.uses_final_art(), label + " waits for real resource application")
	check(coordinator.visual_subscription_is_current(child.visual.get_instance_id(), key), label + " subscription remains valid")
	check(coordinator.sync_load_count() == before_sync, label + " production-like asynchronous path has no sync loads")
	if label.begins_with("warm"):
		check(coordinator.threaded_texture_request_count() == before_requests, label + " requests no additional atlas load")
	records.append({
		"label": label,
		"factory_cpu_ms": float(returned - started) / 1000.0,
		"factory_return_to_visual_observed_ready_ms": float(Time.get_ticks_usec() - returned) / 1000.0,
		"texture_request_delta": coordinator.threaded_texture_request_count() - before_requests,
		"sync_load_delta": coordinator.sync_load_count() - before_sync,
		"instance_id": child.get_instance_id(),
	})
	return child.visual.uses_final_art()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "m30_d_r1")
	MonsterVisual.set_synchronous_loading_for_tests(false)
	_sampler = Sampler.new()
	add_child(_sampler)
	for value: Node in get_tree().get_nodes_in_group("enemies"):
		value.queue_free()
	await _sampler.after_visual
	await _sampler.after_visual
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Fixture.FIXTURE_GROUND_POSITION + Fixture.CASTER_GROUND_OFFSET))
	var coordinator: MonsterVisualStreamingCoordinator = MonsterVisual.streaming_coordinator()
	check(is_instance_valid(coordinator), "formal coordinator exists")
	if not is_instance_valid(coordinator):
		get_tree().quit(1)
		return
	var helper: MonsterVisual = MonsterVisual.new()
	var mapping: Dictionary = helper._client_mapping_for(GameData.get_monster_by_id(127))
	var key: String = helper._client_resource_cache_key(mapping)
	helper.free()
	check(not mapping.is_empty(), "child127 has a formal mapping")
	if mapping.is_empty():
		get_tree().quit(1)
		return
	var cached_paths: int = 0
	var actions: Dictionary = mapping.get("actions", {})
	for action: String in ["idle", "walk", "attack", "hit", "death"]:
		var path: String = str(actions.get(action, {}).get("path", ""))
		if ResourceLoader.has_cached(path):
			cached_paths += 1
	var cold_proven: bool = cached_paths == 0 and coordinator.client_resources(key).is_empty() and not coordinator._threaded_profile_requests.has(key)
	print("M30_D_COLD_PRECONDITION engine_cached_paths=%d coordinator_profile_or_job_absent=%s cold_proven=%s" % [cached_paths, str(coordinator.client_resources(key).is_empty() and not coordinator._threaded_profile_requests.has(key)), str(cold_proven)])
	var cold_ready: bool = await _spawn_and_wait(game, "cold_candidate", key)
	if not cold_ready:
		get_tree().quit(1)
		return
	# First actor stays live, keeping a genuine lease. All warm births follow ready.
	for i: int in range(5):
		check(not coordinator.client_resources(key).is_empty(), "warm profile is genuinely resident")
		var warm_ready: bool = await _spawn_and_wait(game, "warm_%d" % i, key)
		if not warm_ready:
			break
	check(children.size() == 6, "six valid child references, not six null array entries")
	var starts: Dictionary = {}
	for child: EnemyActor in children:
		starts[child.get_instance_id()] = child._hc_starts
	_sampler.begin_window()
	var end: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end:
		await _sampler.after_visual
	_sampler.capture = false
	var attacking: int = 0
	for child: EnemyActor in children:
		if is_instance_valid(child) and child.target == caster and child._hc_starts > int(starts[child.get_instance_id()]):
			attacking += 1
	check(attacking >= 1, "sustained window contains accepted real attacks, not just living nodes")
	var process_stats: Dictionary = Sampler.statistics(_sampler.render_intervals_ms)
	var physics_stats: Dictionary = Sampler.statistics(_sampler.physics_intervals_ms)
	check(bool(process_stats.get("valid", false)) and int(process_stats.get("count", 0)) >= 60, "nonempty process-cadence sample")
	print("M30_D_R1_DATA " + JSON.stringify({"births": records, "cold_proven": cold_proven, "attacking_children": attacking, "process_wall_cadence": process_stats, "physics_wall_cadence": physics_stats, "performance_gate": "NOT_EVALUATED_BY_THIS_FIXTURE", "gpu_time": "NOT_MEASURED"}))
	print("M30_D_R1_RAW_PROCESS_MS " + JSON.stringify(_sampler.render_intervals_ms))
	print("M30_D_R1_RAW_PHYSICS_MS " + JSON.stringify(_sampler.physics_intervals_ms))
	if failures > 0:
		print("M30_ABLATION_D_FAIL failures=%d" % failures)
		get_tree().quit(1)
	elif not cold_proven:
		print("M30_ABLATION_D_BLOCKED cold_state_not_proven warm_and_combat_measurements_retained")
		get_tree().quit(2)
	else:
		print("M30_ABLATION_D_PASS meaning=measurement_integrity_only_not_performance_acceptance")
		get_tree().quit(0)

func _ready() -> void:
	_run.call_deferred()
