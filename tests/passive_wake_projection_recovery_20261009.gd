extends Node

const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const RuntimeDiagnostics := preload("res://scripts/runtime_diagnostics.gd")

const COHORT_SIZE := 30
const MISSING_REGISTRY := "user://passive_wake_projection_recovery_missing_registry.json"

signal recovery_observed

var _game: Node
var _player: PlayerCharacter
var _actors: Array[EnemyActor] = []
var _failures: Array[String] = []
var _evidence: Dictionary = {"status": "NOT_RUN", "cases": {}, "pressure": {}}
var _recovery_observation_pending := false
var _recovery_observation_ready := false
var _recovery_observation_count := 0
var _recovery_observation_frames := 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _ready() -> void:
	process_priority = 1000
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _recovery_observation_pending:
		_recovery_observation_frames += 1
		if _target_count() != _actors.size() and _recovery_observation_frames < 3:
			return
		_recovery_observation_count = _target_count()
		_recovery_observation_ready = true
		_recovery_observation_pending = false
		for actor: EnemyActor in _actors:
			if is_instance_valid(actor):
				actor.set_physics_process(false)
		recovery_observed.emit()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	await _bootstrap()
	if _game != null and _player != null:
		await _prepare_dense_cohort()
		if _actors.size() >= COHORT_SIZE:
			await _run_projection_recovery()
			await _run_generation_rejection()
	_finish()

func _bootstrap() -> void:
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var ready := false
	for _frame: int in 1200:
		await get_tree().process_frame
		if not _game._world_bootstrap_in_progress and not _game._map_transition_in_progress:
			ready = true
			break
	_check(ready, "formal_bootstrap_incomplete")
	if not ready or not is_instance_valid(_game.player):
		return
	_player = _game.player as PlayerCharacter
	_game.set_physics_process(false)
	_player.set_physics_process(false)
	# Keep the real GameRoot process alive: recovery must be consumed by its
	# ordinary process pump, rather than by a direct test call.
	_game.set_process(true)
	# Freeze only the fixture actors' physics callbacks after formal bootstrap;
	# the spatial index and all 30 actors remain live inputs, while unrelated
	# startup combat cannot kill the observation player before the recovery pump
	# is sampled.
	for raw: Variant in _game._active_enemy_cache.values():
		if raw is EnemyActor and is_instance_valid(raw):
			(raw as EnemyActor).set_physics_process(false)

