class_name MapEditorSaveService
extends RefCounted

const EDITOR_ROOT := "res://map_editor_workspace/"
const FORMAL_IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const RUNTIME_RELEASE_REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const SpawnIdentityService := preload(
	"res://scripts/map_editor/map_editor_spawn_identity_service.gd"
)
const PathSafety := preload(
	"res://scripts/map_editor/map_editor_path_safety.gd"
)

const RECOVERY_DIRECTORY_NAME := ".recycle_bin"

## Test-only seam. Production keeps the tracked res:// workspace unchanged.
## B01 tests redirect to user:// and never touch real map data.
static var test_workspace_root_override := ""
static var test_formal_identity_path_override := ""
static var test_runtime_release_registry_path_override := ""


static func default_path(map_id: String) -> String:
	return EDITOR_ROOT + map_id + "/" + map_id + ".editor.json"


static func canonical_workspace_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return normalized
	for identity: Dictionary in _formal_identity_rows():
		var legacy_map_id := str(identity.get("legacy_map_id", ""))
		var formal_map_id := str(identity.get("map_id", ""))
		if legacy_map_id.is_empty() or formal_map_id.is_empty():
			continue
		if normalized != default_path(legacy_map_id):
			continue
		var formal_path := default_path(formal_map_id)
		return formal_path if FileAccess.file_exists(formal_path) else normalized
	return normalized


static func has_formal_workspace_for_legacy_map(map_id: String) -> bool:
	if map_id.is_empty():
		return false
	for identity: Dictionary in _formal_identity_rows():
		if str(identity.get("legacy_map_id", "")) != map_id:
			continue
		var formal_map_id := str(identity.get("map_id", ""))
		return (
			not formal_map_id.is_empty()
			and FileAccess.file_exists(default_path(formal_map_id))
		)
	return false


static func save_document(document: Dictionary, path := "") -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	errors.append_array(
		SpawnIdentityService.validate_document(
			document,
			SpawnIdentityService.requires_formal_semantic_ids(document)
		)
	)
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
	var superseded_legacy_ids := _superseded_legacy_map_ids()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if (
			dir.current_is_dir()
			and not static_ids.has(entry)
			and not superseded_legacy_ids.has(entry)
		):
			var editor_path := EDITOR_ROOT + entry + "/" + entry + ".editor.json"
			if FileAccess.file_exists(editor_path):
				var summary := _read_document_summary(editor_path)
				if not summary.is_empty():
					result.append(summary)
		entry = dir.get_next()
	dir.list_dir_end()
	return result


