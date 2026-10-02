extends Node

const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const SlotIdentity := preload("res://scripts/identity/equipment_identity_codec.gd")
const ItemCodec := preload("res://scripts/items/item_extension_codec.gd")


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
	old_profile.erase("world_clock_generation")
	# This is an actual old writer document, before either identity header.
	old_profile.erase("item_identity")
	old_profile.erase(SlotIdentity.FIELD)
	var old_slots := {}
	for slot: String in old_profile.equipment:
		old_slots[SlotIdentity.display_name(slot)] = old_profile.equipment[slot]
	old_profile.equipment = old_slots
	old_profile.equip_cycle_cursor = {"戒指": "左戒指", "手镯": "左手镯"}
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
	var migrated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(FileAccess.file_exists(PlayerState._world_clock_path(PlayerState.active_profile_id, migrated.world_clock_generation)))
	assert(migrated.has("death_event_sequence") and not migrated.has("world_monster_respawn_state"))
	var original_on_disk: Dictionary = JSON.parse_string(old_bytes)
	assert(PlayerState._shared_digest(archived) == PlayerState._shared_digest(original_on_disk), "original profile is preserved in the migration archive")
	assert(PlayerState.save_game(false))
	var new_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	assert(not new_profile.has("world_monster_respawn_state"))
	assert(new_profile.level == 22 and new_profile.experience == 345 and new_profile.gold == 12345)
	assert(new_profile.inventory.size() == 1)
	assert(str(new_profile.inventory[0].name) == "太阳水")
	assert(int(new_profile.inventory[0].count) == 10)
	assert(str(new_profile.equipment["hc.slot.weapon"].name) == "木剑")
	assert(str(new_profile.equipment["hc.slot.weapon"].instance_id) == "legacy_weapon")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile_path + ".bak"))
	assert(backup.has("death_event_sequence") and backup.world_clock_generation == migrated.world_clock_generation)
	assert(backup.level == old_profile.level)
	assert(backup.experience == old_profile.experience)
	assert(backup.gold == old_profile.gold)
	assert(backup.inventory.size() == 1)
	assert(str(backup.inventory[0].name) == "太阳水")
	assert(int(backup.inventory[0].count) == 10)
	var decoded_backup := ItemCodec.decode_document(backup)
	assert(decoded_backup.status == ItemCodec.KNOWN_VALID)
	assert(str(decoded_backup.document.equipment["hc.slot.weapon"].instance_id) == "legacy_weapon")
	assert(backup.quest_states == old_profile.quest_states)
	PlayerState.reset_progress(false)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.level == 22 and PlayerState.experience == 345 and PlayerState.gold == 12345)
	assert(PlayerState.monster_respawn_entry(913203, "group:0").respawn_at_unix == deadline)
	assert(PlayerState.save_game(false))
	assert(FileAccess.file_exists(archive_path))
	await _test_old_writer_roundtrip()
	await _test_interrupted_import(".tmp", "world_clock_import_profile_failed")
	await _test_interrupted_import(".bak.tmp", "world_clock_import_backup_failed")
	await _test_pre_generation_migration_replay()
	print("WORLD_MONSTER_CLOCK_LEGACY_MIGRATION_PASS")
	get_tree().quit(0)


func _drain_cleanup() -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while PlayerState._clock_cleanup_worker != null or not PlayerState._clock_cleanup_pending.is_empty():
		assert(Time.get_ticks_msec() < deadline)
		PlayerState._advance_world_clock_cleanup()
		await get_tree().process_frame


func _test_old_writer_roundtrip() -> void:
	await _drain_cleanup()
	PlayerState.active_profile_id = "old_writer_roundtrip"
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	PlayerState.level = 22
	PlayerState.experience = 100
	assert(PlayerState._commit_death_event())
	assert(PlayerState.save_game(false))
	assert(PlayerState.save_game(false))
	await _drain_cleanup()
	var path := PlayerState._profile_path(PlayerState.active_profile_id)
	assert(not FileAccess.file_exists(PlayerState._death_event_path(PlayerState.active_profile_id, 1)))
	for round_index in range(2):
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		# v93's serializer writes known fields and has no death sequence or generation.
		old.erase("death_event_sequence")
		old.erase("world_clock_generation")
		old["level"] = 30 + round_index
		old["experience"] = 777 + round_index
		old["gold"] = 67890 + round_index
		old["inventory"] = [{"name": "太阳水", "count": 12 + round_index}]
		var deadline := Time.get_unix_time_from_system() + 3600.0
		old["world_monster_respawn_state"] = WorldState.with_deadline(
			WorldState.empty_snapshot(), 913203, "old_return", 64, "normal_cave", deadline
		)
		assert(PlayerState._write_json_atomic(path, old))
		PlayerState.reset_progress(false)
		PlayerState.load_save()
		assert(PlayerState.last_load_result.success, "old writer return must not replay an unrelated death sequence: " + str(PlayerState.last_load_result))
		assert(PlayerState.level == 30 + round_index and PlayerState.experience == 777 + round_index)
		assert(PlayerState.gold == 67890 + round_index)
		assert(PlayerState.inventory[0].count == 12 + round_index)
		assert(PlayerState.monster_respawn_entry(913203, "old_return").respawn_at_unix == deadline)
		# A new death before the next character checkpoint must survive backup recovery.
		PlayerState.experience += 10
		assert(PlayerState._commit_death_event())
		if round_index == 0:
			# Exercise the byte-validated save fast path without resetting its cache.
			assert(PlayerState._checkpoint_world_clock())
			assert(PlayerState._checkpoint_world_clock())
			assert(PlayerState.save_game(false))
			await _drain_cleanup()
		var corrupt := FileAccess.open(path, FileAccess.WRITE)
		corrupt.store_string("{broken")
		corrupt.close()
		PlayerState.reset_progress(false)
		PlayerState.load_save()
		assert(PlayerState.last_load_result.success)
		assert(PlayerState.level == 30 + round_index and PlayerState.experience == 787 + round_index)
		assert(PlayerState.gold == 67890 + round_index)
		assert(PlayerState.inventory[0].count == 12 + round_index)
		assert(PlayerState._checkpoint_world_clock())
		assert(PlayerState.save_game(false))
		await _drain_cleanup()
		# The first character checkpoint still has a sequence-zero backup. Its
		# recovery event must survive even when both world checkpoints are newer.
		corrupt = FileAccess.open(path, FileAccess.WRITE)
		corrupt.store_string("{broken_again")
		corrupt.close()
		PlayerState.reset_progress(false)
		PlayerState.load_save()
		assert(PlayerState.last_load_result.success, "generation-aware cleanup must retain the older backup's events")
		assert(PlayerState.experience == 787 + round_index)
		assert(PlayerState.save_game(false))
		await _drain_cleanup()


