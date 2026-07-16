extends SceneTree

const DOCUMENT_PATH := "res://map_editor_workspace/bich_province/bich_province.editor.json"

func _init() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	var baked := MapEditorChunkBakeService.bake_dirty_chunks(document)
	assert(baked.ok, str(baked.get("errors", [])))
	var save := MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	assert(save.ok, str(save.get("errors", [])))
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
	assert(approval.ok, str(approval.get("errors", [])))
	var build := MapEditorBuildRuntimeService.build(document, "res://assets/data/runtime/map_editor/bich_province.runtime.json")
	assert(build.ok, str(build.get("errors", [])))
	print("BICH_USER_RUNTIME_BUILD_PASS instances=%d blocked=%d" % [build.runtime.instances.size(), build.runtime.collision.blocked_count])
	quit()
