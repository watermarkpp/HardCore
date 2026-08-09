extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_profile_directory: String = PlayerState.profile_directory
	var original_profile_index_path: String = PlayerState.profile_index_path
	var original_test_mode: bool = PlayerState.test_mode
	var test_directory := "user://safe_logout_atomic_recovery_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	PlayerState.profile_directory = test_directory
	PlayerState.profile_index_path = test_directory + "/profiles.json"
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "atomic_profile"
	PlayerState.character_name = "原子存档回归"
	PlayerState.saved_map_id = 3
	PlayerState.saved_position = Vector2(111.0, 222.0)
	PlayerState.saved_ground_position_gu = Vector2(7.0, 9.0)
	PlayerState.saved_ground_position_gu_valid = true

	# Two valid writes leave both the primary profile and a valid .bak.
	assert(PlayerState.save_game(), "first valid profile write failed")
	assert(PlayerState.save_game(), "second valid profile write failed")
	var profile_path: String = PlayerState._profile_path(
		PlayerState.active_profile_id
	)
	assert(FileAccess.file_exists(profile_path), "primary profile missing")
	assert(FileAccess.file_exists(profile_path + ".bak"), "backup profile missing")

	# An old profile already existing must never turn a new write failure into
	# success, and the tentative Home location must roll back in memory.
	PlayerState._test_force_atomic_write_failure = true
	var safe_logout_ok := PlayerState.save_safe_logout(
		4,
		Vector2(999.0, 888.0),
		Vector2(77.0, 66.0)
	)
	assert(not safe_logout_ok, "existing profile masked atomic write failure")
	assert(PlayerState.saved_map_id == 3, "failed save changed in-memory map")
	assert(
		PlayerState.saved_position == Vector2(111.0, 222.0),
		"failed save changed in-memory screen position"
	)
	assert(
		PlayerState.saved_ground_position_gu == Vector2(7.0, 9.0)
		and PlayerState.saved_ground_position_gu_valid,
		"failed save changed in-memory ground position"
	)
	assert(
		str(PlayerState.last_save_result.get("reason", ""))
		== "atomic_profile_write_failed",
		"write failure did not publish an explicit failure reason"
	)
	var unchanged_primary: Dictionary = PlayerState._read_json_document(
		profile_path
	)
	assert(bool(unchanged_primary.get("valid", false)))
	assert(int(unchanged_primary.data.get("map_id", -1)) == 3)
	assert(unchanged_primary.data.get("position", []) == [111.0, 222.0])

	# A corrupt primary must be restored from the valid backup before loading.
	PlayerState._test_force_atomic_write_failure = false
	var corrupt_file := FileAccess.open(profile_path, FileAccess.WRITE)
	assert(corrupt_file != null, "unable to prepare corrupt-primary fixture")
	corrupt_file.store_string("{not-valid-json")
	corrupt_file.close()
	PlayerState.saved_map_id = 99
	PlayerState.saved_position = Vector2.ZERO
	PlayerState.saved_ground_position_gu = Vector2.ZERO
	PlayerState.saved_ground_position_gu_valid = false
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)))
	assert(
		str(PlayerState.last_load_result.get("reason", ""))
		== "recovered_from_backup",
		"valid backup was not selected for corrupt primary"
	)
	assert(PlayerState.saved_map_id == 3)
	assert(PlayerState.saved_position == Vector2(111.0, 222.0))
	assert(PlayerState.saved_ground_position_gu == Vector2(7.0, 9.0))
	assert(PlayerState.saved_ground_position_gu_valid)
	assert(
		bool(PlayerState._read_json_document(profile_path).get("valid", false)),
		"recovered primary was not valid JSON"
	)

	PlayerState._test_force_atomic_write_failure = false
	PlayerState.active_profile_id = ""
	PlayerState.profile_directory = original_profile_directory
	PlayerState.profile_index_path = original_profile_index_path
	PlayerState.test_mode = original_test_mode
	print(
		"SAFE_LOGOUT_ATOMIC_RECOVERY_PASS: write failure rolled back; "
		+ "corrupt primary recovered from valid backup"
	)
	get_tree().quit(0)
