extends Node

const Lab := preload("res://scripts/device_lab_runtime.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	var closed := Lab.new()
	closed.set_debug_gate_for_test(false)
	assert(not bool(closed.begin_local_performance_capture("full").ok))
	closed.free()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 15000
	while game._world_bootstrap_in_progress and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not game._world_bootstrap_in_progress)
	var lab: Lab = game._device_lab_runtime
	assert(lab != null)
	lab.set_process(false)
	var saved: Array[Dictionary] = []
	lab.local_performance_capture_finished.connect(func(result: Dictionary) -> void: saved.append(result))
	var menu: SystemMenuPanel = game._system_menu_panel
	for index in range(2):
		game._show_system_menu()
		menu.show_settings_page()
		var button := menu.settings_page.get_node("PerformanceCapture%d" % index) as Button
		assert(Rect2(Vector2.ZERO, menu.modal.size).encloses(Rect2(button.position, button.size)))
		assert(not Rect2(button.position, button.size).intersects(
			Rect2(menu.settings_back_button.position, menu.settings_back_button.size)))
		button.pressed.emit()
		assert(not get_tree().paused and not menu.visible)
		assert(RuntimeDiagnostics.performance_enabled())
		var expected_mode := "frame_only" if index == 0 else "full"
		assert(RuntimeDiagnostics.device_lab_detail_mode() == expected_mode, "button captured the wrong loop index")
		assert(not bool(lab.begin_local_performance_capture(expected_mode).ok), "must not overwrite an active capture")
		lab._advance_local_capture(1000)
		RuntimeDiagnostics.record_frame_time_ms(18.0)
		lab._advance_local_capture(2000)
		lab._notification(NOTIFICATION_PAUSED)
		lab._notification(NOTIFICATION_UNPAUSED)
		lab._advance_local_capture(50000)
		assert(is_equal_approx(lab._local_capture_elapsed, 1.0), "pause must not consume gameplay recording time")
		RuntimeDiagnostics.record_frame_time_ms(52.0)
		lab._advance_local_capture(79000)
		assert(saved.size() == index + 1 and bool(saved[index].ok))
		assert(not RuntimeDiagnostics.performance_enabled())
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved[index].path))
		assert(report.complete and report.reason == "duration_complete")
		assert(report.detailMode == expected_mode and report.performance_diagnostics.frame_count == 2)
		assert(report.performance_diagnostics.frames_over_50ms == 1)
		assert(not report.performance_diagnostics.gpu_frame_ms.available)
		assert(report.enemy_activity.has("physics_enabled_count") and report.has("fire_walls"))
		assert(report.coarse_samples.size() == 2)
		assert(report.coarse_samples[0].has("counters") == (index == 1))
		assert(not report.engine_monitor_caveat.is_empty())
	# Exiting the world closes and saves an incomplete window, never leaves
	# expensive CPU timing enabled for character selection or the next world.
	assert(bool(lab.begin_local_performance_capture("full").ok))
	game.queue_free()
	await get_tree().process_frame
	assert(saved.size() == 3 and bool(saved[2].ok))
	assert(not RuntimeDiagnostics.performance_enabled())
	var incomplete: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved[2].path))
	assert(not incomplete.complete and incomplete.reason == "world_exit")
	print("DEVICE_LAB_LOCAL_CAPTURE_PASS buttons=2 frame_modes=2 paused_boundary export end_gate release_gate")
	get_tree().quit(0)
