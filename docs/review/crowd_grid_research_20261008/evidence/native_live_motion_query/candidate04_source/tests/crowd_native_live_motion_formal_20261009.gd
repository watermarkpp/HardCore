extends "res://tests/crowd_formal_grid_comparison_20261008.gd"

const LIVE_MANIFEST := "res://outputs/crowd_native_live_motion_query_20261009/current_run_inputs.json"
var _live_extension: Resource
var _live_kernel: RefCounted
var _live_binding: Dictionary = {}

func _run() -> void:
	var input_file := FileAccess.open(LIVE_MANIFEST, FileAccess.READ)
	if input_file == null:
		push_error("Native live motion formal producer manifest missing")
		get_tree().quit(1)
		return
	var parsed: Variant = JSON.parse_string(input_file.get_as_text())
	if not parsed is Dictionary:
		push_error("Native live motion formal manifest invalid")
		get_tree().quit(1)
		return
	_live_binding = parsed
	_live_binding["manifest_sha256"] = FileAccess.get_sha256(LIVE_MANIFEST)
	_live_binding["engine_actual_sha256"] = FileAccess.get_sha256(OS.get_executable_path())
	for input_path: String in _live_binding.source_sha256:
		if FileAccess.get_sha256("res://" + input_path) != str(_live_binding.source_sha256[input_path]):
			push_error("Native live motion source binding mismatch: " + input_path)
			get_tree().quit(1)
			return
	if str(_live_binding.engine_sha256) != str(_live_binding.engine_actual_sha256):
		push_error("Native live motion engine binding mismatch")
		get_tree().quit(1)
		return
	if FileAccess.get_sha256("res://" + str(_live_binding.dll_path)) != str(_live_binding.dll_sha256):
		push_error("Native live motion DLL binding mismatch")
		get_tree().quit(1)
		return
	_live_extension = load("res://research/native/crowd_kernel/crowd_kernel.gdextension")
	_live_kernel = ClassDB.instantiate("CrowdMeleeKernel")
	if _live_kernel == null or not _live_kernel.has_method(&"motion_candidates_live"):
		push_error("Native live motion query API missing")
		get_tree().quit(1)
		return
	_live_kernel.call(&"configure_live_motion_scripts", load("res://scripts/enemy.gd"), load("res://scripts/world_background.gd"))
	_live_kernel.call(&"reset_live_motion_stats")
	EnemyActor.set_native_live_motion_query_kernel(_live_kernel)
	await super._run()

func _append_scaling_result(result: Dictionary) -> void:
	var stats: Dictionary = _live_kernel.call(&"get_live_motion_stats")
	result["native_live_motion_query"] = {"stats": stats, "scope": "query coverage since setup; original formal CPU/window unchanged", "run_binding": _live_binding}
	if int(stats.get("entries", 0)) <= 0 or int(stats.get("entries", 0)) == int(stats.get("unsupported_owner", 0)):
		_scaling_failures.append("native_live_query_no_supported_coverage")
		result["status"] = "FAIL"
		result["failures"] = Array(result.get("failures", [])) + ["native_live_query_no_supported_coverage"]
	if int(stats.get("revalidation_failures", 0)) != 0:
		_scaling_failures.append("native_live_query_revalidation_failure")
		result["status"] = "FAIL"
		result["failures"] = Array(result.get("failures", [])) + ["native_live_query_revalidation_failure"]
	super._append_scaling_result(result)
