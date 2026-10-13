extends "res://tests/phone_crowd_baseline_20261008.gd"

## v113 density apparatus.  This is deliberately a production-world fixture:
## the only experimental variable is legal spawn geometry and active count.
## It does not alter pursuit, attack, frame, or native budgets.

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "crowd_compute_density_v113_20261013"
const V113_SEED := 20261012
const TOTAL_DEFAULT := 34
const TOTAL_40 := 44
const BACKGROUND_DEFAULT := 4
const SAMPLE_TICKS_V113 := 300

var _proof := Proof.new()
var _v113_failures: Array[String] = []
var _active_count := 10
var _total_count := TOTAL_DEFAULT
var _density := "scattered"
var _label := ""
var _requested_label := ""
var _profile := 0
var _density_samples: Array[Dictionary] = []
var _layout_rows: Array[Dictionary] = []
var _aoe_events: Array[Dictionary] = []
var _full_physical_boundary_samples: Array[Dictionary] = []
var _root_dispatch_samples: Array[Dictionary] = []
var _process_monitor_samples: Array[float] = []
var _sample_start_usec := 0
var _sample_end_usec := 0
var _sample_start_physics_frame := 0
var _sample_end_physics_frame := 0
var _sample_start_dispatch: Dictionary = {}
var _v113_max_targeting := 0
var _v113_max_moving := 0
var _v113_max_awake := 0
var _v113_previous_player_ground := Vector2.INF
var _v113_motion_gu := 0.0
var _activity_before: Dictionary = {}
var _index_before: Dictionary = {}
var _v113_player_motion_gu := 0.0
var _v113_min_targeting := 2147483647
var _v113_min_awake := 2147483647
var _background_original_state: Dictionary = {}
var _compute_mode := "CANDIDATE"
var _compute_actor_initial: Array[Dictionary] = []

func _physics_process(delta: float) -> void:
	var before := Time.get_ticks_usec()
	if not _sampling or not is_instance_valid(_game):
		return
	# This fixture owns the boundary so the inherited 30-actor observer is not
	# used for dynamic active counts.  The parent PhysicsFrameStart is the
	# already-installed -1000000 priority boundary.
	_physics_cpu_ms.append(float(Time.get_ticks_usec() - _physics_start.started_usec) / 1000.0)
	var positions: Array[Dictionary] = []
	var player_ground := _screen_to_ground(_game.player.global_position)
	var hp := int(_game.player.current_hp)
	_player_hp_loss += maxi(0, _player_hp_start - hp)
	_player_hp_start = hp
	var active_alive := 0
	var target_count := 0
	var moving_count := 0
	var awake_count := 0
	var background_sleeping := 0
	var min_distance := INF
	var sum_distance := 0.0
	var tick := Engine.get_physics_frames() - int(_sample_start_physics_frame)
	var player_delta := player_ground.distance_to(_v113_previous_player_ground) if _v113_previous_player_ground.is_finite() else 0.0
	_v113_previous_player_ground = player_ground
	_v113_player_motion_gu += player_delta
	if player_delta > GroundUnitSpace.EPSILON_GU: _player_moving_ticks += 1
	for serial in range(_fixture_enemies.size()):
		var enemy = _fixture_enemies[serial]
		if not is_instance_valid(enemy):
			continue
		var ground := _screen_to_ground(enemy.global_position)
		var previous_ground: Vector2 = _previous_positions.get(str(enemy.get_instance_id()), ground)
		_v113_motion_gu += ground.distance_to(previous_ground)
		_previous_positions[str(enemy.get_instance_id())] = ground
		var distance := ground.distance_to(player_ground)
		if serial < _active_count:
			min_distance = minf(min_distance, distance)
			sum_distance += distance
			if enemy.can_receive_damage(): active_alive += 1
			if enemy.target == _game.player: target_count += 1
			if enemy._movement_step_active: moving_count += 1
			if not enemy._background_deep_sleeping: awake_count += 1
		elif enemy._background_deep_sleeping:
			background_sleeping += 1
		if tick >= 0 and (tick % 15 == 0 or tick == SAMPLE_TICKS_V113 - 1) and serial < _active_count:
			positions.append({"serial": serial, "monster_id": enemy.monster_id,
				"ground": [ground.x, ground.y], "target": enemy.target == _game.player,
				"sleep": enemy._background_deep_sleeping,
				"physics_processing": enemy.is_physics_processing()})
	var counters := EnemyActor.performance_diagnostics()
	_v113_max_targeting = maxi(_v113_max_targeting, target_count)
	_v113_max_moving = maxi(_v113_max_moving, moving_count)
	_v113_max_awake = maxi(_v113_max_awake, awake_count)
	_v113_min_targeting = mini(_v113_min_targeting, target_count)
	_v113_min_awake = mini(_v113_min_awake, awake_count)
	if tick % 15 == 0 or tick == SAMPLE_TICKS_V113 - 1:
		_density_samples.append({"physics_frame": Engine.get_physics_frames(), "sample_tick": tick,
			"active_positions": positions, "active_count": active_alive,
			"target_count": target_count, "active_awake_count": awake_count,
			"background_sleeping_count": background_sleeping,
			"mean_player_distance_gu": sum_distance / maxf(1.0, float(_active_count)),
			"min_player_distance_gu": min_distance,
			"enemy_physics_usec": int(counters.get("enemy_physics_usec", 0)),
			"enemy_physics_calls": int(counters.get("enemy_physics_calls", 0))})
	_full_physical_boundary_samples.append({"physics_frame": Engine.get_physics_frames(),
		"physics_cpu_ms": _physics_cpu_ms.back() if not _physics_cpu_ms.is_empty() else 0.0,
		"enemy_physics_usec": int(counters.get("enemy_physics_usec", 0)),
		"enemy_physics_calls": int(counters.get("enemy_physics_calls", 0))})
	_process_monitor_samples.append(1000.0 * Performance.get_monitor(Performance.TIME_PROCESS))
	if tick == 0 or tick == SAMPLE_TICKS_V113 - 1:
		_root_dispatch_samples.append({"physics_frame": Engine.get_physics_frames(),
			"observer_usec": Time.get_ticks_usec() - before,
			"dispatch": _dispatch_snapshot()})

