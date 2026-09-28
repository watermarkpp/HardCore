extends Node

const State := preload("res://scripts/player_state.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var state := State.new()
	state.test_mode = false
	var root := "user://f03_cleanup_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "cleanup"
	state.reset_progress(false)
	assert(state.save_game(false))
	var directory: String = state._death_event_directory("cleanup", state._world_clock_generation)
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	for name: String in ["000000000001.json", "000000000002.json", "000000000003.json", "000000000001.json.bak", "1.json", "000000000000.json", "000000000001.tmp"]:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		assert(file != null)
		file.store_string("preserved fixture")
		file.close()
	# A genuine earlier, unapproved file transaction must serialize cleanup.
	var front: RefCounted = state._json_persistence.submit(root.path_join("front.json"), {"path": root.path_join("front.json")}, {"value": 1}, Callable(), Callable(), false, null, Callable(), true)
	assert(state._json_persistence.finish_preparation(front, true).success)
	state._start_world_clock_cleanup({"profile_id": "cleanup", "generation": state._world_clock_generation, "through_sequence": 2})
	for iteration: int in range(20):
		state._json_persistence.pump()
		await get_tree().process_frame
	if bool(state._clock_cleanup_worker.result().finished):
		state.free()
		printerr("F03_ORDERED_CLEANUP_FAIL: cleanup ran past an unapproved earlier transaction")
		get_tree().quit(1)
		return
	assert(FileAccess.file_exists(directory.path_join("000000000001.json")))
	assert(state._json_persistence.finish(front, true).success)
	state._json_persistence.drain()
	var outcome: Dictionary = state._clock_cleanup_worker.result()
	assert(outcome.finished and outcome.success and outcome.removed == 2)
	state._profile_saved_death_event_sequence = 2
	state._profile_backup_death_event_sequence = 2
	state._world_clock_snapshot_sequence = 2
	state._world_clock_backup_sequence = 2
	state._queue_world_clock_cleanup()
	assert(state._json_persistence.pending_count() == 0,
		"completed same-frame cleanup receipt scheduled another filesystem job")
	state._queue_world_clock_cleanup()
	assert(state._json_persistence.pending_count() == 0,
		"unchanged cleanup watermark scheduled another filesystem job")
	assert(not FileAccess.file_exists(directory.path_join("000000000001.json")))
	for name: String in ["000000000003.json", "000000000001.json.bak", "1.json", "000000000000.json", "000000000001.tmp"]:
		assert(FileAccess.get_file_as_string(directory.path_join(name)) == "preserved fixture")
	state.free()
	print("F03_ORDERED_CLEANUP_PASS")
	get_tree().quit(0)
