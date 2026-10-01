extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actors: Array[EnemyActor] = []
	# Independent construction: four real .5-GU bodies on corners and four
	# slightly inward axial bodies. All remain inside the exact source box.
	for offset: Vector2 in [Vector2(.91, 0), Vector2(1, 1), Vector2(0, .91), Vector2(-1, 1), Vector2(-.91, 0), Vector2(-1, -1), Vector2(0, -.91), Vector2(1, -1)]:
		var actor := _spawn(89, CENTER + offset)
		actor._leave_background_deep_sleep()
		actor.set_physics_process(false)
		actor.set_combat_position(_ground_to_screen(CENTER + offset), &"packing_fixture_exact_position")
		actors.append(actor)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var evidence: Array = []
	for actor in actors:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = Body.footsole_shape_px(actor.collision_radius_px)
		query.transform = actor.global_transform
		query.margin = actor.safe_margin
		query.collision_mask = actor.collision_mask
		query.exclude = [actor.get_rid()]
		var overlaps := actor.get_world_2d().direct_space_state.intersect_shape(query, 16)
		_check(overlaps.is_empty(), "independent large-body packing intersects another real body")
		_check(actor._hc_access(player) == "CLEAR", "independent packing has no legal source attack access")
		evidence.append({"position": str(actor.spatial_index_position()), "radius": actor.combat_radius_gu, "safe_margin_px": actor.safe_margin, "overlaps": overlaps.size(), "access": actor._hc_access(player)})
	for actor in actors:
		index.unregister(actor.spatial_actor_runtime_id)
		actor.free()
	player.free()
	print("LARGE_SURROUND_PACKING_", "PASS" if failures.is_empty() else "FAIL", " ", evidence, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
