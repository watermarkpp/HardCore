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

	var reset_again_result: Dictionary = await runtime.call(
		"_execute",
		reset_command.duplicate(true),
	)
	var reset_again_window: Dictionary = reset_again_result.get("performance_diagnostics", {})
	assert(int(reset_again_window.get("foreground_ai_ticks", -1)) == 0)
	assert(int(reset_again_window.get("window_id", -1)) > reset_window_id)
	assert(str((reset_again_window.get("context", {}) as Dictionary).get("release_id", "")).is_empty())
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
