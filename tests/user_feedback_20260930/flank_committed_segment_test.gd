extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const Step := preload("res://scripts/monster_source176/source_step_plan.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	# Recorded from the native 30-zombie failure. The straight chord toward
	# the player moves away from the nearby body, but its canonical diagonal
	# prefix crosses that body's core. Candidate selection must use the leg
	# that locomotion will actually commit, including its batch envelope.
	var actor := _spawn(64, Vector2(17.96799, 15.282))
	var blocker := _spawn(64, Vector2(18.42669, 15.82118))
	for item in [actor, blocker]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
	actor._hc_sync_navigation()
	actor._hc_known_target_id = player.get_instance_id()
	actor._hc_known_ground = CENTER
	actor._hc_observed = true
	var current := actor.spatial_index_position()
	_check(actor._hc_motion_clear(current, CENTER), "recorded chord must be clear")
	_check(not actor._hc_motion_clear(current, Step.next_leg(current, CENTER)), "recorded committed prefix must hit the real neighbor core")
	var neighbor := actor._hc_neighbor(current, player, Vector2i(-1, 1))
	_check(neighbor != Vector2i.ZERO, "open alternative flank was not selected")
	var leg := Step.next_leg(current, actor._hc_step_override, 1.0, GU.EPSILON_GU)
	_check(leg.is_finite() and actor._hc_motion_clear(current, leg), "flank selected a clear chord whose committed prefix is blocked")
	for item in [actor, blocker]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("FLANK_COMMITTED_SEGMENT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
