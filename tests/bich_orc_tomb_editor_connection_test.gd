extends Node

const POLICY_ID := "map_connection_unified_bidirectional_v2"


func _ready() -> void:
	var bich := _load_document("bich_province")
	var wooma := _load_document("wooma_forest")
	var tomb := _load_document("orc_tomb_1")
	var bich_runtime := _load_runtime("bich_province")
	assert(bich.layers.map_exit_points.size() == 3)
	var north := _entry(bich.layers.map_exit_points, "map_exit_000001")
	var east := _entry(bich.layers.map_exit_points, "map_exit_000002")
	var bottom := _entry(bich.layers.map_exit_points, "map_exit_000003")
	_assert_pair_endpoint(
		north, wooma, "bich_wooma_forest_pair_v2", Vector2i(6, 5),
		268, "wooma_forest", "前往沃玛森林"
	)
	_assert_pair_endpoint(
		east, tomb, "bich_orc_tomb_1_pair_v2", Vector2i(72, 5),
		217, "orc_tomb_1", "进入兽人古墓一层"
	)
	assert(_tile(bottom) == Vector2i(7, 74))
	assert(int(bottom.target_map_id) == 406)
	assert(str(bottom.target_map_key) == "bich_mine_1")
	assert(str(bottom.connection_mode) == "bidirectional")
	assert(not bool(bottom.one_way))
	_assert_exit_visual_contains(
		bich, north, "mse.map_exit.deep_forest_set_a_edge_north_far_open"
	)
	_assert_exit_visual_contains(
		bich, east, "mse.map_exit.temple_set_b_corner_east_inner_side_open"
	)
	assert(bich_runtime.semantics.map_exit_points.size() == 3)
	var marker := _read_json(
		"res://assets/data/runtime/map_editor/phase1_map_network.manual_ready.json"
	)
	assert(bool(marker.phase1_map_production_complete))
	assert(int(marker.bidirectional_pair_count) == 9)
	assert(int(marker.one_way_exception_count) == 1)
	print(
		"BICH_WOOMA_ORC_TOMB_EDITOR_CONNECTION_PASS "
		+ "north=6,5<->268 east=72,5<->217 bottom=7,74<->406"
	)
	get_tree().quit(0)


func _assert_pair_endpoint(
	endpoint: Dictionary,
	target: Dictionary,
	pair_id: String,
	expected_tile: Vector2i,
	target_runtime_id: int,
	target_map_key: String,
	display_name: String
) -> void:
	assert(_tile(endpoint) == expected_tile)
	assert(str(endpoint.display_name) == display_name)
	assert(bool(endpoint.target_configured))
	assert(int(endpoint.target_map_id) == target_runtime_id)
	assert(str(endpoint.target_map_key) == target_map_key)
	assert(str(endpoint.connection_policy_id) == POLICY_ID)
	assert(str(endpoint.connection_pair_id) == pair_id)
	assert(str(endpoint.connection_mode) == "bidirectional")
	var reciprocal := _pair_endpoint(target.layers.map_exit_points, pair_id)
	assert(str(endpoint.target_portal_id) == str(reciprocal.semantic_id))
	assert(str(reciprocal.target_portal_id) == str(endpoint.semantic_id))


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


func _pair_endpoint(entries: Array, pair_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("connection_pair_id", "")) == pair_id:
			return entry
	assert(false, "missing_pair:%s" % pair_id)
	return {}


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
	var footprint_raw: Array = instance.footprint_tiles
	var footprint := Vector2i(int(footprint_raw[0]), int(footprint_raw[1]))
	assert(Rect2i(_tile(instance), footprint).has_point(_tile(map_exit)))
	assert(str(instance.collision_policy) == "none")


func _tile(entry: Dictionary) -> Vector2i:
	var raw: Array = entry.get("tile", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1]))


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed
