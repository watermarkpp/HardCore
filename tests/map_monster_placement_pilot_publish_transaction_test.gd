extends Node

const PublishTool := preload(
	"res://tools/map_editor/publish_map_monster_placement_pilot.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)

const SOURCE_REGISTRY := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const EDITOR_PATH := (
	"res://map_editor_workspace/gmhl_purgatory_corridor/"
	+ "gmhl_purgatory_corridor.editor.json"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var nonce := Time.get_ticks_usec()
	var registry_path := "user://pilot_publish_%d/registry.json" % nonce
	var runtime_root := "user://pilot_publish_%d/runtime/" % nonce
	var runtime_path := runtime_root + "fengmo_purgatory_corridor.runtime.json"
	var previous_fixture := _build_previous_release_fixture()
	assert(bool(previous_fixture.get("ok", false)), str(previous_fixture))
	_write_bytes(registry_path, previous_fixture.registry_bytes)
	_write_bytes(runtime_path, previous_fixture.runtime_bytes)
	var source_before := _read_bytes(EDITOR_PATH)
	var registry_before := _read_bytes(registry_path)
	var runtime_before := _read_bytes(runtime_path)
	assert(_sha256_bytes(runtime_before) == PublishTool.EXPECTED_RUNTIME_SHA256)
	assert(
		_sha256_bytes(registry_before) == PublishTool.EXPECTED_REGISTRY_SHA256,
		"previous registry hash mismatch: %s"
		% _sha256_bytes(registry_before)
	)

	var dry_run := PublishTool.test_execute_scratch(
		false, registry_path, runtime_root
	)
	assert(bool(dry_run.get("ok", false)), str(dry_run))
	assert(str(dry_run.get("mode", "")) == "dry_run")
	assert(_read_bytes(registry_path) == registry_before)
	assert(_read_bytes(runtime_path) == runtime_before)
	assert(_read_bytes(EDITOR_PATH) == source_before)

	var published := PublishTool.test_execute_scratch(
		true, registry_path, runtime_root
	)
	assert(bool(published.get("ok", false)), str(published))
	assert(str(published.get("mode", "")) == "publish")
	assert(FileAccess.file_exists(runtime_path))
	assert(_read_bytes(EDITOR_PATH) == source_before)
	var registry := _read_json(registry_path)
	var matches: Array = registry.maps.filter(func(entry: Dictionary) -> bool:
		return (
			str(entry.get("map_key", "")) == "fengmo_purgatory_corridor"
			and int(entry.get("runtime_map_id", -1)) == 914007
		)
	)
	assert(matches.size() == 1)
	assert(int(matches[0].approval_revision) == 2)
	assert(
		str(matches[0].approved_build_sha256)
		== PublishTool.EXPECTED_CANDIDATE_SHA256
	)
	var runtime := _read_json(runtime_path)
	assert(
		str(runtime.get("build_sha256", ""))
		== str(matches[0].approved_build_sha256)
	)
	assert(_sorted_monster_ids(runtime.semantics.monster_spawn) == [
		112, 126, 128, 129, 132, 138, 148, 150, 153, 156,
	])
	assert(_sorted_monster_ids(runtime.semantics.boss_spawn) == [
		135, 141, 152, 155, 158,
	])

	var rollback_registry_path := (
		"user://pilot_publish_%d/rollback_registry.json" % nonce
	)
	var rollback_runtime_root := (
		"user://pilot_publish_%d/rollback_runtime/" % nonce
	)
	var rollback_runtime_path := (
		rollback_runtime_root + "fengmo_purgatory_corridor.runtime.json"
	)
	_write_bytes(rollback_registry_path, previous_fixture.registry_bytes)
	_write_bytes(rollback_runtime_path, previous_fixture.runtime_bytes)
	var rollback_registry_before := _read_bytes(rollback_registry_path)
	var rollback_runtime_before := _read_bytes(rollback_runtime_path)
	BuildService.test_fail_registry_commit = true
	var failed := PublishTool.test_execute_scratch(
		true, rollback_registry_path, rollback_runtime_root
	)
	BuildService.test_fail_registry_commit = false
	assert(not bool(failed.get("ok", false)), str(failed))
	assert(str(failed.get("reason", "")) == "formal_publish_failed")
	assert(
		bool(failed.get("evidence", {}).get("rollback_verified", false))
	)
	assert(_read_bytes(rollback_registry_path) == rollback_registry_before)
	assert(_read_bytes(rollback_runtime_path) == rollback_runtime_before)
	assert(BuildService.test_formal_runtime_root_override.is_empty())
	print(
		"MAP_MONSTER_PLACEMENT_PILOT_PUBLISH_TRANSACTION_PASS "
		+ "update_revision=2 rollback_hashes_unchanged=true"
	)
	get_tree().quit(0)


func _build_previous_release_fixture() -> Dictionary:
	var previous_document := _read_json(EDITOR_PATH)
	if previous_document.is_empty():
		return {"ok": false, "reason": "editor_unreadable"}
	var layers: Dictionary = previous_document.get("layers", {})
	layers["monster_spawn"] = _without_monster_ids(
		layers.get("monster_spawn", []), [126]
	)
	layers["boss_spawn"] = _without_monster_ids(
		layers.get("boss_spawn", []), [135, 141, 158]
	)
	var previous_candidate := BuildService.build_formal_candidate(
		previous_document
	)
	if not bool(previous_candidate.get("ok", false)):
		return previous_candidate
	if (
		str(previous_candidate.get("build_sha256", ""))
		!= PublishTool.EXPECTED_PREVIOUS_BUILD_SHA256
	):
		return {"ok": false, "reason": "previous_candidate_hash_mismatch"}
	var previous_registry := _read_json(SOURCE_REGISTRY)
	var target_count := 0
	for raw_entry: Variant in previous_registry.get("maps", []):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if (
			str(entry.get("map_key", ""))
				== "fengmo_purgatory_corridor"
			or int(entry.get("runtime_map_id", -1)) == 914007
		):
			entry["approval_revision"] = 1
			entry["runtime_map_id"] = 914007
			entry["approved_build_sha256"] = (
				PublishTool.EXPECTED_PREVIOUS_BUILD_SHA256
			)
			target_count += 1
	if target_count != 1:
		return {"ok": false, "reason": "previous_registry_target_not_unique"}
	return {
		"ok": true,
		"registry_bytes": JsonCodec.encode(previous_registry).to_utf8_buffer(),
		"runtime_bytes": _read_bytes(
			str(previous_candidate.get("candidate_path", ""))
		),
	}


func _without_monster_ids(entries: Array, removed_ids: Array) -> Array:
	var kept: Array = []
	for entry: Dictionary in entries:
		if int(entry.get("monster_id", -1)) not in removed_ids:
			kept.append(entry)
	return kept


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _sorted_monster_ids(entries: Array) -> Array:
	var ids: Array = []
	for entry: Dictionary in entries:
		ids.append(int(entry.get("monster_id", -1)))
	ids.sort()
	return ids


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var mkdir := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	assert(mkdir == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()


func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_bytes(path).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}
