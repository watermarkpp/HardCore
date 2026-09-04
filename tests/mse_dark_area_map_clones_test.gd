extends Node


const SOURCE_ID := "hadd_2"
const SPECS := [
	{"map_id": "between_life_and_death", "runtime_map_id": 1446, "display_name": "生死之间"},
	{"map_id": "terror_space", "runtime_map_id": 1450, "display_name": "恐怖空间"},
	{"map_id": "thin_sky_passage", "runtime_map_id": 1451, "display_name": "一线天"},
	{"map_id": "death_coffin", "runtime_map_id": 1383, "display_name": "死亡棺材"},
]


func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_ID, SOURCE_ID]
	var source_loaded := MapEditorLoadService.load_document(source_path, false)
	assert(source_loaded.ok, str(source_loaded.get("errors", [])))
	var source: Dictionary = source_loaded.document
	assert(str(source.map_id) == SOURCE_ID)
	assert(str(source.display_name) == "黑暗地带")
	assert(int(source.runtime_map_id) == 990104)
	assert((source.layers.object_base as Array).size() == 25)
	assert((source.layers.collision as Array).size() == 310)
	assert((source.layers.map_exit_points as Array).size() == 2)

	var source_template := MapDesignCatalogService.find_blank_template("blank.hadd_2")
	assert(str(source_template.map_id) == SOURCE_ID)
	assert(str(source_template.workspace_status) == "ready")

	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var loaded := MapEditorLoadService.load_document(path, false)
		assert(loaded.ok, str(loaded.get("errors", [])))
		var document: Dictionary = loaded.document
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(document.display_name) == str(spec.display_name))
		assert(document.design.design_size == source.design.design_size)
		assert((document.layers.object_base as Array).size() == 25)
		assert((document.layers.collision as Array).size() == 310)
		assert((document.layers.map_exit_points as Array).is_empty())
		assert(str(document.editor_meta.clone_source_map_id) == SOURCE_ID)
		assert(str(document.editor_meta.clone_policy) == "full_workspace_clone_without_exit_links_v1")
		assert(str(document.editor_meta.exit_link_status) == "intentionally_unlinked")
		assert(str(document.editor_meta.workspace) == "res://map_editor_workspace/%s" % map_id)
		assert(str(document.ground.workspace_manifest) == "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id)
		assert(str(document.ground.workspace_state) == "res://map_editor_workspace/%s/ground/ground_state.json" % map_id)
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id))
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/baked_preview/bake_manifest.json" % map_id))

		var template := MapDesignCatalogService.find_blank_template("blank.%s" % map_id)
		assert(str(template.map_id) == map_id)
		assert(int(template.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(template.display_name) == str(spec.display_name))
		assert(str(template.strategy) == "exact_clone_of_hadd_2")
		assert(str(template.clone_source_map_id) == SOURCE_ID)
		assert(str(template.workspace_status) == "ready")

		var raw_file := FileAccess.open(path, FileAccess.READ)
		assert(raw_file != null)
		var raw_text := raw_file.get_as_text()
		assert(raw_text.count(SOURCE_ID) == 1)

	print("MSE_DARK_AREA_MAP_CLONES_PASS maps=4 objects=25 collisions=310")
	get_tree().quit(0)
