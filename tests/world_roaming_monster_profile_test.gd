extends "res://tests/world_crowd_firewall_profile_test.gd"

## Attribution probe through the real movement input and collision path.
## The base fixture's map, spawn, camera, cast and sample window stay intact.
## Per-frame observation adds CPU cost; do not compare its timing directly
## with the uninstrumented stationary fixture as an optimization percentage.
var _roam_started := false
var _roam_start_frame := 0
var _roam_last_frame := -1
var _roam_phase := -1
var _roam_distance_gu := 0.0
var _roam_last_ground := Vector2.ZERO
var _roam_start_ground := Vector2.ZERO
var _roam_rows: Array[Dictionary] = []
var _roam_frames: Array[Dictionary] = []
var _previous_actor_usec := 0
var _previous_actor_calls := 0
var _roam_enemies: Array = []


func _process(delta: float) -> void:
	super._process(delta)
	if not _sampling:
		return
	var frame := Engine.get_physics_frames()
	if not _roam_started:
		_roam_started = true
		_roam_start_frame = frame
		_roam_last_ground = _screen_to_ground(_game.player.global_position)
		_roam_start_ground = _roam_last_ground
		_roam_enemies = get_tree().get_nodes_in_group("enemies")
		assert(_game.gameplay_input_is_enabled())
		_game.player.set_physics_process(true)
	if frame == _roam_last_frame:
		return
	_roam_last_frame = frame
	var current := _screen_to_ground(_game.player.global_position)
	_roam_distance_gu += current.distance_to(_roam_last_ground)
	_roam_last_ground = current
	var counters := EnemyActor.performance_diagnostics()
	var actor_usec := int(counters.get("enemy_physics_usec", 0))
	var actor_calls := int(counters.get("enemy_physics_calls", 0))
	var pending := 0
	var physics_active := 0
	for enemy: EnemyActor in _roam_enemies:
		if not is_instance_valid(enemy): continue
		if enemy._hc_path_pending: pending += 1
		if enemy.is_physics_processing(): physics_active += 1
	_roam_frames.append({"physics_frame": frame - _roam_start_frame,
		"actor_usec": actor_usec - _previous_actor_usec,
		"actor_calls": actor_calls - _previous_actor_calls,
		"pending_paths": pending, "physics_active": physics_active,
		"physics_monitor_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"struck_locked": _game.player._struck_lock_remaining > 0 or _game.player._struck_reaction_lock_remaining > 0})
	_previous_actor_usec = actor_usec
	_previous_actor_calls = actor_calls
	var phase := mini(7, int((frame - _roam_start_frame) / 30))
	if phase != _roam_phase:
		_roam_phase = phase
		var heading := Vector2.from_angle(float(phase) * TAU / 8.0)
		var input := (_ground_to_screen(current + heading) - _ground_to_screen(current)).normalized()
		_game._on_gameplay_movement(input)
		_roam_rows.append({"phase": phase, "ground": str(current), "input": str(input),
			"distance_gu": _roam_distance_gu, "census": super._monster_census(_roam_enemies).counts,
			"scheduler": _scheduler_census()})


func _monster_census(enemies: Array) -> Dictionary:
	var result := super._monster_census(enemies)
	if _roam_started:
		_game._on_gameplay_movement(Vector2.ZERO)
		var final_ground := _screen_to_ground(_game.player.global_position)
		_roam_distance_gu += final_ground.distance_to(_roam_last_ground)
		var times: Array[float] = []
		for row: Dictionary in _roam_frames:
			times.append(float(row.actor_usec) / 1000.0)
		result["roaming"] = {"start_ground": str(_roam_start_ground), "end_ground": str(final_ground),
			"distance_gu": _roam_distance_gu, "phases": _roam_rows, "frames": _roam_frames,
			"actor_ms_per_observed_physics_frame": _stats(times),
			"observation_note": "One diagnostic snapshot per observed physics frame plus eight census samples; headless CPU attribution, not phone FPS."}
		assert(_roam_rows.size() == 8, "all eight real movement inputs must be issued")
		assert(_roam_distance_gu > 1.0, "insufficient real movement; no roaming conclusion is valid")
	return result


func _profile_source_hashes() -> Dictionary:
	var result := super._profile_source_hashes()
	for path: String in ["res://scripts/player.gd", "res://tests/world_roaming_monster_profile_test.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result
