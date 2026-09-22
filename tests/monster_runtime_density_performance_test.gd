extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const MAP_ID := 93001


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var old_device_lab_override := RuntimeDiagnostics.device_lab_performance_override_enabled()
	assert(RuntimeDiagnostics.set_device_lab_performance_enabled(true))
	RuntimeDiagnostics.reset_performance_window()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(50000.0, 50000.0)

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.configure_runtime_map_projection(
		MAP_ID,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame

	var spatial_index := SpatialIndexScript.new()
	enemy.configure_spatial_index(spatial_index, 1)
	spatial_index.register(
		1,
		MAP_ID,
		enemy.spatial_index_position(),
		enemy.combat_radius_gu,
		1,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	enemy.target = null
	enemy._threat_table.clear()
	assert(enemy._can_use_background_ai(), "far idle actor did not enter background tier")
	enemy._enter_background_deep_sleep(true)
	assert(enemy._background_deep_sleeping, "far idle actor did not enter deep sleep")
	assert(
		not enemy.is_physics_processing(),
		"far idle actor still owns a 60 Hz physics callback",
	)
	EnemyActor.reset_performance_diagnostics()
	var index_checks_before := spatial_index.index_update_check_count
	for _tick in range(8):
		enemy._background_last_wakeup_msec = (
			Time.get_ticks_msec()
			- int(EnemyActor.BACKGROUND_AI_INTERVAL_SECONDS * 1000.0)
		)
		enemy._on_background_wakeup_timeout()
	var background_metrics := EnemyActor.performance_diagnostics()
	var background_index_checks := spatial_index.index_update_check_count - index_checks_before
	assert(
		int(background_metrics.background_fast_path_skips) == 0,
		"deep-sleep actor unexpectedly re-entered the 60 Hz fast path: %s"
		% background_metrics,
	)
	assert(
		int(background_metrics.background_ai_evaluations) == 8,
		"background maintenance did not remain one evaluation per 4 Hz wake: %s"
		% background_metrics,
	)
	assert(
		int(background_metrics.enemy_background_tick_calls) == 8,
		"background timing probe did not follow wake count: %s" % background_metrics,
	)
	assert(
		int(background_metrics.enemy_background_tick_usec) > 0,
		"background timing probe did not record work: %s" % background_metrics,
	)
	assert(
		int(background_metrics.enemy_retarget_calls) == 8,
		"retarget timing probe did not follow background wakes: %s" % background_metrics,
	)
	assert(
		int(background_metrics.enemy_retarget_usec) > 0,
		"retarget timing probe did not record work: %s" % background_metrics,
	)
	assert(
		background_index_checks <= 1,
		"unchanged background position was resubmitted to the spatial index: %d"
		% background_index_checks,
	)

	# A production-sized density is distributed over every available physics
	# phase slot. No far actor keeps a per-frame physics callback, while each
	# explicit 4 Hz wake performs exactly one maintenance evaluation.
	var sleeping_enemies: Array[EnemyActor] = []
	var phase_counts := {}
	for serial: int in range(1, 61):
		var sleeper := EnemyActor.new()
		sleeper.setup(GameData.get_monster_by_id(18), player, false)
		sleeper.configure_runtime_map_projection(
			MAP_ID,
			Callable(self, "_ground_to_screen"),
			Callable(self, "_screen_to_ground"),
		)
		sleeper.set_meta("spawn_serial", serial)
		sleeper.global_position = Vector2(float(serial), 0.0)
		sleeper.set_meta("spawn_position", sleeper.global_position)
		sleeper.set_meta("safe_zones", [])
		add_child(sleeper)
		assert(sleeper._background_deep_sleeping)
		assert(not sleeper.is_physics_processing())
		var phase_slot := sleeper._background_wakeup_phase_slot()
		phase_counts[phase_slot] = int(phase_counts.get(phase_slot, 0)) + 1
		sleeping_enemies.append(sleeper)
	assert(
		phase_counts.size() == EnemyActor.BACKGROUND_WAKE_PHASE_SLOTS,
		"60 actors did not use every deterministic wake phase: %s" % phase_counts,
	)
	for count: int in phase_counts.values():
		assert(count <= 4, "background wake phase remained batched: %s" % phase_counts)
	EnemyActor.reset_performance_diagnostics()
	for sleeper: EnemyActor in sleeping_enemies:
		sleeper._background_last_wakeup_msec = (
			Time.get_ticks_msec()
			- int(EnemyActor.BACKGROUND_AI_INTERVAL_SECONDS * 1000.0)
		)
		sleeper._on_background_wakeup_timeout()
	var density_metrics := EnemyActor.performance_diagnostics()
	assert(int(density_metrics.background_ai_evaluations) == sleeping_enemies.size())
	assert(int(density_metrics.background_deep_sleep_wakeups) == sleeping_enemies.size())
	assert(int(density_metrics.foreground_ai_ticks) == 0)

	# Threat/status participation must leave the sleep path on the very next
	# physics callback; no background timer is allowed to pin a combatant asleep.
	var attacker := Node2D.new()
	attacker.set_meta("runtime_map_id", MAP_ID)
	attacker.global_position = enemy.global_position + _ground_to_screen(Vector2(2.0, 0.0))
	add_child(attacker)
	enemy._add_threat(attacker, 200.0)
	assert(not enemy._can_use_background_ai(), "damage threat did not wake the actor")
	var foreground_before := int(background_metrics.foreground_ai_ticks)
	enemy._physics_process(1.0 / 60.0)
	var projection_probe := enemy._screen_position_px_to_ground_position_gu(enemy.global_position)
	assert(projection_probe.is_finite())
	var wake_metrics := EnemyActor.performance_diagnostics()
	assert(
		int(wake_metrics.foreground_ai_ticks) == foreground_before + 1,
		"damage wake did not resume foreground AI immediately: %s" % wake_metrics,
	)
	assert(int(wake_metrics.enemy_physics_calls) == 1)
	assert(int(wake_metrics.enemy_physics_usec) > 0)
	assert(int(wake_metrics.enemy_projection_calls) > 0)
	assert(int(wake_metrics.enemy_projection_usec) > 0)
	enemy._threat_table.clear()
	enemy.target = null
	enemy.poison_time = 1.0
	assert(not enemy._can_use_background_ai(), "active status was incorrectly background-throttled")
	enemy.poison_time = 0.0

	# The production step path must consume the 10 Hz cache rather than calling
	# the crowd query directly for every retry.
	enemy._crowd_steering_timer = 0.0
	EnemyActor.reset_performance_diagnostics()
	assert(enemy._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, true, &"test"))
	enemy._clear_autonomous_step_state()
	assert(enemy._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, true, &"test"))
	var crowd_metrics := EnemyActor.performance_diagnostics()
	assert(
		int(crowd_metrics.crowd_steering_evaluations) == 1,
		"production step retries bypassed the 10 Hz crowd cache: %s" % crowd_metrics,
	)
	enemy._clear_autonomous_step_state()

	# Residency is camera-rectangle based. The complete screen and activation
	# guard are retained, while a far authored visual sleeps between 8.3 Hz timer
	# wakeups instead of executing one script process per rendered frame.
	var viewport_rect := get_viewport().get_visible_rect()
	var visual_enemy := EnemyActor.new()
	visual_enemy.setup(GameData.get_monster_by_id(18), player, false)
	visual_enemy.global_position = viewport_rect.end + Vector2(
		MonsterVisual.VISUAL_RELEASE_DISTANCE_PX + 32.0,
		MonsterVisual.VISUAL_RELEASE_DISTANCE_PX + 32.0,
	)
	visual_enemy.set_meta("spawn_position", visual_enemy.global_position)
	add_child(visual_enemy)
	visual_enemy.set_physics_process(false)
	await get_tree().process_frame
	assert(
		not visual_enemy.visual.is_processing(),
		"far inactive authored visual still processed every render frame",
	)
	assert(
		not visual_enemy.visual._residency_wakeup_timer.is_stopped(),
		"inactive visual did not retain its low-frequency residency wakeup",
	)
	visual_enemy.global_position = viewport_rect.get_center()
	visual_enemy.visual._on_residency_wakeup_timeout()
	assert(visual_enemy.visual.uses_final_art(), "on-screen visual did not acquire resources")
	assert(visual_enemy.visual.is_processing(), "active on-screen visual did not resume animation")
	visual_enemy.global_position = viewport_rect.end + Vector2(
		MonsterVisual.VISUAL_RELEASE_DISTANCE_PX + 32.0,
		MonsterVisual.VISUAL_RELEASE_DISTANCE_PX + 32.0,
	)
	visual_enemy.visual._resource_residency_timer = 0.0
	visual_enemy.visual._process(MonsterVisual.RESOURCE_RESIDENCY_CHECK_SECONDS)
	assert(not visual_enemy.visual.is_processing(), "released off-screen visual did not sleep")

	print(
		"MONSTER_RUNTIME_DENSITY_PERFORMANCE_PASS background=%s density=%s phases=%s index_checks=%d crowd=%s"
		% [background_metrics, density_metrics, phase_counts, background_index_checks, crowd_metrics]
	)
	RuntimeDiagnostics.set_device_lab_performance_enabled(old_device_lab_override)
	RuntimeDiagnostics.refresh_performance_gate()
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
