extends Node2D

const Ground := preload("res://scripts/ground_unit_space.gd")
const Directions := preload("res://scripts/monster_neighbor_step_policy.gd")
const DEVICE_POSITION := Vector2(-582.000610351562, -197.884399414062)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var background := WorldBackground.new()
	background.zone_data = {"mapId": 910001}
	add_child(background)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.environment_blocker = background
	await get_tree().physics_frame
	await get_tree().process_frame
	print("DEVICE_ROADBLOCK origin_blocked=", background.is_environment_actor_blocked(DEVICE_POSITION, 18.0))
	player.global_position = DEVICE_POSITION
	player.velocity = Vector2.ZERO
	player.move_and_slide()
	print("DEVICE_ROADBLOCK idle_recovery=", player.global_position - DEVICE_POSITION,
		" collisions=", player.get_slide_collision_count())
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		print("DEVICE_ROADBLOCK contact normal=", hit.get_normal(), " travel=", hit.get_travel(),
			" collider=", hit.get_collider().get_path())
	var escaped := 0
	for neighbor in Directions.allowed_neighbors():
		player.global_position = DEVICE_POSITION
		player.velocity = Vector2.ZERO
		player.set_touch_vector(Ground.ground_delta_gu_to_screen_delta_px(Vector2(neighbor)).normalized())
		await get_tree().physics_frame
		for frame in 12:
			player._physics_process(1.0 / 60.0)
			await get_tree().physics_frame
		var distance := player.global_position.distance_to(DEVICE_POSITION)
		print("DEVICE_ROADBLOCK direction=", neighbor, " distance=", distance, " end=", player.global_position)
		if distance > 5.0 and not background.is_environment_actor_blocked(player.global_position, 18.0):
			escaped += 1
	assert(escaped > 0, "real v95 Bich roadblock position must allow outward movement")
	player.free()
	background.free()
	print("PLAYER_BICH_ROADBLOCK_ESCAPE_PASS")
	get_tree().quit(0)
