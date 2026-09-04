class_name RuntimeDiagnostics
extends RefCounted

# Runtime diagnostics are deliberately opt-in. The performance window is a
# single shared accumulator used by the monster, combat, world and Device Lab
# paths; it is not a second profiler or an autoload. All detailed timing is
# guarded in this class so Release gameplay never reaches Time.get_ticks_usec().

const SETTING_ENABLED := &"hardcore/debug/diagnostics/enabled"
const SETTING_COMBAT := &"hardcore/debug/diagnostics/combat"
const SETTING_SKILL_GEOMETRY := &"hardcore/debug/diagnostics/skill_geometry"
const SETTING_SKILL_VISUAL := &"hardcore/debug/diagnostics/skill_visual"
const SETTING_PROJECTILE := &"hardcore/debug/diagnostics/projectile"
const SETTING_BOOTSTRAP := &"hardcore/debug/diagnostics/bootstrap"
const SETTING_INPUT_GATE := &"hardcore/debug/diagnostics/input_gate"
const SETTING_FILE_OUTPUT := &"hardcore/debug/diagnostics/file_output"
const SETTING_PERFORMANCE := &"hardcore/debug/diagnostics/performance"
const SETTING_DEVICE_LAB_PERFORMANCE := &"hardcore/debug/diagnostics/device_lab_performance"

const PERFORMANCE_SCHEMA_ID := "hardcore.monster_density_diagnostics.v1"
## Frame samples are only retained while the explicit Debug/Device Lab gate is
## enabled.  A 4096-entry ring covers the report's 20-30 second windows at
## normal frame rates without allowing a long-running process to grow memory.
const FRAME_SAMPLE_CAPACITY := 4096
const FRAME_THRESHOLD_MS := {
	"over_16_67": 16.67,
	"over_33_33": 33.33,
	"over_50": 50.0,
	"over_100": 100.0,
}
const GPU_FRAME_METRIC_UNAVAILABLE_REASON := "godot_performance_api_has_no_reliable_gpu_frame_time_monitor"

