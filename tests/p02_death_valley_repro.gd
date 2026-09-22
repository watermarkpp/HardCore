extends Node

## P0-2: reproduce the first death_valley chain failure WITHOUT any test
## driver cleanup, and dump the exact coordinator snapshot at transition
## end. No revival, no lock release, no token finish - observe production
## state as-is.
## Usage: godot --headless --path . res://tests/p02_death_valley_repro.tscn

const AUTHORITY := preload("res://tools/wall_rollout_authority.gd")


func _snapshot(game: Node, label: String) -> void:
	var coord = game._world_bootstrap_coordinator
	var snap: Dictionary = coord.snapshot()
	var locks: Dictionary = game._gameplay_input_locks
	var stats: Dictionary = game.background.wall_render_stats()
	var line := {
		"label": label,
		"stage": str(snap.get("stage", "?")),
		"success": str(snap.get("success", "?")),
		"failure_reason": str(snap.get("failure_reason", "?")),
		"generation": int(coord.generation),
		"map_id": int(game.current_map_id),
		"transition_in_progress": str(game._map_transition_in_progress),
		"locks": JSON.stringify(locks),
		"combat_token_active": str(game.player.combat_transition_is_active()),
		"player_dead": str(game.player._dead),
		"player_hp": int(game.player.current_hp),
		"wall_mode": str(stats.get("wall_render_mode", "?")),
		"composites": _count_meta(game, "editor_runtime_wall_composite"),
		"chunks": _count_meta(game, "wall_static_chunk"),
	}
	print("P02_SNAPSHOT ", JSON.stringify(line))


func _count_meta(game: Node, meta: String) -> int:
	var count := 0
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and bool(node.get_meta(meta, false)):
			count += 1
	return count


func _ready() -> void:
	PlayerState.test_mode = true
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 30000
	while (
		not bool(game.gameplay_input_is_enabled())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.016, true).timeout
	await get_tree().create_timer(0.5, true).timeout
	game._monster_prefetch_enabled = false
	var map_id := 0
	for row: Dictionary in AUTHORITY.classify()["rows"]:
		if str(row["map_key"]) == "mengzhong_death_valley_dungeon":
			map_id = int(row["map_id"])
	_snapshot(game, "initial_world")
	# Hop 1: the predecessor map from the failing chain (913200 segment).
	var op := Callable(game, "_travel_to_map_immediate").bind(913201)
	print("P02_STAGE travel_begin map=913201")
	if not game._begin_map_transition(op, 913201):
		print("P02_STAGE travel_refused")
		get_tree().quit(1)
		return
	var hop := Time.get_ticks_msec() + 10000
	while (
		not bool(game._map_transition_in_progress)
		and Time.get_ticks_msec() < hop
	):
		await get_tree().create_timer(0.016, true).timeout
	game.hud.loading_transition_covered.emit({
		"contract_id": "ui.loading.transition.v1",
		"transition_id": game._active_map_transition_id,
	})
	await get_tree().create_timer(0.016, true).timeout
	var t2 := Time.get_ticks_msec() + 90000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < t2:
		await get_tree().create_timer(0.016, true).timeout
	_snapshot(game, "after_transition_913201")
	await get_tree().create_timer(1.0, true).timeout
	_snapshot(game, "settled_913201")
	# P0-2: walk the ready-contract sub-checks individually (diagnostic
	# mirror of game_root._check_world_ready_contract) to name the exact
	# failing sub-condition.
	var coord = game._world_bootstrap_coordinator
	var summary: Dictionary = coord.ready_contract_summary()
	print("P02_SUMMARY ", JSON.stringify(summary))
	var profile: Dictionary = game._resolve_projection_profile_for_map(
		int(game.current_map_id)
	)
	print("P02_CHECK profile_success=%s" % str(profile.get("success", false)))
	print("P02_CHECK gen_current=%s" % str(
		coord.is_generation_current(int(summary.get("generation", -1)))
	))
	print("P02_CHECK map_id_match=%s" % str(
		int(summary.get("map_id", -1)) == int(game.current_map_id)
	))
	print("P02_CHECK env_nodes=%d chunk_textures=%d" % [
		game.background.environment_node_count(),
		game.background.editor_runtime_chunk_texture_count(),
	])
	print("P02_CHECK map_items=%d/%d collisions=%d/%d failed_collision=%d" % [
		int(summary.get("planned_map_item_count", 0)),
		int(summary.get("built_map_item_count", 0)),
		int(summary.get("planned_collision_count", 0)),
		int(summary.get("built_collision_count", 0)),
		int(summary.get("failed_collision_count", 0)),
	])
	print("P02_CHECK actors=%d spawned=%d deferred=%d failed=%d dup=%d" % [
		int(summary.get("planned_actors", 0)),
		int(summary.get("spawned_actors", 0)),
		int(summary.get("deferred_actors", 0)),
		int(summary.get("failed_actors", 0)),
		int(summary.get("duplicate_actors", 0)),
	])
	print("P02_CHECK sync_loads=%d" % int(
		summary.get("unexpected_sync_load_count", 0)
	))
	print("P02_CHECK spawn_blocked=%s" % str(
		game.background.is_environment_point_blocked(
			game.player.global_position
		)
	))
	print("P02_CHECK hud_hp=%d player_hp=%d hud_max=%d player_max=%d" % [
		int(game.hud._last_hp), int(game.player.current_hp),
		int(game.hud._last_max_hp), int(game.player.max_hp),
	])
	get_tree().quit(0)
