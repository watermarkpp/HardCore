extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Query contracts under the simplified policy: no locomotion/attack writes,
## and a populated identity cache must observe same-frame registrations.
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
	var cached: Dictionary = player.get_meta("hc_crowd_position_candidates", {})
	_check(not cached.is_empty() and cached.get("nodes", []).has(peer), "registration case requires a populated cache first")
	var frame := Engine.get_physics_frames()
	var born := _spawn(89, CENTER + Vector2(-1, 1))
	born._leave_background_deep_sleep()
	born.set_physics_process(false)
	born.target = player
	actor._hc_crowd_position_goal(player)
	_check(Engine.get_physics_frames() == frame, "registration case accidentally advanced physics")
	_check(player.get_meta("hc_crowd_position_candidates", {}).get("nodes", []).has(born), "same-frame newly registered crowd body was missing from candidates")
	for item in [actor, peer, born]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("CROWD_POSITION_CANDIDATES_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