# Stable Device Lab/Android telemetry contract. Values are window deltas:
# event fields are integer counts, *_usec and *_ms fields are accumulated
# active time, and *_max fields are maxima for the window. The enemy segment
# totals are inclusive: physics contains background/retarget/movement/visual
# work, movement contains the environment guard, and terrain path time is
# nested in movement when a fallback path is requested; do not sum them.
const PERFORMANCE_COUNTER_FIELDS: Array[String] = [
	"foreground_ai_ticks",
	"active_enemy_physics_count",
	"enemy_physics_calls",
	"enemy_physics_usec",
	"enemy_projection_calls",
	"enemy_projection_usec",
	"moving_enemy_count",
	"engaged_enemy_count",
	"attack_los_requests",
	"attack_los_evaluations",
	"attack_los_cache_hits",
	"attack_los_map_samples",
	"attack_los_physics_rays",
	"attack_los_usec",
	"physics_moves",
	"move_and_slide_usec",
	"enemy_movement_strategy_calls",
	"enemy_movement_strategy_usec",
	"crowd_queries",
	"crowd_index_candidates",
	"crowd_full_group_scans",
	"crowd_usec",
	"environment_guard_batches",
	"environment_point_samples",
	"environment_query_usec",
	"enemy_environment_guard_calls",
	"enemy_environment_guard_usec",
	"enemy_terrain_path_calls",
	"enemy_terrain_path_usec",
	"enemy_terrain_path_expansions",
	"enemy_terrain_path_expansions_max",
	"enemy_terrain_path_accepted",
	"enemy_terrain_path_budget_rejections",
	"safe_zone_queries",
	"safe_zone_global_actor_scans",
	"safe_zone_usec",
	"actor_redraw_requests",
	"enemy_visual_update_calls",
	"enemy_visual_update_usec",
	"visual_animation_updates",
	"visual_render_state_changes",
	"process_ms",
	"physics_process_ms",
	"draw_calls",
	"render_primitives",
	"texture_mem",
	"video_mem",
	"crowd_grid_builds",
	"crowd_grid_actor_scans",
	"crowd_query_candidates",
	"crowd_steering_evaluations",
	"retarget_full_scans",
	"retarget_decisions",
	"enemy_retarget_calls",
	"enemy_retarget_usec",
	"retarget_target_group_scans",
	"retarget_target_candidates",
	"background_ai_evaluations",
	"enemy_background_tick_calls",
	"enemy_background_tick_usec",
	"background_fast_path_skips",
	"background_deep_sleep_entries",
	"background_deep_sleep_wakeups",
	"death_pending_marks",
	"death_same_release_unregistrations",
	"death_begin_calls",
	"death_physics_process_calls_after_begin",
	"death_batch_count",
	"death_batch_size_max",
	"death_settlement_usec",
	"death_resolve_active_usec",
	"death_target_refresh_count",
	"death_queue_state_transitions",
	"death_queue_retry_count",
	"death_queue_failed_count",
	"death_queue_cancelled_count",
	"death_queue_committed_count",
	"death_queue_materialization_failures",
	"death_work_frames",
	"death_jobs_per_frame_max",
	"drop_nodes_per_frame_max",
	"respawn_state_updates",
	"drop_roll_count",
	"drop_roll_usec",
	"drop_request_count",
	"drop_node_spawn_count",
	"drop_node_spawn_usec",
	"drop_work_frames",
	"drop_queue_depth_max",
	"drop_queue_oldest_age_ms",
	"unexpected_sync_loot_texture_loads",
	"active_loot_pickups",
	"loot_pickup_process_calls",
	"loot_collection_global_checks",
	"loot_collection_spatial_queries",
	"loot_collection_candidates",
	"loot_collection_authority_checks",
	"loot_visual_updates",
	"loot_fallback_redraw_requests",
	"loot_manager_player_events",
	"loot_manager_registration_checks",
	"loot_manager_retry_checks",
	"loot_manager_fail_safe_checks",
	"loot_manager_exact_range_checks",
	"loot_manager_collection_requests",
	"loot_manager_visual_updates",
	"loot_manager_full_scans",
	"loot_manager_visual_registry_scans",
	"loot_manager_visual_registry_entries",
	"loot_collection_origin_rejections",
	"loot_spatial_registers",
	"loot_spatial_unregisters",
	"loot_spatial_queries",
	"loot_spatial_candidates",
	"loot_spatial_full_scans",
	"aoe_release_count",
	"aoe_query_plan_builds",
	"aoe_snapshot_validation_calls",
	"aoe_spatial_queries",
	"aoe_spatial_candidates",
	"aoe_exact_intersection_tests",
	"aoe_selected_targets",
	"aoe_full_enemy_group_scans",
	"aoe_nested_cell_enemy_scans",
	"aoe_candidate_usec",
	"aoe_exact_phase_usec",
	"aoe_max_single_release_candidate_usec",
	"aoe_damage_target_count",
	"direct_spell_stats_snapshot_count",
	"direct_spell_full_monster_data_duplicates",
	"direct_spell_resolution_count",
	"direct_spell_resolution_usec",
	"take_damage_calls",
	"take_damage_usec",
	"lethal_damage_count",
	"hit_animation_requests",
	"overhead_health_refreshes",
	"actor_redraw_requests_from_damage",
]
const PERFORMANCE_FIELDS: Array[String] = PERFORMANCE_COUNTER_FIELDS

static var _performance_counters: Dictionary = {}
static var _performance_values: Dictionary = {}
static var _performance_maxima: Dictionary = {}
static var _performance_window_id := 0
static var _performance_window_started_msec := 0
static var _device_lab_performance_override := false
static var _device_lab_performance_override_set := false
static var _performance_gate_initialized := false
static var _performance_gate_enabled := false
static var _performance_fields_initialized := false
static var _performance_release_context := {
	"release_id": "",
	"skill_id": "",
}
static var _frame_samples: Array = []
static var _frame_sample_write_index := 0
static var _frame_sample_count := 0
static var _frame_sample_dropped_count := 0
static var _frame_threshold_counts := {
	"over_16_67": 0,
	"over_33_33": 0,
	"over_50": 0,
	"over_100": 0,
}


static func is_enabled(category := &"") -> bool:
	var _global: bool = ProjectSettings.get_setting(SETTING_ENABLED, false)
	if not _global:
		return false
	if category.is_empty():
		return true
	return bool(ProjectSettings.get_setting(category, false))


static func combat_enabled() -> bool:
	return is_enabled(SETTING_COMBAT)


static func skill_geometry_enabled() -> bool:
	return is_enabled(SETTING_SKILL_GEOMETRY)


