extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"魔法盾": 3}
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(await _wait_ready(game, 910001))
	game.player.current_mp = 100
	var result: Dictionary = game._execute_canonical_skill(
		"wizard.magic_shield", game.player.global_position, Vector2.DOWN, 0,
		{"primary_stat_roll": 12})
	assert(result.accepted and game.player.magic_shield_snapshot().active)
	assert(_shield_count(game.player) == 1)
	PlayerState.test_mode = false
	for map_id: int in [910007, 910001]:
		assert(game._begin_map_transition(Callable(game, "_teleport_to_map_immediate").bind(
			map_id, MapTeleportRuntimePolicy.DEFAULT_CITY_ARRIVAL_ANCHOR_ID), map_id))
		assert(await _wait_ready(game, map_id))
		assert(game.player.magic_shield_snapshot().active, "map transition erased an active shield buff")
		assert(_shield_count(game.player) == 1, "active shield lost its visual across maps")
	game.player.shield_capacity = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert(_shield_count(game.player) == 0, "depleted shield visual survived")
	game.queue_free()
	await get_tree().process_frame
	print("MAGIC_SHIELD_MAP_LIFECYCLE_PASS")
	get_tree().quit()

func _shield_count(player: Node) -> int:
	var count := 0
	for visual: Node in get_tree().get_nodes_in_group("wizard_magic_shield_persistent_visual"):
		if not visual.is_queued_for_deletion() and visual.target_node == player and visual.visible:
			count += 1
	return count

func _wait_ready(game: Node, map_id: int) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not game._map_transition_in_progress and game.gameplay_input_is_enabled():
			return game.current_map_id == map_id
	return false