func _run() -> void:
	# Same process cadence for every mode; retain the engine's 60 Hz physics.
	Engine.max_fps = 60
	_read_environment()
	PlayerState.test_mode = true
	_compute_mode = OS.get_environment("HARDCORE_COMPUTE_AB_MODE")
	if _compute_mode not in ["CONTROL", "CANDIDATE", "SHADOW"]:
		_finish_early("invalid_compute_mode")
		return
	EnemyActor.compute_optimization_test_mode = {"CONTROL": 0, "CANDIDATE": 1, "SHADOW": 2}[_compute_mode]
	RuntimeCombatSpatialIndex.compute_optimization_journal_enabled = _compute_mode != "CONTROL"
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 38
	PlayerState.recalculate_stats()
	var potion_receive: Dictionary = PlayerState.add_item("强效太阳水", 20)
	if not bool(potion_receive.get("success", false)):
		_v113_failures.append("potion_inventory_setup_failed")
	for record: Dictionary in PlayerState.inventory:
		if str(GameData.get_item_record(record).get("name", "")) == "强效太阳水":
			_potion_entity_id = GameData.item_entity_id(record)
			break
	var potion_binding: Dictionary = PlayerState.assign_quick_item_slot(0, _potion_entity_id)
	if _potion_entity_id.is_empty() or not bool(potion_binding.get("ok", false)):
		_v113_failures.append("potion_quick_slot_binding_failed")
	seed(V113_SEED)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	if not await _ready_map_safe(910001):
		_finish_early("initial_map_ready_failed")
		return
	if not _game._begin_map_transition(Callable(_game, "_travel_to_map_immediate").bind(MAP_ID), MAP_ID):
		_finish_early("map_transition_rejected")
		return
	if not await _ready_map_safe(MAP_ID):
		_finish_early("target_map_ready_failed")
		return
	var formal := get_tree().get_nodes_in_group("enemies")
	if formal.size() < _total_count:
		_v113_failures.append("formal_map_enemy_count_below_requested_total:%d" % formal.size())
	var selected: Array = []
	for index in range(mini(_total_count, formal.size())):
		selected.append(formal[index])
	for index in range(_total_count, formal.size()):
		(formal[index] as Node).queue_free()
	await get_tree().physics_frame
	_fixture_enemies = selected
	if get_tree().get_nodes_in_group("enemies").size() != _total_count:
		_v113_failures.append("actor_trim_failed")
	var layout := _place_v113_actors(selected)
	if _layout_rows.size() != _total_count or _has_layout_capacity_failure():
		_finish_early("layout_setup_failed")
		return
	_game._set_player_world_position(layout.center_screen)
	_game.background.set_focus_position(layout.center_screen)
	_game._world_camera.zoom = Vector2.ONE * 1.06
	_game.player.set_physics_process(false)
	for actor in _fixture_enemies:
		actor.set_physics_process(false)
	for warmup in range(120):
		await get_tree().physics_frame
	if not _fixture_enemies.is_empty():
		_spawn_synthetic_loot(Vector2(layout.center_ground[0], layout.center_ground[1]))
	else:
		_v113_failures.append("loot_setup_skipped_without_formal_enemy_probe")
	await get_tree().physics_frame
	_loot_initial_active = _active_loot_count()
	if _loot_initial_active != LOOT_COUNT:
		_v113_failures.append("initial_active_loot_count:%d" % _loot_initial_active)
	# Wake the real actors briefly after resource warmup. This interval is
	# outside the measured window and does not relocate or reset them.
	_game.player.set_physics_process(true)
	for serial in range(_fixture_enemies.size()):
		var actor = _fixture_enemies[serial]
		if serial < _active_count:
			actor.set_physics_process(true)
		else:
			var original: Dictionary = _background_original_state.get(str(actor.get_instance_id()), {})
			# Keep any real sleep transition made by the production timer during
			# resource preparation. Never restore an older private sleep flag.
			actor.set_physics_process(not actor._background_deep_sleeping and bool(original.get("physics_processing", actor.is_physics_processing())))
	for wake_tick in range(10): await get_tree().physics_frame
	for enemy in _fixture_enemies:
		_previous_positions[str(enemy.get_instance_id())] = _screen_to_ground(enemy.global_position)
	_player_hp_start = int(_game.player.current_hp)
	_previous_player_ground = _screen_to_ground(_game.player.global_position)
	RuntimeDiagnostics.set_device_lab_detail_mode("full")
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	EnemyActor.configure_residual_phase_probe(_profile == 1)
	EnemyActor.reset_residual_phase_probe()
	EnemyActor.reset_performance_diagnostics()
	_sample_start_counters = EnemyActor.performance_diagnostics().duplicate(true)
	_sample_start_attack = {"total": _attack_starts(_fixture_enemies)}
	for actor: EnemyActor in _fixture_enemies:
		_activity_before[actor.get_instance_id()] = {"starts": actor._hc_starts, "settlements": actor._hc_settlements}
	_index_before = _game._combat_spatial_index.diagnostics()
	_sample_start_physics_frame = Engine.get_physics_frames()
	EnemyActor.compute_optimization_shadow_checks = 0
	EnemyActor.compute_optimization_shadow_missing_identities = 0
	EnemyActor.compute_optimization_shadow_mismatches = 0
	EnemyActor.compute_optimization_shadow_supersets = 0
	EnemyActor.compute_optimization_shadow_first_mismatch.clear()
	for serial in range(_fixture_enemies.size()):
		var actor: EnemyActor = _fixture_enemies[serial]
		_compute_actor_initial.append({"serial": serial, "instance_id": actor.get_instance_id(),
			"rng_state": str(actor._rng.state), "ground": _screen_to_ground(actor.global_position),
			"starts": actor._hc_starts, "settlements": actor._hc_settlements})
	_sampling = true
	_sample_start_usec = Time.get_ticks_usec()
	_sample_start_dispatch = _dispatch_snapshot()
	for tick in range(SAMPLE_TICKS_V113):
		if tick % 15 == 0 and _game.player.current_hp < _game.player.max_hp * 0.75:
			var hp_before: int = _game.player.current_hp
			var potion_result: Dictionary = PlayerState.use_quick_item_slot(0, _potion_entity_id)
			_potion_inputs.append({"tick": tick, "hp_before": hp_before,
				"hp_after": _game.player.current_hp, "result": potion_result})
			if not bool(potion_result.get("ok", false)):
				_v113_failures.append("formal_potion_input_rejected:%d" % tick)
		if tick % _movement_period_ticks == 0:
			var phase := int(tick / _movement_period_ticks) % 4
			var heading: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][phase]
			_game._on_gameplay_movement(heading)
			_input_manifest.append({"tick": tick, "input": str(heading), "route": "real_gameplay_movement"})
		await get_tree().physics_frame
	_game._on_gameplay_movement(Vector2.ZERO)
	_sampling = false
	_sample_end_usec = Time.get_ticks_usec()
	_sample_end_physics_frame = Engine.get_physics_frames()
	var enemies := get_tree().get_nodes_in_group("enemies")
	var final_census := _monster_census(enemies)
	var counters := EnemyActor.performance_diagnostics()
	for existing_failure in _v113_failures.duplicate():
		_proof.record(false, "preexisting_failure:%s" % existing_failure)
	_check(_label == _safe_filename(_label) and _requested_label == _label, "label_is_safe_filename")
	_check(_active_count in [10, 20, 30, 40], "active_count_is_supported")
	_check(_density in ["scattered", "clustered"], "density_is_supported")
	_check(enemies.size() == _total_count, "formal_total_actor_count")
	_check(_layout_rows.size() == _total_count, "layout_has_every_actor")
	_check(_loot_manifest.size() == LOOT_COUNT, "real_loot_manifest_count")
	_check(_density_samples.size() > 0, "density_timeseries_present")
	_check(_full_physical_boundary_samples.size() >= SAMPLE_TICKS_V113 - 2, "full_physical_boundary_samples_present")
	_check(_sample_end_physics_frame - _sample_start_physics_frame == SAMPLE_TICKS_V113, "actual_physics_tick_count")
	_check(int(counters.get("enemy_physics_calls", 0)) > 0, "enemy_physics_callbacks_present")
	_check(_v113_max_targeting >= _active_count and _v113_min_targeting >= 1, "all_designated_active_acquired_target")
	_check(_v113_max_awake >= _active_count and _v113_min_awake >= 1, "all_designated_active_awake")
	_check(_v113_max_moving > 0 and _player_moving_ticks > 0 and _v113_player_motion_gu > GroundUnitSpace.EPSILON_GU, "real_movement_observed")
	_check(int(_attack_window().starts) > 0, "at_least_one_real_attack_observed")
	_check(int(_attack_window().settlements) > 0, "at_least_one_real_attack_settlement_observed")
	_check(_native_call_count() == 0, "native_invocation_count_is_zero_at_this_stage")
	_check(_layout_has_no_initial_overlap(), "initial_layout_has_no_overlap")
	for serial in range(mini(_active_count, _fixture_enemies.size())):
		var actor = _fixture_enemies[serial]
		_check(is_instance_valid(actor) and actor.can_receive_damage(), "active_actor_real:%d" % serial)
	for serial in range(_active_count, _fixture_enemies.size()):
		_check(int(_fixture_enemies[serial]._hc_starts) == 0, "background_actor_no_attack:%d" % serial)
	if _compute_mode == "SHADOW":
		_check(EnemyActor.compute_optimization_shadow_checks > 0, "shadow_comparison_has_real_calls")
		_check(EnemyActor.compute_optimization_shadow_mismatches == 0, "shadow_collision_results_match")
		_check(EnemyActor.compute_optimization_shadow_missing_identities == 0, "shadow_no_missing_required_identity")
	var report := _build_report(layout, enemies, final_census, counters)
	report["compute_mode"] = _compute_mode
	report["compute_actor_initial"] = _compute_actor_initial
	report["compute_shadow"] = {"checks": EnemyActor.compute_optimization_shadow_checks,
		"missing_identities": EnemyActor.compute_optimization_shadow_missing_identities,
		"mismatches": EnemyActor.compute_optimization_shadow_mismatches,
		"supersets": EnemyActor.compute_optimization_shadow_supersets,
		"first_mismatch": EnemyActor.compute_optimization_shadow_first_mismatch}
	report["strict_work_equivalence"] = "MISSING"
	report["strict_work_equivalence_reason"] = "Wall-clock decisions and instance-ID staggering are retained; same-call shadow and independent contract tests establish algorithm correctness separately."
	_write_report(report)
	for failure in _v113_failures:
		print("HC_TEST_FAIL ", failure)
	var receipt_ok := _proof.write_receipt(SCENE_ID, _proof.records.size(), _receipt_failed_count())
	print("NATIVE_BATCH_DENSITY_V113_%s label=%s active=%d total=%d density=%s" % ["PASS" if _v113_failures.is_empty() and receipt_ok else "FAIL", _label, _active_count, _total_count, _density])
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _v113_failures.is_empty() and receipt_ok else 1)

