extends Node

const PublishTool := preload(
	"res://tools/map_editor/publish_map_monster_placement_pilot.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
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
	_write_bytes(registry_path, _read_bytes(SOURCE_REGISTRY))
	var source_before := _read_bytes(EDITOR_PATH)
	var registry_before := _read_bytes(registry_path)
	var runtime_path := runtime_root + "fengmo_purgatory_corridor.runtime.json"

	var dry_run := PublishTool.test_execute_scratch(
		false, registry_path, runtime_root
	)
	assert(bool(dry_run.get("ok", false)), str(dry_run))
	assert(str(dry_run.get("mode", "")) == "dry_run")
	assert(_read_bytes(registry_path) == registry_before)
	assert(not FileAccess.file_exists(runtime_path))
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
	assert(
		str(matches[0].approved_build_sha256)
		== PublishTool.EXPECTED_CANDIDATE_SHA256
	)
	var runtime := _read_json(runtime_path)
	assert(
		str(runtime.get("build_sha256", ""))
		== str(matches[0].approved_build_sha256)
	)
	assert(BuildService.test_formal_runtime_root_override.is_empty())
	print("MAP_MONSTER_PLACEMENT_PILOT_PUBLISH_TRANSACTION_PASS")
	get_tree().quit(0)


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
