extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn(238, CENTER + Vector2(1.2, -1.2))
	var ranged := _spawn(150, CENTER + Vector2(-1, 0))
	for item in [actor, ranged]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
		item.target = player
	_check(actor._source176_ordinary_melee(), "238 fixture must use ordinary melee")
	_check(not ranged._source176_ordinary_melee(), "150 fixture must retain ranged delivery")
	var expected := Positions.station(actor, CENTER, actor._target_combat_radius_gu(player), 7)
	var corner := Positions.goal(actor, player, CENTER, 7, [actor, ranged])
	_check(corner == expected, "mixed ranged/ordinary corner still waits for an axial owner")
	ranged.set_combat_position(_ground_to_screen(expected), &"mixed_corner_live_body")
	_check(not Positions.goal(actor, player, CENTER, 7, [actor, ranged]).is_finite(), "mixed ranged body overlap did not block the corner")
	for item in [actor, ranged]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("CORNER_WAIT_REQUIREMENT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
