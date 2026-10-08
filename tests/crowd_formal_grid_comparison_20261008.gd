extends "res://tests/crowd_engagement_scaling_20261008.gd"

## FORMAL_GRID_COMPARISON. This fixture reuses the complete formal crowd
## workload from crowd_engagement_scaling_20261008 and changes only the
## optional grid-trial hook. It is deliberately not an acceptance test by
## itself: v107/current/grid must be run with the same source, map, actor
## identities, layout, inputs, HP, loot and physics window.

const COMPARISON_MODES := ["v107", "current", "grid"]
const FORMAL_GRID_CELL_GU := 1.0
const FORMAL_GRID_NEAR_MIN_GU := 1.8
const FORMAL_GRID_NEAR_MAX_GU := 4.5
const FORMAL_GRID_FAR_MIN_GU := 26.0
const FORMAL_GRID_ENGAGED_COUNT := 30

var _comparison_mode := "current"
var _grid_adapter: RefCounted = null
var _grid_hook_applied := false
var _grid_actor_hooks := 0
var _grid_failures: Array[String] = []


func _run() -> void:

	_comparison_mode = OS.get_environment("HARDCORE_GRID_COMPARISON_MODE").strip_edges().to_lower()
	if _comparison_mode.is_empty():
		_comparison_mode = "current"
	if _comparison_mode not in COMPARISON_MODES:
		_grid_failures.append("unsupported_comparison_mode:%s" % _comparison_mode)
		_comparison_mode = "current"
	await super._run()


func _place_scaling_actors(enemies: Array) -> Dictionary:
	# Every mode uses this exact placement. We intentionally do not snap only
	# the grid run, because that would make the CPU comparison invalid.
	if enemies.is_empty():
		_grid_failures.append("no_formal_actors")
		return {"center_ground": [0.0, 0.0], "center_screen": Vector2.ZERO,
			"actors": [], "layout_sha256": ""}
	var probe: EnemyActor = enemies[0]
	var context: Dictionary = _game._monster_terrain_navigation_context
	var center := Vector2.INF
	var near: Array[Vector2] = []
	var center_candidates: Array[Vector2] = []
	for y in range(6, 58):
		for x in range(5, 34):
			center_candidates.append(Vector2(float(x) + 0.5, float(y) + 0.5))
	for candidate: Vector2 in center_candidates:
		if not probe._hc_point_walkable(candidate):
			continue
		var options: Array[Vector2] = []
		for y in range(-5, 6):
			for x in range(-5, 6):
				var point := candidate + Vector2(float(x), float(y))
				var distance := point.distance_to(candidate)
				if distance < FORMAL_GRID_NEAR_MIN_GU or distance > FORMAL_GRID_NEAR_MAX_GU:
					continue
				if not is_equal_approx(fmod(point.x, FORMAL_GRID_CELL_GU), 0.5) or not is_equal_approx(fmod(point.y, FORMAL_GRID_CELL_GU), 0.5):
					continue
				if probe._hc_point_walkable(point) and Poly.segment_walkable(context, candidate, point, probe.combat_radius_gu):
					options.append(point)
		if options.size() >= FORMAL_GRID_ENGAGED_COUNT:
			center = candidate
			near = options
			break
	if not center.is_finite():
		_grid_failures.append("no_1gu_grid_center_with_30_sites")
		return {"center_ground": [0.0, 0.0], "center_screen": probe.global_position,
			"actors": [], "layout_sha256": ""}
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if is_equal_approx(a.distance_squared_to(center), b.distance_squared_to(center)):
			return a.x < b.x if not is_equal_approx(a.x, b.x) else a.y < b.y
		return a.distance_squared_to(center) < b.distance_squared_to(center))
	var far: Array[Vector2] = []
	for y in range(3, 62):
		for x in range(3, 34):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			if point.distance_to(center) > FORMAL_GRID_FAR_MIN_GU and probe._hc_point_walkable(point):
				far.append(point)
	if far.size() < SCALING_ACTOR_COUNT - FORMAL_GRID_ENGAGED_COUNT:
		_grid_failures.append("insufficient_1gu_grid_background_sites:%d" % far.size())
	var rows: Array[Dictionary] = []
	for serial in range(enemies.size()):
		var ground := near[serial] if serial < FORMAL_GRID_ENGAGED_COUNT else far[serial - FORMAL_GRID_ENGAGED_COUNT]
		var enemy: EnemyActor = enemies[serial]
		enemy.set_combat_position(_ground_to_screen(ground), &"formal_grid_comparison")
		enemy.set_meta("spawn_position", _ground_to_screen(ground))
		enemy._rng.seed = SCALING_SEED + serial
		rows.append({"serial": serial, "instance_id": enemy.get_instance_id(),
			"monster_id": enemy.monster_id, "ground": [ground.x, ground.y],
			"cell": [floori(ground.x / FORMAL_GRID_CELL_GU), floori(ground.y / FORMAL_GRID_CELL_GU)],
			"engaged": serial < FORMAL_GRID_ENGAGED_COUNT})
	var layout := {"center_ground": [center.x, center.y],
		"center_screen": _ground_to_screen(center), "cell_size_gu": FORMAL_GRID_CELL_GU,
		"near_distance_gu": [FORMAL_GRID_NEAR_MIN_GU, FORMAL_GRID_NEAR_MAX_GU],
		"far_min_distance_gu": FORMAL_GRID_FAR_MIN_GU, "actors": rows,
		"layout_sha256": _stable_layout_hash(rows)}
	# Positions are final before the optional hook is called. A missing hook is
	# recorded as unavailable instead of changing baseline/current behavior.
	_configure_grid_trial(enemies, rows)
	return layout


