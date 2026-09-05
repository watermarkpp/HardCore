extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var forest_id := _runtime_map_id("world_wooma_forest")
	var floor_1_id := _runtime_map_id("wooma_temple_f1")
	var floor_2_id := _runtime_map_id("wooma_temple_f2")
	var boss_hall_id := _runtime_map_id("wooma_temple_boss_hall")
	var required_targets := {
		forest_id: [floor_1_id],
		floor_1_id: [forest_id, floor_2_id],
		floor_2_id: [floor_1_id, boss_hall_id],
		boss_hall_id: [floor_2_id],
	}
	for map_id: int in required_targets:
		assert(MapEditorRuntimeBridge.has_runtime_map(map_id))
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		assert(not runtime.is_empty())
		assert(int(runtime.runtime_map_id) == map_id)
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(bool(content.editor_runtime))
		assert(int(content.runtime_map_id) == map_id)
		assert(
			content.get("portals", []).size()
			== runtime.get("semantics", {}).get("map_exit_points", []).size(),
			"published Wooma portal projection count drifted:%d" % map_id
		)

		for target_map_id: int in required_targets[map_id]:
			assert(
				_has_portal_target(content, target_map_id),
				"required Wooma route missing:%d->%d" % [map_id, target_map_id]
			)
	var hall_bosses: Array = MapEditorRuntimeBridge.game_content_for_map(
		boss_hall_id
	).bosses
	var hall_runtime := MapEditorRuntimeBridge.load_map(boss_hall_id)
	assert(
		hall_bosses.size()
		== hall_runtime.get("semantics", {}).get("boss_spawn", []).size(),
		"published Wooma boss projection count drifted"
	)
	assert(not hall_bosses.is_empty())
	for spawn: Dictionary in hall_bosses:
		var monster := GameData.get_monster_by_id(int(spawn.get("monster_id", -1)))
		assert(not monster.is_empty())
		assert(str(monster.get("classification", "")) in ["elite", "boss"])

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null)
	var game := packed.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.travel_to_map(forest_id)
	await get_tree().process_frame
	assert(game.current_map_id == forest_id)
	assert(
		game.background.editor_runtime_chunk_texture_count() > 0,
		"forest_chunks=%d" % game.background.editor_runtime_chunk_texture_count()
	)

	var forward := _portal_to(floor_1_id)
	assert(forward != null)
	assert(not game.travel_via_portal(forward, false))
	assert(game.current_map_id == forest_id, "fresh activation must be required")
	game._portal_guard_state["travel_in_flight"] = true
	assert(not game.travel_via_portal(forward, true))
	game._portal_guard_state["travel_in_flight"] = false

	for target_map_id: int in [floor_1_id, floor_2_id, boss_hall_id]:
		forward = _portal_to(target_map_id)
		assert(forward != null, "forward portal missing:%d" % target_map_id)
		var target_portal_id := str(forward.portal_data.target_portal_id)
		assert(game.travel_via_portal(forward, true))
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		assert(game.background.editor_runtime_chunk_texture_count() > 0)
		var expected_arrival := MapEditorRuntimeBridge.portal_screen_position_px(
			target_map_id, target_portal_id
		)
		assert(game.player.global_position.is_equal_approx(expected_arrival))
		var immediate_return := _portal_to({
			floor_1_id: forest_id,
			floor_2_id: floor_1_id,
			boss_hall_id: floor_2_id,
		}[target_map_id])
		assert(immediate_return != null)
		assert(not game.travel_via_portal(immediate_return, true))
		assert(game.current_map_id == target_map_id)

	_move_from_arrival(game, boss_hall_id)
	assert(game.travel_via_portal(_portal_to(floor_2_id), true))
	await get_tree().process_frame
	assert(game.current_map_id == floor_2_id)
	assert(game.travel_via_portal(_portal_to(floor_1_id), true))
	await get_tree().process_frame
	assert(game.current_map_id == floor_1_id)
	assert(game.travel_via_portal(_portal_to(forest_id), true))
	await get_tree().process_frame
	assert(game.current_map_id == forest_id)

	print(
		"WOOMA_GAME_RUNTIME_INTEGRATION_PASS "
		+ "route=world_wooma_forest<->f1<->f2<->boss_hall visuals=published "
		+ "guard=fresh+3s_or_1.5tiles single_flight boss=canonical"
	)
	game.queue_free()
	get_tree().quit(0)


func _portal_to(target_map_id: int) -> ZonePortal:
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal and node.target_map_id == target_map_id:
			return node
	return null


func _move_from_arrival(game: Node, map_id: int) -> void:
	var runtime := MapEditorRuntimeBridge.load_map(map_id)
	var arrival_ground_gu := MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(
		runtime, game.player.global_position
	)
	var departed_ground_gu := arrival_ground_gu + Vector2(
		MapPortalTravelGuard.UNLOCK_DISTANCE_GU, 0.0
	)
	game.player.global_position = MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, departed_ground_gu
	)
	game._update_portal_arrival_guard()


func _has_portal_target(content: Dictionary, target_map_id: int) -> bool:
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == target_map_id:
			return true
	return false


func _runtime_map_id(map_key: String) -> int:
	for raw_map: Variant in GameData.get_available_maps(true):
		if (
			raw_map is Dictionary
			and str((raw_map as Dictionary).get("formalMapKey", "")) == map_key
		):
			return int((raw_map as Dictionary).get("mapId", -1))
	return -1
