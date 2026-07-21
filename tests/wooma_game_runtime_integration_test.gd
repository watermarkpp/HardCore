extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var expected_portals := {268: 2, 313: 2, 314: 2, 315: 1}
	for map_id: int in [268, 313, 314, 315]:
		assert(MapEditorRuntimeBridge.has_runtime_map(map_id))
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		assert(not runtime.is_empty())
		assert(int(runtime.runtime_map_id) == map_id)
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(bool(content.editor_runtime))
		assert(int(content.runtime_map_id) == map_id)

		assert(
			MapEditorRuntimeBridge.game_content_for_map(map_id).portals.size()
			== int(expected_portals[map_id])
		)
	assert(
		MapEditorRuntimeBridge.game_content_for_map(315).bosses.size()
		== 1
	)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null)
	var game := packed.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.travel_to_map(268)
	await get_tree().process_frame
	assert(game.current_map_id == 268)
	assert(
		game.background.editor_runtime_chunk_texture_count() > 0,
		"forest_chunks=%d" % game.background.editor_runtime_chunk_texture_count()
	)

	var forward := _portal_to(313)
	assert(forward != null)
	assert(not game.travel_via_portal(forward, false))
	assert(game.current_map_id == 268, "fresh activation must be required")
	game._portal_guard_state["travel_in_flight"] = true
	assert(not game.travel_via_portal(forward, true))
	game._portal_guard_state["travel_in_flight"] = false

	for target_map_id: int in [313, 314, 315]:
		forward = _portal_to(target_map_id)
		assert(forward != null, "forward portal missing:%d" % target_map_id)
		var target_portal_id := str(forward.portal_data.target_portal_id)
		assert(game.travel_via_portal(forward, true))
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		assert(game.background.editor_runtime_chunk_texture_count() > 0)
		var expected_arrival := MapEditorRuntimeBridge.portal_position(
			target_map_id, target_portal_id
		)
		assert(game.player.global_position.is_equal_approx(expected_arrival))
		var immediate_return := _portal_to({313: 268, 314: 313, 315: 314}[target_map_id])
		assert(immediate_return != null)
		assert(not game.travel_via_portal(immediate_return, true))
		assert(game.current_map_id == target_map_id)

	_move_from_arrival(game, 315)
	assert(game.travel_via_portal(_portal_to(314), true))
	await get_tree().process_frame
	assert(game.current_map_id == 314)
	assert(game.travel_via_portal(_portal_to(313), true))
	await get_tree().process_frame
	assert(game.current_map_id == 313)
	assert(game.travel_via_portal(_portal_to(268), true))
	await get_tree().process_frame
	assert(game.current_map_id == 268)

	print(
		"WOOMA_GAME_RUNTIME_INTEGRATION_PASS "
		+ "route=268<->313<->314<->315 visuals=published "
		+ "portals=1/2/2/1 guard=fresh+3s_or_1.5tiles single_flight boss=1"
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
	var arrival_tile := MapEditorRuntimeBridge.world_to_tile(
		runtime, game.player.global_position
	)
	var departed_tile := arrival_tile + Vector2(
		MapPortalTravelGuard.UNLOCK_DISTANCE_TILES, 0.0
	)
	game.player.global_position = MapEditorRuntimeBridge.tile_to_world(
		runtime, [departed_tile.x, departed_tile.y]
	)
	game._update_portal_arrival_guard()
