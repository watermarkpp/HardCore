extends Node2D

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const SpatialIndex := preload("res://scripts/runtime_combat_spatial_index.gd")
const MAP_ID := 1
const COUNTS := [10, 20, 30]
const WARMUP_FRAMES := 45
const SAMPLE_FRAMES := 150
const DRAIN_LIMIT_PROCESS_FRAMES := 240

var _blocked_cells: Dictionary = {}
var _environment_revision := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	var label := OS.get_environment("HARDCORE_REV07_LABEL").strip_edges()
	if label.is_empty():
		label = "unlabelled"
	var head := OS.get_environment("HARDCORE_REV07_HEAD").strip_edges()
	var rows: Array[Dictionary] = []
	for count: int in COUNTS:
		rows.append(await _sample_count(count))
	var output := {
		"schema": "hardcore.v3.rev07.full_frame_comparison.v1",
		"label": label,
		"head": head,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(),
		"map_id": MAP_ID,
		"counts": COUNTS,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"rows": rows,
	}
	var directory := "res://outputs/hc_monster_ai_package"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/rev07_%s.json" % label, FileAccess.WRITE)
	assert(file != null, "REV07 output file could not be created")
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print(
		"HC_REV07_FULL_FRAME_PASS label=%s counts=10,20,30 frames=%d"
		% [label, SAMPLE_FRAMES]
	)
	get_tree().quit(0)


