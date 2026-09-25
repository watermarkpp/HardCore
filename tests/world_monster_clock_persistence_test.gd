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
	print("WORLD_MONSTER_CLOCK_PERSISTENCE_PASS")
	get_tree().quit(0)
