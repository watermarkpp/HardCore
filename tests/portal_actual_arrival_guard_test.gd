extends "res://tests/map_transition_missing_arrival_test.gd"

const Portal := preload("res://scripts/map_editor/map_portal_runtime_service.gd")
const Guard := preload("res://scripts/map_editor/map_portal_travel_guard.gd")

func _run() -> void:
	_configure_isolated_persistence("portal_actual_arrival")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(PlayerState.create_character("门点落点", "战士", "男").is_empty())
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(await _wait_for_world_ready(game, GameData.service_home_runtime_map_id(false)))
	for target_id: int in [916004, 916003, 916005, 916003]:
		var runtime := MapEditorRuntimeBridge.load_map(target_id)
		var endpoint := Portal.endpoint_by_id(runtime, "map_exit_000001" if target_id != 916003 else ("map_exit_000002" if game.current_map_id == 916004 else "map_exit_000003"))
		assert(not endpoint.is_empty())
		var tile := Vector2(float(endpoint.tile[0]), float(endpoint.tile[1]))
		var operation := Callable(game, "_complete_portal_travel").bind(target_id, game._runtime_named_map_data(GameData.get_map_by_id(target_id)), runtime, endpoint.semantic_id, tile)
		assert(game._begin_map_transition(operation, target_id))
		assert(await _wait_for_world_ready(game, target_id), "real destination pipeline must reach READY")
		var ground := MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(runtime, game.player.global_position)
		var expected := MapEditorRuntimeBridge.cell_to_ground_position_gu([tile.x, tile.y])
		assert(ground.is_equal_approx(expected))
		var key: String = game._portal_guard_key(target_id, endpoint.semantic_id)
		var now: int = int(game._portal_guard_state.arrival_msec)
		if Guard.can_activate(game._portal_guard_state, key, now, ground + Vector2.RIGHT, true):
			printerr("PORTAL_ACTUAL_ARRIVAL_GUARD_FAIL 1GU movement incorrectly unlocks the real tile-center arrival")
			game.queue_free()
			get_tree().quit(1)
			return
		assert(not Guard.can_activate(game._portal_guard_state, key, now, ground, true))
		assert(Guard.can_activate(game._portal_guard_state, key, now, ground + Vector2(1.5, 0), true))
		assert(Guard.can_activate(game._portal_guard_state, key, now + 3000, ground, true))
		assert(not Guard.can_activate(game._portal_guard_state, key, now + 3000, ground, false))
		assert(Guard.begin_travel(game._portal_guard_state))
		assert(not Guard.begin_travel(game._portal_guard_state))
		game._portal_guard_state.travel_in_flight = false
	game.queue_free()
	_restore_persistence()
	print("PORTAL_ACTUAL_ARRIVAL_GUARD_PASS real_ready_arrivals=4")
	get_tree().quit(0)