func _sample_count(count: int) -> Dictionary:
	_blocked_cells.clear()
	_environment_revision += 1
	var index := SpatialIndex.new()
	var player := PlayerCharacter.new()
	add_child(player)
	player.max_hp = 1000000000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = _ground_to_screen(Vector2(35.5, 30.5))
	player.set_physics_process(false)
	var context := _terrain_context()
	var enemies: Array[EnemyActor] = []
	for actor_index in range(count):
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(64), player, false)
		enemy.configure_runtime_map_projection(
			MAP_ID,
			Callable(self, "_ground_to_screen"),
			Callable(self, "_screen_to_ground"),
		)
		enemy.configure_terrain_navigation_context(context)
		enemy.configure_spatial_index(index, actor_index + 1)
		enemy.environment_blocker = self
		var ground := Vector2(27.5, 10.5 + float(actor_index) * 1.4)
		enemy.set_combat_position(_ground_to_screen(ground), &"rev07_spawn")
		add_child(enemy)
		index.register(
			actor_index + 1,
			MAP_ID,
			ground,
			enemy.combat_radius_gu,
			actor_index + 1,
			enemy,
			Callable(enemy, "spatial_index_position"),
		)
		enemy.target = player
		enemies.append(enemy)
	# First acquire the target on an open map, then apply the same fixed wall to
	# every run. This exercises last-known navigation rather than an artificial
	# never-observed target.
	for _frame in range(5):
		await get_tree().process_frame
	for y in range(6, 56):
		_blocked_cells[Vector2i(28, y)] = true
	_environment_revision += 1
	context = _terrain_context()
	for enemy: EnemyActor in enemies:
		enemy.configure_terrain_navigation_context(context)
	for _frame in range(WARMUP_FRAMES - 5):
		await get_tree().process_frame
	EnemyActor.reset_performance_diagnostics()
	Terrain.reset_diagnostics()
	Search.reset_diagnostics()
	var scheduler := get_tree().root.get_node_or_null("HCMonsterPathBudget")
	var scheduler_services_before := int(scheduler.get("service_count")) if scheduler != null else 0
	var scheduler_expansions_before := int(scheduler.get("expansions_count")) if scheduler != null else 0
	var scheduler_pump_calls_before := int(scheduler.get("diagnostic_pump_calls")) if scheduler != null else 0
	var scheduler_pump_usec_before := int(scheduler.get("diagnostic_pump_usec")) if scheduler != null else 0
	var full_frame_samples_ms: Array[float] = []
	var godot_monitor_samples_ms: Array[float] = []
	var previous_frame_usec := Time.get_ticks_usec()
	var sample_physics_started := Engine.get_physics_frames()
	for _frame in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		full_frame_samples_ms.append(float(now_usec - previous_frame_usec) / 1000.0)
		previous_frame_usec = now_usec
		godot_monitor_samples_ms.append(
			1000.0 * (
				float(Performance.get_monitor(Performance.TIME_PROCESS))
				+ float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
			)
		)
	assert(get_tree().get_nodes_in_group("enemies").size() == count)
	# The first HC replan may create the shared scheduler during this window.
	# Reacquire it so the 10-actor row does not mislabel candidate diagnostics as
	# unsupported merely because no job existed at window start.
	if scheduler == null:
		scheduler = get_tree().root.get_node_or_null("HCMonsterPathBudget")
	var enemy_metrics := EnemyActor.performance_diagnostics()
	var terrain_metrics := Terrain.diagnostics()
	var path_search_metrics := Search.diagnostics()
	var scheduler_services := (
		int(scheduler.get("service_count")) - scheduler_services_before
		if scheduler != null
		else 0
	)
	var scheduler_expansions := (
		int(scheduler.get("expansions_count")) - scheduler_expansions_before
		if scheduler != null
		else 0
	)
	var scheduler_pump_calls: Variant = int(scheduler.get("diagnostic_pump_calls")) - scheduler_pump_calls_before if scheduler != null else null
	var scheduler_pump_usec: Variant = int(scheduler.get("diagnostic_pump_usec")) - scheduler_pump_usec_before if scheduler != null else null
	var sample_physics_ticks := Engine.get_physics_frames() - sample_physics_started
	var sample_pending_jobs: Variant = int((scheduler.get("jobs") as Dictionary).size()) if scheduler != null else null
	var path_status_counts := _path_status_counts(enemies)
	# Drain starts after the fixed measurement window, so completion evidence cannot
	# dilute the p95 samples. Pausing actors prevents completed jobs from being
	# replaced by new replans while the same scheduler finishes its valid queue.
	for enemy: EnemyActor in enemies:
		enemy.set_physics_process(false)
	var drain_services_before := int(scheduler.get("service_count")) if scheduler != null else 0
	var drain_expansions_before := int(scheduler.get("expansions_count")) if scheduler != null else 0
	var drain_physics_started := Engine.get_physics_frames()
	var drain_process_frames := 0
	while scheduler != null and not (scheduler.get("jobs") as Dictionary).is_empty() and drain_process_frames < DRAIN_LIMIT_PROCESS_FRAMES:
		drain_process_frames += 1
		await get_tree().process_frame
	var drain_end_pending: Variant = int((scheduler.get("jobs") as Dictionary).size()) if scheduler != null else null
	var drain := {
		"start_pending_jobs": sample_pending_jobs,
		"end_pending_jobs": drain_end_pending,
		"completed_within_limit": drain_end_pending == 0 if scheduler != null else null,
		"process_frames": drain_process_frames,
		"physics_ticks": Engine.get_physics_frames() - drain_physics_started,
		"services": int(scheduler.get("service_count")) - drain_services_before if scheduler != null else null,
		"expansions": int(scheduler.get("expansions_count")) - drain_expansions_before if scheduler != null else null,
		"terminal_path_status_counts": _path_status_counts(enemies),
	}
	var row := {
		"monster_count": count,
		"full_frame_ms": _summary(full_frame_samples_ms),
		"godot_process_monitor_ms_diagnostic_only": _summary(godot_monitor_samples_ms),
		"enemy_metrics": enemy_metrics,
		"terrain_metrics": terrain_metrics,
		"path_search_metrics": path_search_metrics,
		"scheduler_services": scheduler_services,
		"scheduler_expansions": scheduler_expansions,
		"scheduler_pump_calls": scheduler_pump_calls,
		"scheduler_pump_usec": scheduler_pump_usec,
		"scheduler_maximum_wait_frames": int(scheduler.get("maximum_wait_frames")) if scheduler != null else null,
		"scheduler_pending_jobs": sample_pending_jobs,
		"path_status_counts": path_status_counts,
		"sample_process_frames": SAMPLE_FRAMES,
		"sample_physics_ticks": sample_physics_ticks,
		"post_sample_drain": drain,
	}
	index.clear_map(MAP_ID)
	for enemy: EnemyActor in enemies:
		enemy.queue_free()
	player.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	return row


func _path_status_counts(enemies: Array[EnemyActor]) -> Dictionary:
	var counts: Dictionary = {}
	for enemy: EnemyActor in enemies:
		var status := "unsupported_baseline"
		if enemy.has_method("hc_package_policy_snapshot"):
			status = str(enemy.call("hc_package_policy_snapshot").get("path_status", ""))
		counts[status] = int(counts.get(status, 0)) + 1
	return counts


func _summary(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"min": sorted[0],
		"max": sorted[-1],
		"samples": sorted.size(),
	}


func _percentile(sorted: Array[float], ratio: float) -> float:
	var index := clampi(ceili(float(sorted.size()) * ratio) - 1, 0, sorted.size() - 1)
	return sorted[index]


func is_environment_point_blocked(world_px: Vector2) -> bool:
	return _blocked_cells.has(Vector2i(_screen_to_ground(world_px).floor()))


func environment_collision_revision() -> int:
	return _environment_revision


func _terrain_context() -> Dictionary:
	var blocked := _blocked_cells.duplicate()
	blocked.make_read_only()
	var context := {
		"valid": true,
		"contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": MAP_ID,
		"build_sha256": "a".repeat(63) + ("%x" % posmod(_environment_revision, 16)),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(64, 64),
		"blocked_cells": blocked,
	}
	context.make_read_only()
	return context


func _ground_to_screen(value: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(value)
