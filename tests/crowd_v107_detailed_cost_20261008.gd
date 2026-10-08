extends "res://tests/crowd_v107_cost_growth_20261008.gd"

const Trace := preload("res://tests/helpers/crowd_v107_profile_trace.gd")

func _run() -> void:
	Trace.armed = true
	await super._run()

func _append_scaling_result(result: Dictionary) -> void:
	result["detailed_cpu_trace"] = Trace.stop_window()
	if result.detailed_cpu_trace.segments.is_empty():
		_scaling_failures.append("profile_not_active")
		result.status = "FAIL"
	if int(result.detailed_cpu_trace.open_segments) != 0:
		_scaling_failures.append("profile_stack_not_closed")
		result.status = "FAIL"
	super._append_scaling_result(result)

func _scaling_source_hashes() -> Dictionary:
	var hashes := super._scaling_source_hashes()
	for path: String in ["res://tests/crowd_v107_detailed_cost_20261008.gd", "res://tests/helpers/crowd_v107_profile_trace.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
