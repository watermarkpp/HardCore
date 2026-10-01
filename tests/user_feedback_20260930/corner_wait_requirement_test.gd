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
	var other := _spawn(150, CENTER + Vector2(-1.0, 0.0))
	for item in [actor, other]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
		item.target = player
	_check(actor._source176_ordinary_melee(), "natural 238 fixture is not ordinary melee")
	_check(not other._source176_ordinary_melee(), "mixed peer fixture is not a ranged body")
	var corner := Positions.goal(actor, player, CENTER, 7, [actor, other])
	_check(maxf(absf(corner.x - CENTER.x), absf(corner.y - CENTER.y)) <= 1.0 + GU.EPSILON_GU, "corner waits outside reach for axial stations that nobody claims")
	var pending := _spawn(64, CENTER + Vector2(1.5, 0))
	pending._leave_background_deep_sleep()
	pending.set_physics_process(false)
	pending.target = player
	pending._hc_surround_scope = [MAP_ID, 1, pending._hc_life(pending), player.get_instance_id(), pending._hc_life(player)]
	pending._hc_surround_anchor = CENTER
	pending._hc_surround_slot = 0
	pending._hc_surround_goal = Positions.station(pending, CENTER, pending._target_combat_radius_gu(player), 0)
	corner = Positions.goal(actor, player, CENTER, 7, [actor, other, pending])
	_check(maxf(absf(corner.x - CENTER.x), absf(corner.y - CENTER.y)) > 1.0 + GU.EPSILON_GU, "corner closed a claimed axial entrance before its body arrived")
	pending.target = null
	corner = Positions.goal(actor, player, CENTER, 7, [actor, other, pending])
	_check(maxf(absf(corner.x - CENTER.x), absf(corner.y - CENTER.y)) <= 1.0 + GU.EPSILON_GU, "old target claim retained the corner wait")
	for item in [actor, other, pending]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("CORNER_WAIT_REQUIREMENT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
