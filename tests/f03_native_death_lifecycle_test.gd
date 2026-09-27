extends Node

const Fixture := preload("res://tests/f05_settlement_display_separation_test.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	var game: Node = Fixture.FixtureGame.new()
	game.current_map_id = 5317
	game._zone_generation = 11
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	game._enemy_death_flush_queued = true
	PlayerState.set_process(false)
	var root := "user://f03_native_death_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.active_profile_id = "native"
	PlayerState.test_mode = false
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	assert(PlayerState.save_game(false))
	var canonical := GameData.get_monster_by_id(64)
	var reward: int = int(game._build_enemy_death_runtime_snapshot(canonical).experience)
	var rng_before: int = game._rng.state
	_queue(game, canonical, "cancelled")
	game._pump_enemy_death_work_queue()
	assert(game._pending_enemy_deaths[0].state == "PERSISTING")
	assert(PlayerState._death_event_sequence == 0 and PlayerState.experience == 0)
	assert(PlayerState.world_monster_respawn_state.entries.is_empty())
	var cancelled: Dictionary = game._prepared_enemy_death_settlement.plan
	assert(cancelled.writer.result(true).success)
	game._zone_generation += 1
	game._cancel_pending_enemy_deaths_for_generation_change()
	assert(game._pending_enemy_deaths.is_empty() and cancelled.completed and not cancelled.completion.success)
	assert(PlayerState._death_event_sequence == 0 and PlayerState.experience == 0 and game._rng.state == rng_before)
	_queue(game, canonical, "committing")
	game._pump_enemy_death_work_queue()
	var committing: Dictionary = game._prepared_enemy_death_settlement.plan
	_start_promotion(committing)
	assert(PlayerState.experience == 0 and PlayerState.world_monster_respawn_state.entries.is_empty())
	game._zone_generation += 1
	game._cancel_pending_enemy_deaths_for_generation_change()
	assert(PlayerState._death_event_sequence == 1 and PlayerState.experience == reward)
	assert(PlayerState.world_monster_respawn_state.entries.size() == 1)
	assert(game._pending_enemy_deaths.is_empty() and game._rng.state == rng_before)
	# A real root exit consumes an accepted request. It must not mark a future
	# as "no progress" or leave its worker/callback holding a deleted root.
	_queue(game, canonical, "exiting")
	game._pump_enemy_death_work_queue()
	var exiting: Dictionary = game._prepared_enemy_death_settlement.plan
	assert(exiting.writer.result(true).success)
	game.free()
	assert(exiting.completed and exiting.completion.success)
	assert(PlayerState._death_event_sequence == 2 and PlayerState.experience == reward * 2)
	assert(PlayerState.world_monster_respawn_state.entries.size() == 2)
	assert(PlayerState.finish_prepared_death_settlement(exiting).success and PlayerState.experience == reward * 2)
	assert(RuntimeDiagnostics.performance_counter(&"drop_roll_count") == 1)
	assert(PlayerState._json_persistence.pending_count() == 0)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success and PlayerState._death_event_sequence == 2)
	assert(PlayerState.experience == reward * 2 and PlayerState.world_monster_respawn_state.entries.size() == 2)
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	await get_tree().process_frame
	print("F03_NATIVE_DEATH_LIFECYCLE_PASS")
	get_tree().quit(0)

func _start_promotion(plan: Dictionary) -> void:
	assert(plan.writer.result(true).success)
	assert(PlayerState.finish_prepared_death_settlement(plan).get("pending", false))
	assert(plan.writer.job.stage_result(true).result.success)
	assert(PlayerState.finish_prepared_death_settlement(plan).get("pending", false))
	assert(plan.writer.job.stage_result(true).result.success)
	assert(not plan.completed)

func _queue(game: Node, canonical: Dictionary, slot: String) -> void:
	var enemy := EnemyActor.new()
	enemy.global_position = Vector2(5000, 5000)
	enemy.set_meta("respawn_enabled", true)
	enemy.set_meta("respawn_seconds", 480.0)
	enemy.set_meta("death_runtime_snapshot", game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("death_origin", {"captured": true, "map_id": game.current_map_id,
		"generation": game._zone_generation, "death_position": enemy.global_position,
		"spawn_position": enemy.global_position, "spawn_context": {"respawn_runtime_map_id": 5317,
			"spawn_slot_id": slot, "respawn_policy_id": "normal_cave"}})
	game._on_enemy_died(enemy, canonical)
	enemy.free()
