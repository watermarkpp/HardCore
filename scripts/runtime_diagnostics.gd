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
const SLOW_FRAME_TRACE_CAPACITY := 32
const SLOW_EVENT_TRACE_CAPACITY := 64
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
	"enemy_crowd_goal_calls",
	"enemy_crowd_goal_usec",
	"enemy_neighbor_calls",
	"enemy_neighbor_usec",
	"enemy_motion_clear_calls",
	"enemy_motion_clear_usec",
	"enemy_motion_candidate_checks",
	"enemy_motion_body_checks",
	"enemy_motion_polygon_checks",
	"enemy_motion_pool_refills",
	"enemy_motion_pool_reuses",
	"enemy_motion_pool_revision_misses",
	"enemy_motion_pool_candidates",
	"enemy_observation_calls",
	"enemy_observation_wait_returns",
	"enemy_observation_scope_changes",
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
	"durability_event_commits",
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
	## R1 monster struck system: aggregate counters only, never per-hit logs.
	"monster_struck_event_count",
	"monster_struck_visual_pending_max",
	"monster_direct_magic_walk_delay_count",
	"monster_magic_mine_struck_count",
	"monster_dot_no_struck_count",
	## R1.2 presentation FIFO overflow (fixed ring capacity exhausted; the
	## newest event is dropped - queued actions keep their order).
	"monster_presentation_queue_overflow",
]
const PERFORMANCE_FIELDS: Array[String] = PERFORMANCE_COUNTER_FIELDS

const NumericDiagnostics := preload("res://scripts/gameplay/profile/profile_diagnostics_core.gd")
static var _numeric_core: RefCounted

static func performance_owner_core() -> RefCounted:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if _numeric_core == null: _numeric_core = NumericDiagnostics.new()
	_numeric_core.configure_policy({"enabled":performance_enabled(),"detail_enabled":performance_detail_enabled(),"detail_mode":device_lab_detail_mode()},"main")
	return _numeric_core

static var _performance_counters:
	get: return performance_owner_core()._performance_counters
	set(value): performance_owner_core()._performance_counters = value
static var _performance_values:
	get: return performance_owner_core()._performance_values
	set(value): performance_owner_core()._performance_values = value
static var _performance_maxima:
	get: return performance_owner_core()._performance_maxima
	set(value): performance_owner_core()._performance_maxima = value
static var _performance_window_id:
	get: return performance_owner_core()._performance_window_id
	set(value): performance_owner_core()._performance_window_id = value
static var _performance_window_started_msec:
	get: return performance_owner_core()._performance_window_started_msec
	set(value): performance_owner_core()._performance_window_started_msec = value
static var _performance_fields_initialized:
	get: return performance_owner_core()._performance_fields_initialized
	set(value): performance_owner_core()._performance_fields_initialized = value
static var _performance_release_context:
	get: return performance_owner_core()._performance_release_context
	set(value): performance_owner_core()._performance_release_context = value
static var _frame_samples:
	get: return performance_owner_core()._frame_samples
	set(value): performance_owner_core()._frame_samples = value
static var _recent_slow_events:
	get: return performance_owner_core()._recent_slow_events
	set(value): performance_owner_core()._recent_slow_events = value
static var _slow_frame_trace:
	get: return performance_owner_core()._slow_frame_trace
	set(value): performance_owner_core()._slow_frame_trace = value
static var _frame_sample_write_index:
	get: return performance_owner_core()._frame_sample_write_index
	set(value): performance_owner_core()._frame_sample_write_index = value
static var _frame_sample_count:
	get: return performance_owner_core()._frame_sample_count
	set(value): performance_owner_core()._frame_sample_count = value
static var _frame_sample_dropped_count:
	get: return performance_owner_core()._frame_sample_dropped_count
	set(value): performance_owner_core()._frame_sample_dropped_count = value
static var _frame_threshold_counts:
	get: return performance_owner_core()._frame_threshold_counts
	set(value): performance_owner_core()._frame_threshold_counts = value
static var _wall_usec_prev:
	get: return performance_owner_core()._wall_usec_prev
	set(value): performance_owner_core()._wall_usec_prev = value
static var _wall_usec_valid:
	get: return performance_owner_core()._wall_usec_valid
	set(value): performance_owner_core()._wall_usec_valid = value
static var _wall_boundary_discards:
	get: return performance_owner_core()._wall_boundary_discards
	set(value): performance_owner_core()._wall_boundary_discards = value
static var _device_lab_wall_usec_prev:
	get: return performance_owner_core()._device_lab_wall_usec_prev
	set(value): performance_owner_core()._device_lab_wall_usec_prev = value
static var _device_lab_wall_usec_valid:
	get: return performance_owner_core()._device_lab_wall_usec_valid
	set(value): performance_owner_core()._device_lab_wall_usec_valid = value
static var _device_lab_wall_boundary_discards:
	get: return performance_owner_core()._device_lab_wall_boundary_discards
	set(value): performance_owner_core()._device_lab_wall_boundary_discards = value