func _configure_grid_trial(enemies: Array, rows: Array[Dictionary]) -> void:
	if _comparison_mode != "grid":
		return
	var adapter_script: Script = load("res://scripts/monster_ai_package/grid_crowd_trial.gd")
	if adapter_script == null:
		_grid_failures.append("grid_adapter_load_failed")
		_scaling_failures.append("grid_adapter_load_failed")
		return
	_grid_adapter = adapter_script.new()
	for index in range(enemies.size()):
		var actor: EnemyActor = enemies[index]
		if not actor.has_method(&"configure_grid_crowd_trial"):
			continue
		actor.call(&"configure_grid_crowd_trial", _grid_adapter)
		_grid_actor_hooks += 1
	if _grid_actor_hooks > 0:
		_grid_hook_applied = true
	elif _game.has_method(&"configure_grid_crowd_trial"):
		_game.call(&"configure_grid_crowd_trial", _grid_adapter)
		_grid_hook_applied = true
	else:
		_grid_failures.append("grid_hook_unavailable")
		_scaling_failures.append("grid_hook_unavailable")
	if _grid_hook_applied:
		if not _grid_adapter.has_method(&"seal"):
			_grid_failures.append("grid_adapter_seal_unavailable")
			_scaling_failures.append("grid_adapter_seal_unavailable")
		else:
			var seal_result: Variant = _grid_adapter.call(&"seal", enemies)
			var seal_ok := bool(seal_result)
			if seal_result is Dictionary:
				seal_ok = bool(seal_result.get("ok", seal_result.get("success", false)))
			if not seal_ok:
				_grid_failures.append("grid_adapter_seal_failed")
				_scaling_failures.append("grid_adapter_seal_failed")


func _append_scaling_result(result: Dictionary) -> void:
	if _comparison_mode == "grid" and (_grid_adapter == null or not _grid_adapter.enabled()):
		_scaling_failures.append("grid_not_active_at_sample_end")
		result["status"] = "FAIL"
	result["fixture"] = "FORMAL_GRID_COMPARISON_crowd_30_20261008"
	result["diagnostic_only"] = true
	result["comparison_mode"] = _comparison_mode
	var contract_engaged := int(result.get("growth_contract", {}).get("engaged_requested", FORMAL_GRID_ENGAGED_COUNT))
	result["comparison_contract"] = {
		"formal_map_id": SCALING_MAP_ID, "formal_actor_count": SCALING_ACTOR_COUNT,
		"engaged_count": contract_engaged, "background_count": SCALING_ACTOR_COUNT - contract_engaged,
		"loot_count": SCALING_LOOT_COUNT, "real_physics_ticks": SCALING_SAMPLE_TICKS,
		"same_layout_across_modes": true, "same_identity_order": true,
		"same_hp_ai_physics_inputs": true, "gpu_fps": "NOT_MEASURED"}
	result["grid_trial"] = {"cell_size_gu": FORMAL_GRID_CELL_GU,
		"hook_applied": _grid_hook_applied, "actor_hooks": _grid_actor_hooks,
		"failures": _grid_failures,
		"adapter_snapshot": _grid_adapter.snapshot() if _grid_adapter != null and _grid_adapter.has_method(&"snapshot") else {}}
	result["failures"] = Array(result.get("failures", [])) + _grid_failures
	result["memory_static_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	result["actor_templates"] = _actor_template_snapshot()
	result["source_hashes"] = _scaling_source_hashes()
	var run_id := OS.get_environment("HARDCORE_GRID_COMPARISON_RUN_ID")
	if run_id.is_empty():
		run_id = "%s_%d" % [_comparison_mode, Time.get_unix_time_from_system()]
	var output_dir := "res://outputs/crowd_formal_grid_comparison_20261008"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var file := FileAccess.open("%s/%s.json" % [output_dir, run_id], FileAccess.WRITE)
	if file == null:
		_grid_failures.append("comparison_output_open_failed:%s" % run_id)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()


func _scaling_source_hashes() -> Dictionary:
	var result := super._scaling_source_hashes()
	result["res://tests/crowd_formal_grid_comparison_20261008.gd"] = FileAccess.get_sha256("res://tests/crowd_formal_grid_comparison_20261008.gd")
	for path in [
		"res://scripts/monster_ai_package/grid_crowd_trial.gd",
		"res://scripts/monster_ai_package/grid_occupancy_service.gd",
	]:
		if FileAccess.file_exists(path):
			result[path] = FileAccess.get_sha256(path)
	return result


func _stable_layout_hash(rows: Array[Dictionary]) -> String:
	var identity_rows: Array[Dictionary] = []
	for row: Dictionary in rows:
		identity_rows.append({
			"serial": row.get("serial"), "monster_id": row.get("monster_id"),
			"ground": row.get("ground"), "cell": row.get("cell"),
			"engaged": row.get("engaged"),
		})
	return JSON.stringify(identity_rows).sha256_text()


func _actor_template_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for actor in _scaling_enemies:
		if not is_instance_valid(actor):
			continue
		rows.append({
			"instance_id": actor.get_instance_id(),
			"monster_id": actor.monster_id,
			"combat_radius_gu": float(actor.combat_radius_gu),
			"move_speed_gu_per_sec": float(actor.move_speed_gu_per_sec),
			"max_hp": int(actor.get("max_hp")) if actor.get("max_hp") != null else null,
			"position_ground": [_screen_to_ground(actor.global_position).x, _screen_to_ground(actor.global_position).y],
		})
	return rows
