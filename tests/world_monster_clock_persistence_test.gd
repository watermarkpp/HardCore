extends Node

const WorldState := preload("res://scripts/world_monster_respawn_state.gd")


func _ready() -> void:
	PlayerState.test_mode = false
	PlayerState.profile_directory = "user://clock_persistence_test_profiles_%d" % Time.get_ticks_usec()
	PlayerState.active_profile_id = "clock_persistence_test"
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	var profile_path := PlayerState._profile_path(PlayerState.active_profile_id)
	var initial_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(not initial_profile.has("world_monster_respawn_state"))
	assert(initial_profile.death_event_sequence == 0)
	var deadline := Time.get_unix_time_from_system() + 3600.0
	assert(PlayerState.mark_monster_respawn_dead(913203, "group:0", 64, "normal_cave", deadline))
	var settlement := PlayerState.record_kills_and_experience_batch(
		[{"monster_name": "", "experience": 5}], true
	)
	assert(settlement.success)
	assert(PlayerState.experience == 3 and PlayerState.level == 2)
	var uncheckpointed_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(uncheckpointed_profile.experience == 0)
	assert(uncheckpointed_profile.death_event_sequence == 0)
	var event_path := PlayerState._death_event_path(PlayerState.active_profile_id, 1)
	assert(FileAccess.file_exists(event_path))
	PlayerState.experience = 999
	PlayerState.world_monster_respawn_state = WorldState.empty_snapshot()
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.experience == 3 and PlayerState.level == 2)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	assert(PlayerState.save_game(false))
	var checkpointed_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(checkpointed_profile.death_event_sequence == 1)
	assert(not checkpointed_profile.has("world_monster_respawn_state"))
	# The older profile backup still needs the journal to recover level and XP.
	assert(FileAccess.file_exists(event_path))
	var clock_path := PlayerState._world_clock_path(PlayerState.active_profile_id)
	var broken_clock := FileAccess.open(clock_path, FileAccess.WRITE)
	assert(broken_clock != null)
	broken_clock.store_string("{broken")
	broken_clock.close()
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.experience == 3 and PlayerState.level == 2)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	var broken := FileAccess.open(profile_path, FileAccess.WRITE)
	assert(broken != null)
	broken.store_string("{broken")
	broken.close()
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.experience == 3 and PlayerState.level == 2)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	assert(PlayerState.save_game(false))
	assert(PlayerState.save_game(false))
	var cleanup_deadline := Time.get_ticks_msec() + 2000
	while FileAccess.file_exists(event_path) and Time.get_ticks_msec() < cleanup_deadline:
		await get_tree().process_frame
	assert(not FileAccess.file_exists(event_path))
	PlayerState.experience = 999
	PlayerState.world_monster_respawn_state = WorldState.empty_snapshot()
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.experience == 3 and PlayerState.level == 2)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	for mode: String in ["profile", "world", "pickup"]:
		await _test_preserved_backup_recovery(mode)
	await _test_creation_runtime_rollback()
	print("WORLD_MONSTER_CLOCK_PERSISTENCE_PASS")
	get_tree().quit(0)


func _drain_cleanup() -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while PlayerState._clock_cleanup_worker != null or not PlayerState._clock_cleanup_pending.is_empty():
		assert(Time.get_ticks_msec() < deadline, "cleanup must finish")
		PlayerState._advance_world_clock_cleanup()
		await get_tree().process_frame


func _corrupt(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string("{broken")
	file.close()


func _test_preserved_backup_recovery(mode: String) -> void:
	await _drain_cleanup()
	PlayerState.active_profile_id = "preserved_backup_" + mode
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	assert(PlayerState._commit_death_event())
	assert(PlayerState.save_game(false))
	assert(PlayerState.save_game(false))
	await _drain_cleanup()
	assert(PlayerState._commit_death_event())
	assert(PlayerState.save_game(false))
	await _drain_cleanup()
	var path := PlayerState._world_clock_path(PlayerState.active_profile_id) if mode == "world" else PlayerState._profile_path(PlayerState.active_profile_id)
	var field := "sequence" if mode == "world" else "death_event_sequence"
	var event_path := PlayerState._death_event_path(PlayerState.active_profile_id, 2)
	assert(FileAccess.file_exists(event_path))
	if mode == "pickup":
		var plan := PlayerState.prepare_loot_save([{"gold": true, "amount": 7}])
		assert(plan.has("writer"))
		while not bool(plan.writer.result().finished):
			await get_tree().process_frame
		_corrupt(path)
		assert(PlayerState.finish_prepared_loot_save(plan, true).success)
	else:
		_corrupt(path)
		assert(PlayerState.save_game(false))
	await _drain_cleanup()
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	assert(int(backup[field]) == 1)
	var tracked := PlayerState._world_clock_backup_sequence if mode == "world" else PlayerState._profile_backup_death_event_sequence
	assert(tracked == 1, "preserved backup sequence must match disk: " + mode)
	assert(FileAccess.file_exists(event_path), "preserved backup still needs event 2")
	_corrupt(path)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success, "backup and retained journal must recover: " + mode)
	assert(PlayerState._death_event_sequence == 2)


func _test_creation_runtime_rollback() -> void:
	await _drain_cleanup()
	PlayerState.active_profile_id = "creation_rollback"
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	assert(PlayerState.mark_monster_respawn_dead(913203, "rollback_slot", 64, "normal_cave", Time.get_unix_time_from_system() + 600))
	assert(PlayerState._commit_death_event())
	var expected_world := PlayerState.world_monster_respawn_state.duplicate(true)
	var snapshot := PlayerState._creation_runtime_snapshot()
	# Same transaction boundary used when starter creation or its save fails.
	PlayerState.active_profile_id = "rejected_new_character"
	PlayerState.reset_progress(false)
	PlayerState._restore_creation_runtime(snapshot)
	assert(PlayerState.active_profile_id == "creation_rollback")
	assert(PlayerState.world_monster_respawn_state == expected_world)
	assert(PlayerState._death_event_sequence == 1)
	assert(PlayerState._profile_saved_death_event_sequence == 0)
	assert(PlayerState._profile_backup_death_event_sequence == 0)
	assert(PlayerState._world_clock_snapshot_sequence == 0)
	assert(PlayerState._world_clock_backup_sequence == 0)
	assert(PlayerState._world_clock_dirty)
	assert(PlayerState._commit_death_event())
	assert(PlayerState.save_game(false))
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState._death_event_sequence == 2)
	assert(PlayerState.world_monster_respawn_state == expected_world)
	await _drain_cleanup()
