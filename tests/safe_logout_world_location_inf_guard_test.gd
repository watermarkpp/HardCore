extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _game: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().physics_frame
	# Unknown map: world-location recording must not write INF.
	_game.current_map_id = 9999
	var saved_before: int = PlayerState.saved_map_id
	_game._record_player_world_location()
	assert(
		PlayerState.saved_map_id == saved_before,
		"world-location must not be recorded for a projection-less map"
	)
	assert(
		not PlayerState.saved_ground_position_gu_valid
		or PlayerState.saved_ground_position_gu.is_finite(),
		"PlayerState must never hold a non-finite ground position"
	)
	# _ground_position_gu_for_map must fail closed (no delta masquerade).
	var ground: Vector2 = _game._ground_position_gu_for_map(
		9999,
		Vector2(0.0, 80.0)
	)
	assert(
		not ground.is_finite(),
		"unsupported map ground conversion must not return a finite delta"
	)
	assert(
		str(_game.projection_rejection_reason)
		== str(GroundUnit.REASON_UNSUPPORTED_MAP_PROJECTION),
		"unsupported map conversion must use the unified reason"
	)
	_game.queue_free()
	await get_tree().process_frame
	print("SAFE_LOGOUT_WORLD_LOCATION_INF_GUARD_PASS")
	get_tree().quit(0)
