extends Node


func _ready() -> void:
	var profession_ids := {}
	var skill_ids := {}
	var level_counts := {}
	for row: Variant in GameData.skills:
		assert(row is Dictionary, "技能记录格式错误")
		var profession_name := str(row.get("profession", ""))
		var profession_id := str(row.get("profession_id", ""))
		var skill_name := str(row.get("skillName", ""))
		var skill_id := str(row.get("skill_id", ""))
		assert(not profession_id.is_empty() and profession_id == ProfessionRules.profession_id(profession_name), "%s职业ID无效" % skill_name)
		assert(not skill_id.is_empty() and skill_id == ProfessionRules.skill_id(skill_name), "%s技能ID无效" % skill_name)
		assert(ProfessionRules.profession_display_name(profession_id) == profession_name, "%s职业ID不能反查" % profession_id)
		assert(ProfessionRules.skill_display_name(skill_id) == skill_name, "%s技能ID不能反查" % skill_id)
		assert(str(row.get("display_name", "")) == skill_name, "%s显示名缺失" % skill_id)
		var trace: Dictionary = row.get("source_trace", {})
		for field: String in ["required_character_level", "training_points", "mana_cost", "server_delay"]:
			assert(trace.has(field), "%s缺少%s追溯" % [skill_id, field])
		profession_ids[profession_id] = true
		skill_ids[skill_id] = true
		level_counts[skill_id] = int(level_counts.get(skill_id, 0)) + 1
	assert(profession_ids.size() == 3, "稳定职业ID应为3个")
	assert(skill_ids.size() == 33, "稳定技能ID应为33个")
	for skill_id: String in level_counts:
		assert(int(level_counts[skill_id]) == 4, "%s应有0—3级四条记录" % skill_id)
	var stable_profile := ProfessionRules.skill_combat_profile("wizard.lightning", 3)
	var legacy_profile := ProfessionRules.skill_combat_profile("雷电术", 3)
	assert(stable_profile == legacy_profile and stable_profile.skill_id == "wizard.lightning", "稳定ID和中文别名没有解析到同一档案")
	print("PROFESSION_SKILL_ID_PASS：3职业、33技能、132等级记录稳定ID与字段追溯完整")
	get_tree().quit(0)
