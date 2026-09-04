extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var delta_seconds := 1.0 / float(Engine.physics_ticks_per_second)
	for sample_index: int in range(32):
		var input_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 32.0
		)
		var input_screen_px := GroundUnit.ground_delta_gu_to_screen_delta_px(
			input_ground_gu
		).normalized()
		player.global_position = Vector2(400.0, 240.0)
		player.velocity = Vector2.ZERO
		player.touch_vector = input_screen_px
		var physics_frame_before := Engine.get_physics_frames()
		await get_tree().physics_frame
		await get_tree().process_frame
		var elapsed_physics_frames := maxi(
			1, Engine.get_physics_frames() - physics_frame_before
		)
		var expected_distance_gu := (
			player.move_speed_gu_per_sec
			* delta_seconds
			* float(elapsed_physics_frames)
		)
		var measured_ground_gu := (
			GroundUnit.actual_ground_motion_gu_from_screen_positions(
				Vector2(400.0, 240.0),
				player.global_position
			)
		)
		assert(is_equal_approx(
			measured_ground_gu.length(), expected_distance_gu
		), "sample=%d measured=%f expected=%f screen=%s" % [
			sample_index,
			measured_ground_gu.length(),
			expected_distance_gu,
			str(player.global_position),
		])
	player.free()
	print("PLAYER_CHARACTER_GROUND_MOVEMENT_PASS: 32 directions use equal GU speed with no PX movement alias")
	get_tree().quit(0)
