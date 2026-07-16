class_name AuthoredMapLoader
extends RefCounted

const MAP_ROOT := "res://assets/maps/"

static func load_map(map_id: String) -> Dictionary:
	var path := MAP_ROOT + map_id + "/map.json"
	if not ResourceLoader.exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary and validate_map(parsed).is_empty() else {}

static func validate_map(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in ["mapId", "mapName", "size", "grid", "layers", "objects", "npcs", "spawns", "areas", "portals"]:
		if not data.has(field): errors.append("missing_field:" + field)
	var seen := {}
	for group: String in ["objects", "npcs", "spawns", "areas", "portals"]:
		for record: Variant in data.get(group, []):
			if not record is Dictionary: continue
			var instance_id := str(record.get("instanceId", record.get("id", "")))
			if instance_id.is_empty(): errors.append("missing_instance_id:" + group)
			elif seen.has(instance_id): errors.append("duplicate_instance_id:" + instance_id)
			else: seen[instance_id] = true
	return errors
