extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	assert(game != null, "Game root scene failed to instantiate")
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var home_map_id := GameData.service_runtime_map_id(0)
	var home_position: Vector2 = game._bich_home_screen_position_px()
	assert(game.current_map_id == home_map_id, "Bootstrap must load service home runtime map")
	assert(game.player != null, "Bootstrap must instantiate a player")
	assert(game.hud != null, "Bootstrap must instantiate HUD")
	assert(game.background != null, "Bootstrap must instantiate world background")
	assert(not game._map_transition_in_progress, "Bootstrap should not keep map transition open")
	assert(game.hud.loading_transition_overlay != null and not game.hud.loading_transition_overlay.visible, "Loading transition should finish during bootstrap")
	assert(game.background.editor_runtime_ground_ready(), "Bootstrap should activate runtime ground data")
	assert(game.background.editor_runtime_chunk_texture_count() > 0, "Runtime chunk content should be present after bootstrap")
	assert(game.background.environment_source_map_code() == "0", "Bootstrap should resolve Bich source map")
	assert(game.player.global_position.is_equal_approx(home_position), "Bootstrap should spawn player at service-home anchor")

	game.player.set_touch_vector(Vector2.RIGHT)
	await get_tree().process_frame
	assert(game.player.movement_input_active, "Player input should become active after bootstrap")
	game.player.set_touch_vector(Vector2.ZERO)
	await get_tree().process_frame
	game.queue_free()

	print("INITIAL_WORLD_BOOTSTRAP_PASS: service home map active, transition closed, runtime ground ready, and player input working")
	get_tree().quit(0)
