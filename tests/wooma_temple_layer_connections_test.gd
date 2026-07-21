extends Node

const MAP_IDS := [
	"wooma_forest",
	"wooma_temple_1",
	"wooma_temple_2",
	"wooma_temple_3",
]
const RUNTIME_IDS := [268, 313, 314, 315]
const DISPLAY_NAMES := [
	"沃玛森林",
	"沃玛寺庙一层",
	"沃玛寺庙二层",
	"沃玛教主大厅",
]
const ROUTE_VERSION_ID := "wooma_temple_user_route_v2_bidirectional"


func _ready() -> void:
	var documents := {}
	var runtimes := {}
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var document := _load_document(map_id)
		var runtime := _load_runtime(map_id)
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == RUNTIME_IDS[index])
		assert(str(document.display_name) == DISPLAY_NAMES[index])
		assert(
			str(document.editor_meta.route_version_id)
			== ROUTE_VERSION_ID
		)
		assert(
			str(runtime.source.map_id) == map_id,
			"runtime:%s" % map_id
		)
		documents[map_id] = document
		runtimes[map_id] = runtime

	var floor_one: Dictionary = documents["wooma_temple_1"]
	var floor_two: Dictionary = documents["wooma_temple_2"]
	var leader_hall: Dictionary = documents["wooma_temple_3"]
	for document: Dictionary in [floor_one, floor_two, leader_hall]:
		assert(document.design.design_size == [44.0, 44.0])
		assert(document.layers.map_entrance_points.size() == 1)
		assert(
			str(document.ground.workspace_manifest)
			== (
				"res://map_editor_workspace/%s/ground/"
				+ "ground_manifest.json"
			) % document.map_id
		)
		var ground := MapEditorGroundService.initialize(document)
		assert(
			ground.ok,
			"%s:%s" % [document.map_id, ground.get("errors", [])]
		)
		assert(str(ground.manifest.map_id) == str(document.map_id))
		assert(str(ground.state.map_id) == str(document.map_id))
		if document != floor_one:
			var source_ground := MapEditorGroundService.initialize(
				floor_one
			)
			assert(source_ground.ok)
			assert(
				MapEditorGroundService.tile_overrides(ground.state)
				== MapEditorGroundService.tile_overrides(
					source_ground.state
				)
			)

	_assert_clone_layers(floor_one, floor_two, false)
	_assert_clone_layers(floor_one, leader_hall, true)
	assert(floor_one.layers.map_exit_points.size() == 2)
	assert(floor_two.layers.map_exit_points.size() == 2)
	assert(leader_hall.layers.map_exit_points.size() == 1)

	var forest: Dictionary = documents["wooma_forest"]
	var forest_top := _entry(
		forest.layers.map_exit_points,
		"map_exit_000001"
	)
	_assert_link(
		forest_top,
		Vector2i(51, 4),
		"进入沃玛寺庙一层",
		floor_one,
		"wooma_forest_top_to_temple_1_v2"
	)
	_assert_link(
		floor_one.layers.map_exit_points[0],
		Vector2i(18, 2),
		"前往沃玛寺庙二层",
		floor_two,
		"wooma_temple_1_to_2_v2"
	)
	_assert_link(
		floor_two.layers.map_exit_points[0],
		Vector2i(18, 2),
		"进入沃玛教主大厅",
		leader_hall,
		"wooma_temple_2_to_leader_hall_v2"
	)
	_assert_reciprocal_pair(
		forest_top,
		_entry(floor_one.layers.map_exit_points, "map_exit_000002")
	)
	_assert_reciprocal_pair(
		floor_one.layers.map_exit_points[0],
		_entry(floor_two.layers.map_exit_points, "map_exit_000002")
	)
	_assert_reciprocal_pair(
		floor_two.layers.map_exit_points[0],
		_entry(leader_hall.layers.map_exit_points, "map_exit_000001")
	)
	for semantic_id: String in [
		"map_exit_000002",
		"map_exit_000003",
	]:
		var untouched := _entry(
			forest.layers.map_exit_points,
			semantic_id
		)
		assert(not bool(untouched.target_configured))
		assert(int(untouched.target_map_id) == -1)

	_assert_template(
		"blank.wooma_temple_2",
		"wooma_temple_2",
		314,
		"沃玛寺庙二层"
	)
	_assert_template(
		"blank.wooma_temple_3",
		"wooma_temple_3",
		315,
		"沃玛教主大厅"
	)
	_assert_editor_template_menu(
		[
			{
				"template_id": "blank.wooma_temple_2",
				"map_id": "wooma_temple_2",
				"display_name": "沃玛寺庙二层",
			},
			{
				"template_id": "blank.wooma_temple_3",
				"map_id": "wooma_temple_3",
				"display_name": "沃玛教主大厅",
			},
		]
	)
	var marker := _read_json(
		"res://assets/data/runtime/map_editor/"
		+ "wooma_temple_route.manual_ready.json"
	)
	assert(str(marker.route_version_id) == ROUTE_VERSION_ID)
	assert(marker.maps.size() == 4)
	assert(marker.connection_pairs.size() == 3)
	assert(marker.connections.size() == 6)
	print(
		"WOOMA_TEMPLE_LAYER_CONNECTIONS_PASS "
		+ "maps=4 pairs=3 directed_links=6 clone_size=44x44 "
		+ "route=268<->313<->314<->315"
	)
	get_tree().quit(0)


