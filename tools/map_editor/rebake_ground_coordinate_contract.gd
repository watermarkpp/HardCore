extends SceneTree

const FORMAL_IDENTITY_PATH := (
	"res://assets/data/map_design/map_identity_registry.json"
)


func _initialize() -> void:
	var document_path := _argument_value("--document=")
	if document_path.is_empty() and _has_argument("--all-formal"):
		_rebake_all_formal()
		return
	if document_path.is_empty():
		printerr(
			"REBAKE_GROUND_CONTRACT_FAIL missing "
			+ "--document=res://path/to/map.editor.json or --all-formal"
		)
		quit(2)
		return
	var result := _rebake_document(document_path)
	if not bool(result.get("ok", false)):
		printerr(
			"REBAKE_GROUND_CONTRACT_FAIL %s"
			% str(result.get("errors", []))
		)
		quit(int(result.get("exit_code", 3)))
		return
	print(
		"REBAKE_GROUND_CONTRACT_PASS map_id=%s contract=%s chunks=%d"
		% [
			str(result.get("map_id", "")),
			MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID,
			int(result.get("chunk_count", 0)),
		]
	)
	quit(0)


func _rebake_all_formal() -> void:
	var identity := _read_json(FORMAL_IDENTITY_PATH)
	var maps: Variant = identity.get("maps", [])
	if not maps is Array or maps.is_empty():
		printerr("REBAKE_GROUND_CONTRACT_FAIL formal identity missing")
		quit(6)
		return
	var completed := 0
	var baked_chunks := 0
	for raw_entry: Variant in maps:
		if not raw_entry is Dictionary:
			printerr("REBAKE_GROUND_CONTRACT_FAIL invalid formal identity entry")
			quit(7)
			return
		var map_key := str(raw_entry.get("map_id", ""))
		var document_path := (
			"res://map_editor_workspace/%s/%s.editor.json"
			% [map_key, map_key]
		)
		var result := _rebake_document(document_path)
		if not bool(result.get("ok", false)):
			printerr(
				"REBAKE_GROUND_CONTRACT_FAIL map=%s errors=%s"
				% [map_key, str(result.get("errors", []))]
			)
			quit(int(result.get("exit_code", 8)))
			return
		completed += 1
		baked_chunks += int(result.get("chunk_count", 0))
		print(
			"REBAKE_GROUND_CONTRACT_PROGRESS map=%s completed=%d/%d chunks=%d"
			% [map_key, completed, maps.size(), int(result.get("chunk_count", 0))]
		)
	print(
		"REBAKE_ALL_FORMAL_GROUND_CONTRACT_PASS maps=%d contract=%s chunks=%d"
		% [
			completed,
			MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID,
			baked_chunks,
		]
	)
	quit(0)


func _rebake_document(document_path: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(document_path)
	if not loaded.get("ok", false):
		return {
			"ok": false,
			"exit_code": 3,
			"errors": ["load:%s" % str(loaded.get("errors", []))],
		}
	var document: Dictionary = loaded.document
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.get("ok", false):
		return {
			"ok": false,
			"exit_code": 4,
			"errors": ["initialize:%s" % str(initialized.get("errors", []))],
		}
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bake.get("ok", false):
		return {
			"ok": false,
			"exit_code": 5,
			"errors": ["bake:%s" % str(bake.get("errors", []))],
		}
	return {
		"ok": true,
		"map_id": str(document.get("map_id", "")),
		"chunk_count": (bake.get("baked_chunks", []) as Array).size(),
	}


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _has_argument(expected: String) -> bool:
	return OS.get_cmdline_user_args().has(expected)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
