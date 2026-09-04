extends Node2D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_enabled := bool(ProjectSettings.get_setting(
		RuntimeDiagnostics.SETTING_ENABLED,
		false,
	))
	var old_performance := bool(ProjectSettings.get_setting(
		RuntimeDiagnostics.SETTING_PERFORMANCE,
		false,
	))
	var old_device_lab := bool(ProjectSettings.get_setting(
		RuntimeDiagnostics.SETTING_DEVICE_LAB_PERFORMANCE,
		false,
	))
	var old_device_lab_override := RuntimeDiagnostics.device_lab_performance_override_enabled()
	ProjectSettings.set_setting(RuntimeDiagnostics.SETTING_ENABLED, false)
	ProjectSettings.set_setting(RuntimeDiagnostics.SETTING_PERFORMANCE, false)
	ProjectSettings.set_setting(
		RuntimeDiagnostics.SETTING_DEVICE_LAB_PERFORMANCE,
		false,
	)
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	RuntimeDiagnostics.refresh_performance_gate()
	assert(not RuntimeDiagnostics.performance_enabled())
	assert(RuntimeDiagnostics.timing_start() == 0)
	RuntimeDiagnostics.record_frame_time_ms(99.0)
	assert(int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1)) == 0)
	RuntimeDiagnostics.reset_performance_window()

	set_meta("build_commit", "diagnostics-test")
	var runtime := DeviceLabRuntime.new().configure(self)
	add_child(runtime)
	var reset_command := {
		"schemaVersion": DeviceLabRuntime.PROTOCOL_VERSION,
		"nonce": "diagnostics-window",
		"action": "reset_diagnostics",
		"allowlist": [DeviceLabRuntime.ALLOWLIST_ID, "reset_diagnostics"],
	}
	assert(bool(DeviceLabRuntime.validate_command(reset_command).get("ok", false)))
	var reset_result: Dictionary = await runtime.call("_execute", reset_command)
	assert(bool(reset_result.get("ok", false)))
	var reset_window: Dictionary = reset_result.get("performance_diagnostics", {})
	assert(bool(reset_window.get("diagnostics_enabled", false)))
	assert(bool(reset_window.get("timing_enabled", false)))
	var reset_window_id := int(reset_window.get("window_id", -1))
	runtime.call("_process", 0.016)
	var process_sample_window := RuntimeDiagnostics.read_performance_window()
	assert(int(process_sample_window.get("frame_count", -1)) == 1)
	assert(is_equal_approx(float(process_sample_window.get("frame_ms_p50", -1.0)), 16.0))
	assert(RuntimeDiagnostics.timing_start() > 0)
	RuntimeDiagnostics.set_performance_release_context(
		"release.diagnostics.test",
		"skill.diagnostics.test",
	)
	RuntimeDiagnostics.increment_performance_counter(&"foreground_ai_ticks", 4)
	var timing_started_usec := RuntimeDiagnostics.timing_start()
	await get_tree().process_frame
	assert(RuntimeDiagnostics.record_timing_usec(
		&"aoe_candidate_usec",
		timing_started_usec,
	) > 0)
	var read_command := {
		"schemaVersion": DeviceLabRuntime.PROTOCOL_VERSION,
		"nonce": "diagnostics-window-read",
		"action": "read_diagnostics",
		"allowlist": [DeviceLabRuntime.ALLOWLIST_ID, "read_diagnostics"],
	}
	assert(bool(DeviceLabRuntime.validate_command(read_command).get("ok", false)))
	var read_result: Dictionary = await runtime.call("_execute", read_command)
	var read_window: Dictionary = read_result.get("performance_diagnostics", {})
	assert(bool(read_result.get("ok", false)))
	assert(int(read_window.get("foreground_ai_ticks", -1)) == 4)
	assert(float(read_window.get("aoe_candidate_usec", 0.0)) > 0.0)
	assert(int(read_window.get("window_id", -1)) == reset_window_id)
	var read_context: Dictionary = read_window.get("context", {})
	assert(read_context.get("release_id", "") == "release.diagnostics.test")
	assert(read_context.get("skill_id", "") == "skill.diagnostics.test")
	var nested_counters: Dictionary = read_window.get("counters", {})
	assert(int(nested_counters.get("foreground_ai_ticks", -1)) == 4)
	assert(float(nested_counters.get("aoe_candidate_usec", 0.0)) > 0.0)
	RuntimeDiagnostics.increment_performance_counter(&"foreground_ai_ticks", 3)
	var second_read_result: Dictionary = await runtime.call("_execute", read_command.duplicate(true))
	var second_window: Dictionary = second_read_result.get("performance_diagnostics", {})
	assert(int(second_window.get("foreground_ai_ticks", -1)) == 7)
	assert(int(second_window.get("window_id", -1)) == reset_window_id)

	# A fresh sample set makes the percentile and threshold assertions
	# deterministic; no frame from the process-lifetime startup period may leak
	# into this measured window.
	RuntimeDiagnostics.reset_performance_window()
	RuntimeDiagnostics.set_performance_release_context(
		"release.diagnostics.test",
		"skill.diagnostics.test",
	)
	for frame_ms: float in [10.0, 16.67, 16.68, 33.33, 33.34, 50.01, 100.01]:
		RuntimeDiagnostics.record_frame_time_ms(frame_ms)
	var frame_window := RuntimeDiagnostics.read_performance_window()
	assert(int(frame_window.get("frame_count", -1)) == 7)
	assert(is_equal_approx(float(frame_window.get("frame_ms_p50", -1.0)), 33.33))
	assert(is_equal_approx(float(frame_window.get("frame_ms_p95", -1.0)), 100.01))
	assert(is_equal_approx(float(frame_window.get("frame_ms_p99", -1.0)), 100.01))
	assert(int(frame_window.get("frames_over_16_67ms", -1)) == 5)
	assert(is_equal_approx(float(frame_window.get("frames_over_16_67_ratio", -1.0)), 5.0 / 7.0))
	assert(int(frame_window.get("frames_over_33_33ms", -1)) == 3)
	assert(is_equal_approx(float(frame_window.get("frames_over_33_33_ratio", -1.0)), 3.0 / 7.0))
	assert(int(frame_window.get("frames_over_50ms", -1)) == 2)
	assert(is_equal_approx(float(frame_window.get("frames_over_50_ratio", -1.0)), 2.0 / 7.0))
	assert(int(frame_window.get("frames_over_100ms", -1)) == 1)
	assert(is_equal_approx(float(frame_window.get("frames_over_100_ratio", -1.0)), 1.0 / 7.0))
	var frame_timing: Dictionary = frame_window.get("frame_timing", {})
	assert(int(frame_timing.get("frame_count", -1)) == 7)
	assert(int(frame_timing.get("retained_sample_count", -1)) == 7)
	assert(bool(frame_timing.get("percentiles_exact", false)))
	var gpu: Dictionary = frame_timing.get("gpu", {})
	assert(not bool(gpu.get("available", true)))
	assert(not str(gpu.get("reason", "")).is_empty())

	var snapshot := DeviceLabRuntime.build_snapshot(self)
	var window: Dictionary = snapshot.get("performance_diagnostics", {})
	assert(window.get("schema", "") == RuntimeDiagnostics.PERFORMANCE_SCHEMA_ID)
	assert(window.has("context"))
	var context: Dictionary = window.get("context", {})
	assert(context.get("release_id", "") == "release.diagnostics.test")
	assert(context.get("skill_id", "") == "skill.diagnostics.test")
	for field: String in [
		"map_id",
		"commit",
		"total_monster_count",
		"nearby_1600_px",
		"nearby_2000_px",
		"moving_count",
		"engaged_count",
		"active_visual_count",
		"player_position",
		"camera_zoom",
		"release_id",
		"skill_id",
		"player_profession",
		"nearby_enemy_count_8gu",
		"nearby_enemy_count_16gu",
		"engaged_enemy_count",
		"moving_enemy_count",
		"aoe_selected_target_count",
		"lethal_target_count",
		"active_ground_loot_count",
		"active_corpse_count",
	]:
		assert(context.has(field), "missing diagnostics context field: %s" % field)
	for field: String in RuntimeDiagnostics.PERFORMANCE_FIELDS:
		assert(window.has(field), "missing performance field: %s" % field)
		assert(window.get(field) is int or window.get(field) is float)
	for field: String in [
		"frame_count",
		"frame_samples_retained",
		"frame_sample_capacity",
		"frame_samples_dropped",
		"frame_percentiles_exact",
		"frame_ms_p50",
		"frame_ms_p95",
		"frame_ms_p99",
		"frames_over_16_67ms",
		"frames_over_16_67_ratio",
		"frames_over_33_33ms",
		"frames_over_33_33_ratio",
		"frames_over_50ms",
		"frames_over_50_ratio",
		"frames_over_100ms",
		"frames_over_100_ratio",
		"frame_timing",
		"gpu_frame_ms",
	]:
		assert(window.has(field), "missing frame sampling field: %s" % field)
	var snapshot_gpu: Dictionary = window.get("gpu_frame_ms", {})
	assert(not bool(snapshot_gpu.get("available", true)))
	assert(not str(snapshot_gpu.get("reason", "")).is_empty())

	var reset_again_result: Dictionary = await runtime.call(
		"_execute",
		reset_command.duplicate(true),
	)
	var reset_again_window: Dictionary = reset_again_result.get("performance_diagnostics", {})
	assert(int(reset_again_window.get("foreground_ai_ticks", -1)) == 0)
	assert(int(reset_again_window.get("frame_count", -1)) == 0)
	assert(int(reset_again_window.get("frames_over_100ms", -1)) == 0)
	assert(int(reset_again_window.get("window_id", -1)) > reset_window_id)
	assert(str((reset_again_window.get("context", {}) as Dictionary).get("release_id", "")).is_empty())
	for index: int in range(RuntimeDiagnostics.FRAME_SAMPLE_CAPACITY + 2):
		RuntimeDiagnostics.record_frame_time_ms(float(index))
	var bounded_window := RuntimeDiagnostics.read_performance_window()
	assert(int(bounded_window.get("frame_count", -1)) == RuntimeDiagnostics.FRAME_SAMPLE_CAPACITY + 2)
	assert(int(bounded_window.get("frame_samples_retained", -1)) == RuntimeDiagnostics.FRAME_SAMPLE_CAPACITY)
	assert(int(bounded_window.get("frame_samples_dropped", -1)) == 2)
	assert(bool(bounded_window.get("frame_sample_overflowed", false)))
	assert(not bool(bounded_window.get("frame_percentiles_exact", true)))
	var stop_command := {
		"schemaVersion": DeviceLabRuntime.PROTOCOL_VERSION,
		"nonce": "diagnostics-window-stop",
		"action": "stop_diagnostics",
		"allowlist": [DeviceLabRuntime.ALLOWLIST_ID, "stop_diagnostics"],
	}
	assert(bool(DeviceLabRuntime.validate_command(stop_command).get("ok", false)))
	var stop_result: Dictionary = await runtime.call("_execute", stop_command)
	assert(bool(stop_result.get("ok", false)))
	var stop_window: Dictionary = stop_result.get("performance_diagnostics", {})
	assert(not bool(stop_window.get("diagnostics_enabled", true)))
	var stopped_count := int(stop_window.get("frame_count", -1))
	RuntimeDiagnostics.record_frame_time_ms(1000.0)
	assert(int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1)) == stopped_count)
	runtime.queue_free()

	ProjectSettings.set_setting(RuntimeDiagnostics.SETTING_ENABLED, old_enabled)
	ProjectSettings.set_setting(RuntimeDiagnostics.SETTING_PERFORMANCE, old_performance)
	ProjectSettings.set_setting(
		RuntimeDiagnostics.SETTING_DEVICE_LAB_PERFORMANCE,
		old_device_lab,
	)
	RuntimeDiagnostics.set_device_lab_performance_enabled(old_device_lab_override)
	RuntimeDiagnostics.refresh_performance_gate()
	print("MONSTER_DENSITY_DIAGNOSTICS_WINDOW_PASS fields=%d" % RuntimeDiagnostics.PERFORMANCE_FIELDS.size())
	get_tree().quit(0)
