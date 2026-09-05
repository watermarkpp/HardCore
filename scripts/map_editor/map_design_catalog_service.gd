class_name MapDesignCatalogService
extends RefCounted

const CATALOG_PATH := "res://assets/data/map_design/map_design_catalog.json"
const TEMPLATE_PATH := "res://assets/data/map_design/map_size_templates.json"
const BLANK_TEMPLATE_PATH := "res://assets/data/map_design/map_blank_templates.json"

## Test-only seams. Production continues to read/write the tracked catalog.
static var test_blank_template_path_override := ""
static var test_force_blank_template_write_failure := false


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
	return _read_json(_blank_template_path()).get("templates", [])


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
	file.close()
	return parsed if parsed is Dictionary else {}


static func _blank_template_path() -> String:
	return (
		test_blank_template_path_override
		if not test_blank_template_path_override.strip_edges().is_empty()
		else BLANK_TEMPLATE_PATH
	)


## Read-only phase for a catalog deletion. Both supplied IDs must identify the
## same exact entry; no fuzzy OR matching is allowed.
static func plan_blank_template_deletion(
	template_id: String,
	map_id := ""
) -> Dictionary:
	if template_id.is_empty() and map_id.is_empty():
		return {"ok": false, "errors": ["both_ids_empty"]}

	var data := _read_json(_blank_template_path())
	if data.is_empty() or not data.has("templates") or not data.get("templates") is Array:
		return {"ok": false, "errors": ["file_not_found_or_invalid"]}

	var templates: Array = data.get("templates", [])
	var template_indices: Array = []
	var map_indices: Array = []
	for index: int in range(templates.size()):
		var entry_variant: Variant = templates[index]
		if not entry_variant is Dictionary:
			return {"ok": false, "errors": ["template_entry_invalid:%d" % index]}
		var entry: Dictionary = entry_variant
		if not template_id.is_empty() and str(entry.get("template_id", "")) == template_id:
			template_indices.append(index)
		if not map_id.is_empty() and str(entry.get("map_id", "")) == map_id:
			map_indices.append(index)

	if template_indices.size() > 1:
		return {"ok": false, "errors": ["template_id_ambiguous"]}
	if map_indices.size() > 1:
		return {"ok": false, "errors": ["map_id_ambiguous"]}

	var found_index := -1
	if not template_id.is_empty() and not map_id.is_empty():
		if template_indices.is_empty() and map_indices.is_empty():
			return _blank_template_not_found_plan(data)
		if template_indices.size() != 1 or map_indices.size() != 1 or template_indices[0] != map_indices[0]:
			return {"ok": false, "errors": ["template_identity_mismatch"]}
		found_index = int(template_indices[0])
	elif not template_id.is_empty():
		if template_indices.is_empty():
			return _blank_template_not_found_plan(data)
		found_index = int(template_indices[0])
	else:
		if map_indices.is_empty():
			return _blank_template_not_found_plan(data)
		found_index = int(map_indices[0])

	var before_data := data.duplicate(true)
	var after_data := data.duplicate(true)
	var after_templates: Array = after_data.get("templates", []).duplicate(true)
	var found_entry: Dictionary = after_templates[found_index].duplicate(true)
	after_templates.remove_at(found_index)
	after_data["templates"] = after_templates
	return {
		"ok": true,
		"found": true,
		"template_deleted": false,
		"template_index": found_index,
		"template": found_entry,
		"before_data": before_data,
		"after_data": after_data,
		"errors": [],
	}


static func _blank_template_not_found_plan(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"found": false,
		"template_deleted": false,
		"before_data": data.duplicate(true),
		"after_data": data.duplicate(true),
		"errors": [],
	}


