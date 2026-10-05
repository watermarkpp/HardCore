extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Save := preload("res://scripts/map_editor/map_editor_save_service.gd")
const Codec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const PROPOSAL := "res://outputs/framework_v2/formal_respawn_20261005/RESPAWN_POLICY_PROPOSAL.json"
var proof := Proof.new()
var errors: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> bool:
	proof.record(value, label)
	if not value:
		errors.append(label)
	return value

func _supports_preserved_text() -> bool:
	var script_resource: Script = Save
	for method: Dictionary in script_resource.get_script_method_list():
		if method.name == "save_document":
			return (method.args as Array).size() >= 3
	return false

func _save(document: Dictionary, path: String, source: String) -> Dictionary:
	if _supports_preserved_text():
		return Callable(Save, "save_document").callv([document, path, source])
	return Save.save_document(document, path)

func _run() -> void:
	if not check(OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID") != "", "native proof invocation exists"):
		_finish()
		return
	var proposal := Codec.decode(FileAccess.get_file_as_string(PROPOSAL))
	var sample: Dictionary = {}
	var sample_source := ""
	for key: String in proposal.maps:
		var path := "res://map_editor_workspace/%s/%s.editor.json" % [key, key]
		var source := FileAccess.get_file_as_string(path)
		var document := Codec.decode(source)
		check(not document.is_empty(), key + ": actual authoring source loads")
		var destination := "user://map_authoring_preserved_save/%s.editor.json" % key
		var saved := _save(document, destination, source)
		check(bool(saved.get("ok", false)), key + ": official isolated save succeeds")
		check(FileAccess.get_file_as_string(destination) == source, key + ": unrelated authored numbers and all raw bytes survive official save")
		if sample.is_empty():
			sample = document
			sample_source = source
		await get_tree().process_frame
	var mismatch := sample.duplicate(true)
	check(not Save._preserved_json_value_matches(9007199254740993, 9007199254740992.0),
		"unsafe integral JSON values cannot pass through rounded floating identity")
	check(not Save._preserved_json_value_matches(-9223372036854775807 - 1, -9223372036854775808.0),
		"minimum signed integer cannot overflow the exact-normalization range guard")
	check(not Save._preserved_json_value_matches(true, 1.0), "boolean and numeric values remain distinct")
	var typed := sample.duplicate(true)
	typed.editor_meta.revision = int(typed.editor_meta.revision)
	var typed_path := "user://map_authoring_preserved_save/typed_revision.editor.json"
	var typed_saved := _save(typed, typed_path, sample_source)
	check(bool(typed_saved.get("ok", false)) and FileAccess.get_file_as_string(typed_path) == sample_source,
		"typed integral revision and JSON numeric revision retain identical authoritative value and bytes")
	var precision := sample.duplicate(true)
	precision.design.design_size[0] = float(precision.design.design_size[0]) + 0.00000001
	var precision_path := "user://map_authoring_preserved_save/precision_rejected.editor.json"
	var precision_rejected := _save(precision, precision_path, sample_source)
	check(not bool(precision_rejected.get("ok", false)) and not FileAccess.file_exists(precision_path),
		"a real fractional authored-number change is not accepted as integral normalization")
	mismatch.editor_meta.revision = int(mismatch.editor_meta.revision) + 1
	var rejected_path := "user://map_authoring_preserved_save/rejected.editor.json"
	var rejected := _save(mismatch, rejected_path, sample_source)
	check(not bool(rejected.get("ok", false)), "source text cannot replace a different authoritative document")
	check(not FileAccess.file_exists(rejected_path) and not FileAccess.file_exists(rejected_path + ".tmp"), "mismatch refuses before any output or temp file")
	var invalid_path := "user://map_authoring_preserved_save/invalid.editor.json"
	var invalid := _save(sample, invalid_path, "{invalid")
	check(not bool(invalid.get("ok", false)), "malformed preservation text is refused")
	check(not FileAccess.file_exists(invalid_path) and not FileAccess.file_exists(invalid_path + ".tmp"), "malformed text refuses before any file mutation")
	Save.test_workspace_root_override = "user://map_authoring_preserved_save/workspace/"
	var formal_path := "res://map_editor_workspace/%s/%s.editor.json" % [sample.map_id, sample.map_id]
	var original_sha := FileAccess.get_sha256(formal_path)
	var forbidden := _save(sample, formal_path, sample_source)
	check(not bool(forbidden.get("ok", false)) and FileAccess.get_sha256(formal_path) == original_sha,
		"preserved text does not bypass the formal-workspace isolation guard")
	Save.test_workspace_root_override = ""
	_finish()

func _finish() -> void:
	var written := proof.write_receipt("map_authoring_preserved_save_test", proof.records.size(), errors.size())
	print("MAP_AUTHORING_PRESERVED_SAVE_", "PASS" if written and errors.is_empty() else "FAIL", " checks=", proof.records.size(), " errors=", errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
