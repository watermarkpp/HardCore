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


static func find_blank_template_by_map_id(
	map_id: String
) -> Dictionary:
	if map_id.is_empty():
		return {}

	for entry: Dictionary in blank_templates():
		if str(entry.get("map_id", "")) == map_id:
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


static func delete_blank_template(
	template_id: String,
	map_id := ""
) -> Dictionary:
	if template_id.is_empty() and map_id.is_empty():
		return {
			"ok": false,
			"errors": ["both_ids_empty"],
		}

	var data := _read_json(BLANK_TEMPLATE_PATH)

	if data.is_empty():
		return {
			"ok": false,
			"errors": ["file_not_found_or_empty"],
		}

	var templates: Array = data.get(
		"templates",
		[]
	)

	var found_index := -1
	var found_entry: Dictionary = {}

	for index: int in range(templates.size()):
		var entry_variant: Variant = templates[index]

		if not entry_variant is Dictionary:
			continue

		var entry: Dictionary = entry_variant
		var entry_template_id := str(
			entry.get(
				"template_id",
				""
			)
		)
		var entry_map_id := str(
			entry.get(
				"map_id",
				""
			)
		)

		var template_matches := (
			not template_id.is_empty()
			and entry_template_id == template_id
		)

		var map_matches := (
			not map_id.is_empty()
			and entry_map_id == map_id
		)

		if template_matches or map_matches:
			found_index = index
			found_entry = entry.duplicate(true)
			break

	if found_index < 0:
		return {
			"ok": false,
			"errors": ["template_not_found"],
		}

	templates.remove_at(found_index)
	data["templates"] = templates

	var absolute_path := ProjectSettings.globalize_path(
		BLANK_TEMPLATE_PATH
	)

	var temporary := absolute_path + ".tmp"
	var backup := absolute_path + ".bak"

	var file := FileAccess.open(
		temporary,
		FileAccess.WRITE
	)

	if file == null:
		return {
			"ok": false,
			"errors": ["open_temp_failed"],
		}

	file.store_string(
		JSON.stringify(
			data,
			"\t",
			false
		)
	)

	file.flush()
	file.close()

	# 重新读取临时文件，确认 JSON 可解析。
	var verify_file := FileAccess.open(
		temporary,
		FileAccess.READ
	)

	if verify_file == null:
		DirAccess.remove_absolute(temporary)

		return {
			"ok": false,
			"errors": ["temp_reopen_failed"],
		}

	var verify_text := verify_file.get_as_text()
	verify_file.close()

	var verify_parsed: Variant = JSON.parse_string(
		verify_text
	)

	if not verify_parsed is Dictionary:
		DirAccess.remove_absolute(temporary)

		return {
			"ok": false,
			"errors": ["temp_verification_failed"],
		}

	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)

	if FileAccess.file_exists(absolute_path):
		var backup_error := DirAccess.rename_absolute(
			absolute_path,
			backup
		)

		if backup_error != OK:
			DirAccess.remove_absolute(temporary)

			return {
				"ok": false,
				"errors": [
					"backup_failed:%d"
					% backup_error
				],
			}

	var promote_error := DirAccess.rename_absolute(
		temporary,
		absolute_path
	)

	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(
				backup,
				absolute_path
			)

		return {
			"ok": false,
			"errors": [
				"promote_failed:%d"
				% promote_error
			],
		}

	# 再验证正式文件。
	var final_data := _read_json(
		BLANK_TEMPLATE_PATH
	)

	if final_data.is_empty():
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(
				absolute_path
			)

			DirAccess.rename_absolute(
				backup,
				absolute_path
			)

		return {
			"ok": false,
			"errors": [
				"final_verification_failed"
			],
		}

	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)

	return {
		"ok": true,
		"deleted_template_id": str(
			found_entry.get(
				"template_id",
				""
			)
		),
		"deleted_map_id": str(
			found_entry.get(
				"map_id",
				""
			)
		),
		"deleted_display_name": str(
			found_entry.get(
				"display_name",
				""
			)
		),
	}
