extends Node


func _ready() -> void:
	var original_persistence := {
		"profile_directory": PlayerState.profile_directory,
		"profile_index_path": PlayerState.profile_index_path,
		"shared_warehouse_path": PlayerState.shared_warehouse_path,
		"transaction_path": PlayerState.shared_warehouse_transaction_log_path,
		"initialized": PlayerState._shared_warehouse_initialized,
	}
	var test_root := "user://skill_progression_save_isolated_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = test_root.path_join("characters")
	PlayerState.profile_index_path = test_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = test_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = test_root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 40
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {
		"火球术": 2,
		"雷电术": 1,
	}
	PlayerState.active_profile_id = "canonical_skill_progression_test"
	PlayerState.character_name = "成长迁移测试"
	PlayerState.attack_ring_slots = ["火球术", "雷电术", "", "", "", ""]
	PlayerState._sync_legacy_quick_slots_from_ring()
	PlayerState.save_game()
	var save_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var saved: Dictionary = PlayerState._read_json(save_path)
	assert(int(saved.get("save_version", 0)) == PlayerState.SAVE_VERSION, "SAVE_VERSION 未升级到 v8")
	var snapshot: Dictionary = saved.get("skill_progression", {})
	assert(
		str(snapshot.get("contract_id", "")) == "skills.progression.hardcore.v2",
		"v8 存档缺少 hardcore.v2 进度合同"
	)
	var skills: Dictionary = snapshot.get("skills", {})
	assert(int(skills.get("wizard.fireball", {}).get("base_rank", -1)) == 2, "火球术 base_rank 未写入")
	assert(int(skills.get("wizard.lightning", {}).get("base_rank", -1)) == 1, "雷电术 base_rank 未写入")
	assert(not (skills.get("wizard.fireball", {}) as Dictionary).has("current_proficiency"), "v8 不得持久化熟练度")

	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	assert(PlayerState.attack_ring_slots == ["火球术", "雷电术", "", "", "", ""], "v8 重载丢失技能按钮绑定")
	assert(PlayerState.quick_slots[0] == "火球术" and PlayerState.quick_slots[1] == "雷电术", "v8 重载丢失 quick slots")
	assert(int(PlayerState.learned_skills.get("火球术", -1)) == 2, "v8 重载丢失中文旧兼容视图")

	_assert_legacy_chinese_migration(save_path)
	_assert_v1_canonical_migration(save_path)
	_assert_base_rank_bounds(save_path)

	var absolute_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(absolute_path)
	if FileAccess.file_exists("%s.bak" % save_path):
		DirAccess.remove_absolute("%s.bak" % absolute_path)
	PlayerState.active_profile_id = ""
	_cleanup_isolated_persistence(test_root)
	PlayerState.profile_directory = str(original_persistence.profile_directory)
	PlayerState.profile_index_path = str(original_persistence.profile_index_path)
	PlayerState.shared_warehouse_path = str(original_persistence.shared_warehouse_path)
	PlayerState.shared_warehouse_transaction_log_path = str(original_persistence.transaction_path)
	PlayerState._shared_warehouse_initialized = bool(original_persistence.initialized)
	print("SKILL_PROGRESSION_SAVE_INTEGRATION_PASS")
	get_tree().quit(0)


