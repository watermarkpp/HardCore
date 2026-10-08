extends Node

const Policy := preload("res://scripts/monster_ai_package/policy.gd")
const EXTENSION_PATH := "res://research/native/crowd_kernel/crowd_kernel.gdextension"

var checks: Array[Dictionary] = []
var failed := false
var run_binding: Dictionary = {}

func check(condition: bool, id: String, message: String) -> void:
	checks.append({"id": id, "passed": condition, "message": message})
	if not condition:
		failed = true
		print("HC_TEST_FAIL ", id, " ", message)

func compare(kernel: Object, a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float, id: String) -> void:
	var expected := Policy.core_crossed(a, b, c, ra, rb)
	var actual := bool(kernel.core_crossed(a, b, c, ra, rb))
	check(actual == expected, id, "native result differs from stock core_crossed")

func _ready() -> void:
	# Inputs are recorded by the invocation producer before explicit DLL load.
	var manifest_path := "res://outputs/crowd_native_kernel_20261009/task1/current_run_inputs.json"
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	check(manifest_file != null, "binding-manifest", "invocation inputs exist before load")
	if manifest_file == null:
		finish()
		return
	var raw_manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	check(raw_manifest is Dictionary, "binding-json", "invocation inputs are valid")
	if not raw_manifest is Dictionary:
		finish()
		return
	run_binding = raw_manifest
	run_binding["manifest_sha256"] = FileAccess.get_sha256(manifest_path)
	run_binding["engine_actual_path"] = OS.get_executable_path()
	run_binding["engine_actual_sha256"] = FileAccess.get_sha256(OS.get_executable_path())
	for input_path: String in run_binding.get("source_sha256", {}):
		check(FileAccess.get_sha256("res://" + input_path) == str(run_binding.source_sha256[input_path]), "binding-source-" + input_path, "tested input hash matches producer")
	check(FileAccess.get_sha256(OS.get_executable_path()) == str(run_binding.get("engine_sha256", "")), "binding-engine", "native engine matches producer")
	check(FileAccess.get_sha256("res://research/native/crowd_kernel/bin/crowd_melee_kernel.windows.template_debug.x86_64.dll") == str(run_binding.get("dll_sha256", "")), "binding-dll", "loaded DLL matches producer")
	var extension = load(EXTENSION_PATH)
	var kernel: Object = ClassDB.instantiate("CrowdMeleeKernel")
	check(extension != null, "ABI-load", "explicit extension resource loads")
	check(kernel != null, "ABI-class", "explicit extension registers CrowdMeleeKernel")
	if kernel == null:
		finish()
		return
	check(int(kernel.get_abi_version()) == 1, "ABI-version", "kernel ABI version is 1")
	compare(kernel, Vector2(-1, 0), Vector2(1, 0), Vector2.ZERO, .35, .35, "core-through")
	compare(kernel, Vector2(-.4, 0), Vector2(.9, 0), Vector2.ZERO, .35, .35, "core-overlap-enter")
	compare(kernel, Vector2(-.4, 0), Vector2(-.9, 0), Vector2.ZERO, .35, .35, "core-overlap-exit")
	compare(kernel, Vector2(-1, .5), Vector2(1, .5), Vector2.ZERO, .25, .25, "core-actual-tangent")
	# Both radii collapse to one float32 value but cross the float64 policy
	# threshold. A real_t native parameter must fail at least one of these.
	var threshold_radius := sqrt(.25 + .0001)
	var scalar_low := threshold_radius - 0.0000000001
	var scalar_high := threshold_radius + 0.0000000001
	check(not Policy.core_crossed(Vector2(-1,.5), Vector2(1,.5), Vector2.ZERO, scalar_low, 0.0), "corpus-radius-low", "low threshold branch is false")
	check(Policy.core_crossed(Vector2(-1,.5), Vector2(1,.5), Vector2.ZERO, scalar_high, 0.0), "corpus-radius-high", "high threshold branch is true")
	compare(kernel, Vector2(-1,.5), Vector2(1,.5), Vector2.ZERO, scalar_low, 0.0, "core-radius-double-low")
	compare(kernel, Vector2(-1,.5), Vector2(1,.5), Vector2.ZERO, scalar_high, 0.0, "core-radius-double-high")
	for y: float in [.5 - pow(2.0,-25.0), .5, .5 + pow(2.0,-24.0)]:
		compare(kernel, Vector2(-1,y), Vector2(1,y), Vector2.ZERO, threshold_radius, 0.0, "core-vector32-neighbor-" + str(y))
	for center: Vector2 in [Vector2(-2,.5), Vector2(-1,.5), Vector2(1,.5), Vector2(2,.5), Vector2.ZERO]:
		compare(kernel, Vector2(-1,0), Vector2(1,0), center, .35, .35, "core-clamp-" + str(center))
	compare(kernel, Vector2(1,1), Vector2(1,1), Vector2.ZERO, 2.0, 0.0, "core-degenerate-nonzero")
	for bx: float in [.9999 - pow(2.0,-24.0), .9999, .9999 + pow(2.0,-24.0)]:
		compare(kernel, Vector2(1,0), Vector2(bx,.02), Vector2.ZERO, 1.0, 1.0, "core-dot-epsilon-neighbor-" + str(bx))
	compare(kernel, Vector2(-1,0), Vector2(1,0), Vector2.ZERO, NAN, 0.0, "core-radius-nan")
	compare(kernel, Vector2(-1,0), Vector2(1,0), Vector2.ZERO, INF, -INF, "core-radius-inf-sum-nan")
	compare(kernel, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, .35, .35, "core-degenerate")
	compare(kernel, Vector2(-1, 0), Vector2(1, 0), Vector2.ZERO, -2.0, -.5, "core-negative-radii")
	compare(kernel, Vector2.INF, Vector2.ZERO, Vector2.ZERO, .35, .35, "core-inf")
	compare(kernel, Vector2(INF, INF) * 0.0, Vector2.ZERO, Vector2.ZERO, .35, .35, "core-nan")
	var seed := 0x5EED1234
	for index in range(256):
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var x0 := float(seed % 2001 - 1000) / 100.0
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var y0 := float(seed % 2001 - 1000) / 100.0
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var x1 := float(seed % 2001 - 1000) / 100.0
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var y1 := float(seed % 2001 - 1000) / 100.0
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var xc := float(seed % 2001 - 1000) / 100.0
		seed = int((seed * 1664525 + 1013904223) & 0x7fffffff)
		var yc := float(seed % 2001 - 1000) / 100.0
		compare(kernel, Vector2(x0, y0), Vector2(x1, y1), Vector2(xc, yc), .35, .398, "fuzz-%03d" % index)
	finish()

func finish() -> void:
	var root := "res://outputs/crowd_native_kernel_20261009/task1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var file := FileAccess.open(root + "/contract.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"test": "crowd_native_kernel_contract_20261009", "passed": not failed, "checks": checks, "run_binding": run_binding}, "\t"))
		file.close()
	print("HC_CROWD_NATIVE_KERNEL_CONTRACT_20261009_", "FAIL" if failed else "PASS", " checks=", checks.size())
	get_tree().quit(1 if failed else 0)
