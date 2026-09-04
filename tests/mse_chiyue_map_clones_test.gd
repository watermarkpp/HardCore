extends Node


# Baselines captured from the corresponding source maps.  The source maps are
# intentionally not staged in this task worktree, so the test also loads them
# when they are available after integration.
const SOURCE_BASELINES := {
	"cyxggc_2": {
		"runtime_map_id": 990280,
		"design_size": [96, 96],
		"object_instances": 207,
		"layer_counts": {"terrain_base": 181, "object_base": 26, "collision": 8, "map_exit_points": 2},
	},
	"cyxg_2": {
		"runtime_map_id": 990330,
		"design_size": [32, 128],
		"object_instances": 334,
		"layer_counts": {"terrain_base": 300, "object_base": 34, "collision": 16, "map_exit_points": 2},
	},
}

const SPECS := [
	{
		"map_id": "chiyue_choice_land",
		"source_id": "cyxggc_2",
		"display_name": "抉择之地",
	},
	{
		"map_id": "chiyue_valley_secret_passage_a",
		"source_id": "cyxg_2",
		"display_name": "山谷密道A",
	},
	{
		"map_id": "chiyue_valley_secret_passage_b",
		"source_id": "cyxg_2",
		"display_name": "山谷密道B",
	},
]


func _ready() -> void:
	for spec: Dictionary in SPECS:
		_assert_clone(spec)

	print("MSE_CHIYUE_MAP_CLONES_PASS maps=3 choice_objects=26 choice_collisions=8 valley_objects=34 valley_collisions=16")
	get_tree().quit(0)


func _assert_clone(spec: Dictionary) -> void:
	var map_id := str(spec.map_id)
	var source_id := str(spec.source_id)
	var workspace := "res://map_editor_workspace/%s" % map_id
	var editor_path := "%s/%s.editor.json" % [workspace, map_id]
	var loaded := MapEditorLoadService.load_document(editor_path, false)
	assert(bool(loaded.get("ok", false)), "%s:%s" % [map_id, loaded.get("errors", [])])
	var document: Dictionary = loaded.document
	var baseline := _baseline_for(source_id)

	assert(str(document.get("map_id", "")) == map_id, "%s map_id mismatch" % map_id)
	assert(str(document.get("display_name", "")) == str(spec.display_name), "%s display_name mismatch" % map_id)
	assert(int(document.get("runtime_map_id", -1)) == int(baseline.runtime_map_id), "%s runtime_map_id mismatch" % map_id)
	var design_size: Array = document.get("design", {}).get("design_size", [])
	assert(design_size == baseline.design_size, "%s design_size mismatch" % map_id)

	var editor_meta: Dictionary = document.get("editor_meta", {})
	assert(str(editor_meta.get("workspace", "")) == workspace, "%s workspace mismatch" % map_id)
	var ground: Dictionary = document.get("ground", {})
	var expected_ground_paths := {
		"chunk_manifest": "res://assets/data/maps/ground/%s.ground_chunks.json" % map_id,
		"paint_manifest": "res://assets/data/maps/ground_paint/%s.ground_paint_ops.json" % map_id,
		"paint_state": "res://assets/data/maps/ground_paint/%s.ground_paint_state.json" % map_id,
		"source_manifest": "res://assets/data/maps/ground_paint/%s.ground_source_manifest.json" % map_id,
		"workspace_manifest": "%s/ground/ground_manifest.json" % workspace,
		"workspace_state": "%s/ground/ground_state.json" % workspace,
	}
	for key: String in expected_ground_paths:
		assert(str(ground.get(key, "")) == str(expected_ground_paths[key]), "%s ground.%s mismatch" % [map_id, key])

	assert(FileAccess.file_exists(editor_path), "%s editor JSON missing" % map_id)
	assert(FileAccess.file_exists(editor_path + ".bak"), "%s editor backup missing" % map_id)
	assert(FileAccess.file_exists("%s/ground/ground_manifest.json" % workspace), "%s ground manifest missing" % map_id)
	assert(FileAccess.file_exists("%s/ground/ground_state.json" % workspace), "%s ground state missing" % map_id)
	assert(FileAccess.file_exists("%s/ground/baked_preview/bake_manifest.json" % workspace), "%s bake manifest missing" % map_id)

	_assert_layer_counts(document, baseline, map_id)
	_assert_no_source_id(workspace, source_id)


func _baseline_for(source_id: String) -> Dictionary:
	var baseline: Dictionary = (SOURCE_BASELINES[source_id] as Dictionary).duplicate(true)
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [source_id, source_id]
	if not FileAccess.file_exists(source_path):
		return baseline
	var loaded := MapEditorLoadService.load_document(source_path, false)
	assert(bool(loaded.get("ok", false)), "%s:%s" % [source_id, loaded.get("errors", [])])
	var source: Dictionary = loaded.document
	baseline["runtime_map_id"] = int(source.get("runtime_map_id", -1))
	baseline["design_size"] = source.get("design", {}).get("design_size", [])
	baseline["object_instances"] = MapEditorInstanceService.all_instances(source).size()
	baseline["layer_counts"] = _layer_counts(source)
	return baseline


func _layer_counts(document: Dictionary) -> Dictionary:
	var counts := {}
	var layers: Dictionary = document.get("layers", {})
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		counts[layer_name] = (layers.get(layer_name, []) as Array).size()
	return counts


func _assert_layer_counts(document: Dictionary, baseline: Dictionary, map_id: String) -> void:
	var expected_counts: Dictionary = baseline.get("layer_counts", {})
	var actual_counts := _layer_counts(document)
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		var expected := int(expected_counts.get(layer_name, 0))
		var actual := int(actual_counts.get(layer_name, 0))
		assert(actual == expected, "%s %s count mismatch: %d != %d" % [map_id, layer_name, actual, expected])
	var expected_instances := int(baseline.get("object_instances", 0))
	var actual_instances := MapEditorInstanceService.all_instances(document).size()
	assert(actual_instances == expected_instances, "%s object_instances mismatch: %d != %d" % [map_id, actual_instances, expected_instances])


func _assert_no_source_id(path: String, source_id: String) -> void:
	var dir := DirAccess.open(path)
	assert(dir != null, "cannot open %s" % path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var is_directory := dir.current_is_dir()
		var child_path := path.path_join(entry)
		if is_directory:
			_assert_no_source_id(child_path, source_id)
		elif entry.ends_with(".json") or entry.ends_with(".json.bak"):
			var file := FileAccess.open(child_path, FileAccess.READ)
			assert(file != null, "cannot read %s" % child_path)
			var text := file.get_as_text()
			file.close()
			assert(not text.contains(source_id), "residual source map_id %s in %s" % [source_id, child_path])
		entry = dir.get_next()
	dir.list_dir_end()
