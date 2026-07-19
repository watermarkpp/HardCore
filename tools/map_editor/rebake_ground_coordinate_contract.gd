extends SceneTree


func _initialize() -> void:
	var document_path := _argument_value("--document=")
	if document_path.is_empty():
		printerr("REBAKE_GROUND_CONTRACT_FAIL missing --document=res://path/to/map.editor.json")
		quit(2)
		return
	var loaded := MapEditorLoadService.load_document(document_path)
	if not loaded.get("ok", false):
		printerr("REBAKE_GROUND_CONTRACT_FAIL load %s" % loaded.get("errors", []))
		quit(3)
		return
	var document: Dictionary = loaded.document
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.get("ok", false):
		printerr("REBAKE_GROUND_CONTRACT_FAIL initialize %s" % initialized.get("errors", []))
		quit(4)
		return
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bake.get("ok", false):
		printerr("REBAKE_GROUND_CONTRACT_FAIL bake %s" % bake.get("errors", []))
		quit(5)
		return
	print(
		"REBAKE_GROUND_CONTRACT_PASS map_id=%s contract=%s chunks=%d"
		% [
			str(document.get("map_id", "")),
			MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID,
			(bake.get("baked_chunks", []) as Array).size(),
		]
	)
	quit(0)


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
