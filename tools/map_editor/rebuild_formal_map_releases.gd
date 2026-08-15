extends Node

## Rebuild/publish the formal map release set after an identity migration.
## This is deliberately a separate headless process: the migration wrapper
## must not preload integration-owned runtime bridge code before its files are
## atomically rewritten, and every promotion still goes through the existing
## Build/Publish transaction.

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const BuildService := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")
const MapEditorTypes := preload("res://scripts/map_editor/map_editor_types.gd")
const MapEditorContentCatalogService := preload("res://scripts/map_editor/map_editor_content_catalog_service.gd")

var _errors: Array[String] = []


func _ready() -> void:
	var registry := _read_json(REGISTRY_PATH)
	var maps: Variant = registry.get("maps", [])
	if not maps is Array or maps.size() != 11:
		_fail("release_registry_maps_invalid")
		return
	for raw: Variant in maps:
		if not raw is Dictionary:
			_errors.append("registry_map_entry_invalid")
			continue
		var map_entry: Dictionary = raw
		var map_key := str(map_entry.get("map_key", ""))
		var editor_path := "res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
		var raw_document := _read_json(editor_path)
		if raw_document.is_empty():
			_errors.append("editor_document_missing:%s" % editor_path)
			continue
		# Formal workspace documents in the release registry are v4 authoring
		# files.  Use the same deterministic upgrade path as the editor loader
		# before the v5 Build/Publish validator sees them; never rewrite the
		# source document here.
		var document := MapEditorTypes.upgrade_document(raw_document)
		MapEditorContentCatalogService.canonicalize_document_npc_labels(document)
		var candidate := BuildService.build_candidate(document)
		if not bool(candidate.get("ok", false)):
			_errors.append("build_failed:%s:%s" % [map_key, str(candidate.get("errors", []))])
			continue
		var published := BuildService.publish_runtime_release(
			str(candidate.get("candidate_path", "")),
			int(map_entry.get("runtime_map_id", -1)),
			candidate.get("document_binding", {}),
			REGISTRY_PATH,
			map_key
		)
		if not bool(published.get("success", false)):
			_errors.append("publish_failed:%s:%s" % [map_key, str(published)])
	if _errors.is_empty():
		print("MAP_FORMAL_RELEASE_REBUILD_PASS maps=%d" % maps.size())
		get_tree().quit(0)
		return
	_fail(";".join(_errors))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _fail(message: String) -> void:
	push_error("MAP_FORMAL_RELEASE_REBUILD_FAILED %s" % message)
	get_tree().quit(1)
