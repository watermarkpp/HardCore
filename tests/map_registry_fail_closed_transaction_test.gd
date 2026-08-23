extends Node

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const Bridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)

const MAP_KEY := "registry_fail_closed_map"
const MAP_ID := 991111


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	var nonce := Time.get_ticks_usec()
	var root := "user://registry_fail_closed_formal_%d/" % nonce
	BuildService.test_formal_runtime_root_override = root
	var document := Fixtures.make_document(
		MAP_KEY, MAP_ID, "Registry Fail Closed 地图"
	)
	assert(BuildService.approve_for_runtime(document).ok)
	var candidate_a := BuildService.build_candidate(document)
	assert(candidate_a.ok, str(candidate_a.get("errors", [])))
	var formal_path := BuildService.default_runtime_path(MAP_KEY)

	var missing_registry := "user://missing_registry_%d.json" % nonce
	var missing := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		missing_registry,
		MAP_KEY
	)
	assert(
		str(missing.get("reason", "")) == "release_registry_missing",
		str(missing)
	)
	assert(not FileAccess.file_exists(formal_path))
	assert(not FileAccess.file_exists(missing_registry))

	var invalid_json_registry := "user://invalid_registry_%d.json" % nonce
	_write_text(invalid_json_registry, "{ definitely not json")
	var invalid_json_hash := Fixtures.file_sha256(invalid_json_registry)
	var invalid_json := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		invalid_json_registry,
		MAP_KEY
	)
	assert(
		str(invalid_json.get("reason", ""))
		== "release_registry_json_invalid"
	)
	assert(Fixtures.file_sha256(invalid_json_registry) == invalid_json_hash)
	assert(not FileAccess.file_exists(formal_path))

	var invalid_schema_registry := "user://invalid_schema_%d.json" % nonce
	Fixtures.write_json(invalid_schema_registry, {
		"schema_version": 999,
		"registry_contract_id": "wrong.contract",
		"maps": [],
	})
	var invalid_schema_hash := Fixtures.file_sha256(invalid_schema_registry)
	var invalid_schema := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		invalid_schema_registry,
		MAP_KEY
	)
	assert(
		str(invalid_schema.get("reason", "")) == "release_registry_invalid",
		str(invalid_schema)
	)
	assert(
		Fixtures.file_sha256(invalid_schema_registry) == invalid_schema_hash
	)
	assert(not FileAccess.file_exists(formal_path))

	var invalid_shape_registry := "user://invalid_shape_%d.json" % nonce
	Fixtures.write_json(invalid_shape_registry, {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": {},
	})
	var invalid_shape_hash := Fixtures.file_sha256(invalid_shape_registry)
	var invalid_shape := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		invalid_shape_registry,
		MAP_KEY
	)
	assert(
		str(invalid_shape.get("reason", "")) == "release_registry_invalid",
		str(invalid_shape)
	)
	assert(Fixtures.file_sha256(invalid_shape_registry) == invalid_shape_hash)
	assert(not FileAccess.file_exists(formal_path))

	var registry_path := "user://transaction_registry_%d.json" % nonce
	Fixtures.write_registry(registry_path, [])
	Bridge.test_override_release_registry_path(registry_path)
	var published_a := BuildService.publish_runtime_release(
		str(candidate_a.candidate_path),
		MAP_ID,
		candidate_a.document_binding,
		registry_path,
		MAP_KEY
	)
	assert(published_a.success, str(published_a))
	var formal_hash_a := Fixtures.file_sha256(formal_path)
	Fixtures.mutate_and_bake(document)
	var candidate_b := BuildService.build_candidate(document)
	assert(candidate_b.ok, str(candidate_b.get("errors", [])))

	# Keep the registry valid but deliberately non-canonical so a rollback that
	# reserializes the parsed dictionary cannot pass the byte identity check.
	var registry: Dictionary = Fixtures.read_json(registry_path)
	_write_text(registry_path, " \n" + JsonCodec.encode(registry) + "\n")
	var registry_bytes_before := _read_bytes(registry_path)
	Bridge.invalidate_release_registry()
	BuildService.test_fail_post_publish_verify = true
	var failed := BuildService.publish_runtime_release(
		str(candidate_b.candidate_path),
		MAP_ID,
		candidate_b.document_binding,
		registry_path,
		MAP_KEY
	)
	BuildService.test_fail_post_publish_verify = false
	assert(
		str(failed.get("reason", "")) == "post_publish_verify_failed",
		str(failed)
	)
	assert(
		_read_bytes(registry_path) == registry_bytes_before,
		"failed publish must restore registry bytes exactly"
	)
	assert(
		Fixtures.file_sha256(formal_path) == formal_hash_a,
		"failed publish must restore the formal runtime bytes"
	)
	Fixtures.reset_seams()
	print("MAP_REGISTRY_FAIL_CLOSED_TRANSACTION_PASS")
	get_tree().quit(0)


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string(value)
	file.close()


func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read %s" % path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes
