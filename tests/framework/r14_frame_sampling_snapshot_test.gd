extends Node

const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		errors.append(label)

func _run() -> void:
	var output_root := OS.get_environment("HARDCORE_R14_SCHEMA_OUT")
	if output_root.is_empty():
		output_root = "user://b22_r14_schema"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	check(RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true), "debug performance gate opens")
	check(RuntimeDiagnosticsScript.set_device_lab_detail_mode(RuntimeDiagnosticsScript.DEVICE_LAB_DETAIL_FRAME_ONLY), "frame-only detail mode accepted")
	var no_overflow := _capture(4096)
	var overflow := _capture(4097)
	var no_path := output_root.path_join("frame_sampling_no_overflow.json")
	var overflow_path := output_root.path_join("frame_sampling_overflow.json")
	_write_snapshot(no_path, no_overflow)
	_write_snapshot(overflow_path, overflow)
	check(int(no_overflow.get("frame_count", -1)) == 4096, "producer no-overflow frame count")
	check(int(no_overflow.get("frame_samples_dropped", -1)) == 0, "producer no-overflow dropped count")
	check(not bool(no_overflow.get("frame_sample_overflowed", true)), "producer no-overflow flag")
	check(bool(no_overflow.get("frame_percentiles_exact", false)), "producer no-overflow exact flag")
	check(int(overflow.get("frame_count", -1)) == 4097, "producer overflow frame count")
	check(int(overflow.get("frame_samples_dropped", 0)) == 1, "producer overflow dropped count")
	check(bool(overflow.get("frame_sample_overflowed", false)), "producer overflow flag")
	check(not bool(overflow.get("frame_percentiles_exact", true)), "producer overflow exact flag")
	print("R14_FRAME_SAMPLING_SNAPSHOT_PASS checks=%d no_overflow=%s overflow=%s" % [checks, ProjectSettings.globalize_path(no_path), ProjectSettings.globalize_path(overflow_path)])
	if not proof.write_receipt("r14_frame_sampling_snapshot_test", checks, errors.size()):
		errors.append("receipt write failed")
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	get_tree().quit(0 if errors.is_empty() else 1)

func _capture(count: int) -> Dictionary:
	RuntimeDiagnosticsScript.reset_performance_window()
	for index in range(count):
		RuntimeDiagnosticsScript.record_frame_time_ms(16.0 + float(index % 3))
	return RuntimeDiagnosticsScript.read_performance_window({"fixture": "r14_schema", "count": count})

func _write_snapshot(path: String, snapshot: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "snapshot output opened")
	# DeviceLab/quiet collection receipts carry the runtime window under the
	# same performance_diagnostics envelope as reset/read/stop responses.
	file.store_string(JSON.stringify({"performance_diagnostics": snapshot}, "  "))
	file.close()
