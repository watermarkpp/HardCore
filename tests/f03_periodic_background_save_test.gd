extends Node

const State := preload("res://scripts/player_state.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var state := State.new()
	var root := "user://f03_periodic_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "periodic"
	state.character_name = "周期角色"
	state.test_mode = false
	state.reset_progress(false)
	state.character_name = "周期角色"
	assert(state.save_game())
	var profile: String = state._profile_path("periodic")
	state.gold = 12
	var before_generation: int = state._atomic_write_generation
	state._process(state.AUTOSAVE_INTERVAL)
	if state._json_persistence.pending_count() == 0 or state._atomic_write_generation != before_generation:
		state.free()
		printerr("F03_PERIODIC_BACKGROUND_SAVE_FAIL: periodic save synchronously promoted files")
		get_tree().quit(1)
		return
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(profile)).gold) == 0)
	state._json_persistence.drain()
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(profile)).gold) == 12)
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.profile_index_path))
	assert(index.profiles.size() == 1 and index.profiles[0].name == "周期角色")
	# The older saved revision must not clear a newer genuine wear event.
	assert(state.receive_record({"item_id": 80, "name": "木剑"}).success)
	assert(state.equip_inventory_index(0).begins_with("已装备"))
	assert(state.save_game(false))
	assert(state.apply_durability_event(state.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT, {"confirmed_hit": true, "damage": 10, "weapon_roll": 0, "weapon_strong": 0}).applied)
	state._advance_durability_runtime(state.DURABILITY_SAVE_INTERVAL)
	assert(state._json_persistence.pending_count() > 0)
	assert(state.apply_durability_event(state.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT, {"confirmed_hit": true, "damage": 10, "weapon_roll": 0, "weapon_strong": 0}).applied)
	state._json_persistence.drain()
	assert(state._durability_save_pending, "older receipt incorrectly cleared newer wear")
	assert(int(state.equipment["武器"].durability_raw) == 3996)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(profile)).equipment["武器"].durability_raw) == 3998)
	state._advance_durability_runtime(state.DURABILITY_SAVE_INTERVAL)
	state._json_persistence.drain()
	assert(not state._durability_save_pending)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(profile)).equipment["武器"].durability_raw) == 3996)
	# Recover the index from a real valid backup, retaining every other role.
	var valid_index := {"version": 1, "profiles": [index.profiles[0], {"id": "another", "name": "另一个角色", "level": 3}]}
	assert(state._write_json_atomic(state.profile_index_path, valid_index))
	assert(state._write_json_atomic(state.profile_index_path, valid_index))
	var broken := FileAccess.open(state.profile_index_path, FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	state.gold = 15
	state._process(state.AUTOSAVE_INTERVAL)
	print("F03_PERIODIC_INDEX_STARTED " + JSON.stringify({"pending": state._json_persistence.pending_count(), "background": not state._background_save.is_empty(), "last": state.last_save_result}))
	state._json_persistence.drain()
	print("F03_PERIODIC_INDEX_COMPLETED " + JSON.stringify({"pending": state._json_persistence.pending_count(), "last": state.last_save_result}))
	index = JSON.parse_string(FileAccess.get_file_as_string(state.profile_index_path))
	assert(index.profiles.size() == 2 and index.profiles[1].id == "another")
	assert(state.last_save_result.success and state.last_save_result.profile_index_updated)
	# A future index blocks only the index update; never overwrite unknown data
	# or pretend that the already-durable role itself failed to save.
	var future := FileAccess.open(state.profile_index_path, FileAccess.WRITE)
	future.store_string(JSON.stringify({"version": 99, "profiles": index.profiles}))
	future.close()
	var future_bytes := FileAccess.get_file_as_bytes(state.profile_index_path)
	state.gold = 19
	state._process(state.AUTOSAVE_INTERVAL)
	state._json_persistence.drain()
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(profile)).gold) == 19)
	assert(FileAccess.get_file_as_bytes(state.profile_index_path) == future_bytes)
	assert(state.last_save_result.success and not state.last_save_result.profile_index_updated)
	var restore_index := FileAccess.open(state.profile_index_path, FileAccess.WRITE)
	restore_index.store_string(JSON.stringify(index))
	restore_index.close()
	var deadline := Time.get_unix_time_from_system() + 3600.0
	assert(state.mark_monster_respawn_dead(913203, "first", 64, "normal_cave", deadline))
	state._process(state.AUTOSAVE_INTERVAL)
	assert(state._json_persistence.pending_count() > 0)
	assert(state.mark_monster_respawn_dead(913203, "second", 64, "normal_cave", deadline))
	state._json_persistence.drain()
	assert(state._world_json_persistence.pending_count() > 0,
		"character writer completion must not also drain the world writer")
	state._world_json_persistence.drain()
	var clock_path: String = state._world_clock_path("periodic", state._world_clock_generation)
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(clock_path))
	assert(checkpoint.world_state.entries.size() == 1 and state._world_clock_dirty)
	assert(state.world_monster_respawn_state.entries.size() == 2)
	state._process(state.AUTOSAVE_INTERVAL)
	state._json_persistence.drain()
	state._world_json_persistence.drain()
	checkpoint = JSON.parse_string(FileAccess.get_file_as_string(clock_path))
	assert(checkpoint.world_state.entries.size() == 2 and not state._world_clock_dirty)
	state.free()
	print("F03_PERIODIC_BACKGROUND_SAVE_PASS")
	get_tree().quit(0)
