extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	assert(game != null, "Game root failed to instantiate")
	assert(game.player != null, "Player node should exist on game root")
	assert(game.hud != null, "HUD node should exist on game root")

	await get_tree().process_frame
	assert(int(game.hud._last_hp) == int(game.player.current_hp), "HUD did not sync current HP at startup")
	assert(int(game.hud._last_max_hp) == int(game.player.max_hp), "HUD did not sync max HP at startup")
	assert(int(game.hud._last_mp) == int(game.player.current_mp), "HUD did not sync current MP at startup")
	assert(int(game.hud._last_max_mp) == int(game.player.max_mp), "HUD did not sync max MP at startup")

	game.player.current_hp = max(1, game.player.current_hp - 1)
	game.player.resources_changed.emit(game.player.current_hp, game.player.max_hp, game.player.current_mp, game.player.max_mp)
	await get_tree().process_frame
	assert(int(game.hud._last_hp) == int(game.player.current_hp), "HUD did not track resource-changed updates after startup")

	print("PLAYER_INITIAL_RESOURCE_SYNC_PASS")
	game.queue_free()
	get_tree().quit(0)
