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