func _prepare_dense_cohort() -> void:
	var anchor: EnemyActor = null
	for raw: Variant in _game._active_enemy_cache.values():
		if raw is EnemyActor and is_instance_valid(raw):
			var candidate := raw as EnemyActor
			if not candidate.is_boss and candidate.passive_acquisition_extent_gu() > 0.0:
				anchor = candidate
				break
	_check(anchor != null, "formal_dense_anchor_missing")
	if anchor == null:
		return
	var player_ground: Vector2 = _game._canonical_screen_px_to_ground_gu(_player.global_position)
	if not player_ground.is_finite():
		_failures.append("player_ground_nonfinite")
		return
	var found_ground := Vector2.INF
	for radius: float in range(2, 28):
		for offset: Vector2 in [Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
			var point: Vector2 = player_ground + offset
			var screen: Vector2 = _game._canonical_ground_gu_to_screen_px(point)
			if screen.is_finite() and anchor._hc_point_walkable(point) and not anchor._point_inside_safe_zone(screen):
				found_ground = point
				break
		if found_ground.is_finite():
			break
	_check(found_ground.is_finite(), "formal_dense_non_safe_anchor_missing")
	if not found_ground.is_finite():
		return
	_player.global_position = _game._canonical_ground_gu_to_screen_px(found_ground)
	var candidates: Array[Vector2] = []
	for radius: float in [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5]:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized(), Vector2(1, -1).normalized()]:
			candidates.append(found_ground + axis * radius)
	var used_points: Dictionary = {}
	for raw: Variant in _game._active_enemy_cache.values():
		if _actors.size() >= COHORT_SIZE:
			break
		if not raw is EnemyActor:
			continue
		var actor := raw as EnemyActor
		if not is_instance_valid(actor) or actor.is_boss or actor.passive_acquisition_extent_gu() <= 0.0:
			continue
		var point := Vector2.INF
		var original_position := actor.global_position
		for candidate_point: Vector2 in candidates:
			if used_points.has(candidate_point) or candidate_point.distance_to(found_ground) > actor.passive_acquisition_extent_gu():
				continue
			var candidate_screen: Vector2 = _game._canonical_ground_gu_to_screen_px(candidate_point)
			if not candidate_screen.is_finite() or not actor._hc_point_walkable(candidate_point) or actor._point_inside_safe_zone(candidate_screen):
				continue
			actor.set_combat_position(candidate_screen, &"projection_recovery_fixture_probe")
			if not actor._initial_acquisition_static_los_clear(_player):
				actor.set_combat_position(original_position, &"projection_recovery_fixture_probe_revert")
				continue
			point = candidate_point
			break
		if not point.is_finite():
			continue
		var screen: Vector2 = _game._canonical_ground_gu_to_screen_px(point)
		actor.set_combat_position(screen, &"projection_recovery_fixture")
		used_points[point] = true
		actor.set_meta("spawn_position", actor.global_position)
		actor.set_meta("zone_generation", _game._zone_generation)
		actor._hc_forget(actor.target)
		actor.target = null
		actor._threat_table.clear()
		actor._hc_damage_dirty = false
		actor._clear_passive_wake()
		actor._enter_background_deep_sleep(true)
		actor.set_physics_process(false)
		_actors.append(actor)
	_evidence["setup"] = {"map_id": _game.current_map_id, "generation": _game._zone_generation, "cohort": _actors.size(), "player_ground": [found_ground.x, found_ground.y]}
	_check(_actors.size() >= COHORT_SIZE, "formal_dense_cohort:%d/%d" % [_actors.size(), COHORT_SIZE])

func _invalidate_projection() -> void:
	Bridge.test_override_release_registry_path(MISSING_REGISTRY)
	Bridge.invalidate_release_registry()
	_game._projection_profile_cache.clear()
	_game._projection_profile_runtime_identity_cache.clear()

func _restore_projection() -> void:
	Bridge.reset_release_registry_override()
	Bridge.invalidate_release_registry()
	_game._projection_profile_cache.clear()
	_game._projection_profile_runtime_identity_cache.clear()

func _emit_real_movement(delta: Vector2) -> void:
	_player.global_position += delta
	_player.movement_performed.emit(_player.global_position, _player.facing)

func _counter_snapshot() -> Dictionary:
	var index: RuntimeCombatSpatialIndex = _game._combat_spatial_index
	var spatial := {"index_query_count": int(index.index_query_count), "index_enemy_node_aabb_query_count": int(index.index_enemy_node_aabb_query_count), "index_enemy_node_segment_query_count": int(index.index_enemy_node_segment_query_count)}
	return {"diagnostics": RuntimeDiagnostics.performance_counters(), "frame_budget": FrameBudget.snapshot(), "spatial_index": spatial, "queue": _game._passive_wake_emitter_queue.duplicate(), "active": _game._passive_wake_active_emitter_id, "candidate_buffer": _game._passive_wake_candidates.size(), "used": _game._passive_wake_candidates_used}

func _counter_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var before_counters: Dictionary = before.get("diagnostics", {})
	var after_counters: Dictionary = after.get("diagnostics", {})
	for raw_key: Variant in after_counters.keys():
		var key := str(raw_key)
		if "query" in key or "candidate" in key or "passive" in key:
			result[key] = int(after_counters.get(key, 0)) - int(before_counters.get(key, 0))
	var before_spatial: Dictionary = before.get("spatial_index", {})
	var after_spatial: Dictionary = after.get("spatial_index", {})
	for raw_key: Variant in after_spatial.keys():
		var spatial_key := str(raw_key)
		result[spatial_key] = int(after_spatial.get(spatial_key, 0)) - int(before_spatial.get(spatial_key, 0))
	return result

