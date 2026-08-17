class_name MapEditorSaveService
extends RefCounted

const EDITOR_ROOT := "res://map_editor_workspace/"


static func default_path(map_id: String) -> String:
	return EDITOR_ROOT + map_id + "/" + map_id + ".editor.json"


static func save_document(document: Dictionary, path := "") -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var target_path := path if not path.is_empty() else default_path(str(document.map_id))
	var absolute := ProjectSettings.globalize_path(target_path)
	var directory := absolute.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		return {"ok": false, "errors": ["mkdir_failed:%d" % mkdir_error]}
	var temporary := absolute + ".tmp"
	var backup := absolute + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["open_temp_failed"]}
	file.store_string(MapEditorJsonCodec.encode(document))
	file.flush()
	file.close()
	var verification := MapEditorLoadService.load_document(temporary, false)
	if not bool(verification.get("ok", false)):
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["temp_verification_failed"] + verification.get("errors", [])}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute):
		var backup_error := DirAccess.rename_absolute(absolute, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["backup_failed:%d" % backup_error]}
	var promote_error := DirAccess.rename_absolute(temporary, absolute)
	if promote_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return {"ok": false, "errors": ["promote_failed:%d" % promote_error]}
	return {"ok": true, "path": target_path, "backup": backup if FileAccess.file_exists(backup) else ""}


static func list_workspace_maps() -> Array:
	var result: Array = []
	var dir := DirAccess.open(EDITOR_ROOT)
	if dir == null:
		return result
	var static_ids := {}
	for template: Dictionary in MapDesignCatalogService.blank_templates():
		static_ids[str(template.get("map_id", ""))] = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not static_ids.has(entry):
			var editor_path := EDITOR_ROOT + entry + "/" + entry + ".editor.json"
			if FileAccess.file_exists(editor_path):
				var summary := _read_document_summary(editor_path)
				if not summary.is_empty():
					result.append(summary)
		entry = dir.get_next()
	dir.list_dir_end()
	return result


static func _read_document_summary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var editor_meta: Variant = parsed.get("editor_meta", {})
	if not editor_meta is Dictionary:
		return {}
	if str(editor_meta.get("template_kind", "")) != "custom_empty_map":
		return {}
	var design: Variant = parsed.get("design", {})
	var design_size: Array = design.get("design_size", [0, 0]) if design is Dictionary else [0, 0]
	if design_size.size() < 2:
		design_size = [0, 0]
	return {
		"map_id": str(parsed.get("map_id", "")),
		"display_name": str(parsed.get("display_name", "")),
		"design_size": design_size,
		"path": path,
	}
