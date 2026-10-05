extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = ProfessionRules.profession_display_name("warrior")

	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	var refresh_before_burst := panel._refresh_execution_count
	for _burst_index in range(4):
		PlayerState.skills_changed.emit()
		PlayerState.inventory_changed.emit()
	assert(panel._refresh_execution_count == refresh_before_burst, "技能/背包信号 burst 在同帧重复刷新")
	await get_tree().process_frame
	assert(panel._refresh_execution_count == refresh_before_burst + 1, "技能/背包信号 burst 未合并为一次刷新")
	assert(panel._layout_apply_count == 1, "技能面板重复打开/刷新重复应用布局")

	var skill_id := "warrior.thrusting"
	var selected_index := -1
	for index: int in range(panel.skill_entries.size()):
		var skill_name := str(panel.skill_entries[index].get("skillName", ""))
		if ProfessionRules.skill_id(skill_name) == skill_id:
			selected_index = index
			break
	assert(selected_index >= 0, "技能面板缺少刺杀剑术条目")

	panel._on_skill_selected(selected_index)
	var skill_name := str(panel.skill_entries[selected_index].get("skillName", ""))
	var combat := ProfessionRules.skill_combat_profile(skill_name)
	var maximum_range_gu := float(combat.get("maximum_range_gu", -1.0))
	assert(maximum_range_gu > 0.0, "正式技能接口缺少 maximum_range_gu")
	assert("3 格直线" in panel.description_label.text, "readable description lost formal thrust range")
	assert(not "GU" in panel.detail_label.text and not "熟练度" in panel.detail_label.text)
	# User now requires effects to reflect equipment's effective cast rank.
	PlayerState.learned_skills = {"hc.skill.warrior.thrusting": 3}
	panel._rebuild_skill_cards()
	panel._show_skill_detail(selected_index)
	var base_description := panel.description_label.text
	PlayerState.computed_stats["skill_level_affix"] = {
		"contributions": {"skill:warrior.thrusting": 2}, "legacy": {},
	}
	assert(PlayerState.effective_skill_level(skill_name) == 5)
	panel._rebuild_skill_cards()
	panel._show_skill_detail(selected_index)
	assert("5 级（基础 3 级）" in panel.detail_label.text)
	assert("Lv.5" in (panel.skill_buttons[selected_index].get_node("CenteredText") as Label).text)
	assert(panel.description_label.text != base_description)
	assert("121.0%" in panel.description_label.text)

	var source := FileAccess.get_file_as_string("res://scripts/skill_panel.gd")
	assert(source.contains('SkillDescription.describe('), "技能面板没有使用正式运行时说明")
	assert(not source.contains('combat.get("range"'), "技能面板仍保留无单位射程 fallback")

	print("SKILL_PANEL_COMBAT_UNIT_PASS: canonical readable range and effective rank; refresh coalescing preserved")
	get_tree().quit(0)