static func bootstrap_enabled() -> bool:
	return is_enabled(SETTING_BOOTSTRAP)


static func input_gate_enabled() -> bool:
	return is_enabled(SETTING_INPUT_GATE)


static func file_output_enabled() -> bool:
	return is_enabled(SETTING_FILE_OUTPUT)


static func performance_enabled() -> bool:
	if not _performance_gate_initialized:
		refresh_performance_gate()
	return _performance_gate_enabled


static func refresh_performance_gate() -> bool:
	# ProjectSettings are intentionally read only at startup or at an explicit
	# Device Lab/test refresh boundary. The monster loop only sees the cached
	# bool above, while Release remains fail-closed regardless of settings.
	if not OS.is_debug_build():
		_performance_gate_enabled = false
	else:
		var explicit_device_lab_switch := (
			bool(ProjectSettings.get_setting(SETTING_DEVICE_LAB_PERFORMANCE, false))
			or (_device_lab_performance_override_set and _device_lab_performance_override)
		)
		_performance_gate_enabled = explicit_device_lab_switch or (
			bool(ProjectSettings.get_setting(SETTING_ENABLED, false))
			and bool(ProjectSettings.get_setting(SETTING_PERFORMANCE, false))
		)
	_performance_gate_initialized = true
	return _performance_gate_enabled


static func performance_timing_enabled() -> bool:
	return performance_enabled()


static func performance_window_enabled() -> bool:
	return performance_enabled()


static func set_device_lab_performance_enabled(enabled: bool) -> bool:
	# This is an in-memory Debug/Device Lab switch only. It cannot enable
	# diagnostics in Release and never writes project settings or save data.
	if not OS.is_debug_build():
		return false
	_device_lab_performance_override_set = true
	_device_lab_performance_override = enabled
	refresh_performance_gate()
	return true


static func device_lab_performance_override_enabled() -> bool:
	return (
		_device_lab_performance_override_set
		and _device_lab_performance_override
	)


static func _ensure_performance_window() -> void:
	if _performance_window_started_msec <= 0:
		_performance_window_started_msec = Time.get_ticks_msec()
	if _performance_fields_initialized:
		return
	for field: String in PERFORMANCE_COUNTER_FIELDS:
		_performance_counters[field] = 0
	_performance_fields_initialized = true


static func increment_performance_counter(field: StringName, amount := 1) -> void:
	if not performance_enabled() or amount == 0:
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_counters[key] = int(_performance_counters.get(key, 0)) + amount


static func add_performance_value(field: StringName, amount: float) -> void:
	if not performance_enabled() or not is_finite(amount) or is_zero_approx(amount):
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_values[key] = float(_performance_values.get(key, 0.0)) + amount


static func set_performance_value(field: StringName, value: float) -> void:
	if not performance_enabled() or not is_finite(value):
		return
	_ensure_performance_window()
	_performance_values[str(field)] = value


static func record_performance_max(field: StringName, value: float) -> void:
	if not performance_enabled() or not is_finite(value):
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_maxima[key] = maxf(float(_performance_maxima.get(key, 0.0)), value)


## Records one total idle-frame duration in milliseconds.  This is deliberately
## separate from process/physics timings: the reports require the total frame
## pacing seen by the player, including rendering and scheduling.  Callers must
## already be on the explicit Debug/Device Lab path; this method repeats the
## gate check so an accidental Release caller is a no-op.
static func record_frame_time_ms(frame_ms: float) -> void:
	if not performance_enabled() or not is_finite(frame_ms) or frame_ms < 0.0:
		return
	_ensure_performance_window()
	var sample := maxf(frame_ms, 0.0)
	if _frame_samples.size() < FRAME_SAMPLE_CAPACITY:
		_frame_samples.append(sample)
	else:
		_frame_samples[_frame_sample_write_index] = sample
		_frame_sample_write_index = (_frame_sample_write_index + 1) % FRAME_SAMPLE_CAPACITY
		_frame_sample_dropped_count += 1
	_frame_sample_count += 1
	if sample > float(FRAME_THRESHOLD_MS["over_16_67"]):
		_frame_threshold_counts["over_16_67"] = int(_frame_threshold_counts["over_16_67"]) + 1
	if sample > float(FRAME_THRESHOLD_MS["over_33_33"]):
		_frame_threshold_counts["over_33_33"] = int(_frame_threshold_counts["over_33_33"]) + 1
	if sample > float(FRAME_THRESHOLD_MS["over_50"]):
		_frame_threshold_counts["over_50"] = int(_frame_threshold_counts["over_50"]) + 1
	if sample > float(FRAME_THRESHOLD_MS["over_100"]):
		_frame_threshold_counts["over_100"] = int(_frame_threshold_counts["over_100"]) + 1