func _assert_clone_layers(
	source: Dictionary,
	clone: Dictionary,
	final_hall: bool
) -> void:
	# The user edits every copied floor independently after creation.  Preserve
	# clone provenance, but never require live map content to remain identical.
	assert(source.design.design_size == clone.design.design_size)
	assert(
		str(clone.editor_meta.clone_source_map_id)
		== "wooma_temple_1"
	)
	assert(
		str(clone.editor_meta.clone_size_policy)
		== "exact_source_copy_44x44"
	)
	assert(final_hall == (str(clone.map_id) == "wooma_temple_3"))


func _assert_link(
	map_exit: Dictionary,
	expected_tile: Vector2i,
	expected_name: String,
	target: Dictionary,
	connection_id: String
) -> void:
	var entrance: Dictionary = target.layers.map_entrance_points[0]
	assert(_tile(map_exit) == expected_tile)
	assert(str(map_exit.display_name) == expected_name)
	assert(bool(map_exit.target_configured))
	assert(int(map_exit.target_map_id) == int(target.runtime_map_id))
	assert(str(map_exit.target_map_key) == str(target.map_id))
	assert(
		str(map_exit.target_entrance_id)
		== str(entrance.entrance_id)
	)
	assert(_tile_value(map_exit.target_tile) == _tile(entrance))
	assert(str(map_exit.official_connection_id) == connection_id)
	assert(str(map_exit.connection_mode) == "bidirectional")
	assert(not bool(map_exit.one_way))
	assert(bool(map_exit.requires_leave_before_retrigger))


func _assert_reciprocal_pair(
	forward_exit: Dictionary,
	reverse_exit: Dictionary
) -> void:
	assert(str(forward_exit.connection_direction) == "forward")
	assert(str(reverse_exit.connection_direction) == "reverse")
	assert(
		str(forward_exit.connection_pair_id)
		== str(reverse_exit.connection_pair_id)
	)
	assert(
		str(forward_exit.reciprocal_exit_id)
		== str(reverse_exit.semantic_id)
	)
	assert(
		str(reverse_exit.reciprocal_exit_id)
		== str(forward_exit.semantic_id)
	)


func _assert_template(
	template_id: String,
	map_id: String,
	runtime_map_id: int,
	display_name: String
) -> void:
	var template := MapDesignCatalogService.find_blank_template(
		template_id
	)
	assert(not template.is_empty())
	assert(str(template.map_id) == map_id)
	assert(int(template.runtime_map_id) == runtime_map_id)
	assert(str(template.display_name) == display_name)
	assert(template.design_size == [44.0, 44.0])
	assert(
		str(template.template_kind)
		== "existing_map_or_empty_template"
	)
	assert(str(template.workspace_status) == "ready")
	assert(
		str(template.clone_source_map_id)
		== "wooma_temple_1"
	)


func _assert_editor_template_menu(expected: Array) -> void:
	var editor_scene := load(
		"res://scenes/tools/mafa_scene_editor.tscn"
	) as PackedScene
	var editor := editor_scene.instantiate() as MapEditorApp
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	for entry: Dictionary in expected:
		editor._refresh_map_template_options(str(entry.template_id))
		assert(
			str(
				editor.map_template_option.get_item_metadata(
					editor.map_template_option.selected
				)
			) == str(entry.template_id)
		)
		var menu_text := editor.map_template_option.get_item_text(
			editor.map_template_option.selected
		)
		assert(str(entry.display_name) in menu_text)
		assert("44×44" in menu_text)
		assert(editor._open_template_by_id(str(entry.template_id)))
		assert(str(editor.current_document.map_id) == str(entry.map_id))
		assert(editor.current_document.design.design_size == [44.0, 44.0])
	editor.queue_free()


func _load_document(map_id: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(
		MapEditorSaveService.default_path(map_id)
	)
	assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
	return loaded.document


func _load_runtime(map_id: String) -> Dictionary:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		MapEditorBuildRuntimeService.default_runtime_path(map_id)
	)
	assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
	return loaded.runtime


func _entry(entries: Array, semantic_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("semantic_id", "")) == semantic_id:
			return entry
	assert(false, "missing_semantic:%s" % semantic_id)
	return {}


func _tile(entry: Dictionary) -> Vector2i:
	return _tile_value(entry.get("tile", [0, 0]))


func _tile_value(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