func _run_projection_recovery() -> void:
	_invalidate_projection()
	var before := _counter_snapshot()
	_emit_real_movement(Vector2(0.01, 0.0))
	var after_failure := _counter_snapshot()
	_check(str(_game.projection_rejection_reason) != "", "projection_failure_not_recorded")
	_check(after_failure.queue.size() <= 1, "failed_projection_duplicate_queue:%d" % after_failure.queue.size())
	var epoch := Engine.get_process_frames()
	var callback_usec: Array[int] = []
	for _event: int in 10:
		var callback_started := Time.get_ticks_usec()
		_emit_real_movement(Vector2(0.01, 0.0))
		callback_usec.append(Time.get_ticks_usec() - callback_started)
	var after_pressure := _counter_snapshot()
	_check(Engine.get_process_frames() == epoch, "pressure_events_crossed_process_epoch")
	_check(after_pressure.used == 0, "failed_projection_processed_candidates:%d" % after_pressure.used)
	var callback_total := 0
	var callback_max := 0
	for elapsed: int in callback_usec:
		callback_total += elapsed
		callback_max = maxi(callback_max, elapsed)
	_evidence["cases"]["projection_unavailable"] = {"before": before, "after_failure": after_failure, "after_ten_same_process_events": after_pressure, "same_process_event_count": 10, "callback_usec": callback_usec, "callback_total_usec": callback_total, "callback_max_usec": callback_max, "query_counter_delta": _counter_delta(before, after_pressure)}
	_restore_projection()
	# No movement signal is emitted here. The next ordinary GameRoot process
	# must consume the retained failed event after projection recovery.
	_recovery_observation_pending = true
	_recovery_observation_ready = false
	await recovery_observed
	var target_count: int = _recovery_observation_count
	var post_recovery := _counter_snapshot()
	_check(target_count == _actors.size(), "projection_recovery_not_full:%d/%d" % [target_count, _actors.size()])
	_evidence["cases"]["projection_recovered_without_new_movement"] = {"target_count": target_count, "cohort": _actors.size(), "snapshot": post_recovery, "diagnostics": _actor_diagnostics()}
	for actor: EnemyActor in _actors:
		_check(not actor._attack_action_active, "recovery_actor_committed_before_pressure:%d" % actor.get_instance_id())
		actor.target = null
		actor._clear_passive_wake()
		actor._enter_background_deep_sleep(true)
		actor.set_physics_process(false)
	var valid_before := _counter_snapshot()
	var valid_epoch := Engine.get_process_frames()
	var valid_callback_usec: Array[int] = []
	for _event: int in 10:
		var started := Time.get_ticks_usec()
		_emit_real_movement(Vector2(0.01, 0.0))
		valid_callback_usec.append(Time.get_ticks_usec() - started)
	var valid_after := _counter_snapshot()
	_check(Engine.get_process_frames() == valid_epoch, "valid_pressure_events_crossed_process_epoch")
	_check(valid_after.used >= _actors.size(), "valid_pressure_did_not_process_full_cohort:%d/%d" % [valid_after.used, _actors.size()])
	_check(_target_count() == _actors.size(), "valid_pressure_not_full:%d/%d" % [_target_count(), _actors.size()])
	_check(valid_after.queue.size() <= 1, "valid_pressure_duplicate_queue:%d" % valid_after.queue.size())
	_evidence["cases"]["valid_projection_ten_event_pressure"] = {"event_count": 10, "cohort": _actors.size(), "candidate_used": valid_after.used, "callback_usec": valid_callback_usec, "callback_total_usec": _sum_ints(valid_callback_usec), "callback_max_usec": _max_ints(valid_callback_usec), "query_counter_delta": _counter_delta(valid_before, valid_after), "before": valid_before, "after": valid_after, "diagnostics": _actor_diagnostics()}
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor):
			actor.set_physics_process(false)

func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value: int in values:
		total += value
	return total

func _max_ints(values: Array[int]) -> int:
	var maximum := 0
	for value: int in values:
		maximum = maxi(maximum, value)
	return maximum

