extends SceneTree

const DOCUMENT_PATH := "res://map_editor_workspace/bich_province/bich_province.editor.json"


func _init() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	document.editor_meta.revision = int(document.editor_meta.get("revision", 2)) + 1
	document.editor_meta.milestone = "BICH-MAP-3"
	document.layers.collision = []
	# Entrance art marks a doorway and must never block its own route.
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("asset_id", "")).begins_with("v1_5.b012_"):
			instance["collision_policy"] = "none"
	# Building collisions cover the rear mass only; the front interaction edge stays reachable.
	for rect: Array in [[100,116,7,4],[101,132,7,3],[147,116,7,4],[119,100,8,4],[119,148,7,3]]:
		assert(MapEditorCollisionService.add_manual_shape(document, "rect", {"rect":rect}).ok)
	# Map boundary strips deliberately leave every authored exit open.
	for rect: Array in [[0,0,124,1],[132,0,124,1],[0,255,124,1],[132,255,124,1],
		[0,0,1,124],[0,132,1,56],[0,196,1,60],[255,0,1,124],[255,132,1,124]]:
		assert(MapEditorCollisionService.add_manual_shape(document, "rect", {"rect":rect}).ok)
	var save := MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	assert(save.ok, str(save.get("errors", [])))
	assert(MapEditorBuildRuntimeService.approve_for_runtime(document).ok)
	var build := MapEditorBuildRuntimeService.build(document, "res://assets/data/runtime/map_editor/bich_province.runtime.json")
	assert(build.ok, str(build.get("errors", [])))
	print("BICH_MAP_3_COLLISION_PASS shapes=%d blocked=%d" % [document.layers.collision.size(), build.runtime.collision.blocked_count])
	quit()
