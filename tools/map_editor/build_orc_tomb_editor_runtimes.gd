extends SceneTree

const MAP_IDS := ["orc_tomb_2", "orc_tomb_3"]


func _init() -> void:
	for map_id: String in MAP_IDS:
		var path := MapEditorSaveService.default_path(map_id)
		var loaded := MapEditorLoadService.load_document(path)
		if not bool(loaded.get("ok", false)):
			_fail("%s_load_failed:%s" % [map_id, loaded.get("errors", [])])
			return
		var document: Dictionary = loaded.document
		var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
		if not bool(bake.get("ok", false)):
			_fail("%s_bake_failed:%s" % [map_id, bake.get("errors", [])])
			return
		var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
		if not bool(approval.get("ok", false)):
			_fail("%s_approval_failed:%s" % [map_id, approval.get("errors", [])])
			return
		var saved := MapEditorSaveService.save_document(document, path)
		if not bool(saved.get("ok", false)):
			_fail("%s_save_failed:%s" % [map_id, saved.get("errors", [])])
			return
		var built := MapEditorBuildRuntimeService.build(document)
		if not bool(built.get("ok", false)):
			_fail("%s_build_failed:%s" % [map_id, built.get("errors", [])])
			return
		print(
			"ORC_TOMB_RUNTIME_BUILT map=%s runtime_id=%d instances=%d exits=%d"
			% [
				map_id,
				int(document.get("runtime_map_id", 0)),
				built.runtime.get("instances", []).size(),
				built.runtime.get("semantics", {}).get("map_exit_points", []).size(),
			]
		)
	print("ORC_TOMB_EDITOR_RUNTIMES_PASS maps=%s" % ",".join(MAP_IDS))
	quit(0)


func _fail(message: String) -> void:
	push_error("ORC_TOMB_EDITOR_RUNTIMES_FAILED %s" % message)
	quit(1)