func _read_environment() -> void:
	var active_text := OS.get_environment("HARDCORE_NATIVE_AB_ACTIVE")
	if not active_text.is_empty(): _active_count = int(active_text)
	_total_count = TOTAL_40 if _active_count == 40 else TOTAL_DEFAULT
	_density = OS.get_environment("HARDCORE_NATIVE_AB_DENSITY")
	if _density.is_empty(): _density = "scattered"
	_requested_label = OS.get_environment("HARDCORE_NATIVE_AB_LABEL")
	if _requested_label.is_empty(): _requested_label = "%s_%d" % [_density, _active_count]
	_label = _requested_label
	_profile = int(OS.get_environment("HARDCORE_NATIVE_AB_PROFILE"))
	if _active_count > _total_count: _v113_failures.append("active_exceeds_total")
	var label_re := RegEx.new()
	label_re.compile("^[A-Za-z0-9_-]+$")
	if label_re.search(_requested_label) == null:
		_v113_failures.append("label_filename_contract_failed")
		_label = "invalid_label"

func _place_v113_actors(enemies: Array) -> Dictionary:
	if enemies.is_empty():
		_v113_failures.append("formal_map_has_no_enemies")
		return {"center_ground": [0.0, 0.0], "center_screen": Vector2.ZERO, "actors": [], "layout_kind": _density}
	var probe: EnemyActor = enemies[0]
	var context: Dictionary = _game._monster_terrain_navigation_context
	var center := Vector2.INF
	var candidates: Array[Vector2] = []
	var background_candidates: Array[Vector2] = []
	var max_radius := 0.0
	for actor in enemies: max_radius = maxf(max_radius, float(actor.combat_radius_gu))
	var candidate_clearance := 2.0 * max_radius + GroundUnitSpace.EPSILON_GU
	var radius_steps := ceili(5.2 / candidate_clearance)
	for y in range(6, 58, 2):
		for x in range(5, 28, 2):
			var point := Vector2(x, y)
			if not probe._hc_point_walkable(point): continue
			var legal: Array[Vector2] = []
			for oy in range(-radius_steps, radius_steps + 1):
				for ox in range(-radius_steps, radius_steps + 1):
					var near := point + Vector2(ox, oy) * candidate_clearance
					var d := near.distance_to(point)
					if d >= 2.0 and d <= 5.2 and probe._hc_point_walkable(near) and Poly.segment_walkable(context, point, near, max_radius): legal.append(near)
			# Select the same deterministic capacity-qualified site for every count.
			if legal.size() >= 40:
				center = point
				candidates = legal
				break
		if center.is_finite(): break
	if not center.is_finite():
		_v113_failures.append("no_legal_density_center")
		return {"center_ground": [0.0, 0.0], "center_screen": probe.global_position}
	for y in range(3, 62):
		for x in range(3, 30):
			var point := Vector2(x, y)
			if point.distance_to(center) < 22.0 or not probe._hc_point_walkable(point): continue
			var unique := true
			for prior in background_candidates:
				if prior.distance_to(point) < candidate_clearance: unique = false; break
			if unique: background_candidates.append(point)
	if candidates.size() < _active_count or background_candidates.size() < _total_count - _active_count:
		_v113_failures.append("insufficient_radius_constrained_sites:%d/%d" % [candidates.size(), background_candidates.size()])
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := a.distance_squared_to(center)
		var db := b.distance_squared_to(center)
		return da < db if da != db else (a.x < b.x if a.x != b.x else a.y < b.y))
	var chosen: Array[Vector2] = []
	if _density == "clustered":
		for point in candidates.slice(0, mini(_active_count, candidates.size())): chosen.append(point)
	else:
		# Farthest-first max-min selection keeps all active actors in the same
		# acquisition radius while maximizing separation within that radius.
		var remaining := candidates.duplicate()
		if not remaining.is_empty(): chosen.append(remaining.pop_front())
		while chosen.size() < _active_count and not remaining.is_empty():
			var best_index := 0
			var best_distance := -1.0
			for candidate_index in range(remaining.size()):
				var nearest := INF
				for selected_point in chosen: nearest = minf(nearest, remaining[candidate_index].distance_to(selected_point))
				if nearest > best_distance: best_distance = nearest; best_index = candidate_index
			chosen.append(remaining[best_index]); remaining.remove_at(best_index)
	for point in background_candidates.slice(0, mini(_total_count - _active_count, background_candidates.size())):
		chosen.append(point)
	for serial in range(enemies.size()):
		if serial >= chosen.size():
			_v113_failures.append("insufficient_chosen_sites_for_actor:%d" % serial)
			break
		var ground := chosen[serial]
		var actor: EnemyActor = enemies[serial]
		_background_original_state[str(actor.get_instance_id())] = {"physics_processing": actor.is_physics_processing(),
			"deep_sleep": actor._background_deep_sleeping}
		actor.set_combat_position(_ground_to_screen(ground), &"crowd_compute_density_v113_20261013")
		actor.set_meta("spawn_position", actor.global_position)
		actor._rng.seed = V113_SEED + serial
		actor.set_physics_process(false)
		_layout_rows.append({"serial": serial, "monster_id": actor.monster_id,
			"active": serial < _active_count, "ground": [ground.x, ground.y],
			"combat_radius_gu": actor.combat_radius_gu})
	return {"center_ground": [center.x, center.y], "center_screen": _ground_to_screen(center),
		"actors": _layout_rows, "layout_kind": _density,
		"layout_sha256": JSON.stringify(_layout_rows).sha256_text()}

