extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(await _wait_ready(game, 910001))
	game.player.max_hp = 1000000
	game.player.current_hp = 1000000
	PlayerState.test_mode = false
	# These six real clothing dungeons contain only a boss. Persisted dead
	# slots are valid deferred actors, including after a character reload.
	for map_id: int in [918001, 918002, 918003, 918004, 918005, 918006]:
		var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
		var bosses: Array = content.get("bosses", [])
		assert(not bosses.is_empty())
		for boss: Dictionary in bosses:
			var group: Dictionary = boss.spawn_group
			var slot := "%s:0" % str(group.get("spawn_group_id", "editor:%d:boss:%d" % [map_id, bosses.find(boss)]))
			assert(PlayerState.mark_monster_respawn_dead(map_id, slot, int(boss.monster_id), "boss", Time.get_unix_time_from_system() + 3600.0))
		PlayerState.world_monster_respawn_state = WorldMonsterRespawnState.normalize_snapshot(JSON.parse_string(JSON.stringify(PlayerState.monster_respawn_state_for_restore())))
		assert(game._begin_map_transition(Callable(game, "_travel_to_map_immediate").bind(map_id), map_id))
		if not await _wait_ready(game, map_id):
			get_tree().quit(1)
			return
		var summary: Dictionary = game._world_bootstrap_coordinator.ready_contract_summary()
		assert(int(summary.deferred_actors) == bosses.size())
		assert(not game.player.combat_transition_is_active())
		print("BOSS_RESPAWN_REENTRY_READY map=%d deferred=%d" % [map_id, summary.deferred_actors])
	# Cross the actual deadline before/during/after the async world build.
	# Each slot must materialize exactly once and clear only its death record.
	var first_boss: Dictionary = MapEditorRuntimeBridge.game_content_for_map(918001).bosses[0]
	var first_slot := "%s:0" % str(first_boss.spawn_group.spawn_group_id)
	for offset: float in [-0.01, 0.05, 1.0]:
		assert(game._begin_map_transition(Callable(game, "_travel_to_map_immediate").bind(910001), 910001))
		assert(await _wait_ready(game, 910001))
		assert(PlayerState.mark_monster_respawn_dead(918001, first_slot, int(first_boss.monster_id), "boss", Time.get_unix_time_from_system() + offset))
		assert(game._begin_map_transition(Callable(game, "_travel_to_map_immediate").bind(918001), 918001))
		assert(await _wait_ready(game, 918001))
		var deadline := Time.get_ticks_msec() + 3000
		while not game._spawn_slot_is_alive(first_slot, game._zone_generation) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var matching := 0
		for enemy: Node in get_tree().get_nodes_in_group("enemies"):
			if not enemy.is_queued_for_deletion() and str(enemy.get_meta("spawn_slot_id", "")) == first_slot:
				matching += 1
		assert(matching == 1, "respawn deadline must produce exactly one live boss")
		assert(PlayerState.monster_respawn_entry(918001, first_slot).is_empty())
		assert(PlayerState.world_monster_respawn_state.entries.size() == 5, "unrelated maps' deadlines changed")
	game.queue_free()
	await get_tree().process_frame
	print("BOSS_RESPAWN_MAP_REENTRY_PASS")
	get_tree().quit()

func _wait_ready(game: Node, expected_map: int) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not game._map_transition_in_progress and game.gameplay_input_is_enabled():
			if int(game.current_map_id) == expected_map:
				return true
			print("BOSS_REENTRY_WRONG_MAP expected=%d actual=%d state=%s" % [expected_map, game.current_map_id, game._world_bootstrap_coordinator.snapshot()])
			return false
	print("BOSS_REENTRY_TIMEOUT ", game._world_bootstrap_coordinator.snapshot())
	return false
