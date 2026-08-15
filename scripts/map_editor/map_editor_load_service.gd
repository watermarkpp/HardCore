class_name MapEditorLoadService
extends RefCounted


static func load_document(path: String, use_resource_path := true) -> Dictionary:
	var resolved := ProjectSettings.globalize_path(path) if use_resource_path and path.begins_with("res://") else path
	if not FileAccess.file_exists(resolved):
		return {"ok": false, "errors": ["file_missing"]}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["open_failed"]}
	var document := MapEditorTypes.upgrade_document(MapEditorJsonCodec.decode(file.get_as_text()))
	MapEditorContentCatalogService.canonicalize_document_npc_labels(document)
	var errors := MapEditorTypes.validate_document(document)
	return {"ok": errors.is_empty(), "document": document, "errors": errors, "path": path}