func _build_report(layout: Dictionary, enemies: Array, final_census: Dictionary, counters: Dictionary) -> Dictionary:
	return {"schema_version": 1, "scene_id": SCENE_ID, "label": _label,
		"status": "FAIL" if not _v113_failures.is_empty() else "PASS", "map_id": MAP_ID,
		"seed": V113_SEED, "active_count": _active_count, "total_count": _total_count,
		"background_count": _total_count - _active_count, "density": _density, "profile": _profile,
		"layout": layout, "layout_rows": _layout_rows, "sample_physics_ticks": SAMPLE_TICKS_V113,
		"actual_physics_ticks": _sample_end_physics_frame - _sample_start_physics_frame,
		"sample_elapsed_usec": _sample_end_usec - _sample_start_usec,
		"density_timeseries": _density_samples, "full_physical_boundary_samples": _full_physical_boundary_samples,
		"root_dispatch_diagnostics": _root_dispatch_samples, "process_monitor_samples": _process_monitor_samples,
		"diagnostic_mode": "full", "profile_mode": "residual_phase_probe" if _profile == 1 else "disabled",
		"residual_phase_probe": EnemyActor.residual_phase_probe_snapshot(),
		"native_invocation_count": _native_call_count(), "native_status": "baseline_no_native_loaded",
		"counters": counters,
		"enemy_physics": {"calls": counters.get("enemy_physics_calls", 0), "usec": counters.get("enemy_physics_usec", 0)},
		"actual_work": {"movement_gu": _v113_motion_gu, "player_motion_gu": _v113_player_motion_gu, "attack_starts": _attack_window().starts,
			"attack_settlements": _attack_window().settlements,
			"player_hp_loss": _player_hp_loss,
			"player_moving_physics_ticks": _player_moving_ticks}, "monster_census_after": final_census,
		"collision_path": enemies.map(func(actor): return {"monster_id": actor.monster_id,
			"path_status": actor._hc_path_status, "path_pending": actor._hc_path_pending,
			"last_reason": actor._hc_last_reason}),
		"loot": {"requested_count": LOOT_COUNT, "initial_active_count": _loot_initial_active,
			"ending_active_count": _active_loot_count(), "manifest": _loot_manifest},
		"inputs": _input_manifest, "potion_inputs": _potion_inputs, "aoe_events": _aoe_events,
		"physics_cpu_samples_ms": _physics_cpu_ms, "physics_cpu_ms": _stats(_physics_cpu_ms),
		"frame_interval_ms": _stats(_intervals), "process_monitor_ms": _stats(_process_ms),
		"source_hashes": _profile_source_hashes(), "failures": _v113_failures,
		"activity_window": {"targeting_min": _v113_min_targeting, "targeting_max": _v113_max_targeting,
			"awake_min": _v113_min_awake, "awake_max": _v113_max_awake},
		"engine_version": Engine.get_version_info(), "renderer": {"display_server": DisplayServer.get_name(), "headless_gpu": "MISSING"},
		"aoe": {"status": "NOT_RUN", "reason": "baseline fixture leaves real AOE to an independently confirmed production-input phase"},
		"dispatch_start": _sample_start_dispatch, "dispatch_end": _dispatch_snapshot(),
		"index_start": _index_before, "index_end": _game._combat_spatial_index.diagnostics(),
		"engine_settings": {"max_fps": Engine.max_fps, "physics_ticks_per_second": Engine.physics_ticks_per_second},
		"fixture_source_sha256": FileAccess.get_sha256("res://tests/framework/crowd_compute_density_v113_20261013.gd"),
		"framework_run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"framework_invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}