static func _formal_identity_rows() -> Array:
	if not FileAccess.file_exists(FORMAL_IDENTITY_PATH):
		return []
	var file := FileAccess.open(FORMAL_IDENTITY_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return []
	var rows: Variant = parsed.get("maps", [])
	return rows if rows is Array else []


static func _superseded_legacy_map_ids() -> Dictionary:
	var result := {}
	for identity: Dictionary in _formal_identity_rows():
		var legacy_map_id := str(identity.get("legacy_map_id", ""))
		var formal_map_id := str(identity.get("map_id", ""))
		if legacy_map_id.is_empty() or formal_map_id.is_empty():
			continue
		if FileAccess.file_exists(default_path(formal_map_id)):
			result[legacy_map_id] = true
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


static func delete_workspace_map(
	map_id: String,
	expected_document_path := "",
	expected_document := {}
) -> Dictionary:
	## The public operation is intentionally plan-first.  All identity, path,
	## protection and reparse-point checks run before the one mutating rename.
	var planned := plan_workspace_map_deletion(
		map_id,
		expected_document_path,
		expected_document
	)
	if not bool(planned.get("ok", false)):
		return planned
	var plan: Dictionary = planned.get("plan", {})
	var target_absolute := str(plan.get("target_absolute", ""))
	var workspace_root_absolute := str(plan.get("workspace_root_absolute", ""))
	var recovery_root_absolute := str(plan.get("recovery_root_absolute", ""))
	if (
		target_absolute.is_empty()
		or workspace_root_absolute.is_empty()
		or recovery_root_absolute.is_empty()
	):
		return {"ok": false, "errors": ["delete_plan_incomplete"]}

	# Re-run the link/tree probe immediately before creating the recovery slot.
	# This keeps a caller from planning one tree and moving a changed tree.
	var current_root_status := PathSafety.link_status(workspace_root_absolute)
	if not bool(current_root_status.get("ok", false)):
		return {"ok": false, "errors": ["workspace_root_link_probe_failed"]}
	if bool(current_root_status.get("is_link", false)):
		return {"ok": false, "errors": ["workspace_root_linked"]}
	var current_target_status := PathSafety.link_status(target_absolute)
	if not bool(current_target_status.get("ok", false)):
		return {"ok": false, "errors": ["target_link_probe_failed"]}
	if bool(current_target_status.get("is_link", false)):
		return {"ok": false, "errors": ["target_directory_linked"]}
	var fresh_tree := _preflight_tree(target_absolute)
	if not bool(fresh_tree.get("ok", false)):
		return {
			"ok": false,
			"errors": fresh_tree.get("errors", []),
		}

	var recovery_status := PathSafety.link_status(recovery_root_absolute)
	if not bool(recovery_status.get("ok", false)):
		return {"ok": false, "errors": [str(recovery_status.get("error", "recovery_link_probe_failed"))]}
	if bool(recovery_status.get("is_link", false)):
		return {"ok": false, "errors": ["recovery_root_linked"]}
	var had_recovery_root := DirAccess.dir_exists_absolute(recovery_root_absolute)
	var created_recovery_root := false
	if not had_recovery_root:
		var recovery_mkdir := DirAccess.make_dir_absolute(recovery_root_absolute)
		if recovery_mkdir != OK and not DirAccess.dir_exists_absolute(recovery_root_absolute):
			return {"ok": false, "errors": ["recovery_root_create_failed:%d" % recovery_mkdir]}
		created_recovery_root = recovery_mkdir == OK

	var recovery_name := "%s.deleted-%d" % [map_id, Time.get_ticks_usec()]
	var recovery_absolute := recovery_root_absolute.path_join(recovery_name)
	var recovery_target_status := PathSafety.link_status(recovery_absolute)
	if not bool(recovery_target_status.get("ok", false)):
		if created_recovery_root and DirAccess.dir_exists_absolute(recovery_root_absolute):
			DirAccess.remove_absolute(recovery_root_absolute)
		return {"ok": false, "errors": ["recovery_target_link_probe_failed"]}
	if bool(recovery_target_status.get("is_link", false)):
		if created_recovery_root and DirAccess.dir_exists_absolute(recovery_root_absolute):
			DirAccess.remove_absolute(recovery_root_absolute)
		return {"ok": false, "errors": ["recovery_target_linked"]}
	if (
		DirAccess.dir_exists_absolute(recovery_absolute)
		or FileAccess.file_exists(recovery_absolute)
	):
		if created_recovery_root:
			DirAccess.remove_absolute(recovery_root_absolute)
		return {"ok": false, "errors": ["recovery_target_exists"]}

	var move_error := DirAccess.rename_absolute(target_absolute, recovery_absolute)
	if move_error != OK:
		if created_recovery_root and DirAccess.dir_exists_absolute(recovery_root_absolute):
			DirAccess.remove_absolute(recovery_root_absolute)
		return {
			"ok": false,
			"deleted_path": str(plan.get("target_path", "")),
			"failed_files": 0,
			"errors": ["recovery_move_failed:%d" % move_error],
		}

	return {
		"ok": true,
		"map_id": map_id,
		"deleted_path": str(plan.get("target_path", "")),
		"recovery_path": recovery_absolute,
		"target_absolute": target_absolute,
		"workspace_root_absolute": workspace_root_absolute,
		"recovery_root_absolute": recovery_root_absolute,
		"deleted_files": int(fresh_tree.get("file_count", 0)),
		"deleted_directories": int(fresh_tree.get("directory_count", 0)),
		"failed_files": 0,
		"errors": [],
	}


## Validate all identity and protection guards before any catalog/workspace
## mutation. Missing or malformed authority registries fail closed.
static func validate_map_deletion_guard(
	map_id: String,
	expected_metadata := {}
) -> Dictionary:
	var identity_error := PathSafety.map_id_error(map_id)
	if not identity_error.is_empty():
		return {"ok": false, "errors": [identity_error]}
	if not expected_metadata is Dictionary:
		return {"ok": false, "errors": ["expected_document_invalid"]}
	var authority := _formal_identity_status()
	if not bool(authority.get("ok", false)):
		return {
			"ok": false,
			"errors": [str(authority.get("error", "formal_identity_registry_unavailable"))],
		}
	var formal_ids: Dictionary = authority.get("ids", {})
	if bool(formal_ids.get(map_id, false)):
		return {"ok": false, "errors": ["formal_map_protected"]}
	var metadata_reason := _metadata_protection_reason(expected_metadata)
	if not metadata_reason.is_empty():
		return {"ok": false, "errors": [metadata_reason]}
	return {"ok": true, "errors": []}


## Atomic authoring deletion. The workspace is first moved into a quarantine
## directory; catalog commit happens only after that move succeeds. A catalog
## failure restores the exact workspace directory and reports failure.
static func delete_map_authoring_transaction(
	map_id: String,
	template_id := "",
	expected_document_path := "",
	expected_document := {}
) -> Dictionary:
	var guard := validate_map_deletion_guard(map_id, expected_document)
	if not bool(guard.get("ok", false)):
		return guard

	var template_plan := MapDesignCatalogService.plan_blank_template_deletion(
		template_id,
		map_id
	)
	if not bool(template_plan.get("ok", false)):
		return {"ok": false, "errors": template_plan.get("errors", [])}
	if bool(template_plan.get("found", false)):
		var template_entry: Variant = template_plan.get("template", {})
		var template_guard := validate_map_deletion_guard(map_id, template_entry)
		if not bool(template_guard.get("ok", false)):
			return template_guard

	var workspace_plan := plan_workspace_map_deletion(
		map_id,
		expected_document_path,
		expected_document
	)
	var workspace_exists := true
	if not bool(workspace_plan.get("ok", false)):
		var workspace_errors: Array = workspace_plan.get("errors", [])
		if _workspace_absence_is_allowed(workspace_errors):
			workspace_exists = false
		else:
			return {"ok": false, "errors": workspace_errors}
	if not workspace_exists and not bool(template_plan.get("found", false)):
		return {"ok": false, "errors": ["authoring_target_not_found"]}

	var workspace_result: Dictionary = {}
	if workspace_exists:
		workspace_result = delete_workspace_map(
			map_id,
			expected_document_path,
			expected_document
		)
		if not bool(workspace_result.get("ok", false)):
			return {
				"ok": false,
				"errors": workspace_result.get("errors", []),
				"template_deleted": false,
				"workspace_deleted": false,
			}

	var template_result := MapDesignCatalogService.commit_blank_template_deletion(
		template_plan
	)
	if not bool(template_result.get("ok", false)):
		var rollback_errors: Array[String] = []
		var catalog_restored := true
		var catalog_restore := MapDesignCatalogService.restore_blank_template_deletion(
			template_plan
		)
		catalog_restored = bool(catalog_restore.get("ok", false))
		if not catalog_restored:
			rollback_errors.append("catalog_rollback_failed")
			rollback_errors.append_array(
				_to_string_array(catalog_restore.get("errors", []))
			)
		var workspace_restored := true
		if workspace_exists:
			var workspace_restore := restore_workspace_map(workspace_result)
			workspace_restored = bool(workspace_restore.get("ok", false))
			if not workspace_restored:
				rollback_errors.append_array(
					_to_string_array(workspace_restore.get("errors", []))
				)
		var errors: Array[String] = ["template_commit_failed"]
		errors.append_array(_to_string_array(template_result.get("errors", [])))
		if not rollback_errors.is_empty():
			errors.append("workspace_rollback_failed")
			errors.append_array(rollback_errors)
		return {
			"ok": false,
			"errors": errors,
			"template_deleted": false,
			"workspace_deleted": false,
			"workspace_restored": workspace_restored,
			"catalog_restored": catalog_restored,
			"transaction_rolled_back": rollback_errors.is_empty(),
		}

	return {
		"ok": true,
		"map_id": map_id,
		"template_deleted": bool(template_result.get("template_deleted", false)),
		"workspace_deleted": workspace_exists,
		"recovery_path": str(workspace_result.get("recovery_path", "")),
		"deleted_files": int(workspace_result.get("deleted_files", 0)),
		"deleted_directories": int(workspace_result.get("deleted_directories", 0)),
		"errors": [],
	}


static func _workspace_absence_is_allowed(errors: Array) -> bool:
	return (
		errors.size() == 1
		and str(errors[0]) in ["directory_not_found", "workspace_root_not_found"]
	)


## Restore a quarantined workspace only when every path and document identity
## still points to the original direct child. No recursive cleanup is done.
static func restore_workspace_map(delete_result: Dictionary) -> Dictionary:
	if not bool(delete_result.get("ok", false)):
		return {"ok": false, "errors": ["delete_result_invalid"]}
	var map_id := str(delete_result.get("map_id", ""))
	var identity_error := PathSafety.map_id_error(map_id)
	if not identity_error.is_empty():
		return {"ok": false, "errors": [identity_error]}
	var root_absolute := PathSafety.absolute_path(_workspace_root_path())
	if not DirAccess.dir_exists_absolute(root_absolute):
		return {"ok": false, "errors": ["workspace_root_not_found"]}
	var root_link := PathSafety.link_status(root_absolute)
	if not bool(root_link.get("ok", false)) or bool(root_link.get("is_link", false)):
		return {"ok": false, "errors": ["workspace_root_linked"]}
	var target_absolute := root_absolute.path_join(map_id)
	var target_scope := PathSafety.strict_child_path(root_absolute, target_absolute)
	if not bool(target_scope.get("ok", false)):
		return {"ok": false, "errors": ["restore_target_scope_invalid"]}
	if DirAccess.dir_exists_absolute(target_absolute) or FileAccess.file_exists(target_absolute):
		return {"ok": false, "errors": ["restore_target_exists"]}
	var recovery_root := root_absolute.path_join(RECOVERY_DIRECTORY_NAME)
	var recovery_scope := PathSafety.strict_child_path(root_absolute, recovery_root)
	if not bool(recovery_scope.get("ok", false)):
		return {"ok": false, "errors": ["recovery_root_scope_invalid"]}
	var expected_recovery_root := str(delete_result.get("recovery_root_absolute", ""))
	if (
		not expected_recovery_root.is_empty()
		and PathSafety.path_key(expected_recovery_root) != PathSafety.path_key(recovery_root)
	):
		return {"ok": false, "errors": ["recovery_root_mismatch"]}
	var recovery_link := PathSafety.link_status(recovery_root)
	if not bool(recovery_link.get("ok", false)) or bool(recovery_link.get("is_link", false)):
		return {"ok": false, "errors": ["recovery_root_linked"]}
	var recovery_absolute := PathSafety.absolute_path(str(delete_result.get("recovery_path", "")))
	var recovery_target_scope := PathSafety.strict_child_path(recovery_root, recovery_absolute)
	if not bool(recovery_target_scope.get("ok", false)):
		return {"ok": false, "errors": ["recovery_target_scope_invalid"]}
	var recovery_target_link := PathSafety.link_status(recovery_absolute)
	if not bool(recovery_target_link.get("ok", false)) or bool(recovery_target_link.get("is_link", false)):
		return {"ok": false, "errors": ["recovery_target_linked"]}
	if not DirAccess.dir_exists_absolute(recovery_absolute):
		return {"ok": false, "errors": ["recovery_target_not_found"]}
	var tree := _preflight_tree(recovery_absolute)
	if not bool(tree.get("ok", false)):
		return {"ok": false, "errors": tree.get("errors", [])}
	var editor_path := recovery_absolute.path_join(map_id + ".editor.json")
	var loaded := _read_workspace_document(editor_path)
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "errors": ["recovery_document_invalid"]}
	var document: Dictionary = loaded.get("document", {})
	if str(document.get("map_id", "")) != map_id:
		return {"ok": false, "errors": ["recovery_document_map_id_mismatch"]}
	var meta_variant: Variant = document.get("editor_meta", {})
	if not meta_variant is Dictionary:
		return {"ok": false, "errors": ["recovery_document_meta_invalid"]}
	var meta: Dictionary = meta_variant
	if PathSafety.path_key(str(meta.get("workspace", ""))) != PathSafety.path_key(target_absolute):
		return {"ok": false, "errors": ["recovery_document_workspace_mismatch"]}
	if str(meta.get("template_kind", "")) != "custom_empty_map":
		return {"ok": false, "errors": ["recovery_document_not_user_owned"]}
	var move_error := DirAccess.rename_absolute(recovery_absolute, target_absolute)
	if move_error != OK:
		return {"ok": false, "errors": ["workspace_restore_failed:%d" % move_error]}
	return {"ok": true, "errors": []}


