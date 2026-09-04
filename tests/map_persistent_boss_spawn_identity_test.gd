extends Node

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry := _read_json(REGISTRY_PATH)
	assert(not registry.is_empty(), "formal map release registry must load")
	var boss_count := 0
	for raw_entry: Variant in registry.get("maps", []):
		assert(raw_entry is Dictionary, "release entries must be dictionaries")
		var release_entry: Dictionary = raw_entry
		var runtime_path := str(release_entry.get("runtime_path", ""))
		var runtime := _read_json(runtime_path)
		assert(not runtime.is_empty(), "formal runtime must load: %s" % runtime_path)
		for raw_spawn: Variant in runtime.get("semantics", {}).get("boss_spawn", []):
			assert(raw_spawn is Dictionary, "boss spawn entries must be dictionaries")
			var spawn: Dictionary = raw_spawn
			boss_count += 1
			assert(int(spawn.get("monster_id", -1)) > 0, "persistent boss requires canonical monster_id")
			assert(
				not str(spawn.get("spawn_group_id", "")).strip_edges().is_empty(),
				"persistent boss requires explicit stable spawn_group_id: %s:%s" % [
					str(release_entry.get("map_key", "")),
					str(spawn.get("semantic_id", "")),
				]
			)
	assert(boss_count > 0, "stable boss identity gate must not pass vacuously")
	await get_tree().process_frame
	print("MAP_PERSISTENT_BOSS_SPAWN_IDENTITY_PASS bosses=%d" % boss_count)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
