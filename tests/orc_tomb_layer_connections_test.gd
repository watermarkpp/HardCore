extends Node

const MAP_IDS := ["orc_tomb_1", "orc_tomb_2", "orc_tomb_3"]
const RUNTIME_IDS := [217, 218, 221]
const DISPLAY_NAMES := ["兽人古墓一层", "兽人古墓二层", "兽人古墓三层"]


func _ready() -> void:
	var documents: Array[Dictionary] = []
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var loaded := MapEditorLoadService.load_document(MapEditorSaveService.default_path(map_id))
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var document: Dictionary = loaded.document
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == RUNTIME_IDS[index])
		assert(str(document.display_name) == DISPLAY_NAMES[index])
		assert(Vector2i(int(document.design.design_size[0]), int(document.design.design_size[1])) == Vector2i(38, 38))
		assert(str(document.editor_meta.workspace) == "res://map_editor_workspace/%s" % map_id)
		assert(str(document.ground.workspace_manifest) == "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id)
		assert(str(document.ground.workspace_state) == "res://map_editor_workspace/%s/ground/ground_state.json" % map_id)
		assert(document.layers.map_entrance_points.size() == 1)
		assert(document.layers.map_exit_points.size() == 1)
		var ground := MapEditorGroundService.initialize(document)
		assert(ground.ok, "%s:%s" % [map_id, ground.get("errors", [])])
		assert(str(ground.manifest.map_id) == map_id)
		assert(str(ground.state.map_id) == map_id)
		documents.append(document)

	_assert_link(documents[0], documents[1])
	_assert_link(documents[1], documents[2])
	assert(str(documents[2].layers.map_exit_points[0].target_map_id).is_empty())
	assert(str(documents[2].layers.map_exit_points[0].target_entrance_id).is_empty())
	print("ORC_TOMB_LAYER_CONNECTIONS_PASS maps=3 links=2 size=38x38")
	get_tree().quit()


func _assert_link(source: Dictionary, target: Dictionary) -> void:
	var map_exit: Dictionary = source.layers.map_exit_points[0]
	var entrance: Dictionary = target.layers.map_entrance_points[0]
	assert(str(map_exit.target_map_id) == str(target.map_id))
	assert(str(map_exit.target_entrance_id) == str(entrance.entrance_id))
