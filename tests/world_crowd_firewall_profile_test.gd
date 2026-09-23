extends Node

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Geometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const Field := preload("res://scripts/fire_wall_field_controller.gd")
var map_id := 913203
var _formal_cast := false
var _cast_ms: Array[float] = []
var _context_profiles: Dictionary = {}
const SAMPLE_FRAMES := 240
var _game: Node
var _sampling := false
var _last_usec := 0
var _intervals: Array[float] = []
var _process_ms: Array[float] = []
var _direction_mismatches: Dictionary = {}
var _physics_start: PhysicsFrameStart
var _physics_cpu_ms: Array[float] = []

class PhysicsFrameStart extends Node:
	var started_usec := 0
	var physics_tick := -1
	func _physics_process(_delta: float) -> void:
		physics_tick = Engine.get_physics_frames()
		started_usec = Time.get_ticks_usec()


func _ready() -> void:
	# Two test-only boundaries observe all normal-priority production physics
	# callbacks, without enabling per-method timing/dictionary instrumentation.
	_physics_start = PhysicsFrameStart.new()
	_physics_start.process_physics_priority = -1000000
	add_child(_physics_start)
	process_physics_priority = 1000000
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if _sampling and _physics_start.physics_tick == Engine.get_physics_frames():
		_physics_cpu_ms.append(float(Time.get_ticks_usec() - _physics_start.started_usec) / 1000.0)


