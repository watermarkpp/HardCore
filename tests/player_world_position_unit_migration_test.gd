extends Node

const TEST_DIRECTORY := "user://position_unit_migration_profiles"
const TEST_INDEX := "user://position_unit_migration_index.json"
const LEGACY_PROFILE_ID := "legacy_position_v6"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TEST_DIRECTORY)
	)
	var previous := {
		"profile_directory": PlayerState.profile_directory,
		"profile_index_path": PlayerState.profile_index_path,
		"active_profile_id": PlayerState.active_profile_id,
		"test_mode": PlayerState.test_mode,
	}
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.active_profile_id = LEGACY_PROFILE_ID
	PlayerState.test_mode = false
	var legacy_screen_position_px := Vector2(321.5, -84.0)
	var legacy_payload := {
		"save_version": 6,
		"profile_id": LEGACY_PROFILE_ID,
		"character_name": "旧坐标测试",
		"level": 1,
		"profession": "战士",
		"gender": "男",
		"map_id": 217,
		"position": [legacy_screen_position_px.x, legacy_screen_position_px.y],
	}
	var profile_path := TEST_DIRECTORY + "/" + LEGACY_PROFILE_ID + ".json"
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(legacy_payload))
	file.close()
	PlayerState.load_save()
	assert(PlayerState.saved_position.is_equal_approx(
		legacy_screen_position_px
	))
	assert(not PlayerState.saved_ground_position_gu_valid)
	var migrated_without_map := _read_json(profile_path)
	assert(int(migrated_without_map.save_version) == PlayerState.SAVE_VERSION)
	assert(str(migrated_without_map.position_space_contract_id) == (
		PlayerState.WORLD_POSITION_CONTRACT_ID
	))
	assert(migrated_without_map.position_ground_gu.is_empty())
	# Once GameRoot has loaded the map, it supplies the absolute GU coordinate.
	var resolved_ground_position_gu := Vector2(18.25, 7.75)
	PlayerState.update_world_location(
		217,
		legacy_screen_position_px,
		resolved_ground_position_gu
	)
	PlayerState.save_game()
	var migrated_with_map := _read_json(profile_path)
	assert(Vector2(
		float(migrated_with_map.position_ground_gu[0]),
		float(migrated_with_map.position_ground_gu[1])
	).is_equal_approx(resolved_ground_position_gu))
	PlayerState.profile_directory = str(previous.profile_directory)
	PlayerState.profile_index_path = str(previous.profile_index_path)
	PlayerState.active_profile_id = str(previous.active_profile_id)
	PlayerState.test_mode = bool(previous.test_mode)
	_cleanup()
	print("PLAYER_WORLD_POSITION_UNIT_MIGRATION_PASS: v6 PX remains valid and v7 adds explicit GU")
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed as Dictionary


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var index_path := TEST_INDEX + suffix
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if not DirAccess.dir_exists_absolute(absolute_directory):
		return
	var directory := DirAccess.open(TEST_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			DirAccess.remove_absolute(absolute_directory.path_join(file_name))
	DirAccess.remove_absolute(absolute_directory)