func _write_report(report: Dictionary) -> void:
	var directory := "res://outputs/crowd_compute_optimization_v113_20261013/runs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join(_label + ".json"), FileAccess.WRITE)
	if file == null:
		_v113_failures.append("run_report_open_failed")
		return
	file.store_string(JSON.stringify(report, "\t")); file.close()

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value: _v113_failures.append(label)

func _safe_filename(value: String) -> String:
	return value.strip_edges().replace("/", "_").replace("\\", "_").replace("..", "_")

func _ready_map_safe(expected_map: int) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _game._map_transition_in_progress and _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY:
			return _game.current_map_id == expected_map
	return false

func _finish_early(reason: String) -> void:
	_v113_failures.append(reason)
	_check(false, reason)
	_write_report({"schema_version": 1, "scene_id": SCENE_ID, "label": _label,
		"status": "FAIL", "failures": _v113_failures,
		"fixture_source_sha256": FileAccess.get_sha256("res://tests/framework/crowd_compute_density_v113_20261013.gd"),
		"framework_run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"framework_invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256")})
	var receipt_ok := _proof.write_receipt(SCENE_ID, _proof.records.size(), _receipt_failed_count())
	if is_instance_valid(_game): _game.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if not receipt_ok else 1)

func _native_call_count() -> int:
	return 0

func _attack_window() -> Dictionary:
	var starts := 0
	var settlements := 0
	for actor: EnemyActor in _fixture_enemies:
		if not is_instance_valid(actor): continue
		var previous: Dictionary = _activity_before.get(actor.get_instance_id(), {})
		starts += actor._hc_starts - int(previous.get("starts", 0))
		settlements += actor._hc_settlements - int(previous.get("settlements", 0))
	return {"starts": starts, "settlements": settlements}

func _has_layout_capacity_failure() -> bool:
	for failure in _v113_failures:
		if str(failure).begins_with("insufficient_radius_constrained_sites") or str(failure).begins_with("insufficient_chosen_sites"):
			return true
	return false

func _dispatch_snapshot() -> Dictionary:
	if _game == null: return {"available": false}
	var rows := EnemyActor.pursuit_process_budget_diagnostics()
	var budget: Dictionary = rows.get("decision_budget", {})
	return {"available": true, "dispatch_usec_total": budget.get("dispatch_usec_total", 0),
		"dispatch_calls": budget.get("dispatch_calls", 0), "snapshot": rows}

func _layout_has_no_initial_overlap() -> bool:
	for left in range(_layout_rows.size()):
		var a := Vector2(_layout_rows[left].ground[0], _layout_rows[left].ground[1])
		for right in range(left + 1, _layout_rows.size()):
			var b := Vector2(_layout_rows[right].ground[0], _layout_rows[right].ground[1])
			var clearance := float(_layout_rows[left].get("combat_radius_gu", 0.0)) + float(_layout_rows[right].get("combat_radius_gu", 0.0))
			if a.distance_to(b) < clearance:
				return false
	return true

func _receipt_failed_count() -> int:
	var failed := 0
	for item: Dictionary in _proof.records:
		if not bool(item.get("passed", false)): failed += 1
	return failed
