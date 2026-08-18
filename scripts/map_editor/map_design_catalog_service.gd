class_name MapDesignCatalogService
extends RefCounted

const CATALOG_PATH := "res://assets/data/map_design/map_design_catalog.json"
const TEMPLATE_PATH := "res://assets/data/map_design/map_size_templates.json"
const BLANK_TEMPLATE_PATH := "res://assets/data/map_design/map_blank_templates.json"


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


static func blank_templates() -> Array:
	return _read_json(BLANK_TEMPLATE_PATH).get("templates", [])


static func find_blank_template(template_id: String) -> Dictionary:
	for entry: Dictionary in blank_templates():
		if str(entry.get("template_id", "")) == template_id:
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


static func delete_blank_template(template_id: String, map_id := "") -> Dictionary:
	if template_id.is_empty() and map_id.is_empty():
		return {"ok": false, "errors": ["both_ids_empty"]}
	var data := _read_json(BLANK_TEMPLATE_PATH)
	if data.is_empty():
		return {"ok": false, "errors": ["file_not_found_or_empty"]}
	var templates: Array = data.get("templates", [])
	var found_index := -1
	var found_entry := {}
	for i in range(templates.size()):
		var entry: Dictionary = templates[i]
		var entry_template_id := str(entry.get("template_id", ""))
		var entry_map_id := str(entry.get("map_id", ""))
		var match := false
		if not template_id.is_empty() and entry_template_id == template_id:
			match = true
		elif not map_id.is_empty() and entry_map_id == map_id:
			match = true
		if match:
			found_index = i
			found_entry = entry
			break
	if found_index < 0:
		return {"ok": false, "errors": ["template_not_found"]}
	templates.remove_at(found_index)
	data["templates"] = templates
	var absolute_path := ProjectSettings.globalize_path(BLANK_TEMPLATE_PATH)
	var temporary := absolute_path + ".tmp"
	var backup := absolute_path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["open_temp_failed"]}
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	file.close()
	var verify_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(temporary))
	if not verify_parsed is Dictionary:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["temp_verification_failed"]}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute_path):
		var backup_error := DirAccess.rename_absolute(absolute_path, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["backup_failed:%d" % backup_error]}
	var promote_error := DirAccess.rename_absolute(temporary, absolute_path)
	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute_path)
		return {"ok": false, "errors": ["promote_failed:%d" % promote_error]}
	return {
		"ok": true,
		"deleted_template_id": str(found_entry.get("template_id", "")),
		"deleted_map_id": str(found_entry.get("map_id", "")),
		"deleted_display_name": str(found_entry.get("display_name", "")),
	}
