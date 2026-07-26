extends Node


func _ready() -> void:
	var checked := {}
	for row: Variant in GameData.skills:
		if not row is Dictionary:
			continue
		var skill_name := str(row.get("skillName", ""))
		if skill_name.is_empty() or checked.has(skill_name):
			continue
		checked[skill_name] = true
		var profile := ProfessionRules.skill_combat_profile(skill_name)
		assert(not profile.is_empty(), "%s缺少手机战斗参数" % skill_name)
		for field in ["cast_type", "target_mode", "range", "search_range", "multiplier", "area_radius", "windup", "hit_frame", "cooldown", "verification"]:
			assert(profile.has(field), "%s缺少字段%s" % [skill_name, field])
		assert(int(profile.get("hit_frame", -1)) >= 0 and int(profile.get("hit_frame", 99)) <= 6, "%s命中帧越界" % skill_name)
		assert(float(profile.get("cooldown", -1.0)) >= 0.0, "%s冷却无效" % skill_name)
	assert(checked.size() == 33, "技能战斗参数应覆盖33种技能")
	var fire := ProfessionRules.skill_combat_profile("烈火剑法", 3)
	assert(int(fire.service_magic_id) == 26 and str(fire.service_mode) == "arm_next_hit", "烈火剑法服务端溯源模式错误")
	assert(str(fire.runtime_activation_mode) == "toggle_auto_use" and str(fire.toggle_state_id) == "warrior.fire_sword.auto_enabled", "烈火自动开关运行时契约错误")
	assert(float(fire.auto_release_cooldown) == 10.0, "烈火自动释放冷却契约错误")
	assert(int(fire.hit_frame) == 2 and float(fire.cooldown) == 0.85 and float(fire.action_duration) == 0.51, "烈火剑法客户端动作基线错误")
	assert(is_equal_approx(WarriorCombatMath.fire_sword_multiplier(3), 2.6), "烈火三级伤害倍率错误")
	var lightning := ProfessionRules.skill_combat_profile("雷电术")
	assert(str(lightning.target_mode) == "single" and float(lightning.search_range) >= float(lightning.range), "雷电术自动选敌范围错误")
	var summon := ProfessionRules.skill_combat_profile("召唤神兽")
	assert(str(summon.target_mode) == "self" and float(summon.search_range) == 0.0, "召唤技能不应自动抢目标")
	print("SKILL_COMBAT_PROFILE_PASS：33技能目标、距离、倍率、范围、前摇、命中帧和冷却基线正常")
	get_tree().quit(0)
