extends Node


const SOURCE_ID := "gmd_1"
const SPECS := [
	{"map_id": "gmd_1", "runtime_map_id": 99011, "display_name": "骨魔洞一层"},
	{"map_id": "gmd_2", "runtime_map_id": 99012, "display_name": "骨魔洞二层"},
	{"map_id": "gmd_3", "runtime_map_id": 99013, "display_name": "骨魔洞三层"},
	{"map_id": "gmd_4", "runtime_map_id": 99014, "display_name": "骨魔洞四层"},
	{"map_id": "gmd_5", "runtime_map_id": 99015, "display_name": "骨魔洞五层"},
]


func _ready() -> void:
	var source := _load_document(SOURCE_ID)
	assert((source.layers.collision as Array).size() == 44)
	assert((source.layers.terrain_base as Array).size() == 94)
	assert((source.layers.object_base as Array).size() == 22)

	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var document := _load_document(map_id)
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(document.display_name) == str(spec.display_name))
		assert(document.design == source.design)
		assert(document.layers == source.layers)
		assert(str(document.editor_meta.workspace) == "res://map_editor_workspace/%s" % map_id)
		assert(str(document.ground.workspace_manifest) == "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id)
		assert(str(document.ground.workspace_state) == "res://map_editor_workspace/%s/ground/ground_state.json" % map_id)

		var template := MapDesignCatalogService.find_blank_template("blank.%s" % map_id)
		assert(str(template.map_id) == map_id)
		assert(int(template.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(template.display_name) == str(spec.display_name))
		assert(str(template.workspace_status) == "ready")
		if map_id != SOURCE_ID:
			assert(str(template.strategy) == "exact_clone_of_gmd_1")
			assert(str(template.clone_source_map_id) == SOURCE_ID)

	print("MSE_BONE_CAVE_MAP_CLONES_PASS maps=5 collisions=44 terrain=94 objects=22")
	get_tree().quit(0)


func _load_document(map_id: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(
		"res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id],
		false
	)
	assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
	return loaded.document
