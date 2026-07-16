class_name MapDesignCatalogService
extends RefCounted

const CATALOG_PATH := "res://assets/data/map_design/map_design_catalog.json"
const TEMPLATE_PATH := "res://assets/data/map_design/map_size_templates.json"


static func load_catalog() -> Dictionary:
	return _read_json(CATALOG_PATH)


static func find_map(map_id: String) -> Dictionary:
	for entry: Dictionary in load_catalog().get("maps", []):
		if str(entry.get("map_id", "")) == map_id:
			return entry.duplicate(true)
	return {}


static func get_template(map_type: String) -> Dictionary:
	for entry: Dictionary in _read_json(TEMPLATE_PATH).get("templates", []):
		if str(entry.get("id", "")) == map_type:
			return entry.duplicate(true)
	return {}


static func recommended_size(map_id: String, map_type := "dungeon_floor") -> Vector2i:
	var entry := find_map(map_id)
	var size: Array = entry.get("design_size", [])
	if size.size() != 2:
		size = get_template(map_type).get("default_size", [128, 128])
	return Vector2i(int(size[0]), int(size[1]))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
