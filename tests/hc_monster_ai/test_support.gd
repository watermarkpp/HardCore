extends Node2D

var checks: Array[Dictionary] = []
var failed := false
var _receipt_nonce := ""
var last_receipt_path := ""
var _receipt_written := false

func check(condition: bool, id: String, message: String) -> void:
	checks.append({"id": id, "passed": condition, "message": message})
	if not condition:
		failed = true
		print("HC_TEST_FAIL ", id, " ", message)

func _safe_receipt_name(name: String) -> String:
	var cleaned := ""
	for character: String in name:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			cleaned += character
	if cleaned.is_empty():
		return "unnamed"
	return cleaned

func _receipt_instance_nonce() -> String:
	if not _receipt_nonce.is_empty():
		return _receipt_nonce
	var run_id := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	var invocation_id := OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var seed := "%s_%s_%d_%d" % [run_id, invocation_id, OS.get_process_id(), Time.get_ticks_usec()]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(seed.to_utf8_buffer())
	_receipt_nonce = context.finish().hex_encode().left(24)
	return _receipt_nonce

func _correlated_id(value: String, field: String) -> Dictionary:
	if not value.is_empty():
		return {"value": value, "source": "environment"}
	return {"value": "missing:%s:%s" % [field, _receipt_instance_nonce()], "source": "derived_missing_environment"}

func separate_write_receipt(name: String) -> bool:
	if _receipt_written:
		return false
	var safe_name := _safe_receipt_name(name)
	var directory := "res://outputs/hc_monster_ai_package"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var owned_directory := directory + "/" + safe_name + "__" + _receipt_instance_nonce()
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(owned_directory)) != OK:
		return false
	var scene_path := ""
	if is_inside_tree():
		if get_tree().current_scene != null:
			scene_path = get_tree().current_scene.scene_file_path
		if scene_path.is_empty():
			scene_path = get_scene_file_path()
	if scene_path.is_empty():
		scene_path = "runtime_scene_unknown"
	var run_identity := _correlated_id(OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "run_id")
	var invocation_identity := _correlated_id(OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"), "invocation_id")
	var source_hash := OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	var source_hash_source := "environment"
	if source_hash.is_empty():
		source_hash = "missing:source_sha256:%s" % _receipt_instance_nonce()
		source_hash_source = "derived_missing_environment"
	var payload := {
		"schema_version": 2,
		"test": safe_name,
		"passed": not failed,
		"checks": checks.duplicate(true),
		"source_content_sha256": source_hash,
		"source_content_sha256_source": source_hash_source,
		"engine_version": Engine.get_version_info().string,
		"scene": scene_path,
		"run_id": run_identity.value,
		"run_id_source": run_identity.source,
		"invocation_id": invocation_identity.value,
		"invocation_id_source": invocation_identity.source,
		"native_process_id": OS.get_process_id(),
		"receipt_nonce": _receipt_instance_nonce(),
	}
	var path := owned_directory + "/receipt.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var serialized := JSON.stringify(payload, "\t")
	file.store_string(serialized)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(path) != serialized:
		return false
	last_receipt_path = path
	_receipt_written = true
	return true

func finish(name: String) -> void:
	if not separate_write_receipt(name):
		failed = true
	print("HC_", name.to_upper(), "_", "FAIL" if failed else "PASS", " checks=", checks.size())
	get_tree().quit(1 if failed else 0)
