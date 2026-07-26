extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 40
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {
		"火球术": 2,
		"雷电术": 1,
	}
	PlayerState.active_profile_id = "canonical_skill_progression_test"
	PlayerState.character_name = "熟练度迁移测试"
	PlayerState.save_game()
	var save_path: String = PlayerState._profile_path(PlayerState.active_profile_id)
	var saved: Dictionary = PlayerState._read_json(save_path)
	var snapshot: Dictionary = saved.get("skill_progression", {})
	assert(str(snapshot.get("contract_id", "")) == "skills.progression.cn_mir2_176.v1", "存档缺少canonical熟练度合同")
	var skills: Dictionary = snapshot.get("skills", {})
	assert(int(skills.get("wizard.fireball", {}).get("rank", -1)) == 2, "火球术中文旧名未迁移为稳定ID")
	assert(int(skills.get("wizard.lightning", {}).get("rank", -1)) == 1, "雷电术中文旧名未迁移为稳定ID")

	saved.erase("skill_progression")
	saved["learned_skills"] = {"火球术": 3, "雷电术": 2}
	assert(PlayerState._write_json_atomic(save_path, saved), "无法写入旧中文名迁移样本")
	PlayerState.load_save()
	var migrated := PlayerState.skill_progression_snapshot()
	assert(int(migrated.get("skills", {}).get("wizard.fireball", {}).get("rank", -1)) == 3, "旧存档火球术未迁移")
	assert(int(PlayerState.learned_skills.get("火球术", -1)) == 3, "canonical snapshot未保留现有UI中文视图")

	var absolute_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(absolute_path)
	var backup_path := "%s.bak" % absolute_path
	if FileAccess.file_exists("%s.bak" % save_path):
		DirAccess.remove_absolute(backup_path)
	PlayerState.active_profile_id = ""
	print("SKILL_PROGRESSION_SAVE_INTEGRATION_PASS")
	get_tree().quit(0)