func _process(_delta: float) -> void:
	if not _sampling:
		return
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_intervals.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_process_ms.append(1000.0 * Performance.get_monitor(Performance.TIME_PROCESS))


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var selected_map := OS.get_environment("HARDCORE_V92_MAP_ID")
	if not selected_map.is_empty(): map_id = int(selected_map)
	_formal_cast = OS.get_environment("HARDCORE_V92_FORMAL_CAST") == "1"
	if _formal_cast:
		PlayerState.profession = "法师"
		PlayerState.level = 50
		PlayerState.learned_skills = {"火墙": 3}
		PlayerState.recalculate_stats()
	seed(20260922)
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await _ready_map(910001)
	_game.player.max_hp = 1000000
	_game.player.current_hp = 1000000
	assert(_game._begin_map_transition(Callable(_game, "_travel_to_map_immediate").bind(map_id), map_id))
	await _ready_map(map_id)
	var enemies := get_tree().get_nodes_in_group("enemies")
	var initial_layout: Array[Dictionary] = []
	for enemy: EnemyActor in enemies:
		initial_layout.append({"monster_id": enemy.monster_id, "position": str(enemy.global_position)})
	var expected_renderer := OS.get_environment("HARDCORE_V92_EXPECT_RENDERER")
	if not expected_renderer.is_empty():
		assert(_game.background.wall_render_stats().get("wall_render_mode") == expected_renderer,
			"requested renderer was not activated: %s" % str(_game.background.wall_render_stats()))
	if _formal_cast:
		for index in range(enemies.size()):
			(enemies[index] as EnemyActor)._rng.seed = 20260922 + index
	var selected := _select_profile_focus(enemies)
	var focus: Vector2 = selected.position
	var most_nearby: int = selected.nearby
	_game._set_player_world_position(focus)
	_game.background.set_focus_position(focus)
	_game.player.set_physics_process(false)
	for frame in range(60):
		await get_tree().physics_frame
	var fields: Array[Field] = []
	if _formal_cast:
		_profile_contexts()
	_game._rng.seed = 20260922
	if OS.get_environment("HARDCORE_V92_FIRE_WALL") == "1":
		CasterSkillVisualRegistry.set_loading_window_active(true)
		var base := _screen_to_ground(_game.player.global_position).floor()
		var field_count := 8 if _formal_cast else 6
		for serial in range(field_count):
			var anchor := base + Vector2((serial % 3) * 2 - 2, (serial / 3) * 2 - 1)
			if _formal_cast:
				_game.player.current_mp = 100000
				var closest: EnemyActor
				var distance := INF
				for enemy: EnemyActor in enemies:
					var current := enemy.global_position.distance_squared_to(focus)
					if current < distance and enemy.can_receive_damage():
						closest = enemy
						distance = current
				assert(closest != null)
				_game._skill_cast_target = closest
				var started := Time.get_ticks_usec()
				var cast: Dictionary = _game._execute_canonical_skill("wizard.fire_wall",
					_game.player.global_position, Vector2.RIGHT, 0,
					{"primary_stat_roll": 1, "target_tile": Vector2i(anchor)}, true, true)
				_cast_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
				assert(cast.get("accepted", false), str(cast.get("reason", "")))
				continue
			var context := Snapshot.make_absolute_runtime_context(map_id, anchor, anchor, _ground_to_screen)
			context["expected_runtime_map_id"] = map_id
			var cells: Array[Vector2i] = []
			var positions: Array[Vector2] = []
			for y in range(-1, 2):
				for x in range(-1, 2):
					cells.append(Vector2i(anchor) + Vector2i(x, y))
					positions.append(_ground_to_screen(anchor + Vector2(x, y)))
			var release_id := "world-profile-field:%d" % serial
			var snapshot := Geometry.create_exact_cell_union_release_snapshot("wizard.fire_wall", release_id, anchor, cells, context)
			var field := Field.new()
			var filters: Array[Callable] = []
			field.setup_fire_wall_field(_game.player, "wizard.fire_wall",
				{"raw_power": 1, "duration_seconds": 60.0, "tick_interval_ms": 1000},
				positions, cells, filters, _damage, _screen_to_ground, release_id, snapshot, context,
				_game._combat_spatial_index, map_id)
			_game.add_child(field)
			fields.append(field)
		CasterSkillVisualRegistry.set_loading_window_active(false)
		if _formal_cast:
			for node: Node in _game.get_children():
				if node is Field and not node.is_queued_for_deletion(): fields.append(node)
			assert(fields.size() == 8, "formal casts must create the full eight-field workload")
	for frame in range(30):
		await get_tree().physics_frame
	var census_before := _monster_census(enemies)
	var scheduler_before := _scheduler_census()
	var detailed_timing := OS.get_environment("HARDCORE_PROFILE_FRAME_ONLY") != "1"
	RuntimeDiagnostics.set_device_lab_performance_enabled(detailed_timing)
	EnemyActor.reset_performance_diagnostics()
	_sampling = true
	for frame in range(SAMPLE_FRAMES):
		await get_tree().physics_frame
		for enemy: EnemyActor in enemies:
			if not is_instance_valid(enemy) or not enemy._movement_step_active:
				continue
			var actual := _ground_to_screen(enemy._movement_step_target_ground_gu) - _ground_to_screen(enemy._movement_step_start_ground_gu)
			if actual.length_squared() > 0.01 and ArtSpec.mir2_client_direction_row(actual) != ArtSpec.mir2_client_direction_row(enemy.movement_facing):
				var key := str(enemy.monster_id)
				_direction_mismatches[key] = int(_direction_mismatches.get(key, 0)) + 1
	_sampling = false
	var census_after := _monster_census(enemies)
	var scheduler_after := _scheduler_census()
	var label := OS.get_environment("HARDCORE_V92_LABEL")
	if label.is_empty(): label = "unlabelled"
	var result := {
		"workload": selected,
		"detailed_timing": detailed_timing, "physics_cpu_ms": _stats(_physics_cpu_ms),
		"physics_cpu_samples_ms": _physics_cpu_ms,
		"map_id": map_id, "seed": 20260922,
		"initial_layout": initial_layout,
		"initial_layout_sha256": JSON.stringify(initial_layout).sha256_text(),
		"display_server": DisplayServer.get_name(),
		"expected_renderer": expected_renderer,
		"camera_position": str(_game._world_camera.position), "camera_zoom": str(_game._world_camera.zoom),
		"background_node_counts": _background_node_counts(),
		"wall_object_counts": _wall_object_counts(),
		"formal_cast": _formal_cast, "cast_ms": _stats(_cast_ms), "context_profiles": _context_profiles,
		"damage_lane": "production_magic_MAC_MAGSTRUCK_MINE" if _formal_cast else "legacy_benchmark_direct_damage",
		"spatial_index": _game._combat_spatial_index.diagnostics(), "enemy_count": enemies.size(), "focus": str(focus),
		"nearby_initial": most_nearby, "sample_physics_frames": SAMPLE_FRAMES,
		"monster_census_before": census_before, "monster_census_after": census_after,
		"scheduler_before": scheduler_before, "scheduler_after": scheduler_after,
		"streaming_after": _game._streaming_coordinator.monster_streaming_diagnostics(),
		"source_hashes": _profile_source_hashes(),
		"fire_wall_count": fields.size(), "frame_interval_ms": _stats(_intervals),
		"process_monitor_ms": _stats(_process_ms), "counters": EnemyActor.performance_diagnostics(),
		"wall_renderer": _game.background.wall_render_stats(), "direction_mismatches": _direction_mismatches,
		"fire_wall": fields.map(func(field: Field) -> Dictionary: return field.fire_wall_controller_diagnostics()),
		"frame_intervals": _intervals,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/repair_v92"))
	var file := FileAccess.open("res://outputs/repair_v92/world_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("WORLD_PROFILE_SUMMARY label=%s enemies=%d nearby=%d fields=%d frames=%s cpu_usec=%s direction=%s" % [
		label, enemies.size(), most_nearby, fields.size(), str(result.frame_interval_ms),
		str(result.counters.get("enemy_physics_usec", 0)), str(_direction_mismatches)])
	_game.queue_free()
	await get_tree().process_frame
	print("WORLD_CROWD_FIREWALL_PROFILE_PASS")
	get_tree().quit(0)


