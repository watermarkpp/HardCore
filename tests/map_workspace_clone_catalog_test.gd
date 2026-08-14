extends Node


const SPECS := [
	{
		"map_id": "connection_passage_1",
		"runtime_map_id": 1544,
		"display_name": "连接通道1",
		"clone_source_map_id": "bich_mine_1",
	},
	{
		"map_id": "connection_passage_2",
		"runtime_map_id": 1545,
		"display_name": "连接通道2",
		"clone_source_map_id": "bich_mine_2",
	},
]


func _ready() -> void:
	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var loaded := MapEditorLoadService.load_document(path, false)
		assert(loaded.ok, str(loaded.get("errors", [])))
		var document: Dictionary = loaded.document
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(document.display_name) == str(spec.display_name))
		assert(document.design.design_size == [50.0, 50.0])
		assert((document.layers.map_exit_points as Array).is_empty())
		assert(str(document.editor_meta.clone_source_map_id) == str(spec.clone_source_map_id))
		assert(str(document.editor_meta.clone_policy) == "full_workspace_clone_without_exit_links_v1")
		assert(str(document.editor_meta.exit_link_status) == "intentionally_unlinked")
		assert(str(document.editor_meta.workspace) == "res://map_editor_workspace/%s" % map_id)
		assert(str(document.ground.workspace_manifest).contains(map_id))
		assert(str(document.ground.workspace_state).contains(map_id))
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id))
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/baked_preview/bake_manifest.json" % map_id))
		assert(not FileAccess.file_exists("res://assets/data/runtime/map_editor/%s.runtime.json" % map_id))
		var raw_file := FileAccess.open(path, FileAccess.READ)
		assert(raw_file != null)
		var raw_text := raw_file.get_as_text()
		assert(not raw_text.contains("official_connection_id"))
		assert(not raw_text.contains("target_map_key"))
		assert(not raw_text.contains("reciprocal_map_key"))

	var passage_1 := MapDesignCatalogService.find_blank_template("blank.connection_passage_1")
	var passage_2 := MapDesignCatalogService.find_blank_template("blank.connection_passage_2")
	var unknown_dark := MapDesignCatalogService.find_blank_template("blank.unknown_dark_palace")
	assert(passage_1.runtime_map_id == 1544 and passage_1.display_name == "连接通道1")
	assert(passage_2.runtime_map_id == 1545 and passage_2.display_name == "连接通道2")
	assert(passage_1.design_size == [50.0, 50.0] and passage_2.design_size == [50.0, 50.0])
	assert(unknown_dark.runtime_map_id == 1571 and unknown_dark.display_name == "未知暗殿")
	assert(unknown_dark.design_size == [40.0, 40.0])
	var unknown_document := MapEditorTypes.new_map_from_blank_template("blank.unknown_dark_palace")
	assert(unknown_document.map_id == "unknown_dark_palace")
	assert(unknown_document.layers.map_exit_points.is_empty())
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		assert((unknown_document.layers[layer_name] as Array).is_empty())

	print("MAP_WORKSPACE_CLONE_CATALOG_PASS")
	get_tree().quit(0)
