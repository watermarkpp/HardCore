extends Node


const SOURCE_ID := "gmhl_1"
const SOURCE_RUNTIME_MAP_ID := 99450
const SOURCE_DISPLAY_NAME := "光芒回廊"
const SOURCE_DOCUMENT_SHA256 := "cf4bed38eaeceff53ba2006151cef31217e5c3f70b89a65442fa403e62ae3514"
const SPECS := [
	{"map_id": "gmhl_thunder_road", "runtime_map_id": 99451, "display_name": "雷霆之路"},
	{"map_id": "gmhl_bazhe_hall", "runtime_map_id": 99452, "display_name": "霸者大厅"},
	{"map_id": "gmhl_zonghengdao", "runtime_map_id": 99453, "display_name": "纵横道"},
	{"map_id": "gmhl_mohun_dian", "runtime_map_id": 99454, "display_name": "魔魂殿"},
	{"map_id": "gmhl_purgatory_corridor", "runtime_map_id": 99455, "display_name": "炼狱回廊"},
	{"map_id": "gmhl_fengmo_dian", "runtime_map_id": 99456, "display_name": "封魔殿"},
]


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	return JSON.parse_string(file.get_as_text())


func _normalize_ids(value: Variant, source_id: String, target_id: String) -> Variant:
	if value is String:
		return (value as String).replace(target_id, source_id)
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value as Array:
			normalized_array.append(_normalize_ids(item, source_id, target_id))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			var normalized_key: Variant = _normalize_ids(key, source_id, target_id)
			normalized_dictionary[normalized_key] = _normalize_ids(
				(value as Dictionary)[key], source_id, target_id
			)
		return normalized_dictionary
	return value


func _collect_files(path: String, prefix: String, output: Array[String]) -> void:
	var directory := DirAccess.open(path)
	assert(directory != null, path)
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var relative := entry if prefix.is_empty() else prefix.path_join(entry)
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_collect_files(child, relative, output)
		elif not entry.ends_with(".bak"):
			output.append(relative)
		entry = directory.get_next()
	directory.list_dir_end()


func _workspace_files(map_id: String) -> Array[String]:
	var files: Array[String] = []
	_collect_files(
		ProjectSettings.globalize_path("res://map_editor_workspace/%s" % map_id),
		"",
		files,
	)
	files.sort()
	return files


func _workspace_path(map_id: String, relative: String) -> String:
	return ProjectSettings.globalize_path(
		"res://map_editor_workspace/%s/%s" % [map_id, relative]
	)


func _assert_ground_copy(source_id: String, target_id: String) -> int:
	var source_files: Array[String] = []
	var target_files: Array[String] = []
	_collect_files(_workspace_path(source_id, "ground"), "", source_files)
	_collect_files(_workspace_path(target_id, "ground"), "", target_files)
	source_files.sort()
	target_files.sort()
	assert(source_files == target_files, "%s: ground file set differs" % target_id)
	var png_count := 0
	for relative: String in source_files:
		var source_path := _workspace_path(source_id, "ground/%s" % relative)
		var target_path := _workspace_path(target_id, "ground/%s" % relative)
		assert(FileAccess.file_exists(target_path), target_path)
		if relative.ends_with(".png"):
			assert(FileAccess.get_sha256(source_path) == FileAccess.get_sha256(target_path), target_path)
			png_count += 1
			continue
		if relative.ends_with(".json"):
			var source_json: Variant = _read_json(source_path)
			var target_json: Variant = _read_json(target_path)
			assert(
				_normalize_ids(target_json, source_id, target_id) == source_json,
				"%s: ground JSON differs" % target_path,
			)
	return png_count


