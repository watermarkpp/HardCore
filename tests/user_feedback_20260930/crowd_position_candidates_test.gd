extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Query contracts under the simplified policy: no locomotion/attack writes,
## and every local decision must observe same-frame registrations.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn(89, CENTER + Vector2(1.5, 0))
	var peer := _spawn(89, CENTER + Vector2(1, 1))
	for item in [actor, peer]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
		item.target = player
	var before := actor.global_position
	var rng := actor._rng.state
	var timer := actor._attack_timer
	var parent := actor._attack_logic_serial
	var goal := actor._hc_crowd_position_goal(player)
	_check(goal.is_finite(), "large formal body was excluded from crowd candidates")
	_check(actor.global_position == before and actor._rng.state == rng and actor._attack_timer == timer and actor._attack_logic_serial == parent, "candidate selection changed movement or attack state")
	_check(not player.has_meta("hc_crowd_position_candidates"), "simplified crowd must not retain a target-wide peer snapshot")
	var frame := Engine.get_physics_frames()
	var first_goal := goal
	var born := _spawn(89, first_goal)
	born._leave_background_deep_sleep()
	born.set_physics_process(false)
	born.target = player
	actor._hc_crowd_position_goal(player)
	_check(Engine.get_physics_frames() == frame, "registration case accidentally advanced physics")
	_check(not actor._hc_surround_goal.is_finite() or actor._hc_surround_goal != first_goal, "same-frame body did not affect the fresh local contact query")
	for item in [actor, peer, born]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("CROWD_POSITION_CANDIDATES_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
