extends Node

const WorldState := preload("res://scripts/world_monster_respawn_state.gd")


func _ready() -> void:
	PlayerState.test_mode = false
	PlayerState.profile_directory = "user://clock_legacy_migration_test_%d" % Time.get_ticks_usec()
	PlayerState.active_profile_id = "legacy_profile"
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	var profile_path := PlayerState._profile_path(PlayerState.active_profile_id)
	var clock_path := PlayerState._world_clock_path(PlayerState.active_profile_id)
	var old_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	var deadline := Time.get_unix_time_from_system() + 3600.0
	var legacy_world := WorldState.with_deadline(
		WorldState.empty_snapshot(), 913203, "group:0", 64, "normal_cave", deadline
	)
	old_profile.erase("death_event_sequence")
	old_profile["level"] = 22
	old_profile["experience"] = 345
	old_profile["gold"] = 12345
	old_profile["inventory"] = [{"name": "太阳水", "count": 10}]
	(old_profile["equipment"] as Dictionary)["武器"] = (
		PlayerState._developer_item("木剑", "legacy_weapon")
	)
	old_profile["world_monster_respawn_state"] = legacy_world
	var old_bytes := JSON.stringify(old_profile)
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(old_bytes)
	file.close()
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(clock_path)) == OK)
	if FileAccess.file_exists(clock_path + ".bak"):
		assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(clock_path + ".bak")) == OK)
	PlayerState.reset_progress(false)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	var archive_path := str(PlayerState.last_load_result.get("world_clock_migration_archive", ""))
	assert(not archive_path.is_empty() and FileAccess.file_exists(archive_path))
	var archived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(archive_path))
	assert(archived.has("world_monster_respawn_state"))
	assert(archived.level == 22 and archived.gold == 12345)
	assert(PlayerState.level == 22 and PlayerState.experience == 345 and PlayerState.gold == 12345)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	assert(FileAccess.file_exists(clock_path))
	assert(FileAccess.get_file_as_string(profile_path) == old_bytes)
	assert(PlayerState.save_game(false))
	var new_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(not new_profile.has("world_monster_respawn_state"))
	assert(new_profile.level == 22 and new_profile.experience == 345 and new_profile.gold == 12345)
	assert(new_profile.inventory.size() == 1)
	assert(str(new_profile.inventory[0].name) == "太阳水")
	assert(int(new_profile.inventory[0].count) == 10)
	assert(str(new_profile.equipment["武器"].name) == "木剑")
	assert(str(new_profile.equipment["武器"].instance_id) == "legacy_weapon")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path + ".bak"))
	assert(backup.has("world_monster_respawn_state"))
	assert(backup.level == old_profile.level)
	assert(backup.experience == old_profile.experience)
	assert(backup.gold == old_profile.gold)
	assert(backup.inventory.size() == 1)
	assert(str(backup.inventory[0].name) == "太阳水")
	assert(int(backup.inventory[0].count) == 10)
	assert(str(backup.equipment["武器"].instance_id) == "legacy_weapon")
	assert(backup.quest_states == old_profile.quest_states)
	assert(WorldState.entry_for(
		backup.world_monster_respawn_state, 913203, "group:0"
	).respawn_at_unix == deadline)
	PlayerState.reset_progress(false)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.level == 22 and PlayerState.experience == 345 and PlayerState.gold == 12345)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	assert(PlayerState.save_game(false))
	assert(FileAccess.file_exists(archive_path))
	print("WORLD_MONSTER_CLOCK_LEGACY_MIGRATION_PASS")
	get_tree().quit(0)
