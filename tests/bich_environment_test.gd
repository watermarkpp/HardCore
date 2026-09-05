extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var background: WorldBackground = game.background
	assert(background.uses_bich_art(), "Bich presentation art is not active")
	assert(background.bich_ground_atlas_size() == Vector2i(512, 32), "Bich ground atlas dimensions changed")
	assert(background.bich_prop_atlas_size() == Vector2i(384, 128), "Bich prop atlas dimensions changed")
	assert(background.bich_collision_count() == 0, "Legacy Bich collision must not be mixed with editor runtime collision")
	assert(background.source_collision_shape_count() >= 4, "Editor obstacles and four-sided hard boundary were not built")

	var runtime := MapEditorRuntimeBridge.load_bich()
	var blocked_tiles: Array = runtime.get("collision", {}).get("blocked_tiles", [])
	assert(not blocked_tiles.is_empty(), "Editor runtime has no obstacle occupancy data")
	var blocked_parts := str(blocked_tiles[0]).split(",")
	var blocked_world := MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime, [float(blocked_parts[0]), float(blocked_parts[1])])
	assert(background.is_environment_point_blocked(blocked_world), "Editor obstacle is absent from unified spatial query")
	var outside_world := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime, Vector2(-1.0, 0.0))
	assert(background.is_environment_point_blocked(outside_world), "Black area outside the map is not a hard boundary")

	var required_portals: Array = MapEditorRuntimeBridge.game_content().get("portals", []).map(func(portal: Dictionary) -> Vector2: return portal.screen_position_px)
	for portal_position: Vector2 in required_portals:
		assert(not background.is_environment_point_blocked(portal_position), "Portal is blocked: %s" % portal_position)

	var orc_tomb_f1_id := _runtime_map_id("bich_orc_tomb_f1")
	assert(MapEditorRuntimeBridge.has_runtime_map(orc_tomb_f1_id))
	game.travel_to_map(orc_tomb_f1_id)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == orc_tomb_f1_id, "formal orc tomb map change failed")
	assert(background.editor_runtime_ground_ready(), "formal orc tomb ground is not ready")
	assert(not background.uses_bich_art(), "Bich presentation remained active after map change")
	assert(background.bich_collision_count() == 0, "Bich legacy collision remained after map change")
	print("BICH_ENVIRONMENT_PASS: editor occupancy, portals, hard boundary and map cleanup share one spatial contract")
	get_tree().quit(0)


func _runtime_map_id(map_key: String) -> int:
	for raw_map: Variant in GameData.get_available_maps(true):
		if (
			raw_map is Dictionary
			and str((raw_map as Dictionary).get("formalMapKey", "")) == map_key
		):
			return int((raw_map as Dictionary).get("mapId", -1))
	return -1