static func _frame_percentile(samples: Array, fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array = samples.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return float(sorted[index])


static func _frame_ratio(count: int) -> float:
	if _frame_sample_count <= 0:
		return 0.0
	return float(count) / float(_frame_sample_count)


static func frame_sampling_snapshot() -> Dictionary:
	var samples: Array = _frame_samples.duplicate()
	var p50 := _frame_percentile(samples, 0.50)
	var p95 := _frame_percentile(samples, 0.95)
	var p99 := _frame_percentile(samples, 0.99)
	var over_16_67 := int(_frame_threshold_counts["over_16_67"])
	var over_33_33 := int(_frame_threshold_counts["over_33_33"])
	var over_50 := int(_frame_threshold_counts["over_50"])
	var over_100 := int(_frame_threshold_counts["over_100"])
	var thresholds := {
		"over_16_67_ms": {
			"threshold_ms": float(FRAME_THRESHOLD_MS["over_16_67"]),
			"count": over_16_67,
			"ratio": _frame_ratio(over_16_67),
		},
		"over_33_33_ms": {
			"threshold_ms": float(FRAME_THRESHOLD_MS["over_33_33"]),
			"count": over_33_33,
			"ratio": _frame_ratio(over_33_33),
		},
		"over_50_ms": {
			"threshold_ms": float(FRAME_THRESHOLD_MS["over_50"]),
			"count": over_50,
			"ratio": _frame_ratio(over_50),
		},
		"over_100_ms": {
			"threshold_ms": float(FRAME_THRESHOLD_MS["over_100"]),
			"count": over_100,
			"ratio": _frame_ratio(over_100),
		},
	}
	var gpu := {
		"available": false,
		"frame_ms": null,
		"reason": GPU_FRAME_METRIC_UNAVAILABLE_REASON,
	}
	# Keep the simple top-level aliases for CSV/PowerShell consumers while the
	# nested object is the versioned, self-describing contract.
	return {
		"frame_count": _frame_sample_count,
		"frame_samples_retained": samples.size(),
		"frame_sample_capacity": FRAME_SAMPLE_CAPACITY,
		"frame_samples_dropped": _frame_sample_dropped_count,
		"frame_sample_overflowed": _frame_sample_dropped_count > 0,
		"frame_percentiles_exact": _frame_sample_count > 0 and _frame_sample_dropped_count == 0,
		"frame_ms_p50": p50,
		"frame_ms_p95": p95,
		"frame_ms_p99": p99,
		"p50_ms": p50,
		"p95_ms": p95,
		"p99_ms": p99,
		"frames_over_16_67ms": over_16_67,
		"frames_over_16_67_ratio": _frame_ratio(over_16_67),
		"frames_over_33_33ms": over_33_33,
		"frames_over_33_33_ratio": _frame_ratio(over_33_33),
		"frames_over_50ms": over_50,
		"frames_over_50_ratio": _frame_ratio(over_50),
		"frames_over_100ms": over_100,
		"frames_over_100_ratio": _frame_ratio(over_100),
		"frame_timing": {
			"frame_count": _frame_sample_count,
			"retained_sample_count": samples.size(),
			"sample_capacity": FRAME_SAMPLE_CAPACITY,
			"dropped_sample_count": _frame_sample_dropped_count,
			"percentiles_exact": _frame_sample_count > 0 and _frame_sample_dropped_count == 0,
			"p50_ms": p50,
			"p95_ms": p95,
			"p99_ms": p99,
			"thresholds": thresholds,
			"gpu": gpu,
		},
		"gpu_frame_ms": gpu,
	}


static func timing_start() -> int:
	if not performance_timing_enabled():
		return 0
	return Time.get_ticks_usec()


static func timing_now() -> int:
	if not performance_timing_enabled():
		return 0
	return Time.get_ticks_usec()


static func timing_elapsed_usec(started_usec: int) -> int:
	if started_usec <= 0 or not performance_timing_enabled():
		return 0
	return maxi(0, timing_now() - started_usec)


static func record_timing_usec(field: StringName, started_usec: int) -> int:
	var elapsed := timing_elapsed_usec(started_usec)
	if elapsed > 0:
		increment_performance_counter(field, elapsed)
	return elapsed


## Starts one inclusive runtime segment and records its call in the same
## cached-gate branch. A zero token is the disabled fast path; the matching
## end call then returns without reading the clock or touching the window.
static func begin_timed_segment(call_field: StringName) -> int:
	if not performance_timing_enabled():
		return 0
	_ensure_performance_window()
	var key := str(call_field)
	_performance_counters[key] = int(_performance_counters.get(key, 0)) + 1
	return Time.get_ticks_usec()


static func end_timed_segment(duration_field: StringName, started_usec: int) -> int:
	if started_usec <= 0 or not performance_timing_enabled():
		return 0
	var elapsed := maxi(0, Time.get_ticks_usec() - started_usec)
	if elapsed > 0:
		var key := str(duration_field)
		_performance_counters[key] = int(_performance_counters.get(key, 0)) + elapsed
	return elapsed


static func record_timing_ms(field: StringName, started_usec: int) -> float:
	var elapsed := timing_elapsed_usec(started_usec)
	if elapsed > 0:
		add_performance_value(field, float(elapsed) / 1000.0)
	return float(elapsed) / 1000.0


static func performance_counter(field: StringName) -> int:
	return int(_performance_counters.get(str(field), 0))


static func set_performance_release_context(release_id: String, skill_id: String) -> void:
	if not performance_enabled():
		return
	var resolved_release_id := release_id
	var resolved_skill_id := skill_id
	if resolved_release_id.is_empty() and not resolved_skill_id.is_empty():
		resolved_release_id = resolved_skill_id
	if resolved_skill_id.is_empty() and not resolved_release_id.is_empty():
		resolved_skill_id = resolved_release_id
	if resolved_release_id.is_empty() and resolved_skill_id.is_empty():
		return
	_performance_release_context = {
		"release_id": resolved_release_id,
		"skill_id": resolved_skill_id,
	}


static func mark_performance_release_context(release_id: String, skill_id: String) -> void:
	set_performance_release_context(release_id, skill_id)


static func performance_release_context() -> Dictionary:
	return _performance_release_context.duplicate(true)


static func performance_counters() -> Dictionary:
	_ensure_performance_window()
	var result := {}
	for field: String in PERFORMANCE_COUNTER_FIELDS:
		result[field] = int(_performance_counters.get(field, 0))
	for key: Variant in _performance_values.keys():
		result[str(key)] = float(_performance_values[key])
	for key: Variant in _performance_maxima.keys():
		result[str(key)] = float(_performance_maxima[key])
	return result


static func reset_performance_window() -> Dictionary:
	_performance_counters.clear()
	_performance_fields_initialized = false
	_performance_values.clear()
	_performance_maxima.clear()
	_frame_samples.clear()
	_frame_sample_write_index = 0
	_frame_sample_count = 0
	_frame_sample_dropped_count = 0
	_frame_threshold_counts = {
		"over_16_67": 0,
		"over_33_33": 0,
		"over_50": 0,
		"over_100": 0,
	}
	_performance_release_context = {
		"release_id": "",
		"skill_id": "",
	}
	_performance_window_id += 1
	_performance_window_started_msec = Time.get_ticks_msec()
	_ensure_performance_window()
	return read_performance_window()


static func reset_window() -> Dictionary:
	return reset_performance_window()


static func read_performance_window(context: Dictionary = {}) -> Dictionary:
	var result := performance_counters()
	var frame_sampling := frame_sampling_snapshot()
	for key: Variant in frame_sampling.keys():
		result[str(key)] = frame_sampling[key]
	result["schema"] = PERFORMANCE_SCHEMA_ID
	result["window_id"] = _performance_window_id
	result["window_started_ms"] = _performance_window_started_msec
	result["window_elapsed_ms"] = maxi(
		0,
		Time.get_ticks_msec() - _performance_window_started_msec
	)
	result["diagnostics_enabled"] = performance_enabled()
	result["timing_enabled"] = performance_timing_enabled()
	result["context"] = context.duplicate(true)
	result["counters"] = performance_counters()
	return result


static func read_window(context: Dictionary = {}) -> Dictionary:
	return read_performance_window(context)
