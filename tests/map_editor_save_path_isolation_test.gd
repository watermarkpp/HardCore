extends Node

## MAP-SAFETY-R1 minimal save-path isolation test.
## Only user:// paths are created or removed; no real map workspace document
## is read, saved, or deleted. The formal workspace is only referenced
## negatively (asserting nothing was written there).


func _ready() -> void:
	# A. default_path must follow the test workspace override.
	MapEditorSaveService.test_workspace_root_override = "user://mse_save_path_isolation/ws/"
	var sandboxed := MapEditorSaveService.default_path("abc")
	assert(sandboxed == "user://mse_save_path_isolation/ws/abc/abc.editor.json", sandboxed)

	# B. An explicit document path whose file name disagrees with the
	# document map_id must fail closed: no save, no redirect, no writes.
	var editor_scene := load("res://scenes/tools/mafa_scene_editor.tscn") as PackedScene
	var editor := editor_scene.instantiate() as MapEditorApp
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	var mismatch_root := "user://mse_save_path_isolation/mismatch"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mismatch_root))
	var mismatch_path := mismatch_root.path_join("zzz_other.editor.json")
	var mismatch_document := MapEditorTypes.new_custom_map(
		"zzz_isolation_none", 990201, "隔离测试B", "outdoor_field", Vector2i(2, 2)
	)
	# Ground contract persistence must also stay inside the sandbox.
	mismatch_document.editor_meta["workspace"] = mismatch_root.path_join("ground_workspace")
	editor._adopt_new_document(mismatch_document, "隔离测试B", mismatch_path)
	assert(editor.current_document.map_id == "zzz_isolation_none")
	assert(editor.current_document_path == mismatch_path)
	var formal_default := "res://map_editor_workspace/zzz_isolation_none/zzz_isolation_none.editor.json"
	assert(not FileAccess.file_exists(formal_default))
	var mismatch_result := editor._save_current_document()
	assert(not bool(mismatch_result.get("ok", false)), str(mismatch_result))
	assert(
		(mismatch_result.get("errors", []) as Array).has("document_path_map_id_mismatch"),
		str(mismatch_result)
	)
	assert(not FileAccess.file_exists(formal_default))

	# C. With the override active, an explicit formal workspace target is
	# forbidden before any file API runs.
	var document := MapEditorTypes.new_map_from_catalog("sandbox_64", "quest_room", 990001, "64格沙盒")
	var forbidden := MapEditorSaveService.save_document(
		document, "res://map_editor_workspace/zzz_isolation_c/zzz_isolation_c.editor.json"
	)
	assert(not bool(forbidden.get("ok", false)), str(forbidden))
	assert(
		(forbidden.get("errors", []) as Array).has("test_formal_workspace_write_forbidden"),
		str(forbidden)
	)
	assert(not FileAccess.file_exists("res://map_editor_workspace/zzz_isolation_c/zzz_isolation_c.editor.json"))

	MapEditorSaveService.test_workspace_root_override = ""
	editor.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mismatch_root))
	print("MAP_EDITOR_SAVE_PATH_ISOLATION_PASS")
	get_tree().quit(0)