static func plan_workspace_map_deletion(
	map_id: String,
	expected_document_path := "",
	expected_document := {}
) -> Dictionary:
	var deletion_guard := validate_map_deletion_guard(map_id)
	if not bool(deletion_guard.get("ok", false)):
		return deletion_guard
	if not expected_document is Dictionary:
		return {"ok": false, "errors": ["expected_document_invalid"]}

	var workspace_root := _workspace_root_path()
	var workspace_root_absolute := PathSafety.absolute_path(workspace_root)
	if not DirAccess.dir_exists_absolute(workspace_root_absolute):
		return {"ok": false, "errors": ["workspace_root_not_found"]}
	var root_link := PathSafety.link_status(workspace_root_absolute)
	if not bool(root_link.get("ok", false)):
		return {"ok": false, "errors": ["workspace_root_link_probe_failed"]}
	if bool(root_link.get("is_link", false)):
		return {"ok": false, "errors": ["workspace_root_linked"]}

	var target_path := workspace_root + map_id + "/"
	var target_absolute := PathSafety.absolute_path(target_path)
	var scope := PathSafety.strict_child_path(
		workspace_root_absolute,
		target_absolute
	)
	if not bool(scope.get("ok", false)):
		return {"ok": false, "errors": [str(scope.get("error", "path_scope_invalid"))]}
	if not DirAccess.dir_exists_absolute(target_absolute):
		return {"ok": false, "errors": ["directory_not_found"]}
	var target_link := PathSafety.link_status(target_absolute)
	if not bool(target_link.get("ok", false)):
		return {"ok": false, "errors": ["target_link_probe_failed"]}
	if bool(target_link.get("is_link", false)):
		return {"ok": false, "errors": ["target_directory_linked"]}

	var editor_path := target_absolute.path_join(map_id + ".editor.json")
	if not FileAccess.file_exists(editor_path):
		return {"ok": false, "errors": ["document_not_found"]}
	var document_link := PathSafety.link_status(editor_path)
	if not bool(document_link.get("ok", false)):
		return {"ok": false, "errors": ["document_link_probe_failed"]}
	if bool(document_link.get("is_link", false)):
		return {"ok": false, "errors": ["document_linked"]}

	if not str(expected_document_path).strip_edges().is_empty():
		if PathSafety.path_key(expected_document_path) != PathSafety.path_key(editor_path):
			return {"ok": false, "errors": ["document_path_mismatch"]}
	if not expected_document.is_empty():
		if str(expected_document.get("map_id", "")) != map_id:
			return {"ok": false, "errors": ["expected_document_identity_mismatch"]}
		var expected_path_in_document := str(expected_document.get("path", "")).strip_edges()
		if (
			not expected_path_in_document.is_empty()
			and PathSafety.path_key(expected_path_in_document) != PathSafety.path_key(editor_path)
		):
			return {"ok": false, "errors": ["expected_document_path_mismatch"]}

	var loaded := _read_workspace_document(editor_path)
	if not bool(loaded.get("ok", false)):
		return loaded
	var document: Dictionary = loaded.get("document", {})
	if not document.has("map_id") or not document.get("map_id") is String:
		return {"ok": false, "errors": ["document_map_id_missing"]}
	if str(document.get("map_id", "")) != map_id:
		return {"ok": false, "errors": ["document_map_id_mismatch"]}
	var meta_variant: Variant = document.get("editor_meta", {})
	if not meta_variant is Dictionary:
		return {"ok": false, "errors": ["document_meta_invalid"]}
	var meta: Dictionary = meta_variant
	var workspace_reference := str(meta.get("workspace", "")).strip_edges()
	if workspace_reference.is_empty():
		return {"ok": false, "errors": ["document_workspace_missing"]}
	if PathSafety.path_key(workspace_reference) != PathSafety.path_key(target_absolute):
		return {"ok": false, "errors": ["document_workspace_mismatch"]}
	var protected_reason := _protected_document_reason(map_id, document, meta)
	if not protected_reason.is_empty():
		return {"ok": false, "errors": [protected_reason]}
	if str(meta.get("template_kind", "")) != "custom_empty_map":
		return {"ok": false, "errors": ["map_not_user_owned"]}

	var tree := _preflight_tree(target_absolute)
	if not bool(tree.get("ok", false)):
		return {"ok": false, "errors": tree.get("errors", [])}
	var recovery_root := target_absolute.get_base_dir().path_join(RECOVERY_DIRECTORY_NAME)
	# The recovery directory is deliberately a sibling of the map child, under
	# the same workspace root, so rename stays on the same filesystem.
	recovery_root = workspace_root_absolute.path_join(RECOVERY_DIRECTORY_NAME)
	var recovery_scope := PathSafety.strict_child_path(
		workspace_root_absolute,
		recovery_root
	)
	if not bool(recovery_scope.get("ok", false)):
		return {"ok": false, "errors": ["recovery_root_scope_invalid"]}
	var recovery_status := PathSafety.link_status(recovery_root)
	if not bool(recovery_status.get("ok", false)):
		return {"ok": false, "errors": ["recovery_link_probe_failed"]}
	if bool(recovery_status.get("is_link", false)):
		return {"ok": false, "errors": ["recovery_root_linked"]}
	return {
		"ok": true,
		"plan": {
			"map_id": map_id,
			"target_path": target_path,
			"target_absolute": target_absolute,
			"document_path": editor_path,
			"workspace_root_absolute": workspace_root_absolute,
			"recovery_root_absolute": recovery_root,
			"file_count": int(tree.get("file_count", 0)),
			"directory_count": int(tree.get("directory_count", 0)),
		},
		"errors": [],
	}


