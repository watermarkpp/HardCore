extends RefCounted

## One owner instance per domain. Numeric algorithms below are extracted from
## RuntimeDiagnostics without changing thresholds, rings, counters or clock
## calculations. Only Main may observe actual M frame intervals.
var _owner_thread := OS.get_thread_caller_id()
var _enabled := false
var _detail := false
var _detail_mode := "full"
var _measurement_domain := "simulation"

func configure_policy(policy: Dictionary, measurement_domain: String) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	assert(measurement_domain in ["main", "simulation"])
	assert(policy.has("enabled") and policy.has("detail_enabled") and policy.has("detail_mode"))
	_enabled = bool(policy.enabled)
	_detail = bool(policy.detail_enabled)
	_detail_mode = str(policy.detail_mode)
	_measurement_domain = measurement_domain

func performance_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _enabled

func performance_detail_enabled() -> bool:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _detail

func performance_timing_enabled() -> bool:
	return performance_detail_enabled()

func device_lab_detail_mode() -> String:
	return _detail_mode

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

var _performance_counters: Dictionary = {}
var _performance_values: Dictionary = {}
var _performance_maxima: Dictionary = {}
var _performance_window_id := 0
var _performance_window_started_msec := 0
var _performance_fields_initialized := false
var _performance_release_context := {
	"release_id": "",
	"skill_id": "",
}
var _frame_samples: Array = []
var _recent_slow_events: Array[Dictionary] = []
var _slow_frame_trace: Array[Dictionary] = []
var _frame_sample_write_index := 0
var _frame_sample_count := 0
var _frame_sample_dropped_count := 0
var _frame_threshold_counts := {
	"over_16_67": 0,
	"over_33_33": 0,
	"over_50": 0,
	"over_100": 0,
}
## Real wall-clock frame pacing (perf-smoothness-r1 Phase A). `_process(delta)`
## is clamped by the engine at max_physics_steps_per_frame/physics_ticks_per_second
## (8/60 ≈ 0.133s by default), so delta-based sampling is blind to real stalls.
## This recorder measures the wall time between consecutive process callbacks
## with Time.get_ticks_usec instead. Deliberately NOT gated: the ungated
## FRAME-STALL/AOE window probes in GameRoot share it, and it costs one native
## clock read per process frame on Debug builds only (Release call sites are
## guarded by OS.is_debug_build() before calling).
const WALL_BOUNDARY_DISCARD_MS := 5000.0
var _wall_usec_prev := 0
var _wall_usec_valid := false
var _wall_boundary_discards := 0
# Device Lab keeps its OWN prev timestamp: it is gated and may be toggled
# independently of the ungated probe recorder, and two recorders sharing one
# prev would steal each other's intervals within the same process frame.
var _device_lab_wall_usec_prev := 0
var _device_lab_wall_usec_valid := false
var _device_lab_wall_boundary_discards := 0



func _ensure_performance_window() -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if _performance_window_started_msec <= 0:
		_performance_window_started_msec = Time.get_ticks_msec()
	if _performance_fields_initialized:
		return
	for field: String in PERFORMANCE_COUNTER_FIELDS:
		_performance_counters[field] = 0
	_performance_fields_initialized = true

func increment_performance_counter(field: StringName, amount := 1) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# R14-A: observer counters are disabled in frame_only mode.
	if not performance_detail_enabled() or amount == 0:
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_counters[key] = int(_performance_counters.get(key, 0)) + amount

