extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1复活测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game.player._dead = true
	game._test_force_home_failure = true
	var position_before: Vector2 = game.player.global_position
	var dead_before: bool = game.player._dead

	game._finish_death_revival()
	assert(
		game.player.global_position == position_before,
		"death revival must not move the player on Home failure"
	)
	assert(
		game.player.global_position != Vector2.ZERO,
		"death revival must not write Vector2.ZERO"
	)
	assert(
		game.player._dead == dead_before,
		"death state must be preserved when revival cannot resolve Home"
	)
	assert(
		_captured_error_reason.contains("death_revival"),
		"death revival must report the home-resolution failure"
	)

	game.queue_free()
	print("DEATH_REVIVAL_HOME_FAILURE_TEST_PASS")
	get_tree().quit(0)
