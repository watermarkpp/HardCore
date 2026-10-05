extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "code_preparation_engine_namespace_capture_test"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "metadata capture keeps the real non-test runtime setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(),
		"formal runner supplies isolated APPDATA and run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(),
		"metadata producer binds invocation and exact tested source content")
	var target_cached_before := ResourceLoader.has_cached(TARGET_SCRIPT)
	var object_names: Array[String] = []
	for class_name_value: String in ClassDB.get_class_list():
		object_names.append(class_name_value)
	object_names.sort()
	check(not object_names.is_empty() and "Object" in object_names and "RefCounted" in object_names,
		"ClassDB returns real native object classes")
	var variants: Array[String] = []
	for type_id in range(TYPE_MAX):
		variants.append(type_string(type_id))
	check(variants.size() == TYPE_MAX and "Vector2" in variants,
		"Variant type names are captured separately from ClassDB object classes")
	var singletons: Array[String] = []
	for singleton_name: String in Engine.get_singleton_list():
		singletons.append(singleton_name)
	singletons.sort()
	var engine_path := OS.get_executable_path()
	var engine_sha := FileAccess.get_sha256(engine_path)
	check(engine_sha.length() == 64, "fixed executing engine bytes have a real FileAccess SHA256")
	var target_cached_after := ResourceLoader.has_cached(TARGET_SCRIPT)
	check(target_cached_after == target_cached_before,
		"metadata enumeration does not change target Script cache state")
	var envelope := {
		"schema_version": 1,
		"producer_id": "hc.code_preparation.engine_namespace.capture.candidate.v1",
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"engine": {"version": Engine.get_version_info(), "executable_path": engine_path, "binary_sha256": engine_sha},
		"runtime_environment": {"runtime_appdata": appdata, "user_data_directory": OS.get_user_data_dir(),
			"project_root": ProjectSettings.globalize_path("res://"), "native_process_id": OS.get_process_id()},
		"object_classes": object_names,
		"variant_type_names": variants,
		"singletons": singletons,
		"global_functions": {"status": "MISSING", "names": [], "reason": "No verified public metadata API was used."},
		"global_constants": {"status": "MISSING", "names": [], "reason": "ClassDB object classes are not the whole GDScript namespace."},
		"autoload_residency": {"status": "MISSING", "reason": "This capture does not grant live autoload resource leases."},
		"global_script_class_cache_sha256": FileAccess.get_sha256("res://.godot/global_script_class_cache.cfg"),
		"project_godot_sha256": FileAccess.get_sha256("res://project.godot"),
		"target_observation": {"path": TARGET_SCRIPT, "cached_before": target_cached_before, "cached_after": target_cached_after,
			"fixture_target_request_calls": 0, "fixture_target_get_calls": 0},
		"whole_gdscript_namespace": "MISSING",
		"gpu_first_draw": "NOT_RUN",
	}
	var directory := "res://outputs/test_logs/framework"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK,
		"metadata artifact uses the formal evidence directory")
	var output := directory.path_join(SCENE_ID + ".namespace.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "metadata artifact opens at one exact evidence path")
	if file != null:
		file.store_string(JSON.stringify(envelope, "  "))
		file.close()
	check(FileAccess.get_sha256(output).length() == 64, "metadata artifact bytes have a recorded exact SHA256")
	print("CODE_PREPARATION_NAMESPACE_ARTIFACT path=%s sha256=%s whole_namespace=MISSING" % [output, FileAccess.get_sha256(output)])
	if not proof.write_receipt(SCENE_ID, checks, failures.size()):
		failures.append("receipt")
	print("CODE_PREPARATION_ENGINE_NAMESPACE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