func _run_generation_rejection() -> void:
	for actor: EnemyActor in _actors:
		actor.target = null
		actor._clear_passive_wake()
		actor.set_physics_process(false)
	_invalidate_projection()
	_emit_real_movement(Vector2(0.01, 0.0))
	var old_map: int = _game.current_map_id
	var old_generation: int = _game._zone_generation
	_game.current_map_id = old_map + 1
	_game._zone_generation = old_generation + 1
	# Consume the queued event while its map/generation lease is stale. This
	# verifies revocation rather than merely restoring the old values before the
	# ordinary process pump sees the queue.
	_game._pump_passive_monster_wakeup()
	_restore_projection()
	_game.current_map_id = old_map
	_game._zone_generation = old_generation
	_check(_target_count() == 0, "stale_map_generation_event_woke_old_candidates")
	_evidence["cases"]["map_generation_revocation"] = {"target_count_before_new_event": _target_count(), "old_map": old_map, "old_generation": old_generation}
	_emit_real_movement(Vector2(0.01, 0.0))
	var new_target_count := _target_count()
	_check(new_target_count == _actors.size(), "new_generation_event_not_full:%d/%d" % [new_target_count, _actors.size()])
	_evidence["cases"]["map_generation_new_event"] = {"target_count": new_target_count, "cohort": _actors.size(), "snapshot": _counter_snapshot()}

func _target_count() -> int:
	var count := 0
	for actor: EnemyActor in _actors:
		if is_instance_valid(actor) and is_instance_valid(actor.target):
			count += 1
	return count

func _actor_diagnostics() -> Dictionary:
	var player_ground: Vector2 = _game._canonical_screen_px_to_ground_gu(_player.global_position)
	var player_state: Dictionary = {
		"position_px": [_player.global_position.x, _player.global_position.y],
		"ground": [player_ground.x, player_ground.y],
		"current_hp": _player.current_hp,
		"max_hp": _player.max_hp,
		"dead": _player._dead,
		"runtime_map_id": int(_player.get_meta("runtime_map_id", -1)),
		"zone_generation": int(_player.get_meta("zone_generation", -1)),
		"in_tree": _player.is_inside_tree(),
	}
	var actor_rows: Array[Dictionary] = []
	for actor: EnemyActor in _actors:
		var actor_ground: Vector2 = _game._canonical_screen_px_to_ground_gu(actor.global_position)
		var target_id := 0
		if is_instance_valid(actor.target):
			target_id = actor.target.get_instance_id()
		var distance := actor_ground.distance_to(player_ground) if actor_ground.is_finite() and player_ground.is_finite() else INF
		actor_rows.append({
			"instance_id": actor.get_instance_id(),
			"in_tree": actor.is_inside_tree(),
			"physics_processing": actor.is_physics_processing(),
			"position_px": [actor.global_position.x, actor.global_position.y],
			"ground": [actor_ground.x, actor_ground.y],
			"current_hp": actor.current_hp,
			"dead": actor.current_hp <= 0,
			"dying": actor._dying,
			"death_pending": actor._death_pending,
			"target_id": target_id,
			"committed_attack": actor._attack_action_active,
			"source_extent_gu": actor.passive_acquisition_extent_gu(),
			"distance_to_player_gu": distance,
			"static_los_clear": actor._initial_acquisition_static_los_clear(_player),
			"runtime_map_id": actor.runtime_map_id,
			"zone_generation": int(actor.get_meta("zone_generation", -1)),
			"wake_pending": actor._passive_wake_pending,
		})
	return {"player": player_state, "actors": actor_rows, "game_map_id": _game.current_map_id, "game_generation": _game._zone_generation}

func _finish() -> void:
	_restore_projection()
	_evidence["diagnostics_enabled_for_observation"] = RuntimeDiagnostics.performance_enabled()
	_evidence["failures"] = _failures
	_evidence["status"] = "PASS" if _failures.is_empty() else "FAIL"
	var output := FileAccess.open("res://outputs/test_logs/passive_wake_projection_recovery_20261009.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(_evidence, "\t"))
	if _failures.is_empty():
		print("HC_PASSIVE_WAKE_PROJECTION_RECOVERY_20261009_PASS")
	else:
		for failure: String in _failures:
			print("HC_TEST_FAIL ", failure)
	if is_instance_valid(_game):
		_game.queue_free()
		await get_tree().process_frame
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	get_tree().quit(0 if _failures.is_empty() else 1)
