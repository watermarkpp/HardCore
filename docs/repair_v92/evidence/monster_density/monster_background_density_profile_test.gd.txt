extends "res://tests/hc_monster_ai/m30_sampling_copy.gd"

## Attribution experiment: identical 12 engaged actors and 50 idle actors.
## Only the idle actors' distance changes. This does not alter shipped maps,
## AI cadence, collision masks, animation cadence or gameplay data.
const ENGAGED_COUNT := 12
const BACKGROUND_COUNT := 50
var _coordinator: MonsterVisualStreamingCoordinator


func _process(delta: float) -> void:
	if _coordinator != null:
		_coordinator.poll_once(Engine.get_process_frames())
	super._process(delta)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	var mode := OS.get_environment("HARDCORE_DENSITY_DISTANCE")
	assert(mode in ["near", "far"])
	var label := _safe_label(OS.get_environment("HARDCORE_DENSITY_LABEL"))
	assert(not label.is_empty())
	var occluded_pursuit := OS.get_environment("HARDCORE_DENSITY_OCCLUDED_PURSUIT") == "1"
	_coordinator = MonsterVisualStreamingCoordinator.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	var index := SpatialIndex.new()
	var player := _make_player(_target_ground())
	var camera := Camera2D.new()
	camera.position = player.position
	camera.zoom = Vector2.ONE * ArtSpec.CAMERA_ZOOM
	add_child(camera)
	camera.make_current()
	var context := _terrain_context()
	var safe_context := {"valid": true, "zones": [], "revision": 1}
	var enemies: Array[EnemyActor] = []
	var core_layout: Array[Vector2] = []
	for serial in range(ENGAGED_COUNT + BACKGROUND_COUNT):
		var ground: Vector2
		if serial < ENGAGED_COUNT:
			ground = _layout_position("sustained_close_attacks", serial)
			core_layout.append(ground)
		else:
			var background_serial := serial - ENGAGED_COUNT
			# Both rectangles fit in the same valid 80x80 terrain. The near
			# rectangle is outside this exact monster's acquisition square.
			var offset := Vector2(6 + background_serial % 5, -4 + background_serial / 5)
			if mode == "far": offset += Vector2(34, 24)
			ground = _target_ground() + offset
		var enemy := _make_enemy(player, index, context, ground, serial + 1)
		enemy._rng.seed = LAYOUT_SEED + serial
		enemy.set_meta("safe_zone_context", safe_context)
		if serial >= ENGAGED_COUNT:
			if not occluded_pursuit: enemy.target = null
			assert(enemy._target_acquisition_policy.view_range_cells < 6)
		enemies.append(enemy)
	_assert_initial_layout_valid(enemies, player)
	if occluded_pursuit:
		# Let production observation acquire the player once, then introduce
		# the same real WORLD barrier in near/far samples. The original m30
		# world-obstacle fixture uses this last-known-position setup too.
		await _await_real_frame()
		var wall: Array[Vector2i] = []
		for y in range(80): wall.append(Vector2i(24, y))
		_set_environment(wall)
		context = _terrain_context()
		for enemy: EnemyActor in enemies: enemy.configure_terrain_navigation_context(context)
	for frame in range(120):
		await _await_real_frame()
	var start_state := _density_state(enemies)
	var expected_engaged := ENGAGED_COUNT + BACKGROUND_COUNT if occluded_pursuit and mode == "near" else ENGAGED_COUNT
	assert(start_state.engaged == expected_engaged,
		"workload drift before sampling: %s" % str(start_state))
	_reset_probe_counters(enemies, player)
	EnemyActor.reset_performance_diagnostics()
	_full_frame_samples_ms.clear()
	_frame_delta_diagnostic_ms.clear()
	_process_monitor_samples_ms.clear()
	_last_process_usec = 0
	_capture_frame_timing = true
	for frame in range(240):
		await _await_real_frame()
	_capture_frame_timing = false
	var counters := EnemyActor.performance_diagnostics()
	var end_state := _density_state(enemies)
	assert(end_state.engaged == expected_engaged,
		"workload drift after sampling: %s" % str(end_state))
	for serial in range(ENGAGED_COUNT, enemies.size()):
		assert(enemies[serial].probe_damage_applications == 0, "background actors must not add real attacks")
	var output := {"mode": mode, "label": label, "seed": LAYOUT_SEED,
		"occluded_pursuit": occluded_pursuit, "world_bodies": _world_bodies.size(),
		"display_server": DisplayServer.get_name(), "sample_physics_frames": 240,
		"enemy_count": enemies.size(), "engaged_layout": str(core_layout),
		"start_state": start_state, "end_state": end_state,
		"frame_ms": _summary(_full_frame_samples_ms), "raw_frame_ms": _full_frame_samples_ms,
		"counters": counters, "index": index.diagnostics(),
		"streaming": _coordinator.monster_streaming_diagnostics(),
		"scheduler": _scheduler_snapshot(_path_scheduler()), "path_statuses": _path_status_counts(enemies),
		"damage_calls": player.probe_damage_calls, "damage_total": player.probe_damage_total,
		"source_hashes": _source_hashes(),
		"visual_source_sha256": FileAccess.get_sha256("res://scripts/monster_visual.gd"),
		"fixture_sha256": FileAccess.get_sha256("res://tests/monster_background_density_profile_test.gd")}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/repair_v92"))
	for enemy: EnemyActor in enemies: enemy.set_physics_process(false)
	output["post_sample_drain"] = await _drain_scheduler(_path_scheduler())
	var file := FileAccess.open("res://outputs/repair_v92/density_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	for enemy: EnemyActor in enemies: enemy.queue_free()
	player.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	MonsterVisual.set_streaming_coordinator(null)
	_coordinator = null
	print("MONSTER_BACKGROUND_DENSITY_PROFILE_PASS mode=%s frames=%s state=%s" % [mode, str(output.frame_ms), str(end_state)])
	get_tree().quit(0)


func _density_state(enemies: Array[EnemyActor]) -> Dictionary:
	var result := {"engaged": 0, "background_sleeping": 0, "physics_processing": 0,
		"visual_processing": 0, "visual_active_resources": 0, "visual_origin_in_viewport": 0,
		"path_pending": 0, "observed": 0}
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy.target): result.engaged += 1
		if enemy._background_deep_sleeping: result.background_sleeping += 1
		if enemy.is_physics_processing(): result.physics_processing += 1
		if enemy._hc_path_pending: result.path_pending += 1
		if enemy._hc_observed: result.observed += 1
		var visual: MonsterVisual = enemy.visual
		if is_instance_valid(visual):
			if visual.is_processing(): result.visual_processing += 1
			if not visual.active_resources.is_empty(): result.visual_active_resources += 1
			if visual._inside_visual_distance_px(0): result.visual_origin_in_viewport += 1
	return result
