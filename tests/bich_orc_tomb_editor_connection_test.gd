extends Node


func _ready() -> void:
	var bich := _load_document("bich_province")
	var wooma := _load_document("wooma_forest")
	var tomb := _load_document("orc_tomb_1")
	var bich_runtime := _load_runtime("bich_province")
	var wooma_runtime := _load_runtime("wooma_forest")

	assert(bich.layers.map_exit_points.size() == 2)
	var north_exit := _entry(
		bich.layers.map_exit_points,
		"map_exit_000001"
	)
	var east_exit := _entry(
		bich.layers.map_exit_points,
		"map_exit_000002"
	)
	var wooma_entrance: Dictionary = wooma.layers.map_entrance_points[0]
	var tomb_entrance: Dictionary = tomb.layers.map_entrance_points[0]

	_assert_exit(
		north_exit,
		Vector2i(6, 5),
		"前往沃玛森林",
		268,
		"wooma_forest",
		wooma_entrance,
		"bich_north_to_wooma_forest_v1"
	)
	_assert_exit(
		east_exit,
		Vector2i(72, 5),
		"进入兽人古墓一层",
		217,
		"orc_tomb_1",
		tomb_entrance,
		"bich_east_to_orc_tomb_1_v2"
	)
	assert(
		not str(north_exit.display_name).begins_with("半兽")
		and not str(east_exit.display_name).begins_with("半兽")
	)
	assert(not north_exit.has("radius_tiles"))
	assert(not east_exit.has("radius_tiles"))

	_assert_exit_visual_contains(
		bich,
		north_exit,
		"mse.map_exit.deep_forest_set_a_edge_north_far_open"
	)
	_assert_exit_visual_contains(
		bich,
		east_exit,
		"mse.map_exit.temple_set_b_corner_east_inner_side_open"
	)

	var runtime_north := _entry(
		bich_runtime.semantics.map_exit_points,
		"map_exit_000001"
	)
	var runtime_east := _entry(
		bich_runtime.semantics.map_exit_points,
		"map_exit_000002"
	)
	assert(int(runtime_north.target_map_id) == 268)
	assert(int(runtime_east.target_map_id) == 217)
	assert(
		str(runtime_north.target_entrance_id)
		== str(wooma_entrance.entrance_id)
	)
	assert(
		str(runtime_east.target_entrance_id)
		== str(tomb_entrance.entrance_id)
	)
	assert(wooma_runtime.semantics.map_entrance_points.size() == 1)
	assert(
		str(
			wooma_runtime.semantics.map_entrance_points[0].entrance_id
		) == str(wooma_entrance.entrance_id)
	)

	var game_portals: Array = MapEditorRuntimeBridge.game_content().get(
		"portals",
		[]
	)
	assert(game_portals.size() == 2)
	var portals_by_target := {}
	for portal: Dictionary in game_portals:
		portals_by_target[int(portal.target_map_id)] = portal
	assert(portals_by_target.has(217))
	assert(portals_by_target.has(268))
	assert(
		(portals_by_target[268].position as Vector2).is_equal_approx(
			MapEditorRuntimeBridge.tile_to_world(
				bich_runtime,
				north_exit.tile
			)
		)
	)
	assert(
		(portals_by_target[217].position as Vector2).is_equal_approx(
			MapEditorRuntimeBridge.tile_to_world(
				bich_runtime,
				east_exit.tile
			)
		)
	)

	var bich_marker := _read_json(
		"res://assets/data/runtime/map_editor/"
		+ "bich_province.manual_ready.json"
	)
	assert(
		str(bich_marker.connection_version_id)
		== "bich_wooma_connection_v1"
	)
	assert(int(bich_marker.content.map_exits) == 2)
	assert(
		int(bich_marker.content.map_exits_pending_target_configuration)
		== 0
	)
	assert(bich_marker.content.north_exit_tile == [6.0, 5.0])
	assert(bich_marker.content.east_exit_tile == [72.0, 5.0])

	var wooma_marker := _read_json(
		"res://assets/data/runtime/map_editor/"
		+ "wooma_forest.manual_ready.json"
	)
	assert(str(wooma_marker.status) == "user_confirmed_official")
	assert(
		str(wooma_marker.content.entrance_id)
		== str(wooma_entrance.entrance_id)
	)
	assert(wooma_marker.content.entrance_tile == [3.0, 52.0])
	assert(int(wooma_marker.content.incoming_from.runtime_map_id) == 4)
	assert(
		str(wooma_marker.content.incoming_from.exit_id)
		== str(north_exit.semantic_id)
	)
	print(
		"BICH_WOOMA_ORC_TOMB_EDITOR_CONNECTION_PASS "
		+ "north=6,5->268:3,52 east=72,5->217:3,35"
	)
	get_tree().quit(0)


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


func _assert_exit(
	map_exit: Dictionary,
	expected_tile: Vector2i,
	expected_name: String,
	target_runtime_id: int,
	target_map_key: String,
	target_entrance: Dictionary,
	connection_id: String
) -> void:
	assert(_tile(map_exit) == expected_tile)
	assert(str(map_exit.display_name) == expected_name)
	assert(bool(map_exit.target_configured))
	assert(int(map_exit.target_map_id) == target_runtime_id)
	assert(str(map_exit.target_map_key) == target_map_key)
	assert(
		str(map_exit.target_entrance_id)
		== str(target_entrance.entrance_id)
	)
	assert(_tile_value(map_exit.target_tile) == _tile(target_entrance))
	assert(str(map_exit.official_connection_id) == connection_id)


func _assert_exit_visual_contains(
	document: Dictionary,
	map_exit: Dictionary,
	asset_id: String
) -> void:
	var matching := MapEditorInstanceService.all_instances(document).filter(
		func(instance: Dictionary) -> bool:
			return str(instance.get("asset_id", "")) == asset_id
	)
	assert(matching.size() == 1, asset_id)
	var instance: Dictionary = matching[0]
	var origin := _tile(instance)
	var footprint_raw: Array = instance.footprint_tiles
	var footprint := Vector2i(
		int(footprint_raw[0]),
		int(footprint_raw[1])
	)
	assert(Rect2i(origin, footprint).has_point(_tile(map_exit)))
	assert(str(instance.collision_policy) == "none")
	assert(
		not MapEditorCollisionService.build_walkability(
			document
		).blocked_tiles.has(
			"%d,%d" % [_tile(map_exit).x, _tile(map_exit).y]
		)
	)


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
