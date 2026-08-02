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
const ROUTE_VERSION_ID := "wooma_temple_user_route_v3_unified_portals"


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
		_assert_runtime_matches_document(document, runtime)
		documents[map_id] = document
		runtimes[map_id] = runtime

	var floor_one: Dictionary = documents["wooma_temple_1"]
	var floor_two: Dictionary = documents["wooma_temple_2"]
	var leader_hall: Dictionary = documents["wooma_temple_3"]
	for document: Dictionary in [floor_one, floor_two, leader_hall]:
		assert(document.design.design_size == [44.0, 44.0])
		assert(
			document.layers.map_entrance_points.size()
			== (1 if str(document.map_id) == "wooma_forest" else 0)
		)
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
		_entry(floor_one.layers.map_exit_points, "map_exit_000002"),
		"wooma_forest_top_to_temple_1_v2"
	)
	_assert_link(
		floor_one.layers.map_exit_points[0],
		Vector2i(18, 2),
		"前往沃玛寺庙二层",
		floor_two,
		_entry(floor_two.layers.map_exit_points, "map_exit_000002"),
		"wooma_temple_1_to_2_v2"
	)
	_assert_link(
		floor_two.layers.map_exit_points[0],
		Vector2i(18, 2),
		"进入沃玛教主大厅",
		leader_hall,
		_entry(leader_hall.layers.map_exit_points, "map_exit_000001"),
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
	for map_summary: Dictionary in marker.maps:
		var map_id := str(map_summary.map_id)
		assert(runtimes.has(map_id))
		var map_index := MAP_IDS.find(map_id)
		assert(map_index >= 0)
		assert(int(map_summary.runtime_map_id) == RUNTIME_IDS[map_index])
		assert(
			_is_valid_sha256(str(map_summary.runtime_build_sha256)),
			"invalid_historical_runtime_sha256:%s" % map_id
		)
	var marker_pair_ids: Array[String] = []
	for marker_pair: Dictionary in marker.connection_pairs:
		marker_pair_ids.append(str(marker_pair.connection_pair_id))
	for expected_pair_id: String in [
		"wooma_forest_temple_1_pair_v1",
		"wooma_temple_1_2_pair_v1",
		"wooma_temple_2_leader_hall_pair_v1",
	]:
		assert(expected_pair_id in marker_pair_ids)
	var marker_connection_ids: Array[String] = []
	for marker_connection: Dictionary in marker.connections:
		marker_connection_ids.append(str(marker_connection.official_connection_id))
	for expected_connection_id: String in [
		"wooma_forest_top_to_temple_1_v2",
		"wooma_temple_1_to_forest_v1",
		"wooma_temple_1_to_2_v2",
		"wooma_temple_2_to_1_v1",
		"wooma_temple_2_to_leader_hall_v2",
		"wooma_leader_hall_to_temple_2_v1",
	]:
		assert(expected_connection_id in marker_connection_ids)
	print(
		"WOOMA_TEMPLE_LAYER_CONNECTIONS_PASS "
		+ "maps=4 pairs=3 endpoints=6 overlap=0 clone_size=44x44 "
		+ "route=268<->313<->314<->315"
	)
	get_tree().quit(0)


func _is_valid_sha256(value: String) -> bool:
	var normalized := value.to_lower()
	if normalized.length() != 64:
		return false
	for character: String in normalized:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _assert_runtime_matches_document(
	document: Dictionary,
	runtime: Dictionary
) -> void:
	assert(
		int(runtime.source.revision)
		== int(document.editor_meta.revision)
	)
	var exported_instances := MapEditorInstanceService.all_instances(
		document
	).filter(
		func(instance: Dictionary) -> bool:
			return bool(instance.get("runtime_export", true))
	)
	assert(runtime.instances.size() == exported_instances.size())
	assert(
		runtime.collision.manual_shapes.size()
		== document.layers.collision.size()
	)
	assert(
		runtime.collision.erased_cells.size()
		== document.layers.collision_erase.size()
	)
	for layer: String in [
		"npc_points",
		"monster_spawn",
		"boss_spawn",
		"door_points",
		"map_entrance_points",
		"map_exit_points",
		"respawn_points",
		"safe_area",
		"light",
		"region_trigger",
	]:
		assert(
			runtime.semantics.get(layer, []).size()
			== document.layers.get(layer, []).size()
		)
	assert(not str(runtime.build_sha256).is_empty())


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
	target_endpoint: Dictionary,
	connection_id: String
) -> void:
	assert(_tile(map_exit) == expected_tile)
	assert(str(map_exit.display_name) == expected_name)
	assert(bool(map_exit.target_configured))
	assert(int(map_exit.target_map_id) == int(target.runtime_map_id))
	assert(str(map_exit.target_map_key) == str(target.map_id))
	assert(
		str(map_exit.target_entrance_id)
		== str(target_endpoint.semantic_id)
	)
	assert(str(map_exit.target_portal_id) == str(target_endpoint.semantic_id))
	assert(_tile_value(map_exit.target_tile) == _tile(target_endpoint))
	assert(str(map_exit.official_connection_id) == connection_id)
	assert(str(map_exit.connection_mode) == "bidirectional")
	assert(not bool(map_exit.one_way))
	assert(bool(map_exit.requires_leave_before_retrigger))
	assert(float(map_exit.return_minimum_seconds) == 3.0)
	assert(float(map_exit.return_unlock_distance_gu) == 1.5)


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
