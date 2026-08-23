extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B保留测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	var expected_position := Vector2(100.0, 120.0)
	var expected_ground := Vector2(1.0, 1.0)
	assert(
		PlayerState.save_safe_logout(4, expected_position, expected_ground),
		"prior record must be saved"
	)
	var map_before := PlayerState.saved_map_id
	var position_before := PlayerState.saved_position
	var ground_before := PlayerState.saved_ground_position_gu
	var ground_valid_before := PlayerState.saved_ground_position_gu_valid

	game._test_force_home_failure = true
	var result: Dictionary = game._prepare_safe_logout()
	assert(
		not bool(result.get("success", true)),
		"prepare must fail on invalid Home"
	)

	# Every field of the existing valid record must be preserved field-by-field.
	assert(PlayerState.saved_map_id == map_before, "map_id must stay unchanged")
	assert(
		PlayerState.saved_position == position_before,
		"position must stay unchanged"
	)
	assert(
		PlayerState.saved_position == expected_position
		and PlayerState.saved_position != Vector2.ZERO,
		"position must remain the valid non-zero record"
	)
	assert(
		PlayerState.saved_ground_position_gu == ground_before,
		"ground position must stay unchanged"
	)
	assert(
		PlayerState.saved_ground_position_gu_valid == ground_valid_before,
		"ground validity flag must stay unchanged"
	)

	game.queue_free()
	print("SAFE_LOGOUT_EXISTING_STATE_PRESERVATION_TEST_PASS")
	get_tree().quit(0)
