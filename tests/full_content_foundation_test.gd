extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(ProfessionRules.PROFESSIONS.size() == 3, "三职业目录不完整")
	assert(GameData.get_profession_skills("战士").size() == 6, "战士基准技能数量不符")
	assert(GameData.get_profession_skills("法师").size() == 14, "法师基准技能数量不符")
	assert(GameData.get_profession_skills("道士").size() == 13, "道士基准技能数量不符")
	var missing_skills := ProfessionRules.missing_runtime_skills(GameData.skills)
	assert(missing_skills.is_empty(), "存在未登记运行时类型的技能：%s" % [missing_skills])

	var hp_values: Array[int] = []
	var mp_values: Array[int] = []
	for profession_name: String in ProfessionRules.PROFESSIONS:
		PlayerState.select_profession(profession_name)
		PlayerState.level = 20
		PlayerState.recalculate_stats()
		hp_values.append(int(PlayerState.computed_stats.get("max_hp", 0)))
		mp_values.append(int(PlayerState.computed_stats.get("max_mp", 0)))
	assert(hp_values[0] > hp_values[2] and hp_values[2] > hp_values[1], "三职业生命成长未区分")
	assert(mp_values[1] > mp_values[2] and mp_values[2] > mp_values[0], "三职业魔法成长未区分")

	PlayerState.select_profession("法师")
	PlayerState.level = 50
	PlayerState.add_item("基本剑术")
	assert("只能由战士学习" in PlayerState.learn_skill("基本剑术"), "跨职业技能限制失效")
	PlayerState.add_item("火球术")
	assert(PlayerState.learn_skill("火球术").begins_with("已学会"), "法师技能学习失败")

	var monster_ids := {}
	for monster: Variant in GameData.monsters:
		assert(monster is Dictionary, "怪物记录格式错误")
		var monster_id := int(monster.get("monsterId", -1))
		assert(not monster_ids.has(monster_id), "怪物ID重复：%d" % monster_id)
		monster_ids[monster_id] = true
	for boss: Variant in GameData.bosses:
		assert(boss is Dictionary and monster_ids.has(int(boss.get("monsterId", -1))), "Boss无法关联怪物记录")

	print("FULL_CONTENT_FOUNDATION_PASS：三职业、33技能登记与内容引用完整性正常")
	get_tree().quit(0)