func _ready() -> void:
	var source_path := "res://map_editor_workspace/%s/%s.editor.json" % [SOURCE_ID, SOURCE_ID]
	assert(FileAccess.file_exists(source_path), source_path)
	var source_loaded := MapEditorLoadService.load_document(source_path, false)
	assert(source_loaded.ok, str(source_loaded.get("errors", [])))
	var source: Dictionary = source_loaded.document
	assert(str(source.map_id) == SOURCE_ID)
	assert(int(source.runtime_map_id) == SOURCE_RUNTIME_MAP_ID)
	assert(str(source.display_name) == SOURCE_DISPLAY_NAME)
	assert(source.design.design_size == [64.0, 48.0])
	var source_layers: Dictionary = source.layers
	var source_object_count := (source_layers.object_base as Array).size()
	var source_collision_count := (source_layers.collision as Array).size()
	assert(source_object_count > 0)
	assert(source_collision_count > 0)
	var source_ground_files := _workspace_files(SOURCE_ID).filter(
		func(relative: String) -> bool: return relative.begins_with("ground/")
	)
	assert(source_ground_files.size() == 19)

	var source_template := MapDesignCatalogService.find_blank_template("blank.%s" % SOURCE_ID)
	assert(str(source_template.map_id) == SOURCE_ID)
	assert(int(source_template.runtime_map_id) == SOURCE_RUNTIME_MAP_ID)
	assert(str(source_template.display_name) == SOURCE_DISPLAY_NAME)
	assert(str(source_template.strategy) == "custom_blank_layout")
	assert(str(source_template.content_policy) == "open_existing_workspace_first")
	assert(str(source_template.workspace_status) == "ready")
	assert(source_template.design_size == [64.0, 48.0])
	assert(source_template.pre_scale_design_size == [64.0, 48.0])
	assert(str(source_template.size_decision_source) == "user_request_2026-08-23")

	var total_ground_png := 0
	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var loaded := MapEditorLoadService.load_document(path, false)
		assert(loaded.ok, "%s: %s" % [map_id, loaded.errors])
		var document: Dictionary = loaded.document
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(document.display_name) == str(spec.display_name))
		assert(document.design.design_size == source.design.design_size)
		assert((document.layers.object_base as Array).size() == source_object_count)
		assert((document.layers.collision as Array).size() == source_collision_count)
		assert((document.layers.map_exit_points as Array).is_empty())
		assert(str(document.editor_meta.clone_source_map_id) == SOURCE_ID)
		assert(str(document.editor_meta.clone_policy) == "full_workspace_clone_without_exit_links_v1")
		assert(str(document.editor_meta.exit_link_status) == "intentionally_unlinked")
		assert(str(document.editor_meta.clone_source_document_sha256) == SOURCE_DOCUMENT_SHA256)
		assert(str(document.ground.workspace_manifest).contains(map_id))
		assert(str(document.ground.workspace_state).contains(map_id))
		assert(not FileAccess.file_exists("res://map_editor_workspace/%s/%s.editor.json.bak" % [map_id, map_id]))
		for layer_name: String in MapEditorTypes.LAYER_NAMES:
			if layer_name == "map_exit_points":
				continue
			assert(
				_normalize_ids(document.layers[layer_name], SOURCE_ID, map_id)
				== source_layers[layer_name],
				"%s layer differs: %s" % [map_id, layer_name],
			)
		var template := MapDesignCatalogService.find_blank_template("blank.%s" % map_id)
		assert(str(template.map_id) == map_id)
		assert(int(template.runtime_map_id) == int(spec.runtime_map_id))
		assert(str(template.display_name) == str(spec.display_name))
		assert(str(template.strategy) == "exact_clone_of_gmhl_1")
		assert(str(template.content_policy) == "open_existing_workspace_first")
		assert(str(template.clone_source_map_id) == SOURCE_ID)
		assert(str(template.workspace_status) == "ready")
		assert(template.design_size == [64.0, 48.0])
		assert(template.pre_scale_design_size == [64.0, 48.0])
		assert(str(template.size_decision_source) == "user_request_2026-08-23")
		total_ground_png += _assert_ground_copy(SOURCE_ID, map_id)

	print(
		"MSE_GUANGMANG_CORRIDOR_MAP_CLONES_PASS maps=%d objects=%d collisions=%d ground_png=%d"
		% [SPECS.size(), source_object_count, source_collision_count, total_ground_png]
	)
	get_tree().quit(0)
