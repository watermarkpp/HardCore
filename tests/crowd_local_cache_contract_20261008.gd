extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real index/actors: candidate identity caching must remain complete while
## unrelated bucket changes stop invalidating a local motion query.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	_local_case(CENTER + Vector2(4, 0))
	_local_case(Vector2(-16.5, -16.5))
	player.free()
	print("CROWD_LOCAL_CACHE_CONTRACT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _local_case(origin: Vector2) -> void:
	index.clear_map(MAP_ID)
	var actor := _spawn(24, origin)
	var far := _spawn(24, origin + Vector2(12, 12))
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "initial local segment blocked")
	var queries := index.index_enemy_node_segment_query_count
	far.set_combat_position(_ground_to_screen(origin + Vector2(14, 12)), &"unrelated_cross_bucket")
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "far crossing changed local collision")
	_check(index.index_enemy_node_segment_query_count == queries, "unrelated crossing rebuilt local pool")
	var born := _spawn(24, origin + Vector2(18, 12))
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "far registration changed local collision")
	_check(index.index_enemy_node_segment_query_count == queries, "unrelated registration rebuilt local pool")
	index.unregister(born.spatial_actor_runtime_id)
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "far removal changed local collision")
	_check(index.index_enemy_node_segment_query_count == queries, "unrelated removal rebuilt local pool")
	far.set_combat_position(_ground_to_screen(origin + Vector2(-0.6, 0)), &"incoming_local_body")
	_check(not actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "incoming body missed by cached pool")
	_check(index.index_enemy_node_segment_query_count > queries, "incoming bucket did not invalidate local pool")
	far.current_hp = 0
	queries = index.index_enemy_node_segment_query_count
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "live eligibility became a cached body hit")
	_check(index.index_enemy_node_segment_query_count == queries, "live eligibility repeated identity query")
	# Increasing the registered maximum footprint changes every envelope,
	# even when the new center is outside the old cached bucket rectangle.
	var wide := _spawn(24, origin + Vector2(-4, 0))
	wide.combat_radius_gu = 4.0
	wide.set_combat_position(_ground_to_screen(origin + Vector2(-4, 0)), &"wide_fixture_after_spawn_grounding")
	index.register(wide.spatial_actor_runtime_id, MAP_ID, origin + Vector2(-4, 0), 4.0, serial, wide)
	_check(not actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "larger registered footprint omitted outside old envelope")
	queries = index.index_enemy_node_segment_query_count
	index.clear_map(MAP_ID)
	_check(actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "clear_map reused retired identities")
	_check(index.index_enemy_node_segment_query_count > queries, "map clear did not invalidate local pool")
	var replacement := _spawn(24, origin + Vector2(-0.6, 0))
	_check(not actor._hc_motion_clear(origin, origin + Vector2(-0.05, 0)), "same-map replacement body missed")
	for item in [actor, far, born, wide, replacement]:
		item.free()
	index.clear_map(MAP_ID)
