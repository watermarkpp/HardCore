extends "res://tests/hc_monster_ai/runtime_test.gd"

const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")

func _run() -> void:
	PlayerState.test_mode = true
	player = PlayerCharacter.new()
	player.global_position = ground_to_screen(Vector2(20,20))
	player.set_meta("runtime_map_id",1)
	player.set_meta("zone_generation",1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var actor := make_enemy(Vector2(24.5,20))
	var context := open_context()
	context["blocked_cells"] = {Vector2i(22,20):true}
	actor.configure_terrain_navigation_context(context)
	# The engine owns every actor tick. No manual physics/clock/cadence calls.
	actor.set_physics_process(true)
	var rows: Array = []
	for frame in range(420):
		await get_tree().physics_frame
		if frame % 5 == 0:
			rows.append({"frame":Engine.get_physics_frames(),"ground":str(screen_to_ground(actor.global_position)),
				"clock":actor._combat_action_time_s,"reason":actor._hc_last_reason,
				"pending":actor._hc_path_pending,"path_status":actor._hc_path_status,
				"route":str(actor._hc_route),"route_index":actor._hc_route_index,
				"step":actor._movement_step_active,"endpoint":str(actor._movement_step_target_ground_gu),
				"permission":actor._source176_decision_granted,"pursuit":actor._hc_pursuit_session})
	var final_position := screen_to_ground(actor.global_position)
	var distance := final_position.distance_to(Vector2(20,20))
	var relative := final_position-Vector2(20,20)
	var box_extent := maxf(absf(relative.x),absf(relative.y))
	check(box_extent <= 1.000001 and actor._hc_access(player)=="CLEAR","C05-native-reach",
		"native actor detours to the formal L-inf box with clear access, extent=%.6f" % box_extent)
	check(final_position.floor()!=Vector2(22,20),"C05-native-cell","blocked cell is never the endpoint")
	F.write_evidence("c05_native_detour",{"rows":rows,"distance":distance,"box_extent":box_extent,"final":str(final_position)})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
	finish("C05_NATIVE_DETOUR")
