extends Node

const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const JsonCodec := preload("res://scripts/map_editor/map_editor_json_codec.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var errors: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		errors.append(label)

func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids := Bridge.released_map_ids()
	check(not ids.is_empty(), "formal release registry exposes released IDs")
	var valid_count := 0
	for runtime_id: int in ids:
		var runtime := Bridge.load_map(runtime_id)
		check(not runtime.is_empty(), "released runtime loads for %d" % runtime_id)
		if runtime.is_empty():
			continue
		valid_count += 1
		check(int(runtime.get("runtime_map_id", -1)) == runtime_id, "loaded runtime ID remains requested ID")
		check(Bridge._runtime_source_map_id(runtime.get("source", {})) == runtime_id, "source runtime ID matches registry ID")
	check(valid_count == ids.size(), "all currently released runtime IDs pass numeric identity")
	var requested_id: int = int(ids[0])
	var entry: Dictionary = Bridge._release_entry(requested_id)
	var original_path := str(entry.get("runtime_path", ""))
	var original_file := FileAccess.open(original_path, FileAccess.READ)
	var original_runtime: Dictionary = JSON.parse_string(original_file.get_as_text())
	original_file.close()
	var wrong_runtime := original_runtime.duplicate(true)
	var wrong_source: Dictionary = wrong_runtime.source.duplicate(true)
	wrong_source.runtime_map_id = requested_id + 1
	wrong_runtime.source = wrong_source
	wrong_runtime.build_sha256 = ""
	wrong_runtime.build_sha256 = _sha256(JsonCodec.encode(wrong_runtime))
	var nonce := Time.get_ticks_usec()
	var wrong_path := "user://b06_numeric_wrong_%d.runtime.json" % nonce
	var wrong_file := FileAccess.open(wrong_path, FileAccess.WRITE)
	wrong_file.store_string(JsonCodec.encode(wrong_runtime)); wrong_file.close()
	var registry_path := "user://b06_numeric_wrong_%d.registry.json" % nonce
	var registry_file := FileAccess.open(registry_path, FileAccess.WRITE)
	registry_file.store_string(JsonCodec.encode({"schema_version":1,"registry_contract_id":"mse.map.runtime.release.v1","maps":[{"runtime_map_id":requested_id,"map_key":str(entry.get("map_key","")),"display_name":"wrong source","runtime_path":wrong_path,"release_state":"implemented_playable","approved_build_sha256":wrong_runtime.build_sha256,"approval_source":"b06_fixture","approval_revision":1}]})); registry_file.close()
	Bridge.test_override_release_registry_path(registry_path)
	check(not Bridge.has_runtime_map(requested_id), "formal readiness rejects source ID mismatch")
	check(Bridge.release_rejection_reason(requested_id) == Bridge.REASON_RUNTIME_SOURCE_MAP_ID_MISMATCH, "formal rejection specifically proves numeric identity mismatch")
	check(Bridge.load_map(requested_id).is_empty(), "load_map rejects mismatched source ID before injection")
	Bridge.reset_release_registry_override()
	check(Bridge._runtime_source_map_id({"runtime_map_id": "911103"}) == -1, "string identity fails closed")
	check(Bridge._runtime_source_map_id({"runtime_map_id": true}) == -1, "boolean identity fails closed")
	check(Bridge._runtime_source_map_id({"runtime_map_id": 911103.5}) == -1, "fractional identity fails closed")
	check(Bridge._runtime_source_map_id({"runtime_map_id": 911103.0}) == 911103, "canonical JSON integral number is accepted")
	var receipt_ok := proof.write_receipt("map_editor_runtime_numeric_identity_20261010_test", checks, errors.size())
	if not receipt_ok:
		errors.append("receipt write failed")
	print(("FRAMEWORK_MAP_EDITOR_RUNTIME_NUMERIC_IDENTITY_PASS" if errors.is_empty() else "FRAMEWORK_MAP_EDITOR_RUNTIME_NUMERIC_IDENTITY_FAIL") + " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
