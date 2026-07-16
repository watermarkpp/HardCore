extends Node

const TEST_DIRECTORY := "user://character_test_profiles"
const TEST_INDEX := "user://character_test_index.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.test_mode = false
	assert(PlayerState.create_character("长风", "战士", "男").is_empty())
	var first_id: String = PlayerState.active_profile_id
	PlayerState.level = 12
	PlayerState.gold = 3456
	PlayerState.update_world_location(217, Vector2(321.5, -84.0))
	PlayerState.save_game()
	assert(PlayerState.create_character("红叶", "战士", "女").is_empty())
	var second_id: String = PlayerState.active_profile_id
	assert(first_id != second_id, "多角色档案ID重复")
	var profiles: Array[Dictionary] = PlayerState.list_characters()
	assert(profiles.size() == 2, "角色索引未保存两个档案")
	assert(PlayerState.select_character(first_id), "无法选择第一个角色")
	assert(PlayerState.character_name == "长风" and PlayerState.level == 12 and PlayerState.gold == 3456, "角色独立数据恢复失败")
	assert(PlayerState.saved_map_id == 217 and PlayerState.saved_position.is_equal_approx(Vector2(321.5, -84.0)), "角色最近活动位置记录失败")
	var expected_home := MapCoordinateMapper.source_to_world(Vector2(289, 618), Vector2i(700, 700))
	assert(PlayerState.save_safe_logout(4, expected_home), "安全退出未立即写入存档")
	PlayerState.saved_map_id = 217
	PlayerState.saved_position = Vector2.ZERO
	assert(PlayerState.select_character(first_id), "安全退出后无法重载角色")
	assert(PlayerState.saved_map_id == 4 and PlayerState.saved_position.is_equal_approx(expected_home), "退出后没有强制回到最近城镇")
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + first_id + ".json.bak"), "原子存档备份未生成")
	var launcher: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	await get_tree().process_frame
	assert(launcher.get("list_box") != null and launcher.get("name_input") != null, "角色选择画面未正确构建")
	launcher.queue_free()
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.test_mode = old_test_mode
	PlayerState.active_profile_id = ""
	_cleanup()
	print("MULTI_CHARACTER_SAVE_PASS：角色选择、双档隔离、原子写入与备份正常")
	get_tree().quit(0)


func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := TEST_INDEX + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(TEST_DIRECTORY)
		if directory != null:
			for file_name: String in directory.get_files():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		DirAccess.remove_absolute(absolute_directory)
