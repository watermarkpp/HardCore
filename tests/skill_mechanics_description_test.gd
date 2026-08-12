extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var frame := panel.get_node("SkillDetailPanel/SkillDetailV3Frame")
	assert(frame.get_parent().get_child(0) == frame and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var fill := frame.get_node("SkillDetailV3FrameDecoration/SkillDetailV3FrameFill")
	assert(fill.shape_mode == GothicFrameFill.ShapeMode.V3_INNER and fill.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var cases := {
		"warrior.fire_sword": ["倍"], "warrior.slaying_swordsmanship": ["基础物理伤害+", "触发概率"], "warrior.thrusting": ["刺杀", "基础伤害"],
		"warrior.half_moon": ["半月", "基础伤害"], "warrior.wild_rush": ["成功率", "等级"], "warrior.basic_swordsmanship": ["每级准确+3", "当前准确+0"],
		"wizard.magic_shield": ["承受", "减伤"], "wizard.fire_wall": ["持续", "3000"], "wizard.temptation_light": ["成功概率"],
		"taoist.poison": ["毒伤", "抗毒"], "taoist.defense": ["防御"], "taoist.summon_skeleton": ["召唤物等级", "存在时间"]
	}
	for skill_id in cases:
		var name := ProfessionRules.skill_display_name(skill_id)
		var row := GameData.get_skill(name, 0)
		var combat := ProfessionRules.skill_combat_profile(name, 0)
		var text := panel._player_mechanics_description(row, combat)
		for token in cases[skill_id]: assert(str(text).contains(token), "%s missing %s: %s" % [skill_id, token, text])
		for forbidden in ["技能ID", "来源", "可信度", "formula_id", "source_anchor", "source_", "confidence", "random_range", "random", "round", "get_power", "_formula"]: assert(not str(text).contains(forbidden), "%s leaked %s" % [skill_id, forbidden])
	print("SKILL_MECHANICS_DESCRIPTION_PASS")
	get_tree().quit(0)
