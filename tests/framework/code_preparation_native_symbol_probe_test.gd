extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "code_preparation_native_symbol_probe_test"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
const INPUT_PATH := "res://tests/framework/data/code_preparation_native_symbol_candidates.json"
const EXPECTED_INPUT_SHA256 := "fa94a4bbf78aa9831719194a175eae0303615db96d68e33835691a5e34564c41"
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

func _safe_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
		if not letter and not (index > 0 and code >= 48 and code <= 57):
			return false
	return true

func _probe() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "symbol probe keeps the real non-test setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(),
		"formal runner supplies isolated APPDATA and run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(),
		"symbol producer binds invocation and exact tested content")
	var input_sha := FileAccess.get_sha256(INPUT_PATH)
	check(input_sha == EXPECTED_INPUT_SHA256, "only reviewed fixed-source candidate bytes can reach the compiler")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUT_PATH))
	var input: Dictionary = parsed if parsed is Dictionary else {}
	check(input.get("schema_version") == 1 and input.get("producer_id") == "hc.code_preparation.fixed_engine_symbol_candidates.v1"
		and input.get("status") == "PASS" and input.get("binary_availability") == "NOT_RUN", "source registration grants no binary availability")
	var engine_version := Engine.get_version_info()
	check(input.get("engine_commit") == engine_version.get("hash"), "candidate official commit matches the executing binary version")
	var engine_path := OS.get_executable_path()
	var engine_sha := FileAccess.get_sha256(engine_path)
	check(engine_sha.length() == 64, "executing native binary bytes have an exact SHA256")
	var cached_before := ResourceLoader.has_cached(TARGET_SCRIPT)
	check(not cached_before, "target Script remains cold before metadata compilation")
	var raw_rows: Variant = input.get("candidate_rows", [])
	var rows: Array = raw_rows if raw_rows is Array else []
	var identities: Dictionary = {}
	var valid_rows := rows.size() > 0 and rows.size() <= 32
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			valid_rows = false
			continue
		var row: Dictionary = row_value
		var name := str(row.get("name", ""))
		var kind := str(row.get("kind", ""))
		valid_rows = valid_rows and _safe_identifier(name) and not identities.has(name)
		valid_rows = valid_rows and kind in ["global_constant", "global_function"]
		valid_rows = valid_rows and not ClassDB.class_exists(name) and not Engine.has_singleton(name)
		valid_rows = valid_rows and not ProjectSettings.has_setting("autoload/" + name)
		identities[name] = true
	check(valid_rows, "bounded exact native candidates exclude object classes and project autoload symbols")
	var results: Array[Dictionary] = []
	var constants: Array[String] = []
	var functions: Array[String] = []
	if input_sha == EXPECTED_INPUT_SHA256 and valid_rows and input.get("engine_commit") == engine_version.get("hash"):
		for row_value: Variant in rows:
			var row: Dictionary = row_value
			var name: String = row["name"]
			# Compile a reference only. Never execute this method, construct a target
			# object, or resolve any project Script through ResourceLoader.
			var script := GDScript.new()
			script.source_code = "extends RefCounted\nfunc native_symbol_probe():\n\treturn %s\n" % name
			var reloaded := script.reload()
			check(reloaded == OK, "source-derived native reference compiles: " + name)
			results.append({"name": name, "kind": row["kind"], "reload_error": reloaded,
				"source_code_sha256": script.source_code.sha256_text(), "method_invocations": 0,
				"registration": row, "status": "PASS" if reloaded == OK else "FAIL"})
			if reloaded == OK:
				if row["kind"] == "global_constant":
					constants.append(name)
				else:
					functions.append(name)
			script = null
			await get_tree().process_frame
	check(results.size() == rows.size(), "every candidate has one real compile result")
	var cached_after := ResourceLoader.has_cached(TARGET_SCRIPT)
	check(not cached_after and cached_after == cached_before, "in-memory symbol probes leave the target Script cold")
	var envelope := {
		"schema_version": 1, "producer_id": "hc.code_preparation.native_symbols.compile_probe.candidate.v1",
		"engine_commit": engine_version.get("hash"), "engine": {"version": engine_version, "executable_path": engine_path, "binary_sha256": engine_sha},
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "authority": input.get("authority", {}),
		"candidate_artifact_sha256": input_sha, "candidate_producer_id": input.get("producer_id"),
		"global_constants": constants, "global_functions": functions, "probe_results": results,
		"target_observation": {"path": TARGET_SCRIPT, "cached_before": cached_before, "cached_after": cached_after,
			"fixture_target_request_calls": 0, "fixture_target_get_calls": 0, "target_method_invocations": 0},
		"binary_availability": "PASS" if failures.is_empty() else "FAIL", "whole_gdscript_namespace": "MISSING",
		"resource_readiness": "NOT_RUN", "gpu_first_draw": "NOT_RUN",
	}
	var directory := "res://outputs/test_logs/framework"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "native symbol artifact uses the formal evidence directory")
	var output := directory.path_join(SCENE_ID + ".symbols.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "native symbol evidence opens at one exact path")
	if file != null:
		file.store_string(JSON.stringify(envelope, "  "))
		file.close()
	check(FileAccess.get_sha256(output).length() == 64, "native symbol evidence has an exact byte SHA256")
	print("CODE_PREPARATION_SYMBOLS_ARTIFACT path=%s sha256=%s namespace=MISSING" % [output, FileAccess.get_sha256(output)])
	if not proof.write_receipt(SCENE_ID, checks, failures.size()):
		failures.append("receipt")
	print("CODE_PREPARATION_NATIVE_SYMBOL_PROBE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