static func _workspace_root_path() -> String:
	var root := (
		test_workspace_root_override
		if not test_workspace_root_override.strip_edges().is_empty()
		else EDITOR_ROOT
	)
	root = root.strip_edges().replace("\\", "/")
	if not root.ends_with("/"):
		root += "/"
	return root


static func _read_workspace_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["document_open_failed"]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["document_json_invalid"]}
	return {"ok": true, "document": parsed}


static func _preflight_tree(dir_path: String, relative_prefix := "") -> Dictionary:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {"ok": false, "errors": ["open_dir_failed"]}
	dir.include_hidden = true
	dir.include_navigational = false
	var begin_error := dir.list_dir_begin()
	if begin_error != OK:
		dir.list_dir_end()
		return {"ok": false, "errors": ["directory_scan_failed:%d" % begin_error]}
	var file_count := 0
	var directory_count := 0
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var entry_path := dir_path.path_join(entry)
			if dir.is_link(entry):
				dir.list_dir_end()
				return {
					"ok": false,
					"errors": ["linked_entry_rejected:%s" % (relative_prefix + entry)],
				}
			if dir.current_is_dir():
				var nested := _preflight_tree(
					entry_path,
					relative_prefix + entry + "/"
				)
				if not bool(nested.get("ok", false)):
					dir.list_dir_end()
					return nested
				directory_count += 1 + int(nested.get("directory_count", 0))
				file_count += int(nested.get("file_count", 0))
			else:
				file_count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return {
		"ok": true,
		"file_count": file_count,
		"directory_count": directory_count,
		"errors": [],
	}


