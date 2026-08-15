class_name MapEditorContentCatalogService
extends RefCounted

const NPCServiceIdentityScript := preload("res://scripts/npc_service_identity.gd")
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
		if kind == "npc" and content_id in entry.get("legacy_content_ids", []):
			return entry
	return {}


static func canonicalize_document_npc_labels(document: Dictionary) -> int:
	var layers: Dictionary = document.get("layers", {})
	var npc_points: Array = layers.get("npc_points", [])
	var changed := 0
	for index in npc_points.size():
		var entry: Dictionary = npc_points[index]
		var npc_id := str(entry.get("npc_id", entry.get("content_id", "")))
		var catalog_entry := find("npc", npc_id)
		var identity := NPCServiceIdentityScript.resolve(
			str(entry.get("display_name", catalog_entry.get("display_name", "NPC"))),
			str(entry.get("service_role", catalog_entry.get("service_role", "dialogue"))),
			str(catalog_entry.get("stock", ""))
		)
		var identity_id := str(identity.get("id", ""))
		if identity_id.is_empty():
			continue
		var canonical_name := str(identity.get("display_name", "NPC"))
		if (
			str(entry.get("display_name", "")) != canonical_name
			or str(entry.get("service_identity_id", "")) != identity_id
		):
			changed += 1
		entry["display_name"] = canonical_name
		entry["service_identity_id"] = identity_id
		npc_points[index] = entry
	layers["npc_points"] = npc_points
	document["layers"] = layers
	return changed


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
	for record: Dictionary in _read(EXPANSION_NPC_PATH).get("records", []):
		var item := {
			"content_id": str(record.get("npcId", "")), "display_name": str(record.get("name", "NPC")),
			"map_id": int(record.get("mapId", 0)), "service_role": str(record.get("kind", "dialogue")),
			"stock": str(record.get("stock", "")), "source": str(record.get("source", "personal_expansion")),
		}
		if int(record.get("mapId", 0)) == preferred_map_id: preferred.append(item)
		else: others.append(item)
	preferred.append_array(others)

	var canonical: Array[Dictionary] = []
	var canonical_index_by_identity := {}
	for item: Dictionary in preferred:
		var identity := NPCServiceIdentityScript.resolve(
			str(item.get("display_name", "NPC")),
			str(item.get("service_role", "dialogue")),
			str(item.get("stock", ""))
		)
		var identity_id := str(identity.get("id", ""))
		item["display_name"] = str(identity.get("display_name", item.get("display_name", "NPC")))
		item["service_identity_id"] = identity_id
		item["legacy_content_ids"] = [str(item.get("content_id", ""))]
		if identity_id.is_empty():
			canonical.append(item)
			continue
		if canonical_index_by_identity.has(identity_id):
			var canonical_index := int(canonical_index_by_identity[identity_id])
			var aliases: Array = canonical[canonical_index].get("legacy_content_ids", [])
			aliases.append(str(item.get("content_id", "")))
			canonical[canonical_index]["legacy_content_ids"] = aliases
			continue
		canonical_index_by_identity[identity_id] = canonical.size()
		canonical.append(item)
	return canonical


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}
