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
		player.locomotion_state = player.LOCOMOTION_RUN
		player.locomotion_distance_gu = player.WALK_TO_RUN_DISTANCE_GU
		player.touch_vector = input_screen_px
		await get_tree().physics_frame
		await get_tree().process_frame
		var expected_distance_gu := (
			player.move_speed_gu_per_sec
			* delta_seconds
		)
		# Read one completed physics displacement, not a global frame counter
		# sampled across process/physics signals with different callback order.
		var measured_ground_gu := player.actual_ground_motion_gu
		var unit_motion := measured_ground_gu.normalized().abs()
		assert(
			unit_motion.x < 0.0002 or unit_motion.y < 0.0002
			or absf(unit_motion.x - unit_motion.y) < 0.0002,
			"actual player motion must be Ground eight-way, sample=%d motion=%s" % [sample_index, measured_ground_gu]
		)
		assert(is_equal_approx(
			measured_ground_gu.length(), expected_distance_gu
		), "sample=%d measured=%f expected=%f screen=%s" % [
			sample_index,
			measured_ground_gu.length(),
			expected_distance_gu,
			str(player.global_position),
		])
	await _test_monster_contact_escape(player)
	await _test_oblique_wall(player)
	await _test_far_map_positions(player)
	player.free()
	print("PLAYER_CHARACTER_GROUND_MOVEMENT_PASS: 32 inputs snap actual displacement to eight Ground directions at equal GU speed")
	get_tree().quit(0)


func _test_monster_contact_escape(player: PlayerCharacter) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = WorldSpatialRules.ENEMY_LAYER
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = WorldSpatialRules.actor_footprint_shape_px(16.0)
	body.add_child(shape)
	add_child(body)
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = Vector2(-33.9, 0.0)
	await get_tree().physics_frame
	player.set_touch_vector(Vector2.LEFT)
	for frame in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	assert(player.global_position.x < -35.0, "contact recovery against a monster must not glue the player")
	player.set_touch_vector(Vector2.ZERO)
	body.free()


func _test_oblique_wall(player: PlayerCharacter) -> void:
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = Vector2(400.0, 240.0)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(452.0, 258.0)
	wall.rotation = 0.23
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 150.0)
	collider.shape = rectangle
	wall.add_child(collider)
	add_child(wall)
	await get_tree().physics_frame
	player.set_touch_vector(GroundUnit.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT).normalized())
	var stopped := false
	for frame in 60:
		await get_tree().physics_frame
		await get_tree().process_frame
		var motion := player.actual_ground_motion_gu
		assert(absf(motion.y) < 0.0001 and motion.x >= -0.0001, "oblique wall must not slide player off the selected Ground axis")
		stopped = stopped or motion.is_zero_approx()
	assert(stopped, "wall fixture must actually stop the player")
	player.set_touch_vector(Vector2.ZERO)
	wall.free()


func _test_far_map_positions(player: PlayerCharacter) -> void:
	for origin in [Vector2(24000, 12000), Vector2(48000, 23000), Vector2(-42000, 21000)]:
		for i in 8:
			var direction := Vector2.from_angle(TAU * float(i) / 8.0)
			player.global_position = origin
			player.velocity = Vector2.ZERO
			player.locomotion_state = player.LOCOMOTION_RUN
			player.locomotion_distance_gu = player.WALK_TO_RUN_DISTANCE_GU
			player.touch_vector = GroundUnit.ground_delta_gu_to_screen_delta_px(direction).normalized()
			await get_tree().physics_frame
			await get_tree().process_frame
			var motion := player.actual_ground_motion_gu
			var distance := player.move_speed_gu_per_sec / float(Engine.physics_ticks_per_second)
			# Float32 world-position rounding is below 0.004 screen pixels here.
			assert(absf(motion.length() - distance) < 0.0003,
				"large map movement stopped/changed speed: %s direction=%s motion=%s" % [origin, direction, motion])
			assert(absf(motion.cross(direction)) < 0.0003)
	player.set_touch_vector(Vector2.ZERO)