static func _to_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	return result


static func _formal_identity_path() -> String:
	return (
		test_formal_identity_path_override
		if not test_formal_identity_path_override.strip_edges().is_empty()
		else FORMAL_IDENTITY_PATH
	)


static func _runtime_release_registry_path() -> String:
	return (
		test_runtime_release_registry_path_override
		if not test_runtime_release_registry_path_override.strip_edges().is_empty()
		else RUNTIME_RELEASE_REGISTRY_PATH
	)


static func _formal_identity_status() -> Dictionary:
	var identity_path := _formal_identity_path()
	if not FileAccess.file_exists(identity_path):
		return {"ok": false, "error": "formal_identity_registry_unavailable"}
	var identity_file := FileAccess.open(identity_path, FileAccess.READ)
	if identity_file == null:
		return {"ok": false, "error": "formal_identity_registry_unavailable"}
	var identity_parsed: Variant = JSON.parse_string(identity_file.get_as_text())
	identity_file.close()
	if not identity_parsed is Dictionary:
		return {"ok": false, "error": "formal_identity_registry_invalid"}
	var identity_data: Dictionary = identity_parsed
	if str(identity_data.get("contract_id", "")) != "hardcore.formal_map_identity.v1":
		return {"ok": false, "error": "formal_identity_registry_invalid"}
	var identity_rows_variant: Variant = identity_data.get("maps", null)
	if not identity_rows_variant is Array or identity_rows_variant.is_empty():
		return {"ok": false, "error": "formal_identity_registry_invalid"}
	var ids: Dictionary = {}
	for row_variant: Variant in identity_rows_variant:
		if not row_variant is Dictionary:
			return {"ok": false, "error": "formal_identity_registry_invalid"}
		var row: Dictionary = row_variant
		var formal_map_id := str(row.get("map_id", "")).strip_edges()
		var legacy_map_id := str(row.get("legacy_map_id", "")).strip_edges()
		if formal_map_id.is_empty() and legacy_map_id.is_empty():
			return {"ok": false, "error": "formal_identity_registry_invalid"}
		var candidates: Array[String] = [formal_map_id]
		if not legacy_map_id.is_empty() and legacy_map_id != formal_map_id:
			candidates.append(legacy_map_id)
		for candidate: String in candidates:
			if candidate.is_empty():
				continue
			if ids.has(candidate):
				return {"ok": false, "error": "formal_identity_registry_invalid"}
			ids[candidate] = true

	var release_path := _runtime_release_registry_path()
	if not FileAccess.file_exists(release_path):
		return {"ok": false, "error": "runtime_release_registry_unavailable"}
	var release_file := FileAccess.open(release_path, FileAccess.READ)
	if release_file == null:
		return {"ok": false, "error": "runtime_release_registry_unavailable"}
	var release_parsed: Variant = JSON.parse_string(release_file.get_as_text())
	release_file.close()
	if not release_parsed is Dictionary:
		return {"ok": false, "error": "runtime_release_registry_invalid"}
	var release_data: Dictionary = release_parsed
	var release_rows_variant: Variant = release_data.get("maps", null)
	if not release_rows_variant is Array or release_rows_variant.is_empty():
		return {"ok": false, "error": "runtime_release_registry_invalid"}
	var release_ids: Dictionary = {}
	for row_variant: Variant in release_rows_variant:
		if not row_variant is Dictionary:
			return {"ok": false, "error": "runtime_release_registry_invalid"}
		var row: Dictionary = row_variant
		var map_key := str(row.get("map_key", "")).strip_edges()
		if map_key.is_empty() or release_ids.has(map_key):
			return {"ok": false, "error": "runtime_release_registry_invalid"}
		release_ids[map_key] = true
		ids[map_key] = true
	return {"ok": true, "ids": ids, "formal_ids": ids.duplicate(true)}


