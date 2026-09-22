extends Node


const REQUIRED_PORTAL_TARGETS := {
	"world_bich_province": [
		"bich_orc_tomb_f1", "bich_mine_f1", "world_wooma_forest",
	],
	"bich_orc_tomb_f1": ["world_bich_province", "bich_orc_tomb_f2"],
	"bich_orc_tomb_f2": ["bich_orc_tomb_f1", "bich_orc_tomb_f3"],
	"bich_orc_tomb_f3": ["bich_orc_tomb_f2"],
	"world_wooma_forest": ["wooma_temple_f1"],
	"wooma_temple_f1": ["world_wooma_forest", "wooma_temple_f2"],
	"wooma_temple_f2": ["wooma_temple_f1", "wooma_temple_boss_hall"],
	"wooma_temple_boss_hall": ["wooma_temple_f2"],
	"bich_mine_f1": ["world_bich_province", "bich_mine_f2"],
	"bich_mine_f2": ["bich_mine_f1", "bich_corpse_king_hall"],
	"bich_corpse_king_hall": [],
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
	assert(game.player.global_position.is_equal_approx(game._bich_home_screen_position_px()))

	await _travel_mine_route_to_corpse_hall(game)
	game.player.defense_min = 0
	game.player.defense_max = 0
	game.player.take_damage(999999)
	await get_tree().create_timer(0.9).timeout
	assert(game.hud.death_revival_panel.visible, "death did not open the revival choice")
	assert(
		game.current_map_id == _runtime_map_id("bich_corpse_king_hall"),
		"death moved before a revival method was selected"
	)
	game.hud.death_revival_panel.town_button.pressed.emit()
	await _wait_for_transition(game)
	assert(game.current_map_id == GameData.service_home_runtime_map_id(false))
	assert(game.player.global_position.is_equal_approx(game._bich_home_screen_position_px()))
	assert(game.player.current_hp == game.player.max_hp and not game.player._dead)

	await _travel_orc_tomb_round_trip(game)
	print(
		"PHASE1_GAME_RUNTIME_INTEGRATION_PASS "
		+ "route=world_bich_province<->mine_f1<->mine_f2->corpse_hall "
		+ "corpse_exit=town_scroll_or_death_only orc=stable_ids "
		+ "wooma=registered guard=portal_arrival_guard_v2"
	)
	game.queue_free()
	get_tree().quit(0)


func _validate_phase1_runtime_bridge() -> void:
	for map_key: String in REQUIRED_PORTAL_TARGETS:
		var map_id: int = _runtime_map_id(map_key)
		assert(MapEditorRuntimeBridge.has_runtime_map(map_id), "runtime map missing:%d" % map_id)
		var runtime: Dictionary = MapEditorRuntimeBridge.load_map(map_id)
		var content: Dictionary = MapEditorRuntimeBridge.game_content_for_map(map_id)
		assert(bool(content.get("editor_runtime", false)), "editor content missing:%d" % map_id)
		var published_exits: Array = runtime.get("semantics", {}).get(
			"map_exit_points", []
		)
		var projected_exit_count: int = content.get("portals", []).size()
		if map_key == "bich_corpse_king_hall":
			assert(projected_exit_count == 0, "corpse hall exposed an interactive exit")
		else:
			assert(
				projected_exit_count == published_exits.size(),
				"published portal projection count drifted:%s" % map_key
			)
		for target_key: String in REQUIRED_PORTAL_TARGETS[map_key]:
			var target_map_id: int = _runtime_map_id(target_key)
			assert(
				_has_portal_target(content, target_map_id),
				"required portal missing:%s->%s" % [map_key, target_key]
			)
	var corpse_map_id: int = _runtime_map_id("bich_corpse_king_hall")
	var corpse_runtime: Dictionary = MapEditorRuntimeBridge.load_map(corpse_map_id)
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
	for target_key: String in [
		"bich_mine_f1", "bich_mine_f2", "bich_corpse_king_hall",
	]:
		var target_map_id: int = _runtime_map_id(target_key)
		var portal: ZonePortal = _portal_to(target_map_id)
		assert(portal != null, "mine route portal missing:%d" % target_map_id)
		var target_portal_id := str(portal.portal_data.get("target_portal_id", ""))
		assert(game.travel_via_portal(portal, true), "mine travel failed:%d" % target_map_id)
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		var expected_arrival: Vector2 = MapEditorRuntimeBridge.portal_screen_position_px(
			target_map_id, target_portal_id
		)
		assert(game.player.global_position.is_equal_approx(expected_arrival))
		assert(
			game.background.editor_runtime_chunk_texture_count()
			== _published_chunk_count(target_map_id)
		)


func _validate_corpse_hall_arrival_only(game: Node) -> void:
	var corpse_map_id: int = _runtime_map_id("bich_corpse_king_hall")
	assert(game.current_map_id == corpse_map_id)
	assert(MapEditorRuntimeBridge.game_content_for_map(corpse_map_id).portals.is_empty())
	var runtime_portals := 0
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal:
			runtime_portals += 1
	assert(runtime_portals == 0, "corpse hall must not spawn an interactive exit")


func _travel_orc_tomb_round_trip(game: Node) -> void:
	game.travel_to_service_home(false, false)
	await get_tree().process_frame
	for target_key: String in [
		"bich_orc_tomb_f1", "bich_orc_tomb_f2", "bich_orc_tomb_f3",
	]:
		var target_map_id: int = _runtime_map_id(target_key)
		var forward: ZonePortal = _portal_to(target_map_id)
		assert(forward != null, "orc forward portal missing:%d" % target_map_id)
		assert(game.travel_via_portal(forward, true))
		await get_tree().process_frame
		assert(game.current_map_id == target_map_id)
		assert(game.background.uses_orc_tomb_art(), "orc client art fallback lost:%d" % target_map_id)
		assert(game.background.editor_runtime_ground_ready(), "orc ground missing:%d" % target_map_id)
		assert(
			game.background.editor_runtime_chunk_texture_count()
			== _published_chunk_count(target_map_id),
			"orc visual chunks not active:%d" % target_map_id
		)
		assert(not game.background.uses_editor_runtime_fallback_ground(), "orc legacy fallback unexpectedly active:%d" % target_map_id)
		assert(
			game.background._editor_runtime_size == _runtime_design_size(target_map_id),
			"orc runtime collision size mismatch:%d" % target_map_id
		)
		assert(not game.background.is_environment_point_blocked(game.player.global_position), "orc arrival blocked:%d" % target_map_id)
	_move_from_arrival(game, _runtime_map_id("bich_orc_tomb_f3"))
	for target_key: String in [
		"bich_orc_tomb_f2", "bich_orc_tomb_f1", "world_bich_province",
	]:
		var target_map_id: int = _runtime_map_id(target_key)
		var reverse: ZonePortal = _portal_to(target_map_id)
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
	var runtime: Dictionary = MapEditorRuntimeBridge.load_map(map_id)
	var arrival_ground_gu: Vector2 = MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(
		runtime, game.player.global_position
	)
	var departed_ground_gu: Vector2 = arrival_ground_gu + Vector2(
		MapPortalTravelGuard.UNLOCK_DISTANCE_GU, 0.0
	)
	game.player.global_position = MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, departed_ground_gu
	)
	game._update_portal_arrival_guard()


func _wait_for_transition(game: Node) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while (
		bool(game._map_transition_in_progress)
		and Time.get_ticks_msec() < deadline_msec
	):
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "death revival transition did not finish")


func _has_portal_target(content: Dictionary, target_map_id: int) -> bool:
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == target_map_id:
			return true
	return false


func _published_chunk_count(runtime_map_id: int) -> int:
	var path: String = MapEditorRuntimeBridge.visual_path(runtime_map_id)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "published visual missing:%d" % runtime_map_id)
	return (parsed as Dictionary).get("chunks", []).size()


func _runtime_design_size(runtime_map_id: int) -> Vector2i:
	var runtime: Dictionary = MapEditorRuntimeBridge.load_map(runtime_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	assert(raw_size.size() == 2)
	return Vector2i(int(raw_size[0]), int(raw_size[1]))


func _runtime_map_id(map_key: String) -> int:
	for raw_map: Variant in GameData.get_available_maps(true):
		if (
			raw_map is Dictionary
			and str((raw_map as Dictionary).get("formalMapKey", "")) == map_key
		):
			return int((raw_map as Dictionary).get("mapId", -1))
	return -1
