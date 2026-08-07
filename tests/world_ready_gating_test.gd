extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	# Wait until gameplay input is enabled so the travel gate reaches the
	# projection profile check.
	for _wait in range(600):
		if bool(_game.gameplay_input_is_enabled()):
			break
		await get_tree().process_frame
	# Unknown map: world READY must be gated off by the projection profile.
	_game.current_map_id = 9999
	var rejections_before := int(_game.missing_projection_rejection_count)
	assert(
		not bool(_game._check_world_ready_contract()),
		"world READY must be false on a map without a projection profile"
	)
	assert(
		int(_game.missing_projection_rejection_count) > rejections_before,
		"world READY gating must record the projection rejection"
	)
	# Travel to an unknown map must be refused before any transition.
	var travel_rejections := int(_game.missing_projection_rejection_count)
	var traveled: bool = _game._request_map_travel(9999)
	assert(
		not traveled,
		"map travel to an unknown map must be refused"
	)
	assert(
		int(_game.missing_projection_rejection_count) > travel_rejections,
		"map travel refusal must record the projection rejection"
	)
	assert(
		int(_game.current_map_id) == 9999,
		"refused travel must not switch the current map"
	)
	_game.queue_free()
	await get_tree().process_frame
	print("WORLD_READY_GATING_PASS")
	get_tree().quit(0)
