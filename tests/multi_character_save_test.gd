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
	var slot_result := SkillLoadoutRules.assign_button_slot(PlayerState.skill_button_assignments_snapshot(), PlayerState.learned_skills, {
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack_ring",
		"slot_index": 2,
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.apply_skill_button_assignment(slot_result), "玩法层无法应用野蛮冲撞六环槽置换")
	assert(PlayerState.apply_warrior_runtime_state({
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"toggles": {
			"warrior.thrusting": true,
			"warrior.half_moon": false,
			"warrior.fire_sword.auto_enabled": true,
		},
		"cooldowns": {"warrior.fire_sword.ready_remaining_ms": 4321},
	}), "战士技能运行时快照无法写入PlayerState")
	var field_ground_position_gu := Vector2(17.25, 8.5)
	PlayerState.update_world_location(
		217,
		Vector2(321.5, -84.0),
		field_ground_position_gu
	)
	PlayerState.save_game()
	assert(PlayerState.create_character("红叶", "战士", "女").is_empty())
	var second_id: String = PlayerState.active_profile_id
	assert(first_id != second_id, "多角色档案ID重复")
	assert(not bool(PlayerState.warrior_runtime_state_for_restore().toggles["warrior.fire_sword.auto_enabled"]), "新角色错误继承烈火旧自动开关")
	assert(
		PlayerState.taoist_main_pet_runtime_state_for_restore().is_empty(),
		"新角色错误继承旧召唤物"
	)
	var second_path := TEST_DIRECTORY + "/" + second_id + ".json"
	var missing_field_payload: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(second_path)
	)
	assert(missing_field_payload is Dictionary)
	assert(int(missing_field_payload.get("save_version", 0)) == 9)
	assert(
		not (missing_field_payload as Dictionary).has(
			"taoist_main_pet_runtime_state"
		),
		"empty optional summon field should not be serialized"
	)
	PlayerState.load_save()
	assert(
		PlayerState.taoist_main_pet_runtime_state_for_restore().is_empty(),
		"v9 save without optional summon field did not load compatibly"
	)
	# Character creation is still warrior-only; switch the test profile to the
	# already-supported Taoist runtime before attaching its summon snapshot.
	PlayerState.profession = "道士"
	var summon_snapshot := {
		"contract_id": "skills.summon.persistence.runtime_state.v1",
		"alive": true,
		"runtime_state": "FOLLOW_OWNER",
		"summon_id": "divine_beast",
		"skill_id": "taoist.summon_divine_beast",
		"skill_rank": 3,
		"owner_level": 40,
		"current_hp": 731,
		"max_hp": 840,
		"summon_exp_level": 3,
		"maximum_pet_level": 7,
		"pet_growth_exp": 88,
		"remaining_lifetime": 4567.5,
		"stealth": {
			"remaining_seconds": 7.5,
			"buff_id": "buff.taoist.mass_invisibility",
		},
		"physical_defence": {
			"bonus": 4,
			"remaining_seconds": 8.5,
			"buff_id": "buff.taoist.defense",
		},
		"magic_defence": {
			"bonus": 5,
			"remaining_seconds": 9.5,
			"buff_id": "buff.taoist.magic_defense",
		},
	}
	assert(PlayerState.apply_taoist_main_pet_runtime_state(summon_snapshot))
	assert(PlayerState.save_game(), "道士召唤物状态未写入角色存档")
	var profiles: Array[Dictionary] = PlayerState.list_characters()
	assert(profiles.size() == 2, "角色索引未保存两个档案")
	assert(PlayerState.select_character(first_id), "无法选择第一个角色")
	assert(PlayerState.character_name == "长风" and PlayerState.level == 12 and PlayerState.gold == 3456, "角色独立数据恢复失败")
	assert(
		PlayerState.taoist_main_pet_runtime_state_for_restore().is_empty(),
		"战士角色错误继承道士召唤物"
	)
	assert(PlayerState.attack_ring_slots[2] == "野蛮冲撞", "野蛮冲撞六环槽未从存档恢复")
	assert(PlayerState.quick_slots[2] == "野蛮冲撞", "野蛮冲撞快捷槽置换未从存档恢复")
	var restored_runtime := PlayerState.warrior_runtime_state_for_restore()
	assert(bool(restored_runtime.toggles["warrior.fire_sword.auto_enabled"]), "烈火开关未随角色存档恢复")
	assert(not restored_runtime.cooldowns.has("warrior.fire_sword.ready_remaining_ms"), "旧存档烈火自动冷却被错误恢复")
	assert(PlayerState.saved_map_id == 217 and PlayerState.saved_position.is_equal_approx(Vector2(321.5, -84.0)), "角色最近活动位置记录失败")
	assert(
		PlayerState.saved_ground_position_gu_valid
		and PlayerState.saved_ground_position_gu.is_equal_approx(
			field_ground_position_gu
		),
		"角色最近活动地面GU坐标未独立保存"
	)
	var expected_home := MapCoordinateMapper.source_to_world(Vector2(289, 618), Vector2i(700, 700))
	var expected_home_ground_gu := Vector2(289, 618)
	assert(PlayerState.save_safe_logout(
		4,
		expected_home,
		expected_home_ground_gu
	), "安全退出未立即写入存档")
	PlayerState.saved_map_id = 217
	PlayerState.saved_position = Vector2.ZERO
	PlayerState.saved_ground_position_gu = Vector2.ZERO
	PlayerState.saved_ground_position_gu_valid = false
	assert(PlayerState.select_character(first_id), "安全退出后无法重载角色")
	assert(PlayerState.saved_map_id == 4 and PlayerState.saved_position.is_equal_approx(expected_home), "退出后没有强制回到最近城镇")
	assert(
		PlayerState.saved_ground_position_gu_valid
		and PlayerState.saved_ground_position_gu.is_equal_approx(
			expected_home_ground_gu
		),
		"退出后的地面GU坐标未恢复"
	)
	assert(FileAccess.file_exists(TEST_DIRECTORY + "/" + first_id + ".json.bak"), "原子存档备份未生成")
	assert(PlayerState.select_character(second_id), "无法重载道士角色")
	_assert_summon_snapshot_equal(
		PlayerState.taoist_main_pet_runtime_state_for_restore(),
		summon_snapshot
	)
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
	print("MULTI_CHARACTER_SAVE_PASS：角色选择、双档隔离、召唤状态、原子写入与备份正常")
	get_tree().quit(0)


func _assert_summon_snapshot_equal(actual: Dictionary, expected: Dictionary) -> void:
	for key: String in [
		"contract_id", "alive", "runtime_state", "summon_id", "skill_id",
		"skill_rank", "owner_level", "current_hp", "max_hp",
		"summon_exp_level", "maximum_pet_level", "pet_growth_exp",
		"remaining_lifetime",
	]:
		assert(
			actual.get(key) == expected.get(key),
			"召唤物持久化字段未恢复：%s" % key
		)
	for buff_key: String in ["stealth", "physical_defence", "magic_defence"]:
		var actual_buff: Dictionary = actual.get(buff_key, {})
		var expected_buff: Dictionary = expected.get(buff_key, {})
		for field: String in ["bonus", "remaining_seconds", "buff_id"]:
			if expected_buff.has(field):
				assert(
					actual_buff.get(field) == expected_buff.get(field),
					"召唤物buff字段未恢复：%s.%s" % [buff_key, field]
				)


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