func _select_profile_focus(enemies: Array) -> Dictionary:
	var focus := Vector2.ZERO
	var most_nearby := -1
	for enemy: EnemyActor in enemies:
		var nearby := 0
		for other: EnemyActor in enemies:
			if enemy.spatial_index_position().distance_squared_to(other.spatial_index_position()) <= 144.0:
				nearby += 1
		if nearby > most_nearby:
			most_nearby = nearby
			focus = enemy.global_position
	return {"position": focus, "nearby": most_nearby, "kind": "authored_spawn_layout"}


func _monster_census(enemies: Array) -> Dictionary:
	# Observe outside the timed window. A target reference, actual pursuit,
	# attack reach, sprite visibility and resource residency are distinct.
	var counts := {"alive": 0, "target_player": 0, "physics_processing": 0,
		"deep_sleep": 0, "path_pending": 0, "moving": 0, "observed": 0,
		"within_2_gu": 0, "visual_processing": 0, "resident": 0,
		"sprite_in_viewport": 0, "offscreen_physics": 0}
	var rows: Array[Dictionary] = []
	var paths: Dictionary = {}
	var reasons: Dictionary = {}
	for enemy: EnemyActor in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion(): continue
		var visual: MonsterVisual = enemy.visual
		var in_view := false
		if is_instance_valid(visual) and is_instance_valid(visual.sprite) and visual.sprite.is_visible_in_tree():
			var view_bounds: Rect2 = visual.sprite.get_global_transform_with_canvas() * visual.sprite.get_rect()
			in_view = get_viewport().get_visible_rect().intersects(view_bounds)
		var distance := enemy.spatial_index_position().distance_to(_screen_to_ground(_game.player.global_position))
		var row := {"monster_id": enemy.monster_id, "ground": str(enemy.spatial_index_position()),
			"attack_starts": enemy._hc_starts, "attack_settlements": enemy._hc_settlements,
			"alive": enemy.can_receive_damage(), "target_player": enemy.target == _game.player,
			"physics_processing": enemy.is_physics_processing(), "deep_sleep": enemy._background_deep_sleeping,
			"path_pending": enemy._hc_path_pending, "moving": enemy._movement_step_active,
			"observed": enemy._hc_observed, "distance_gu": distance, "within_2_gu": distance <= 2.0,
			"visual_processing": is_instance_valid(visual) and visual.is_processing(),
			"resident": is_instance_valid(visual) and not visual.active_resources.is_empty(),
			"sprite_in_viewport": in_view, "offscreen_physics": not in_view and enemy.is_physics_processing(),
			"path_status": enemy._hc_path_status, "last_reason": enemy._hc_last_reason}
		for key: String in counts:
			if row[key]: counts[key] += 1
		paths[row.path_status] = int(paths.get(row.path_status, 0)) + 1
		reasons[row.last_reason] = int(reasons.get(row.last_reason, 0)) + 1
		rows.append(row)
	return {"counts": counts, "paths": paths, "reasons": reasons, "actors": rows}