static func _metadata_protection_reason(
	metadata: Dictionary,
	additional_metadata := {}
) -> String:
	var rows: Array = [metadata]
	var nested_variant: Variant = metadata.get("editor_meta", {})
	if nested_variant is Dictionary:
		rows.append(nested_variant)
	if additional_metadata is Dictionary and not additional_metadata.is_empty():
		rows.append(additional_metadata)
	for value: Variant in rows:
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		for key: String in [
			"frozen", "is_frozen", "protected", "deletion_protected",
			"authoring_locked", "runtime_approved", "formal",
		]:
			if bool(row.get(key, false)):
				return "frozen_or_approved_map_protected"
		for key: String in ["release_state", "lifecycle_state", "authoring_status", "status"]:
			var state := str(row.get(key, "")).strip_edges().to_lower()
			if state in ["formal", "published", "implemented_playable", "frozen", "locked"]:
				return "frozen_or_approved_map_protected"
			if state == "implemented_staging" and bool(row.get("runtime_approved", false)):
				return "frozen_or_approved_map_protected"
			if str(row.get("identity_contract_id", "")) == "hardcore.formal_map_identity.v1":
				return "formal_map_protected"
		for key: String in ["official_runtime_map_id", "official_version_id"]:
			if row.has(key) and not str(row.get(key, "")).strip_edges().is_empty():
				return "formal_map_protected"
	return ""


static func _protected_document_reason(
	map_id: String,
	document: Dictionary,
	meta: Dictionary
) -> String:
	var authority := _formal_identity_status()
	if not bool(authority.get("ok", false)):
		return str(authority.get("error", "formal_identity_registry_unavailable"))
	if bool((authority.get("ids", {}) as Dictionary).get(map_id, false)):
		return "formal_map_protected"
	return _metadata_protection_reason(document, meta)


static func _is_formal_map_id(map_id: String) -> bool:
	var authority := _formal_identity_status()
	if not bool(authority.get("ok", false)):
		# A boolean-only legacy caller must fail closed when authority cannot be
		# established; deletion callers use validate_map_deletion_guard() to
		# surface the concrete registry error.
		return true
	return bool((authority.get("ids", {}) as Dictionary).get(map_id, false))
