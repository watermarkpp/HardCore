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

# Stable Device Lab/Android telemetry contract. Values are window deltas:
# event fields are integer counts, *_usec and *_ms fields are accumulated
# active time, and *_max fields are maxima for the window.
const PERFORMANCE_COUNTER_FIELDS: Array[String] = [
	"foreground_ai_ticks",
	"active_enemy_physics_count",
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
	"crowd_queries",
	"crowd_index_candidates",
	"crowd_full_group_scans",
	"crowd_usec",
	"environment_guard_batches",
	"environment_point_samples",
	"environment_query_usec",
	"safe_zone_queries",
	"safe_zone_global_actor_scans",
	"safe_zone_usec",
	"actor_redraw_requests",
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
	"retarget_target_group_scans",
	"retarget_target_candidates",
	"background_ai_evaluations",
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
static var _performance_release_context := {
	"release_id": "",
	"skill_id": "",
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
	for field: String in PERFORMANCE_COUNTER_FIELDS:
		if not _performance_counters.has(field):
			_performance_counters[field] = 0


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
	_performance_values.clear()
	_performance_maxima.clear()
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