func _assert_legacy_chinese_migration(save_path: String) -> void:
	var saved: Dictionary = PlayerState._read_json(save_path)
	saved.erase("skill_progression")
	saved["learned_skills"] = {"火球术": 3, "雷电术": 2}
	saved["save_version"] = 7
	assert(PlayerState._write_json_atomic(save_path, saved), "无法写入旧中文名迁移样本")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	var migrated := PlayerState.skill_progression_snapshot()
	var migrated_skills: Dictionary = migrated.get("skills", {})
	assert(int(migrated_skills.get("wizard.fireball", {}).get("base_rank", -1)) == 3, "旧中文名火球术未迁移")
	assert(int(migrated_skills.get("wizard.lightning", {}).get("base_rank", -1)) == 2, "旧中文名雷电术未迁移")
	assert(int(PlayerState.learned_skills.get("火球术", -1)) == 3, "迁移后中文视图未保留")
	var rewritten: Dictionary = PlayerState._read_json(save_path)
	assert(int(rewritten.get("save_version", 0)) == PlayerState.SAVE_VERSION, "旧档未安全重写为 v8")
	assert(
		str(rewritten.get("skill_progression", {}).get("contract_id", ""))
		== "skills.progression.hardcore.v2",
		"旧档重写后不是 hardcore.v2"
	)
	assert(int(rewritten.get("skill_progression", {}).get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1)) == 3, "重写后 base_rank 错误")
	assert(PlayerState.attack_ring_slots == ["火球术", "雷电术", "", "", "", ""], "旧档迁移丢失技能按钮绑定")
	assert(PlayerState.quick_slots[0] == "火球术", "旧档迁移丢失 quick slots")


func _assert_v1_canonical_migration(save_path: String) -> void:
	var saved: Dictionary = PlayerState._read_json(save_path)
	saved["save_version"] = 7
	saved["skill_progression"] = {
		"contract_id": "skills.progression.cn_mir2_176.v1",
		"skills": {
			"wizard.fireball": {"rank": 2, "current_proficiency": 321},
			"wizard.lightning": {"rank": 1, "current_proficiency": 77},
		},
	}
	saved["learned_skills"] = {"火球术": 2, "雷电术": 1}
	assert(PlayerState._write_json_atomic(save_path, saved), "无法写入 v1 canonical 迁移样本")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	var migrated := PlayerState.skill_progression_snapshot()
	var migrated_skills: Dictionary = migrated.get("skills", {})
	assert(int(migrated_skills.get("wizard.fireball", {}).get("base_rank", -1)) == 2, "v1 rank 未转入 base_rank")
	assert(int(migrated_skills.get("wizard.lightning", {}).get("base_rank", -1)) == 1, "v1 rank 未转入 base_rank")
	var rewritten: Dictionary = PlayerState._read_json(save_path)
	assert(int(rewritten.get("save_version", 0)) == PlayerState.SAVE_VERSION, "v1 档未安全重写为 v8")
	var rewritten_skills: Dictionary = rewritten.get("skill_progression", {}).get("skills", {})
	assert(
		not (rewritten_skills.get("wizard.fireball", {}) as Dictionary).has("current_proficiency"),
		"v1 熟练度被持久化"
	)
	assert(not rewritten_skills.has("current_proficiency"), "熟练度字段泄漏到存档")
	assert(PlayerState.attack_ring_slots == ["火球术", "雷电术", "", "", "", ""], "v1 迁移丢失技能按钮绑定")
	assert(PlayerState.quick_slots[0] == "火球术", "v1 迁移丢失 quick slots")


func _assert_base_rank_bounds(save_path: String) -> void:
	var saved: Dictionary = PlayerState._read_json(save_path)
	saved["save_version"] = 7
	saved["skill_progression"] = {"wizard.fireball": 4, "wizard.lightning": -5}
	assert(PlayerState._write_json_atomic(save_path, saved), "无法写入越界 rank 迁移样本")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	var migrated := PlayerState.skill_progression_snapshot()
	var migrated_skills: Dictionary = migrated.get("skills", {})
	assert(int(migrated_skills.get("wizard.fireball", {}).get("base_rank", -1)) == 3, "base_rank 应钳制到 3")
	assert(int(migrated_skills.get("wizard.lightning", {}).get("base_rank", -1)) == 0, "base_rank 应钳制到 0")


func _cleanup_isolated_persistence(root: String) -> void:
	for file_name: String in [
		"profiles.json", "profiles.json.bak", "shared.json", "shared.json.bak",
		"shared.transaction.json", "shared.transaction.json.bak",
	]:
		var path := root.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var characters := root.path_join("characters")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(characters)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(characters))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root))