static var _device_lab_performance_override := false
static var _device_lab_performance_override_set := false
static var _performance_gate_initialized := false
static var _performance_gate_enabled := false
const WALL_BOUNDARY_DISCARD_MS := 5000.0

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
	# R14-A: detailed per-call counters/timers are observer work; they must
	# be disabled in frame_only mode so the frame pacing sample is measured
	# without instrumenting every enemy hot path.
	return performance_detail_enabled()


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


# R14-A: Device Lab measurement observer correction. Two detail modes:
# "full" keeps the R13 attribution counters/timers; "frame_only" keeps the
# wall-clock frame pacing ring but disables the per-call micro timers and
# performance Dictionary updates, so a release-like pacing baseline can be
# measured without the observer itself skewing CPU attribution. Release is
# fail-closed: performance_enabled() is already false there.
const DEVICE_LAB_DETAIL_FRAME_ONLY := "frame_only"
const DEVICE_LAB_DETAIL_FULL := "full"
static var _device_lab_detail_mode := DEVICE_LAB_DETAIL_FULL


static func set_device_lab_detail_mode(mode: String) -> bool:
	if mode not in [DEVICE_LAB_DETAIL_FRAME_ONLY, DEVICE_LAB_DETAIL_FULL]:
		return false
	_device_lab_detail_mode = mode
	return true


static func device_lab_detail_mode() -> String:
	return _device_lab_detail_mode


static func performance_detail_enabled() -> bool:
	if not performance_enabled():
		return false
	if _device_lab_performance_override_set and _device_lab_performance_override:
		return _device_lab_detail_mode == DEVICE_LAB_DETAIL_FULL
	return true


static func _ensure_performance_window() -> void:
	performance_owner_core()._ensure_performance_window()


static func increment_performance_counter(field: StringName, amount := 1) -> void:
	performance_owner_core().increment_performance_counter(field, amount)


static func add_performance_value(field: StringName, amount: float) -> void:
	performance_owner_core().add_performance_value(field, amount)


static func set_performance_value(field: StringName, value: float) -> void:
	performance_owner_core().set_performance_value(field, value)


static func record_performance_max(field: StringName, value: float) -> void:
	performance_owner_core().record_performance_max(field, value)


static func _note_slow_event(label: String, duration_ms: float) -> void:
	performance_owner_core()._note_slow_event(label, duration_ms)


static func _trace_slow_frame(previous_usec: int, now_usec: int, gap_ms: float) -> void:
	performance_owner_core()._trace_slow_frame(previous_usec, now_usec, gap_ms)
static func record_frame_time_ms(frame_ms: float) -> void:
	performance_owner_core().record_frame_time_ms(frame_ms)
static func wall_frame_interval_ms() -> float:
	return performance_owner_core().wall_frame_interval_ms()


static func reset_wall_frame_interval() -> void:
	performance_owner_core().reset_wall_frame_interval()


static func wall_boundary_discard_count() -> int:
	return performance_owner_core().wall_boundary_discard_count()
static func record_device_lab_frame_interval() -> void:
	performance_owner_core().record_device_lab_frame_interval()


static func reset_device_lab_frame_interval() -> void:
	performance_owner_core().reset_device_lab_frame_interval()


static func _frame_percentile(samples: Array, fraction: float) -> float:
	return performance_owner_core()._frame_percentile(samples, fraction)


static func _frame_ratio(count: int) -> float:
	return performance_owner_core()._frame_ratio(count)


static func frame_sampling_snapshot() -> Dictionary:
	return performance_owner_core().frame_sampling_snapshot()


static func timing_start() -> int:
	return performance_owner_core().timing_start()


static func timing_now() -> int:
	return performance_owner_core().timing_now()


static func timing_elapsed_usec(started_usec: int) -> int:
	return performance_owner_core().timing_elapsed_usec(started_usec)


static func record_timing_usec(field: StringName, started_usec: int) -> int:
	return performance_owner_core().record_timing_usec(field, started_usec)
static func begin_timed_segment(call_field: StringName) -> int:
	return performance_owner_core().begin_timed_segment(call_field)


static func end_timed_segment(duration_field: StringName, started_usec: int) -> int:
	return performance_owner_core().end_timed_segment(duration_field, started_usec)


static func record_timing_ms(field: StringName, started_usec: int) -> float:
	return performance_owner_core().record_timing_ms(field, started_usec)


static func performance_counter(field: StringName) -> int:
	return performance_owner_core().performance_counter(field)


static func set_performance_release_context(release_id: String, skill_id: String) -> void:
	performance_owner_core().set_performance_release_context(release_id, skill_id)


static func mark_performance_release_context(release_id: String, skill_id: String) -> void:
	performance_owner_core().mark_performance_release_context(release_id, skill_id)


static func performance_release_context() -> Dictionary:
	return performance_owner_core().performance_release_context()


static func performance_counters() -> Dictionary:
	return performance_owner_core().performance_counters()


static func reset_performance_window() -> Dictionary:
	return performance_owner_core().reset_performance_window()


static func reset_window() -> Dictionary:
	return performance_owner_core().reset_window()


static func read_performance_window(context: Dictionary = {}) -> Dictionary:
	return performance_owner_core().read_performance_window(context)


static func read_window(context: Dictionary = {}) -> Dictionary:
	return performance_owner_core().read_window(context)
