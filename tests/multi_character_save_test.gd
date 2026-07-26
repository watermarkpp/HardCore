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
	PlayerState.learned_skills = {"烈火剑法": 3, "野蛮冲撞": 3}
	var slot_result := SkillLoadoutRules.assign_quick_slot(PlayerState.quick_slots, PlayerState.learned_skills, {
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "attack_ring",
		"slot_index": 2,
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.apply_quick_slot_assignment(slot_result), "玩法层无法应用野蛮冲撞快捷槽置换")
	assert(PlayerState.apply_warrior_runtime_state({
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"toggles": {
			"warrior.thrusting": true,
			"warrior.half_moon": false,
			"warrior.fire_sword.auto_enabled": true,
		},
		"cooldowns": {"warrior.fire_sword.ready_remaining_ms": 4321},
	}), "战士技能运行时快照无法写入PlayerState")
	PlayerState.update_world_location(217, Vector2(321.5, -84.0))
	PlayerState.save_game()
	assert(PlayerState.create_character("红叶", "战士", "女").is_empty())
	var second_id: String = PlayerState.active_profile_id
	assert(first_id != second_id, "多角色档案ID重复")
	assert(not bool(PlayerState.warrior_runtime_state_for_restore().toggles["warrior.fire_sword.auto_enabled"]), "新角色错误继承上一角色烈火开关")
	var profiles: Array[Dictionary] = PlayerState.list_characters()
	assert(profiles.size() == 2, "角色索引未保存两个档案")
	assert(PlayerState.select_character(first_id), "无法选择第一个角色")
	assert(PlayerState.character_name == "长风" and PlayerState.level == 12 and PlayerState.gold == 3456, "角色独立数据恢复失败")
	assert(PlayerState.quick_slots[2] == "野蛮冲撞", "野蛮冲撞快捷槽置换未从存档恢复")
	var restored_runtime := PlayerState.warrior_runtime_state_for_restore()
	assert(bool(restored_runtime.toggles["warrior.fire_sword.auto_enabled"]), "烈火自动开关未从角色存档恢复")
	assert(int(restored_runtime.cooldowns["warrior.fire_sword.ready_remaining_ms"]) == 4321, "烈火冷却剩余时间未从角色存档恢复")
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
