extends Node


const EXPECTED_PORTALS := {
	4: 3,
	217: 2,
	218: 2,
	221: 1,
	268: 2,
	313: 2,
	314: 2,
	315: 1,
	406: 2,
	408: 2,
	1578: 0,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_validate_phase1_runtime_bridge()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	await _travel_mine_route_to_corpse_hall(game)
	_validate_corpse_hall_arrival_only(game)
	game._on_scroll_used("回城卷")
	await get_tree().process_frame
	assert(game.current_map_id == GameData.service_home_runtime_map_id(false))
	assert(game.player.global_position.is_equal_approx(game._bich_home_world_position()))

	await _travel_mine_route_to_corpse_hall(game)
	game.player.defense_min = 0
	game.player.defense_max = 0
	game.player.take_damage(999999)
	await get_tree().create_timer(0.9).timeout
	assert(game.current_map_id == GameData.service_home_runtime_map_id(false))
	assert(game.player.global_position.is_equal_approx(game._bich_home_world_position()))
	assert(game.player.current_hp == game.player.max_hp and not game.player._dead)

	await _travel_orc_tomb_round_trip(game)
	print(
		"PHASE1_GAME_RUNTIME_INTEGRATION_PASS "
		+ "route=4<->406<->408->1578 corpse_exit=town_scroll_or_death_only "
		+ "orc=4<->217<->218<->221 wooma=registered guard=portal_arrival_guard_v2"
	)
	game.queue_free()
	get_tree().quit(0)


func _validate_phase1_runtime_bridge() -> void:
	for map_id: int in EXPECTED_PORTALS:
		assert(MapEditorRuntimeBridge.has_runtime_map(map_id), "runtime map missing:%d" % map_id)
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(bool(content.get("editor_runtime", false)), "editor content missing:%d" % map_id)
		assert(
			content.get("portals", []).size() == int(EXPECTED_PORTALS[map_id]),
			"portal count mismatch:%d" % map_id
		)
	var corpse_runtime := MapEditorRuntimeBridge.load_map(1578)
	var endpoints: Array = corpse_runtime.get("semantics", {}).get("map_exit_points", [])
	assert(endpoints.size() == 1)
	var arrival: Dictionary = endpoints[0]
	assert(bool(arrival.get("arrival_only", false)))
	assert(not bool(arrival.get("target_configured", true)))
	assert(not bool(arrival.get("trigger_on_enter", true)))
	assert(str(arrival.get("exit_policy", "")) == "town_scroll_or_death_only")


func _travel_mine_route_to_corpse_hall(game: Node) -> void:
	game.travel_to_service_home(false, false)
	await get_tree().process_frame
	for target_map_id: int in [406, 408, 1578]:
		var portal := _portal_to(target_map_id)
		assert(portal != null, "mine route portal missing:%d" % target_map_id)
		var target_portal_id := str(portal.portal_data.get("target_portal_id", ""))
		assert(game.travel_via_portal(portal, true), "mine travel failed:%d" % target_map_id)
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		var expected_arrival := MapEditorRuntimeBridge.portal_position(
			target_map_id, target_portal_id
		)
		assert(game.player.global_position.is_equal_approx(expected_arrival))
		assert(game.background.editor_runtime_chunk_texture_count() == {406: 7, 408: 7, 1578: 2}[target_map_id])


func _validate_corpse_hall_arrival_only(game: Node) -> void:
	assert(game.current_map_id == 1578)
	assert(MapEditorRuntimeBridge.game_content_for_map(1578).portals.is_empty())
	var runtime_portals := 0
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal:
			runtime_portals += 1
	assert(runtime_portals == 0, "corpse hall must not spawn an interactive exit")


func _travel_orc_tomb_round_trip(game: Node) -> void:
	game.travel_to_service_home(false, false)
	await get_tree().process_frame
	for target_map_id: int in [217, 218, 221]:
		var forward := _portal_to(target_map_id)
		assert(forward != null, "orc forward portal missing:%d" % target_map_id)
		assert(game.travel_via_portal(forward, true))
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		assert(game.background.uses_orc_tomb_art(), "orc client art fallback lost:%d" % target_map_id)
		assert(game.background.editor_runtime_ground_ready(), "orc ground missing:%d" % target_map_id)
		assert(game.background.uses_editor_runtime_fallback_ground(), "orc fallback ground not active:%d" % target_map_id)
		assert(game.background._editor_runtime_size == Vector2i(38, 38), "orc runtime collision size mismatch:%d" % target_map_id)
		assert(not game.background.is_environment_point_blocked(game.player.global_position), "orc arrival blocked:%d" % target_map_id)
	_move_from_arrival(game, 221)
	for target_map_id: int in [218, 217, 4]:
		var reverse := _portal_to(target_map_id)
		assert(reverse != null, "orc reverse portal missing:%d" % target_map_id)
		assert(game.travel_via_portal(reverse, true))
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)


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
