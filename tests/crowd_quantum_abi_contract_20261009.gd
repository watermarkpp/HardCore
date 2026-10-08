extends Node

const EXTENSION_PATH := "res://research/native/crowd_kernel/crowd_kernel.gdextension"
const DLL_PATH := "res://research/native/crowd_kernel/bin/crowd_melee_kernel.windows.template_debug.x86_64.dll"

var checks: Array[Dictionary] = []
var failed := false
var run_binding: Dictionary = {}

func check(condition: bool, id: String, message: String) -> void:
	checks.append({"id": id, "passed": condition, "message": message})
	if not condition:
		failed = true
		print("HC_TEST_FAIL ", id, " ", message)

func bytes_equal(actual: PackedByteArray, expected: PackedByteArray) -> bool:
	return actual == expected

func check_channels(result: Variant, scalars: PackedFloat64Array, vectors: PackedVector2Array, identities: PackedInt64Array, prefix: String) -> void:
	check(result is Array, prefix + "-array", "forward_buffers returns an Array")
	if not result is Array:
		return
	var channels: Array = result
	check(channels.size() == 3, prefix + "-shape", "forward_buffers returns exactly three channels")
	if channels.size() != 3:
		return
	check(channels[0] is PackedFloat64Array, prefix + "-scalar-type", "channel 0 is PackedFloat64Array")
	check(channels[1] is PackedVector2Array, prefix + "-vector-type", "channel 1 is PackedVector2Array")
	check(channels[2] is PackedInt64Array, prefix + "-identity-type", "channel 2 is PackedInt64Array")
	if not (channels[0] is PackedFloat64Array and channels[1] is PackedVector2Array and channels[2] is PackedInt64Array):
		return
	var got_scalars: PackedFloat64Array = channels[0]
	var got_vectors: PackedVector2Array = channels[1]
	var got_identities: PackedInt64Array = channels[2]
	check(bytes_equal(got_scalars.to_byte_array(), scalars.to_byte_array()), prefix + "-scalar-bytes", "scalar bytes are exact")
	check(bytes_equal(got_vectors.to_byte_array(), vectors.to_byte_array()), prefix + "-vector-bytes", "vector bytes are exact")
	check(bytes_equal(got_identities.to_byte_array(), identities.to_byte_array()), prefix + "-identity-bytes", "identity bytes are exact")

func _ready() -> void:
	# The producer writes this before loading the extension. It binds source,
	# engine, manifest, and DLL identity to this exact invocation.
	var manifest_path := "res://outputs/crowd_native_kernel_20261009/task2/run_inputs.json"
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	check(manifest_file != null, "binding-manifest", "task2 invocation inputs exist before load")
	if manifest_file == null:
		finish()
		return
	var raw_manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	check(raw_manifest is Dictionary, "binding-json", "task2 invocation inputs are valid")
	if not raw_manifest is Dictionary:
		finish()
		return
	run_binding = raw_manifest
	run_binding["manifest_actual_sha256"] = FileAccess.get_sha256(manifest_path)
	run_binding["engine_actual_path"] = OS.get_executable_path()
	run_binding["engine_actual_sha256"] = FileAccess.get_sha256(OS.get_executable_path())
	run_binding["dll_actual_sha256"] = FileAccess.get_sha256(DLL_PATH)
	for input_path: String in run_binding.get("source_sha256", {}):
		check(FileAccess.get_sha256("res://" + input_path) == str(run_binding.source_sha256[input_path]), "binding-source-" + input_path, "tested input hash matches producer")
	check(FileAccess.get_sha256(OS.get_executable_path()) == str(run_binding.get("engine_sha256", "")), "binding-engine", "native engine matches producer")
	check(FileAccess.get_sha256(DLL_PATH) == str(run_binding.get("dll_sha256", "")), "binding-dll", "loaded DLL matches producer")

	var extension = load(EXTENSION_PATH)
	var kernel: Object = ClassDB.instantiate("CrowdMeleeKernel")
	check(extension != null, "ABI-load", "explicit extension resource loads")
	check(kernel != null, "ABI-class", "explicit extension registers CrowdMeleeKernel")
	if kernel == null:
		finish()
		return
	check(int(kernel.get_abi_version()) == 1, "ABI-version", "kernel ABI version remains 1")
	check(kernel.has_method("forward_buffers"), "ABI-forward-method", "forward_buffers is bound in ClassDB")
	if not kernel.has_method("forward_buffers"):
		finish()
		return

	var scalars := PackedFloat64Array([0.0, -0.0, 1.0 / 3.0, NAN, INF, -INF, 9007199254740993.0])
	var vectors := PackedVector2Array([Vector2(0.0, -0.0), Vector2(1.25, -2.5), Vector2(INF, NAN)])
	var identities := PackedInt64Array([0, -1, 9007199254740993, 9223372036854775807, -9223372036854775807])
	var first: Variant = kernel.forward_buffers(scalars, vectors, identities)
	check_channels(first, scalars, vectors, identities, "forward-exact")
	var first_channels: Array = first
	var first_scalars: PackedFloat64Array = first_channels[0]
	var first_vectors: PackedVector2Array = first_channels[1]
	var first_identities: PackedInt64Array = first_channels[2]
	var first_scalar_bytes := first_scalars.to_byte_array()
	var first_vector_bytes := first_vectors.to_byte_array()
	var first_identity_bytes := first_identities.to_byte_array()
	scalars[0] = 42.5
	vectors[0] = Vector2(77.0, 88.0)
	identities[0] = -9223372036854775807
	check(bytes_equal(first_scalars.to_byte_array(), first_scalar_bytes), "forward-cow-scalars", "caller scalar mutation does not alter prior return")
	check(bytes_equal(first_vectors.to_byte_array(), first_vector_bytes), "forward-cow-vectors", "caller vector mutation does not alter prior return")
	check(bytes_equal(first_identities.to_byte_array(), first_identity_bytes), "forward-cow-identities", "caller identity mutation does not alter prior return")
	var second: Variant = kernel.forward_buffers(scalars, vectors, identities)
	check_channels(second, scalars, vectors, identities, "forward-mutated-call")
	finish()

func finish() -> void:
	var root := "res://outputs/crowd_native_kernel_20261009/task2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var file := FileAccess.open(root + "/contract.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"test": "crowd_quantum_abi_contract_20261009", "passed": not failed, "checks": checks, "run_binding": run_binding}, "\t"))
		file.close()
	print("HC_CROWD_QUANTUM_ABI_CONTRACT_20261009_", "FAIL" if failed else "PASS", " checks=", checks.size())
	get_tree().quit(1 if failed else 0)