## Commit phase for a previously planned deletion. The catalog snapshot is
## re-read before writing so stale UI selections cannot delete a new entry.
static func commit_blank_template_deletion(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return plan
	if not bool(plan.get("found", false)):
		var absent_before: Variant = plan.get("before_data", {})
		if not absent_before is Dictionary:
			return {"ok": false, "errors": ["template_deletion_plan_invalid"]}
		if _read_json(_blank_template_path()) != absent_before:
			return {"ok": false, "errors": ["template_catalog_changed_since_plan"]}
		return {"ok": true, "template_deleted": false, "errors": []}

	var before_variant: Variant = plan.get("before_data", {})
	var after_variant: Variant = plan.get("after_data", {})
	if not before_variant is Dictionary or not after_variant is Dictionary:
		return {"ok": false, "errors": ["template_deletion_plan_invalid"]}
	var current := _read_json(_blank_template_path())
	if current != before_variant:
		return {"ok": false, "errors": ["template_catalog_changed_since_plan"]}
	var written := _write_blank_templates_atomic(after_variant)
	if not bool(written.get("ok", false)):
		return written
	var entry: Dictionary = plan.get("template", {})
	return {
		"ok": true,
		"template_deleted": true,
		"deleted_template_id": str(entry.get("template_id", "")),
		"deleted_map_id": str(entry.get("map_id", "")),
		"deleted_display_name": str(entry.get("display_name", "")),
		"errors": [],
	}


## Restore phase used when a later workspace/catalog step fails. It refuses to
## overwrite an unrelated concurrent catalog change.
static func restore_blank_template_deletion(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)) or not bool(plan.get("found", false)):
		return {"ok": true, "template_restored": false, "errors": []}
	var before_variant: Variant = plan.get("before_data", {})
	var after_variant: Variant = plan.get("after_data", {})
	if not before_variant is Dictionary or not after_variant is Dictionary:
		return {"ok": false, "errors": ["template_deletion_plan_invalid"]}
	var current := _read_json(_blank_template_path())
	if current == before_variant:
		return {"ok": true, "template_restored": false, "errors": []}
	if current != after_variant:
		return {"ok": false, "errors": ["template_restore_conflict"]}
	var written := _write_blank_templates_atomic(before_variant)
	if not bool(written.get("ok", false)):
		return {"ok": false, "errors": ["template_restore_failed"] + written.get("errors", [])}
	return {"ok": true, "template_restored": true, "errors": []}


static func delete_blank_template(
	template_id: String,
	map_id := ""
) -> Dictionary:
	var plan := plan_blank_template_deletion(template_id, map_id)
	if not bool(plan.get("ok", false)):
		return plan
	if not bool(plan.get("found", false)):
		return {"ok": false, "errors": ["template_not_found"]}
	return commit_blank_template_deletion(plan)


static func _write_blank_templates_atomic(data: Dictionary) -> Dictionary:
	if test_force_blank_template_write_failure:
		return {"ok": false, "errors": ["forced_write_failure"]}
	var absolute_path := ProjectSettings.globalize_path(_blank_template_path())
	var temporary := absolute_path + ".tmp"
	var backup := absolute_path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["open_temp_failed"]}
	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()

	var verify_file := FileAccess.open(temporary, FileAccess.READ)
	if verify_file == null:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["temp_reopen_failed"]}
	var verify_parsed: Variant = JSON.parse_string(verify_file.get_as_text())
	verify_file.close()
	if not verify_parsed is Dictionary or verify_parsed != data:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["temp_verification_failed"]}

	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	var had_original := FileAccess.file_exists(absolute_path)
	if had_original:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["backup_failed:%d" % backup_error]}
	var promote_error := DirAccess.rename_absolute(temporary, absolute_path)
	if promote_error != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		if had_original and FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute_path)
		return {"ok": false, "errors": ["promote_failed:%d" % promote_error]}

	var final_data := _read_json(_blank_template_path())
	if final_data != data:
		var rollback_errors: Array[String] = []
		if FileAccess.file_exists(absolute_path) and DirAccess.remove_absolute(absolute_path) != OK:
			rollback_errors.append("remove_promoted_file_failed")
		if had_original and FileAccess.file_exists(backup):
			var restore_error := DirAccess.rename_absolute(backup, absolute_path)
			if restore_error != OK:
				rollback_errors.append("restore_backup_failed:%d" % restore_error)
		return {"ok": false, "errors": ["final_verification_failed"] + rollback_errors}

	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return {"ok": true, "errors": []}
