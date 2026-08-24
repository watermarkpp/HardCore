extends Node


const SOURCE_ID := "nmsm_1"
const SPECS := [
	{"map_id": "nmsm_1", "runtime_map_id": 990177, "display_name": "牛魔寺庙一层"},
	{"map_id": "nmsm_2", "runtime_map_id": 990185, "display_name": "牛魔寺庙二层"},
	{"map_id": "nmsm_3", "runtime_map_id": 990186, "display_name": "牛魔寺庙三层"},
	{"map_id": "nmsm_4", "runtime_map_id": 990187, "display_name": "牛魔寺庙四层"},
	{"map_id": "nmsm_hall", "runtime_map_id": 990188, "display_name": "牛魔寺庙大厅"},
]


func _ready() -> void:
	var source := _load_document(SOURCE_ID)
	assert((source.layers.collision as Array).size() == 137)
	assert((source.layers.terrain_base as Array).size() == 109)
	assert((source.layers.object_base as Array).size() == 37)
	assert((source.layers.map_exit_points as Array).size() == 2)

	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var document := _load_document(map_id)
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(document.display_name) == str(spec.display_name))
		assert(_normalized_json(document.design, map_id) == JSON.stringify(source.design))
		assert(_normalized_json(document.layers, map_id) == JSON.stringify(source.layers))
		assert((document.layers.terrain_base as Array).size() == 109)
		assert((document.layers.object_base as Array).size() == 37)
		assert(str(document.editor_meta.workspace) == "res://map_editor_workspace/%s" % map_id)
		assert(str(document.ground.workspace_manifest) == "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id)
		assert(str(document.ground.workspace_state) == "res://map_editor_workspace/%s/ground/ground_state.json" % map_id)
		if map_id != SOURCE_ID:
			assert(not JSON.stringify(document).contains(SOURCE_ID))

		var template := MapDesignCatalogService.find_blank_template("blank.%s" % map_id)
		assert(str(template.map_id) == map_id)
		assert(int(template.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(template.display_name) == str(spec.display_name))
		assert(str(template.workspace_status) == "ready")
		if map_id != SOURCE_ID:
			assert(str(template.strategy) == "exact_clone_of_nmsm_1")
			assert(str(template.clone_source_map_id) == SOURCE_ID)

	print("MSE_BULL_TEMPLE_MAP_CLONES_PASS maps=5 collisions=137 terrain=109 objects=37 exits=2")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(
		"res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id],
		false
	)
	assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
	return loaded.document


func _normalized_json(value: Variant, map_id: String) -> String:
	return JSON.stringify(value).replace(map_id, SOURCE_ID)