func _legacy_fixture(profile_id: String) -> Dictionary:
	PlayerState.active_profile_id = profile_id
	PlayerState.reset_progress(false)
	assert(PlayerState.save_game(false))
	var path := PlayerState._profile_path(profile_id)
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	legacy.erase("death_event_sequence")
	legacy.erase("world_clock_generation")
	legacy["level"] = 20
	legacy["experience"] = 123
	legacy["gold"] = 4567
	legacy["world_monster_respawn_state"] = WorldState.empty_snapshot()
	assert(PlayerState._write_json_atomic(path, legacy))
	return legacy


func _test_interrupted_import(blocker_suffix: String, expected_reason: String) -> void:
	await _drain_cleanup()
	var profile_id := "interrupted_backup" if blocker_suffix == ".bak.tmp" else "interrupted_primary"
	var original := _legacy_fixture(profile_id)
	var path := PlayerState._profile_path(profile_id)
	var original_bytes := FileAccess.get_file_as_bytes(path)
	# A directory at the exact temporary-file path injects a real write failure.
	var blocker := ProjectSettings.globalize_path(path + blocker_suffix)
	assert(DirAccess.make_dir_recursive_absolute(blocker) == OK)
	PlayerState.load_save()
	assert(not PlayerState.last_load_result.success and PlayerState.last_load_result.reason == expected_reason)
	assert(not PlayerState.save_game(false), "failed import must not allow gameplay state to overwrite the source")
	if blocker_suffix == ".tmp":
		assert(FileAccess.get_file_as_bytes(path) == original_bytes)
	else:
		var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
		assert(PlayerState._shared_digest(backup) == PlayerState._shared_digest(original))
	assert(DirAccess.remove_absolute(blocker) == OK)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success, "interrupted import must resume safely")
	assert(PlayerState.level == 20 and PlayerState.experience == 123 and PlayerState.gold == 4567)
	var creation_rollback := PlayerState._creation_runtime_snapshot()
	PlayerState.reset_progress(false)
	PlayerState._restore_creation_runtime(creation_rollback)
	PlayerState.experience = 133
	assert(PlayerState._commit_death_event())
	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	PlayerState.reset_progress(false)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.level == 20 and PlayerState.experience == 133 and PlayerState.gold == 4567)


func _test_pre_generation_migration_replay() -> void:
	await _drain_cleanup()
	var legacy := _legacy_fixture("partial_previous_clock_migration")
	var profile_id: String = PlayerState.active_profile_id
	# Reproduce the earlier implementation: archive + world baseline, unchanged
	# legacy character file, then a durable death before the next character save.
	var directory := PlayerState.profile_directory.path_join("clock_migration_backups")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var archive := directory.path_join("%s-%s.json" % [profile_id, PlayerState._shared_digest(legacy)])
	assert(PlayerState._write_json_atomic(archive, legacy))
	PlayerState.level = 20
	PlayerState.experience = 173
	assert(PlayerState._commit_death_event())
	var prior_event := PlayerState._death_event_path(profile_id, 1)
	var prior_bytes := FileAccess.get_file_as_bytes(prior_event)
	PlayerState.reset_progress(false)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.level == 20 and PlayerState.experience == 173 and PlayerState.gold == 4567)
	PlayerState.experience = 183
	assert(PlayerState._commit_death_event())
	assert(PlayerState.save_game(false))
	assert(PlayerState.save_game(false))
	await _drain_cleanup()
	assert(FileAccess.get_file_as_bytes(prior_event) == prior_bytes, "cleanup must stay in its captured generation")
