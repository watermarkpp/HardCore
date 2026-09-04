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


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Fixtures.reset_seams()
	var nonce := Time.get_ticks_usec()
	BuildService.test_formal_runtime_root_override = (
		"user://display_name_formal_%d/" % nonce
	)
	_test_republish_preserves_existing_name(nonce)
	_test_new_release_uses_authored_name(nonce)
	_test_new_release_rejects_missing_authored_name(nonce)
	Fixtures.reset_seams()
	print("MAP_RELEASE_DISPLAY_NAME_PASS")
	get_tree().quit(0)


func _test_republish_preserves_existing_name(nonce: int) -> void:
	var map_key := "display_name_existing"
	var map_id := 991121
	var registry_path := "user://display_existing_%d.json" % nonce
	var existing := Fixtures.make_entry(
		map_id,
		map_key,
		"old_hash",
		"user://old_display_name.runtime.json",
		7
	)
	existing["display_name"] = "当前正式中文地图名"
	Fixtures.write_registry(registry_path, [existing])
	var document := Fixtures.make_document(
		map_key, map_id, "编辑器候选名称不应覆盖"
	)
	assert(BuildService.approve_for_runtime(document).ok)
	var candidate := BuildService.build_candidate(document)
	assert(candidate.ok, str(candidate.get("errors", [])))
	Bridge.test_override_release_registry_path(registry_path)
	var published := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		map_id,
		candidate.document_binding,
		registry_path,
		map_key
	)
	assert(published.success, str(published))
	var registry := Fixtures.read_json(registry_path)
	assert(
		str(registry.maps[0].display_name) == "当前正式中文地图名",
		"republish must preserve the existing player-visible name"
	)


func _test_new_release_uses_authored_name(nonce: int) -> void:
	var map_key := "display_name_new"
	var map_id := 991122
	var registry_path := "user://display_new_%d.json" % nonce
	Fixtures.write_registry(registry_path, [])
	var document := Fixtures.make_document(
		map_key, map_id, "全新地图正式名称"
	)
	assert(BuildService.approve_for_runtime(document).ok)
	var candidate := BuildService.build_candidate(document)
	assert(candidate.ok, str(candidate.get("errors", [])))
	Bridge.test_override_release_registry_path(registry_path)
	var published := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		map_id,
		candidate.document_binding,
		registry_path,
		map_key
	)
	assert(published.success, str(published))
	var registry := Fixtures.read_json(registry_path)
	assert(str(registry.maps[0].display_name) == "全新地图正式名称")
	assert(str(registry.maps[0].display_name) != map_key)


func _test_new_release_rejects_missing_authored_name(nonce: int) -> void:
	var map_key := "display_name_missing"
	var map_id := 991123
	var registry_path := "user://display_missing_%d.json" % nonce
	Fixtures.write_registry(registry_path, [])
	var registry_hash := Fixtures.file_sha256(registry_path)
	var document := Fixtures.make_document(map_key, map_id, "")
	assert(BuildService.approve_for_runtime(document).ok)
	var candidate := BuildService.build_candidate(document)
	assert(candidate.ok, str(candidate.get("errors", [])))
	Bridge.test_override_release_registry_path(registry_path)
	var rejected := BuildService.publish_runtime_release(
		str(candidate.candidate_path),
		map_id,
		candidate.document_binding,
		registry_path,
		map_key
	)
	assert(
		str(rejected.get("reason", "")) == "candidate_display_name_missing",
		str(rejected)
	)
	assert(Fixtures.file_sha256(registry_path) == registry_hash)
	assert(
		not FileAccess.file_exists(BuildService.default_runtime_path(map_key))
	)
