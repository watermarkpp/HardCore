class_name MapEditorContentCatalogService
extends RefCounted

const MONSTER_PATH := "res://assets/data/vanilla_176/monsters.json"
const BOSS_PATH := "res://assets/data/vanilla_176/bosses.json"
const NPC_PATH := "res://assets/data/vanilla_176/npcs.json"
const EXPANSION_NPC_PATH := "res://assets/data/expansions/personal_expansion_001/npcs.json"


static func entries(kind: String, preferred_map_id := 4) -> Array[Dictionary]:
	match kind:
		"monster_spawn": return _combat_entries(MONSTER_PATH, "monster")
		"boss_spawn": return _combat_entries(BOSS_PATH, "boss")
		"npc": return _npc_entries(preferred_map_id)
	return []


static func find(kind: String, content_id: String) -> Dictionary:
	for entry: Dictionary in entries(kind, 4):
		if str(entry.get("content_id", "")) == content_id:
			return entry
	return {}


static func _combat_entries(path: String, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _read(path).get("records", []):
		var numeric_id := int(record.get("monsterId", 0))
		result.append({
			"content_id": "%s.%d" % [prefix, numeric_id], "display_name": str(record.get("name", numeric_id)),
			"numeric_id": numeric_id, "level": int(record.get("level", 0)), "hp": int(record.get("hp", 0)),
			"source": str(record.get("source", "vanilla_176")), "confidence": str(record.get("confidence", "")),
		})
	return result


static func _npc_entries(preferred_map_id: int) -> Array[Dictionary]:
	var preferred: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for group: Dictionary in _read(NPC_PATH).get("records", []):
		var map_id := int(group.get("mapId", 0))
		var index := 0
		for record: Dictionary in group.get("records", []):
			index += 1
			var item := {
				"content_id": "npc.%d.%03d" % [map_id, index], "display_name": str(record.get("name", "NPC")),
				"map_id": map_id, "service_role": str(record.get("kind", "dialogue")),
				"stock": str(record.get("stock", "")), "source": "vanilla_176",
			}
			if map_id == preferred_map_id: preferred.append(item)
			else: others.append(item)
	preferred.append_array(others)
	for record: Dictionary in _read(EXPANSION_NPC_PATH).get("records", []):
		if int(record.get("mapId", 0)) != preferred_map_id: continue
		preferred.append({
			"content_id": str(record.get("npcId", "")), "display_name": str(record.get("name", "NPC")),
			"map_id": int(record.get("mapId", 0)), "service_role": str(record.get("kind", "dialogue")),
			"stock": str(record.get("stock", "")), "source": str(record.get("source", "personal_expansion")),
		})
	return preferred


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}
