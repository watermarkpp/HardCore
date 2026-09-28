extends Node

const State := preload("res://scripts/player_state.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	var root := "user://consumable_latency_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.test_mode = false
	assert(PlayerState.create_character("药剂耗时", "战士", "男").is_empty())
	var potion := GameData.get_item_record("金创药(小量)")
	assert(str(potion.get("kind", "")) == "consumable", str(potion))
	PlayerState.inventory = [{"name": "金创药(小量)", "count": 8}]
	assert(PlayerState.save_game())
	var entries: Dictionary = {}
	for slot in 500:
		var slot_id := "probe_%d" % slot
		entries["910001|%s" % slot_id] = {
			"runtime_map_id": 910001, "spawn_slot_id": slot_id,
			"monster_id": 24, "policy_id": "normal_cave",
			"respawn_at_unix": Time.get_unix_time_from_system() + 480.0,
		}
	PlayerState.world_monster_respawn_state["entries"] = entries
	PlayerState._world_clock_dirty = true
	var clock_checkpoint_before := PlayerState._world_clock_snapshot_sequence
	var samples: Array[Dictionary] = []
	for index in 5:
		var started := Time.get_ticks_usec()
		var result := PlayerState.use_inventory_index_result(0)
		assert(bool(result.get("success", false)), str(result))
		assert(PlayerState._world_clock_dirty and PlayerState._world_clock_snapshot_sequence == clock_checkpoint_before,
			"consumable write unexpectedly checkpointed all monster clocks")
		samples.append({
			"ordinal": index,
			"total_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"save": PlayerState._last_save_phase_profile.duplicate(true),
		})
	assert(int((PlayerState.inventory[0] as Dictionary).get("count", 0)) == 3)
	print("CONSUMABLE_SAVE_LATENCY ", JSON.stringify(samples))
	var recovery_root := root + "_recovery"
	var state := State.new()
	state.profile_directory = recovery_root.path_join("characters")
	state.profile_index_path = recovery_root.path_join("profiles.json")
	state.active_profile_id = "recovery"
	state.test_mode = false
	state.reset_progress(false)
	state.inventory = [{"name": "金创药(小量)", "count": 4}]
	assert(state.save_game(false))
	assert(state.record_kills_and_experience_batch([{"monster_name": "稻草人", "experience": 1}], true).success)
	assert(state._world_clock_dirty and state._death_event_sequence == 1)
	var after_death_samples: Array[float] = []
	for _use in 2:
		var use_started_usec := Time.get_ticks_usec()
		assert(state.use_inventory_index_result(0).success)
		after_death_samples.append(float(Time.get_ticks_usec() - use_started_usec) / 1000.0)
	print("CONSUMABLE_AFTER_DEATH_LATENCY ", JSON.stringify(after_death_samples))
	assert(state._world_clock_snapshot_sequence == 0 and state._world_clock_dirty)
	state.world_monster_respawn_state["entries"] = entries.duplicate(true)
	state._world_clock_dirty = true
	var background_start_usec := Time.get_ticks_usec()
	assert(state._start_background_save(false))
	print("BACKGROUND_SAVE_SCHEDULE_MS ",
		float(Time.get_ticks_usec() - background_start_usec) / 1000.0)
	var background_overlap_started_usec := Time.get_ticks_usec()
	assert(state.use_inventory_index_result(0).success)
	print("CONSUMABLE_DURING_BACKGROUND_SAVE_MS ",
		float(Time.get_ticks_usec() - background_overlap_started_usec) / 1000.0)
	state.load_save()
	assert(state.last_load_result.success, str(state.last_load_result))
	assert(state._death_event_sequence == 1 and state.experience == 1,
		"skipping the world checkpoint lost the committed death journal")
	assert(int((state.inventory[0] as Dictionary).get("count", 0)) == 1,
		"the potion count was not committed to the character document")
	state.free()
	print("CONSUMABLE_SAVE_LATENCY_PASS")
	get_tree().quit(0)