func _scheduler_census() -> Dictionary:
	var scheduler := get_tree().root.get_node_or_null("HCMonsterPathBudget")
	if scheduler == null: return {"available": false}
	return {"available": true, "pending_jobs": scheduler.jobs.size(),
		"services": scheduler.service_count, "expansions": scheduler.expansions_count,
		"pump_usec": scheduler.diagnostic_pump_usec, "pump_calls": scheduler.diagnostic_pump_calls}


func _profile_source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["res://scripts/enemy.gd", "res://scripts/monster_visual.gd",
		"res://scripts/monster_ai_package/path_search.gd", "res://scripts/monster_ai_package/path_scheduler.gd",
		"res://scripts/game_root.gd", "res://tests/world_crowd_firewall_profile_test.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result


func _background_node_counts() -> Dictionary:
	var result: Dictionary = {}
	var pending: Array[Node] = [_game.background]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var kind := node.get_class()
		result[kind] = int(result.get(kind, 0)) + 1
		for child: Node in node.get_children(): pending.append(child)
	return result


func _wall_object_counts() -> Dictionary:
	# Count both static background children and dynamic walls owned by the
	# world's Y-sort root, after sampling so the traversal cannot affect timing.
	var probe := WallRuntimePerfProbe.new()
	probe.configure(_game.background, _game, false)
	add_child(probe)
	var result := probe._collect_counts()
	probe.queue_free()
	return result


func _ready_map(map_id: int) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _game._map_transition_in_progress and _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY:
			assert(_game.current_map_id == map_id)
			return
	assert(false, "map did not become ready")


func _screen_to_ground(position: Vector2) -> Vector2:
	return MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(MapEditorRuntimeBridge.load_map(map_id), position)


func _ground_to_screen(position: Vector2) -> Vector2:
	return MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(MapEditorRuntimeBridge.load_map(map_id), position)


func _damage(enemy: EnemyActor, power: int) -> void:
	enemy.take_damage(power, _game.player)


func _stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	if sorted.is_empty(): return {}
	return {"samples": sorted.size(), "p50": sorted[int((sorted.size() - 1) * 0.5)],
		"p95": sorted[int((sorted.size() - 1) * 0.95)], "max": sorted.back()}


func _profile_contexts() -> void:
	var loader := preload("res://scripts/skills/skill_data_loader.gd")
	for skill: String in ["wizard.fire_wall", "wizard.magic_shield", "wizard.fireball", "wizard.hellfire", "wizard.repulsion_ring", "taoist.entrapment"]:
		var definition: Dictionary = loader.skill(skill)
		if definition.is_empty(): continue
		var timings: Array[float] = []
		var candidate_total := 0
		var before: int = _game._combat_spatial_index.index_enemy_node_aabb_query_count
		for trial in range(100):
			var started := Time.get_ticks_usec()
			var context: Dictionary = _game._canonical_target_context(definition,
				_game.player.global_position, Vector2.RIGHT, false)
			timings.append(float(Time.get_ticks_usec() - started) / 1000.0)
			candidate_total += context.get("targets", []).size()
		_context_profiles[skill] = {"timings_ms": _stats(timings),
			"candidate_records": candidate_total, "aabb_queries":
			_game._combat_spatial_index.index_enemy_node_aabb_query_count - before}
