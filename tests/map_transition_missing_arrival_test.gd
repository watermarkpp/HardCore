extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1落点测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game._test_force_home_failure = true
	var map_before: int = game.current_map_id
	var position_before: Vector2 = game.player.global_position

	# The production arrival gate must reject a map-4 target without a Home.
	var arrival: Dictionary = game._pipeline_arrival_position(4)
	assert(
		not bool(arrival.get("valid", true)),
		"pipeline arrival must be invalid when Home cannot resolve"
	)

	# The production pipeline gate must fail the transition and record the
	# diagnostic instead of entering READY.
	_captured_error_reason = ""
	var pipeline_ok: bool = await game._run_world_build_pipeline(4, "q0b1_test")
	assert(
		not pipeline_ok,
		"world build pipeline must fail without a target arrival"
	)
	assert(
		game._world_bootstrap_coordinator.stage
		== WorldBootstrapCoordinator.Stage.FAILED,
		"coordinator must reach FAILED"
	)
	var pipeline_diagnostic: Dictionary = game.get_meta(
		"home_resolution_failure_diagnostic", {}
	)
	assert(
		str(pipeline_diagnostic.get("action", "")) == "world_pipeline_arrival",
		"pipeline arrival failure must be recorded"
	)

	# Sync travel to map 4 with no Home must not switch maps.
	_captured_error_reason = ""
	var travelled: bool = game._travel_to_map_immediate(4)
	assert(not travelled, "map-4 travel must fail without a Home")
	assert(game.current_map_id == map_before, "map must stay unchanged")
	assert(
		game.player.global_position == position_before,
		"player must not be placed from the current position"
	)
	assert(
		not game._map_transition_in_progress,
		"no transition may be in progress"
	)

	game.queue_free()
	print("MAP_TRANSITION_MISSING_ARRIVAL_TEST_PASS")
	get_tree().quit(0)
