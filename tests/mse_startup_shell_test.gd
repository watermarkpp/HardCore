extends Node


func _ready() -> void:
	var editor_scene := load("res://scenes/tools/mafa_scene_editor.tscn") as PackedScene
	assert(editor_scene != null)
	var editor := editor_scene.instantiate() as MapEditorApp
	editor.persist_last_document_path = false
	add_child(editor)

	# _ready must finish with only the shell built. The deferred callback has
	# not started yet, so no document or ground migration may have happened.
	assert(editor.startup_document_load_scheduled)
	assert(not editor.startup_document_load_started)
	assert(not editor.startup_document_load_finished)
	assert(editor.current_document.is_empty())
	assert(editor.status_label != null)

	# Cancel the deferred load before it runs; this keeps the regression test
	# read-only with respect to the repository's real map workspaces while
	# still proving the initial _ready path never opens a document inline.
	editor.load_default_workspace_on_ready = false
	await get_tree().process_frame
	assert(not editor.startup_document_load_started)
	assert(editor.current_document.is_empty())
	editor.queue_free()
	print("MSE_STARTUP_SHELL_PASS")
	get_tree().quit(0)
