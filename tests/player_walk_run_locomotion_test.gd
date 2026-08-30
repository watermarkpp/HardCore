extends Node

class AlwaysBlocked extends Node:
	func is_environment_point_blocked(_point: Vector2) -> bool:
		return true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "world bootstrap did not complete")
	var player: PlayerCharacter = game.player
	# Isolate locomotion cadence from authored map collision for this contract.
	player.collision_mask = 0
	player.environment_blocker = null
	player.set_touch_vector(Vector2.RIGHT)
	await get_tree().create_timer(0.30).timeout
	assert(player.locomotion_state == "walk", "fresh movement must begin in walk")
	assert(player.locomotion_distance_gu > 0.0 and player.locomotion_distance_gu < 1.0, "walk progress must use actual sub-GU displacement")
	await get_tree().create_timer(0.45).timeout
	assert(player.locomotion_state == "run", "one actual GU must transition to run")
	assert(is_equal_approx(player.locomotion_snapshot().run_speed_gu_per_sec, 2.0 / 0.6), "run speed contract changed")
	var run_distance := player.locomotion_distance_gu
	player.set_touch_vector(Vector2.DOWN)
	await get_tree().physics_frame
	assert(player.locomotion_state == "run" and player.locomotion_distance_gu >= run_distance, "turning during continuous input must not reset run")
	var blocker := AlwaysBlocked.new()
	add_child(blocker)
	player.environment_blocker = blocker
	var blocked_distance := player.locomotion_distance_gu
	await get_tree().physics_frame
	assert(is_zero_approx(player.actual_ground_motion_gu.length()), "blocked movement must have zero successful Ground GU")
	assert(is_equal_approx(player.locomotion_distance_gu, blocked_distance), "blocked movement must not accumulate run progress")
	player.environment_blocker = null
	player.set_touch_vector(Vector2.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "neutral must reset walk/run progress")
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_attack(), "attack preflight unexpectedly failed")
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "attack must reset locomotion")
	player.set_touch_vector(Vector2.RIGHT)
	player._attack_action_timer = 0.0
	player._movement_visual_lock_timer = 0.0
	await get_tree().physics_frame
	assert(player.locomotion_state == "walk", "movement after an action lock must restart with walk")
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 1}
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	player._attack_timer = 0.0
	assert(player.request_skill("火球术"), "active skill fixture could not submit")
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "active skill must reset locomotion")
	PlayerState.select_profession("战士")
	PlayerState.learned_skills = {"刺杀剑术": 1}
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	assert(player.request_skill("刺杀剑术"), "passive state skill fixture could not submit")
	assert(player.locomotion_state == "run" and is_equal_approx(player.locomotion_distance_gu, 1.2), "passive state skill must not reset locomotion")
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	player._start_struck_reaction()
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "struck reaction must reset locomotion")
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	player._dead = true
	player.complete_death_revival()
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "death/revival must reset locomotion")
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	game._acquire_gameplay_input_lock(game.INPUT_LOCK_MAP_TRANSITION_LOCAL)
	game._release_gameplay_input_lock(game.INPUT_LOCK_MAP_TRANSITION_LOCAL)
	assert(player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu), "map/bootstrap input-lock release must reset locomotion")
	print("PLAYER_WALK_RUN_LOCOMOTION_PASS")
	get_tree().quit(0)
