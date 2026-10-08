extends "res://tests/crowd_formal_grid_comparison_20261008.gd"

## QUANTUM_ABI_SHAM is a diagnostic boundary experiment. The stock Enemy
## algorithm and all effects remain authoritative; this helper only selects a
## disabled-by-default raw-buffer seam and records the run's actual envelope.
const EXTENSION_PATH := "res://research/native/crowd_kernel/crowd_kernel.gdextension"
const DLL_PATH := "res://research/native/crowd_kernel/bin/crowd_melee_kernel.windows.template_debug.x86_64.dll"
const OUTPUT_ROOT := "res://outputs/crowd_native_kernel_20261009/task2"

var _quantum_mode := "DISABLED"
var _quantum_kernel: Object = null
var _quantum_failures: Array[String] = []
var _quantum_binding: Dictionary = {}

func _run() -> void:
	_quantum_mode = OS.get_environment("HARDCORE_QUANTUM_ABI_MODE").strip_edges().to_upper()
	if _quantum_mode not in ["LOCAL", "ABI_SHAM"]:
		_quantum_failures.append("mode_must_be_LOCAL_or_ABI_SHAM:%s" % _quantum_mode)
		_quantum_mode = "DISABLED"
	# Both modes explicitly load and instantiate the same ClassDB class before
	# the formal fixture starts. No implicit extension discovery is accepted.
	var extension = load(EXTENSION_PATH)
	_quantum_kernel = ClassDB.instantiate("CrowdMeleeKernel")
	_quantum_binding = {
		"extension_loaded": extension != null,
		"extension_path": EXTENSION_PATH,
		"dll_path": DLL_PATH,
		"dll_sha256": FileAccess.get_sha256(DLL_PATH) if FileAccess.file_exists(DLL_PATH) else "MISSING",
		"engine_path": OS.get_executable_path(),
		"engine_sha256": FileAccess.get_sha256(OS.get_executable_path()),
		"mode": _quantum_mode,
	}
	if extension == null:
		_quantum_failures.append("explicit_extension_load_failed")
	if _quantum_kernel == null:
		_quantum_failures.append("ClassDB_CrowdMeleeKernel_missing")
	elif not _quantum_kernel.has_method("forward_buffers"):
		_quantum_failures.append("forward_buffers_missing_from_loaded_class")
	EnemyActor.configure_quantum_abi_diagnostic(_quantum_mode, _quantum_kernel)
	await super._run()

func _append_scaling_result(result: Dictionary) -> void:
	var diagnostic := EnemyActor.quantum_abi_diagnostic_snapshot()
	var counters: Dictionary = diagnostic.get("counters", {})
	var bridge_calls := int(counters.get("bridge_calls", 0))
	if int(counters.get("diagnostic_errors", 0)) != 0:
		_quantum_failures.append("diagnostic_errors:%d" % int(counters.get("diagnostic_errors", 0)))
	if int(counters.get("shape_errors", 0)) != 0:
		_quantum_failures.append("forward_shape_errors:%d" % int(counters.get("shape_errors", 0)))
	if int(counters.get("begin_calls", 0)) != int(counters.get("quantum_calls", 0)):
		_quantum_failures.append("begin_quantum_count_mismatch")
	if bridge_calls != int(counters.get("begin_calls", 0)) + int(counters.get("resume_calls", 0)):
		_quantum_failures.append("bridge_phase_count_mismatch")
	if int(counters.get("writeback_calls", 0)) != int(counters.get("resume_calls", 0)):
		_quantum_failures.append("writeback_resume_count_mismatch")
	if int(counters.get("reread_calls", 0)) != bridge_calls:
		_quantum_failures.append("channel_reread_count_mismatch")
	if int(counters.get("bridge_scalar_bytes", 0)) != bridge_calls * 15 * 8:
		_quantum_failures.append("scalar_bridge_bytes_mismatch")
	if int(counters.get("bridge_vector_bytes", 0)) != bridge_calls * 10 * 8:
		_quantum_failures.append("vector_bridge_bytes_mismatch")
	if int(counters.get("bridge_identity_bytes", 0)) != bridge_calls * 8 * 8:
		_quantum_failures.append("identity_bridge_bytes_mismatch")
	if _quantum_mode == "ABI_SHAM" and int(counters.get("native_bridge_calls", 0)) <= 0:
		_quantum_failures.append("ABI_SHAM_no_real_forward_buffers_calls")
	if _quantum_mode == "ABI_SHAM" and int(counters.get("native_bridge_calls", 0)) != bridge_calls:
		_quantum_failures.append("ABI_SHAM_bridge_count_mismatch")
	if _quantum_mode == "LOCAL" and int(counters.get("native_bridge_calls", 0)) != 0:
		_quantum_failures.append("LOCAL_performed_native_bridge_call")
	if _quantum_mode == "LOCAL" and int(counters.get("local_forward_calls", 0)) != bridge_calls:
		_quantum_failures.append("LOCAL_forward_count_mismatch")
	if int(counters.get("outer_calls", 0)) != SCALING_ACTOR_COUNT * SCALING_SAMPLE_TICKS:
		_quantum_failures.append("outer_callback_count:%d" % int(counters.get("outer_calls", 0)))
	if not _quantum_failures.is_empty():
		_scaling_failures.append_array(_quantum_failures)
	if not _scaling_failures.is_empty():
		result["status"] = "FAIL"
	result["quantum_abi"] = {
		"experiment": "QUANTUM_ABI_SHAM",
		"mode": _quantum_mode,
		"diagnostic_only": true,
		"trajectory_is_actual_inherited_fixture": true,
		"upper_envelope_only": true,
		"buffer_schema": {"version": 1, "scalars": 15, "vectors": 10, "identities": 8,
			"reread_definition": "one successful three-channel shape read per forward call"},
		"snapshot": diagnostic,
		"binding": _quantum_binding,
		"failures": _quantum_failures,
	}
	result["source_hashes"] = _scaling_source_hashes()
	result["quantum_abi_input_hashes"] = {
		"enemy_sha256": FileAccess.get_sha256("res://scripts/enemy.gd"),
		"boundary_trace_sha256": FileAccess.get_sha256("res://tests/helpers/crowd_quantum_boundary_trace_20261009.gd"),
		"contract_sha256": FileAccess.get_sha256("res://tests/crowd_quantum_abi_sham_20261009.gd"),
		"extension_sha256": FileAccess.get_sha256(EXTENSION_PATH),
		"dll_sha256": _quantum_binding.get("dll_sha256", "MISSING"),
	}
	var mode_path := "%s/%s.json" % [OUTPUT_ROOT, _quantum_mode.to_lower()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var file := FileAccess.open(mode_path, FileAccess.WRITE)
	if file == null:
		_scaling_failures.append("quantum_abi_output_open_failed")
	else:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	# Preserve the formal fixture's existing output and cleanup/quit behavior.
	super._append_scaling_result(result)
	EnemyActor.disarm_quantum_abi_diagnostic()

func _scaling_source_hashes() -> Dictionary:
	var result := super._scaling_source_hashes()
	result["res://scripts/enemy.gd"] = FileAccess.get_sha256("res://scripts/enemy.gd")
	result["res://tests/helpers/crowd_quantum_boundary_trace_20261009.gd"] = FileAccess.get_sha256("res://tests/helpers/crowd_quantum_boundary_trace_20261009.gd")
	result["res://tests/crowd_quantum_abi_sham_20261009.gd"] = FileAccess.get_sha256("res://tests/crowd_quantum_abi_sham_20261009.gd")
	return result
