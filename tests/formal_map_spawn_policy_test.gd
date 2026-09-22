extends Node


func _ready() -> void:
	assert(GameData.ensure_loaded(), GameData.load_error)
	var failures: Array[String] = []
	var slots := 0
	var maps := MapEditorRuntimeBridge.released_map_ids()
	for map_id: int in maps:
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(not content.is_empty(), "published map content missing: %d" % map_id)
		for layer: String in ["spawns", "bosses"]:
			for spawn: Dictionary in content.get(layer, []):
				var mid := int(spawn.get("monster_id", -1))
				var canonical := GameData.get_monster_by_id(mid)
				var resolved := MonsterRespawnPolicy.resolve(
					str(spawn.get("respawn_policy_id", "")),
					str(canonical.get("classification", "")),
					float(spawn.get("respawn_seconds", -1)),
					str(canonical.get("spawn_classification", "")))
				slots += 1
				if not bool(resolved.get("valid", false)):
					failures.append("map=%d mid=%d policy=%s reason=%s" % [
						map_id, mid, spawn.get("respawn_policy_id", ""), resolved.get("reason", "")])
	for failure: String in failures:
		print("SPAWN_POLICY_FAILURE ", failure)
	print("FORMAL_SPAWN_POLICY maps=%d slots=%d failures=%d" % [maps.size(), slots, failures.size()])
	if failures.is_empty() and slots > 0:
		print("FORMAL_MAP_SPAWN_POLICY_PASS")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
