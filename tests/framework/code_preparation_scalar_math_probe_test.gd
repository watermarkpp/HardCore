extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "code_preparation_scalar_math_probe_test"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
const INPUT_PATH := "res://tests/framework/data/code_preparation_scalar_math_candidates.json"
const EXPECTED_INPUT_SHA256 := "fe65e52a28b3d5f0951e34b2736a11558003004321f376692199fdd5386fa2b4"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_probe.call_deferred()

func _probe() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "scalar math probe keeps the real non-test setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(), "formal runner supplies isolated APPDATA and run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "math probe binds invocation and exact source content")
	var input_sha := FileAccess.get_sha256(INPUT_PATH)
	check(input_sha == EXPECTED_INPUT_SHA256, "only reviewed source-derived scalar math candidate bytes can compile")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT_PATH))
	var input: Dictionary = parsed if parsed is Dictionary else {}
	check(input.get("schema_version") == 1 and input.get("producer_id") == "hc.code_preparation.scalar_math_fold_candidates.v1" and input.get("status") == "PASS" and input.get("binary_availability") == "NOT_RUN" and input.get("constant_fold_contract") == "NOT_RUN", "fixed source candidates grant no binary or folding permission")
	var engine_version := Engine.get_version_info()
	check(input.get("engine_commit") == engine_version.get("hash"), "scalar math source commit matches the executing binary")
	var engine_path := OS.get_executable_path()
	var engine_sha := FileAccess.get_sha256(engine_path)
	check(engine_sha.length() == 64, "executing native binary has an exact SHA256")
	var cached_before := ResourceLoader.has_cached(TARGET_SCRIPT)
	check(not cached_before, "target Script is cold before scalar metadata compilation")
	var raw_rows: Variant = input.get("candidate_rows", [])
	var rows: Array = raw_rows if raw_rows is Array else []
	var raw_cases: Variant = input.get("constant_fold_cases", [])
	var cases: Array = raw_cases if raw_cases is Array else []
	var valid_input := rows.size() == 1 and cases.size() == 1
	if valid_input:
		valid_input = rows[0] is Dictionary and cases[0] is Dictionary
	if valid_input:
		valid_input = rows[0].get("resource_materialization_policy") == "scalar_direct_math_forwarder" and rows[0].get("utility_category") == "UTILITY_FUNC_TYPE_MATH"
		valid_input = valid_input and rows[0].get("argument_type") == "double" and rows[0].get("return_type") == "double" and cases[0].get("native_functions") == [rows[0].get("name")]
	check(valid_input, "bounded one real eager scalar case has source-proven math forwarders")
	var reference_results: Array[Dictionary] = []
	var fold_results: Array[Dictionary] = []
	var functions: Array[String] = []
	if valid_input and input_sha == EXPECTED_INPUT_SHA256 and input.get("engine_commit") == engine_version.get("hash"):
		for row_value: Variant in rows:
			var row: Dictionary = row_value
			var name: String = row["name"]
			var reference := GDScript.new()
			reference.source_code = "extends RefCounted\nfunc native_symbol_probe():\n\treturn %s\n" % name
			var reload_error := reference.reload()
			check(reload_error == OK, "source-derived scalar utility reference compiles: " + name)
			reference_results.append({"name": name, "kind": "global_function", "reload_error": reload_error, "method_invocations": 0, "source_code_sha256": reference.source_code.sha256_text(), "status": "PASS" if reload_error == OK else "FAIL", "registration": row})
			if reload_error == OK:
				functions.append(name)
			reference = null
			await get_tree().process_frame
		for case_value: Variant in cases:
			var fold_case: Dictionary = case_value
			var source_current: bool = FileAccess.get_sha256(fold_case.owner_path) == fold_case.owner_source_sha256
			check(source_current, "real eager constant owner bytes match the reviewed candidate")
			var expression: String = fold_case.expression
			var folded := GDScript.new()
			# Compilation folds only the reviewed native scalar expression. This
			# method is never invoked; no project Script is loaded or constructed.
			folded.source_code = "extends RefCounted\nconst PROBE_VALUE := %s\nfunc native_symbol_probe():\n\treturn null\n" % expression
			var reload_error := folded.reload()
			check(reload_error == OK, "the exact real eager expression supports native constant folding")
			var constant_map: Dictionary = folded.get_script_constant_map() if reload_error == OK else {}
			var value: Variant = constant_map.get("PROBE_VALUE")
			check(typeof(value) in [TYPE_INT, TYPE_FLOAT], "constant metadata contains a scalar result without invoking a method")
			var result := fold_case.duplicate(true)
			result["reload_error"] = reload_error
			result["method_invocations"] = 0
			result["source_current"] = source_current
			result["result_type"] = type_string(typeof(value))
			result["result_value"] = value
			result["status"] = "PASS" if source_current and reload_error == OK and typeof(value) in [TYPE_INT, TYPE_FLOAT] else "FAIL"
			result["source_code_sha256"] = folded.source_code.sha256_text()
			fold_results.append(result)
			folded = null
			await get_tree().process_frame
	check(reference_results.size() == rows.size() and fold_results.size() == cases.size(), "each reviewed reference and folding case has one actual compile result")
	var cached_after := ResourceLoader.has_cached(TARGET_SCRIPT)
	check(not cached_after and cached_after == cached_before, "scalar probes leave the target Script cache unchanged and cold")
	var envelope := {"schema_version": 1, "producer_id": "hc.code_preparation.native_symbols.compile_probe.candidate.v1", "engine_commit": engine_version.get("hash"), "engine": {"version": engine_version, "executable_path": engine_path, "binary_sha256": engine_sha},
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"), "source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "authority": input.get("authority", {}), "candidate_artifact_sha256": input_sha, "candidate_producer_id": input.get("producer_id"),
		"global_functions": functions, "global_constants": [], "probe_results": reference_results, "constant_fold_cases": fold_results,
		"binary_availability": "PASS" if failures.is_empty() else "FAIL", "constant_fold_contract": "PASS" if failures.is_empty() else "FAIL", "whole_gdscript_namespace": "MISSING", "resource_readiness": "NOT_RUN", "gpu_first_draw": "NOT_RUN",
		"target_observation": {"path": TARGET_SCRIPT, "cached_before": cached_before, "cached_after": cached_after, "fixture_target_request_calls": 0, "fixture_target_get_calls": 0, "target_method_invocations": 0}}
	var directory := "res://outputs/test_logs/framework"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "scalar math metadata uses the formal evidence directory")
	var output := directory.path_join(SCENE_ID + ".symbols.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "scalar math artifact opens at one exact path")
	if file != null:
		file.store_string(JSON.stringify(envelope, "  "))
		file.close()
	check(FileAccess.get_sha256(output).length() == 64, "scalar math artifact bytes have an exact SHA256")
	print("CODE_PREPARATION_SCALAR_MATH_ARTIFACT path=%s sha256=%s namespace=MISSING" % [output, FileAccess.get_sha256(output)])
	if not proof.write_receipt(SCENE_ID, checks, failures.size()):
		failures.append("receipt")
	print("CODE_PREPARATION_SCALAR_MATH_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
