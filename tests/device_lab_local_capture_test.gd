extends Node

# The user retired this temporary feature; keep its scene as a removal regression.
func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var menu := SystemMenuPanel.new()
	add_child(menu)
	assert(not menu.has_signal("performance_capture_requested"))
	for name in ["PerformanceCapture0", "PerformanceCapture1", "PerformanceCaptureNote"]:
		assert(menu.settings_page.get_node_or_null(name) == null)
	var lab := DeviceLabRuntime.new()
	assert(not lab.has_method("begin_local_performance_capture"))
	assert(not lab.has_method("_advance_local_capture"))
	assert(not lab.has_signal("local_performance_capture_finished"))
	assert(not RuntimeDiagnostics.performance_enabled())
	lab.free()
	menu.free()
	print("DEVICE_LAB_LOCAL_CAPTURE_PASS retired_buttons_and_recorder")
	get_tree().quit(0)
