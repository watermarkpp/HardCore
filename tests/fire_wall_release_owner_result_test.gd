extends "res://tests/canonical_skill_production_entry_test.gd"

var _owner_game: Node
var _owner_target: EnemyActor


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"火墙": 3}
	PlayerState.recalculate_stats()
	_owner_game = load("res://scenes/main.tscn").instantiate()
	add_child(_owner_game)
	await _wait_for_formal_world(_owner_game)
	var origin_ground := FIXTURE_GROUND_POSITION - Vector2(2, 0)
	_owner_game._set_player_world_position(_owner_game._canonical_ground_gu_to_screen_px(origin_ground))
	_owner_target = _make_enemy(_owner_game, _owner_game.player,
		_owner_game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION))
	var center := Vector2i(FIXTURE_GROUND_POSITION.floor())
	var first := _cast_owner(center)
	var first_id := first.get_instance_id()
	var visual_ids: Array[int] = []
	for cell: Node in first.visual_cells:
		visual_ids.append(cell.get_instance_id())
	assert(_owner_game._fire_wall_field_registry.size() == 1)
	var refreshed := _cast_owner(center)
	assert(refreshed == first and refreshed.refresh_count == 1,
		"same-tile result must return the existing owner, not a duplicate")
	for index in visual_ids.size():
		assert(refreshed.visual_cells[index].get_instance_id() == visual_ids[index])
	var all_owner_ids: Array[int] = [first_id]
	# Nine distinct release centers exercise the real SOT evict-oldest policy.
	for index in range(1, 9):
		var owner := _cast_owner(center + Vector2i(index % 3, index / 3))
		all_owner_ids.append(owner.get_instance_id())
	assert(first.cancelled and first.is_queued_for_deletion())
	assert(_owner_game._fire_wall_field_registry.size() == 8)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not is_instance_id_valid(first_id), "evicted owner remained alive")
	for cell_id in visual_ids:
		assert(not is_instance_id_valid(cell_id), "eviction retained a visual cell")
	# Formal map transition consumes the same owner registry and releases cells.
	PlayerState.test_mode = false
	assert(_owner_game._begin_map_transition(
		Callable(_owner_game, "_teleport_to_map_immediate").bind(
			910007, MapTeleportRuntimePolicy.DEFAULT_CITY_ARRIVAL_ANCHOR_ID), 910007))
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _owner_game._map_transition_in_progress and _owner_game.gameplay_input_is_enabled():
			break
	assert(_owner_game.current_map_id == 910007 and _owner_game.gameplay_input_is_enabled())
	assert(_owner_game._fire_wall_field_registry.is_empty())
	for owner_id in all_owner_ids:
		assert(not is_instance_id_valid(owner_id), "old-map release owner survived transition")
	assert(int(CasterSkillVisualRegistry.frame_texture_cache_diagnostics().get(
		"leased_sequence_refcount_total", -1)) == 0, "old-map fire wall retained leases")
	_owner_game.queue_free()
	await get_tree().process_frame
	print("FIRE_WALL_RELEASE_OWNER_RESULT_PASS exact_owner=1 refresh=1 eviction=1 map_cleanup=1")
	get_tree().quit(0)


func _cast_owner(center: Vector2i) -> FireWallFieldController:
	_owner_game.player.current_mp = 100000
	_owner_game._skill_cast_target = _owner_target
	var cast: Dictionary = _owner_game._execute_canonical_skill(
		"wizard.fire_wall", _owner_game.player.global_position, Vector2.RIGHT, 0,
		{"primary_stat_roll": 8, "target_tile": center})
	assert(bool(cast.get("accepted", false)) and bool(cast.get("plan_immutable", {}).get("valid", false)), str(cast))
	var execution: Dictionary = cast.get("execution_result", {})
	var ids: Array = execution.get("spawned_ground_effect_ids", [])
	assert(ids.size() == 1, "formal fire wall result must expose its one actual field owner, got %s" % [ids])
	var owner := instance_from_id(int(ids[0])) as FireWallFieldController
	assert(owner != null and not owner.is_queued_for_deletion())
	assert(owner.get_parent() == _owner_game and owner.source_actor == _owner_game.player)
	assert(owner.stable_skill_id == "wizard.fire_wall" and owner._runtime_map_id == _owner_game.current_map_id)
	assert(not owner._release_id.is_empty() and owner._canonical_snapshot_valid)
	assert(owner._release_id == str(execution.get("release_id", "")), "returned owner belongs to a different release")
	assert(owner._snapshot_id == str(execution.get("snapshot_id", "")), "returned owner must retain this release snapshot")
	assert(owner.visual_cells.size() == 9)
	assert(execution.get("spawned_projectile_ids", []).is_empty())
	assert(execution.get("spawned_summon_ids", []).is_empty())
	assert(execution.get("created_visual_ids", []).is_empty(), "field cells must not become separate public owners")
	assert(int(execution.get("side_effect_count", -1)) == 1)
	return owner