func add_performance_value(field: StringName, amount: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# R14-A: observer values are disabled in frame_only mode.
	if not performance_detail_enabled() or not is_finite(amount) or is_zero_approx(amount):
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_values[key] = float(_performance_values.get(key, 0.0)) + amount

func set_performance_value(field: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# R14-A: observer values are disabled in frame_only mode.
	if not performance_detail_enabled() or not is_finite(value):
		return
	_ensure_performance_window()
	_performance_values[str(field)] = value

func record_performance_max(field: StringName, value: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# R14-A: observer maxima are disabled in frame_only mode.
	if not performance_detail_enabled() or not is_finite(value):
		return
	_ensure_performance_window()
	var key := str(field)
	_performance_maxima[key] = maxf(float(_performance_maxima.get(key, 0.0)), value)
	if key in [
		"death_save_max_ms", "durability_save_max_ms",
		"loot_prepare_max_ms", "loot_gold_commit_max_ms",
		"loot_item_commit_max_ms", "monster_streaming_poll_max_ms",
	] and value >= 3.0:
		_note_slow_event(key, value)

func _note_slow_event(label: String, duration_ms: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_detail_enabled() or duration_ms < 3.0:
		return
	_recent_slow_events.append({
		"end_usec": Time.get_ticks_usec(),
		"label": label,
		"duration_ms": duration_ms,
	})
	if _recent_slow_events.size() > SLOW_EVENT_TRACE_CAPACITY:
		_recent_slow_events.pop_front()

func _trace_slow_frame(previous_usec: int, now_usec: int, gap_ms: float) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_detail_enabled() or gap_ms <= 33.33:
		return
	var events: Array[Dictionary] = []
	for event: Dictionary in _recent_slow_events:
		var ended_usec := int(event.get("end_usec", 0))
		if ended_usec <= previous_usec or ended_usec > now_usec:
			continue
		events.append({
			"label": str(event.get("label", "")),
			"duration_ms": float(event.get("duration_ms", 0.0)),
		})
	_slow_frame_trace.append({
		"window_ms": maxi(0, Time.get_ticks_msec() - _performance_window_started_msec),
		"frame_ms": gap_ms,
		"events": events,
	})
	if _slow_frame_trace.size() > SLOW_FRAME_TRACE_CAPACITY:
		_slow_frame_trace.pop_front()


## Records one total idle-frame duration in milliseconds.  This is deliberately
## separate from process/physics timings: the reports require the total frame
## pacing seen by the player, including rendering and scheduling.  Callers must
## already be on the explicit Debug/Device Lab path; this method repeats the
## gate check so an accidental Release caller is a no-op.

func record_frame_time_ms(frame_ms: float) -> void:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
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


## Measures the real wall-clock interval since the previous process callback
## in milliseconds. Returns -1.0 for the first call after a reset/boundary
## (no interval exists yet) and when a gap exceeds WALL_BOUNDARY_DISCARD_MS —
## app pause/resume and scheduler stalls are measurement boundaries, not
## gameplay stalls, and must not enter the frame distribution (each discard
## is counted and disclosed). This is the sole feed for the FRAME-STALL
## long-frame probe, the AOE window probe, and the Device Lab frame samples;
## clamped `_process(delta)` must never be used for real stall detection.

func wall_frame_interval_ms() -> float:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
	var now_usec := Time.get_ticks_usec()
	var prev := _wall_usec_prev
	var had_prev := _wall_usec_valid
	_wall_usec_prev = now_usec
	_wall_usec_valid = true
	# _wall_usec_valid is the baseline sentinel; a timestamp value itself can
	# legitimately be <= 0 right after engine start, so a sign check would
	# misread a real baseline as "unset".
	if not had_prev:
		return -1.0
	var gap_ms := float(now_usec - prev) / 1000.0
	if gap_ms > WALL_BOUNDARY_DISCARD_MS:
		_wall_boundary_discards += 1
		return -1.0
	return gap_ms

func reset_wall_frame_interval() -> void:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
	# Called on APPLICATION_PAUSED/RESUMED so the post-resume frame is treated
	# as a fresh boundary instead of a giant fake frame interval.
	_wall_usec_prev = 0
	_wall_usec_valid = false

func wall_boundary_discard_count() -> int:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _wall_boundary_discards


## Device Lab gated wrapper: feeds the wall-clock interval into the explicit
## Debug/Device Lab frame-sample ring. Replaces the old clamped-delta feeder.
## Uses its own prev timestamp so it cannot interact with the ungated probe
## recorder (see above).

func record_device_lab_frame_interval() -> void:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_enabled():
		return
	var now_usec := Time.get_ticks_usec()
	var prev := _device_lab_wall_usec_prev
	var had_prev := _device_lab_wall_usec_valid
	_device_lab_wall_usec_prev = now_usec
	_device_lab_wall_usec_valid = true
	if not had_prev:
		return
	var gap_ms := float(now_usec - prev) / 1000.0
	if gap_ms > WALL_BOUNDARY_DISCARD_MS:
		_device_lab_wall_boundary_discards += 1
		return
	_trace_slow_frame(prev, now_usec, gap_ms)
	record_frame_time_ms(gap_ms)

func reset_device_lab_frame_interval() -> void:
	assert(_measurement_domain == "main" and OS.get_thread_caller_id() == OS.get_main_thread_id(), "actual M frame statistics cannot use S frame time")
	assert(OS.get_thread_caller_id() == _owner_thread)
	_device_lab_wall_usec_prev = 0
	_device_lab_wall_usec_valid = false

func _frame_percentile(samples: Array, fraction: float) -> float:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if samples.is_empty():
		return 0.0
	var sorted: Array = samples.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return float(sorted[index])

func _frame_ratio(count: int) -> float:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if _frame_sample_count <= 0:
		return 0.0
	return float(count) / float(_frame_sample_count)

func frame_sampling_snapshot() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	var samples: Array = _frame_samples.duplicate()
	var p50 := _frame_percentile(samples, 0.50)
	var p95 := _frame_percentile(samples, 0.95)
	var p99 := _frame_percentile(samples, 0.99)
	# PERF-EVIDENCE: worst retained frame. With an overflowed ring buffer
	# this bounds only the retained window; frame_samples_dropped discloses
	# the truncation.
	var max_ms := 0.0
	for raw_sample: Variant in samples:
		max_ms = maxf(max_ms, float(raw_sample))
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
		"frame_ms_max": max_ms,
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
			"max_ms": max_ms,
			"thresholds": thresholds,
			"gpu": gpu,
		},
		"slow_frame_trace": _slow_frame_trace.duplicate(true),
		"gpu_frame_ms": gpu,
	}

func timing_start() -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_timing_enabled():
		return 0
	return Time.get_ticks_usec()

func timing_now() -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_timing_enabled():
		return 0
	return Time.get_ticks_usec()

func timing_elapsed_usec(started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if started_usec <= 0 or not performance_timing_enabled():
		return 0
	return maxi(0, timing_now() - started_usec)

func record_timing_usec(field: StringName, started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	var elapsed := timing_elapsed_usec(started_usec)
	if elapsed > 0:
		increment_performance_counter(field, elapsed)
		if elapsed >= 3000:
			_note_slow_event(str(field), float(elapsed) / 1000.0)
	return elapsed


## Starts one inclusive runtime segment and records its call in the same
## cached-gate branch. A zero token is the disabled fast path; the matching
## end call then returns without reading the clock or touching the window.

func begin_timed_segment(call_field: StringName) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if not performance_timing_enabled():
		return 0
	_ensure_performance_window()
	var key := str(call_field)
	_performance_counters[key] = int(_performance_counters.get(key, 0)) + 1
	return Time.get_ticks_usec()

func end_timed_segment(duration_field: StringName, started_usec: int) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	if started_usec <= 0 or not performance_timing_enabled():
		return 0
	var elapsed := maxi(0, Time.get_ticks_usec() - started_usec)
	if elapsed > 0:
		var key := str(duration_field)
		_performance_counters[key] = int(_performance_counters.get(key, 0)) + elapsed
		if elapsed >= 3000:
			_note_slow_event(key, float(elapsed) / 1000.0)
	return elapsed

func record_timing_ms(field: StringName, started_usec: int) -> float:
	assert(OS.get_thread_caller_id() == _owner_thread)
	var elapsed := timing_elapsed_usec(started_usec)
	if elapsed > 0:
		add_performance_value(field, float(elapsed) / 1000.0)
		if elapsed >= 3000:
			_note_slow_event(str(field), float(elapsed) / 1000.0)
	return float(elapsed) / 1000.0

func performance_counter(field: StringName) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return int(_performance_counters.get(str(field), 0))

func set_performance_release_context(release_id: String, skill_id: String) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
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

func mark_performance_release_context(release_id: String, skill_id: String) -> void:
	assert(OS.get_thread_caller_id() == _owner_thread)
	set_performance_release_context(release_id, skill_id)

func performance_release_context() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return _performance_release_context.duplicate(true)

func performance_counters() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	_ensure_performance_window()
	var result := {}
	for field: String in PERFORMANCE_COUNTER_FIELDS:
		result[field] = int(_performance_counters.get(field, 0))
	# Keep the stable zero-valued schema above, while also exporting counters
	# registered by runtime producers at a finer bucket granularity (for
	# example loot_prepare_bucket_N_count). The public increment API accepts
	# these fields intentionally; dropping them here silently lost death/drop
	# detail from the Device Lab window.
	for key: Variant in _performance_counters.keys():
		var dynamic_field := str(key)
		if not result.has(dynamic_field):
			result[dynamic_field] = int(_performance_counters[key])
	for key: Variant in _performance_values.keys():
		result[str(key)] = float(_performance_values[key])
	for key: Variant in _performance_maxima.keys():
		result[str(key)] = float(_performance_maxima[key])
	return result

func reset_performance_window() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	_performance_counters.clear()
	_performance_fields_initialized = false
	_performance_values.clear()
	_performance_maxima.clear()
	_frame_samples.clear()
	_recent_slow_events.clear()
	_slow_frame_trace.clear()
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

func reset_window() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return reset_performance_window()

func read_performance_window(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
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
	result["detail_mode"] = device_lab_detail_mode()
	result["context"] = context.duplicate(true)
	result["counters"] = performance_counters()
	return result

func read_window(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	return read_performance_window(context)

func owner_window_snapshot(context: Dictionary = {}) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner_thread)
	# Do not discard S slow events or collapse maxima into additive counters.
	# Root's original window publication/reset barrier consumes these frozen
	# value partitions; actual M frame pacing remains the Main owner's ledger.
	return {"measurement_domain":_measurement_domain,"window":read_performance_window(context),
		"counter_values":_performance_counters.duplicate(true),"additive_values":_performance_values.duplicate(true),
		"maxima":_performance_maxima.duplicate(true),"slow_events":_recent_slow_events.duplicate(true)}
