extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const BUILD_INFO_PATH := "user://character_select_build_version_test.json"
const MISSING_BUILD_INFO_PATH := "user://character_select_build_version_test_missing.json"
var proof := Proof.new()
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _write_build_info(version_code: int, git_short_head: String) -> void:
	var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.WRITE)
	check(file != null, "test build_info file must be writable")
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version_code": version_code,
		"version_name": "hardcore 1.0 正式版",
		"git_short_head": git_short_head,
		"git_head": git_short_head + "0".repeat(32),
		"git_dirty": false,
		"build_type": "official",
	}))
	file.close()


func _write_raw_build_info(raw: String) -> void:
	var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.WRITE)
	check(file != null, "test build_info file must be writable")
	if file == null:
		return
	file.store_string(raw)
	file.close()


func _fingerprint_for_path(launcher: Control, path: String) -> String:
	# Keep the RED phase an assertion failure against the old zero-argument
	# implementation, rather than an engine arity error. Once production adds
	# the optional path, this helper exercises that same FileAccess path.
	for method: Dictionary in launcher.get_method_list():
		if str(method.get("name", "")) != "_build_fingerprint_text":
			continue
		var arguments: Array = method.get("args", [])
		if arguments.size() >= 1:
			return str(launcher.call("_build_fingerprint_text", path))
		return launcher._build_fingerprint_text()
	check(false, "CharacterSelect must expose _build_fingerprint_text")
	return ""


func _legacy_fallback_text() -> String:
	var app_name := str(ProjectSettings.get_setting("application/config/name", "HardCore"))
	if app_name.is_empty():
		app_name = "HardCore"
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	if version.is_empty():
		version = "dev"
	var revision := str(ProjectSettings.get_setting("application/config/build_revision", "local"))
	if revision.is_empty():
		revision = "local"
	return "%s · v%s · %s" % [app_name, version, revision.left(12)]


func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)


func _remove_test_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	var old_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	var launcher: Control = load("res://scenes/character_select.tscn").instantiate()
	launcher.suppress_scene_change_for_test = true
	add_child(launcher)
	await get_tree().process_frame

	_write_build_info(112, "cf50aa73")
	var v112_text := _fingerprint_for_path(launcher, BUILD_INFO_PATH)
	check(v112_text == "HardCore · v112 · cf50aa73", "character hall must show the APK version and source fingerprint from build_info.json")

	_write_build_info(113, "a1b2c3d4")
	var v113_text := _fingerprint_for_path(launcher, BUILD_INFO_PATH)
	check(v113_text == "HardCore · v113 · a1b2c3d4", "character hall version text must change with each generated APK")
	check(v113_text != v112_text, "character hall must not retain the previous package version")
	check(not v113_text.contains("<") and not v113_text.contains(">"), "valid build info must not render placeholder or malformed fingerprint text")
	check(v113_text.length() <= 32, "version text must fit the existing 470 pixel fingerprint label")

	_write_raw_build_info(JSON.stringify({"version_code": 999, "git_short_head": "unknown"}))
	var unknown_text := _fingerprint_for_path(launcher, BUILD_INFO_PATH)
	check(unknown_text == _legacy_fallback_text(), "unknown build info must use the existing ProjectSettings fallback")

	_write_raw_build_info(JSON.stringify({
		"version_code": 113.5,
		"version_name": "hardcore 1.0 正式版",
		"git_short_head": "a1b2c3d4",
		"git_head": "a1b2c3d4" + "0".repeat(32),
	}))
	var non_integral_text := _fingerprint_for_path(launcher, BUILD_INFO_PATH)
	check(non_integral_text == _legacy_fallback_text(), "non-integral version_code must use the existing ProjectSettings fallback")

	_write_raw_build_info("{ malformed build info")
	var malformed_text := _fingerprint_for_path(launcher, BUILD_INFO_PATH)
	check(malformed_text == _legacy_fallback_text(), "malformed build info must use the existing ProjectSettings fallback")

	_remove_test_file(BUILD_INFO_PATH)
	var missing_text := _fingerprint_for_path(launcher, MISSING_BUILD_INFO_PATH)
	check(missing_text == _legacy_fallback_text(), "missing build info must use the existing ProjectSettings fallback")

	_remove_test_file(BUILD_INFO_PATH)
	_remove_test_file(MISSING_BUILD_INFO_PATH)
	launcher.queue_free()
	PlayerState.test_mode = old_test_mode
	var receipt_written := proof.write_receipt("character_select_build_version_test", proof.records.size(), failures.size())
	print("CHARACTER_SELECT_BUILD_VERSION_TEST_%s failures=%s" % ["PASS" if receipt_written and failures.is_empty() else "FAIL", str(failures)])
	get_tree().quit(0 if receipt_written and failures.is_empty() else 1)
