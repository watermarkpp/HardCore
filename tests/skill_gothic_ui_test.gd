extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/skill_quick_slot_assignment_contract.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 40
	PlayerState.learned_skills = {
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"野蛮冲撞": 3,
		"烈火剑法": 3,
	}
	PlayerState.quick_slots = ["刺杀剑术", "半月弯刀", "烈火剑法", "野蛮冲撞"]
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "技能快捷栏分配契约无法解析")
	assert(contract.get("contractId", "") == "ui.skill.quick_slot_assignment.v1", "技能快捷栏分配契约 ID 不稳定")
	assert("never decides" in str(contract.get("policy", "")), "UI 不应决定技能放置资格")
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	await get_tree().process_frame

	assert(panel.size == Vector2(1208, 650), "技能面板没有使用既定横屏尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "技能面板没有使用公共哥特外框")
	assert(panel.get_node("SkillListPanel").theme_type_variation == "GothicInsetFrame", "技能列表没有使用公共内框")
	assert(panel.get_node("SkillDetailPanel").theme_type_variation == "GothicInsetFrame", "技能详情没有使用公共内框")
	assert(panel.get_node("AssignmentPanel").theme_type_variation == "GothicInsetFrame", "快捷技能配置没有使用公共内框")
	assert(panel.skill_entries.size() == 6 and panel.skill_buttons.size() == 6, "战士技能列表没有显示 6 项")
	assert(panel.assignment_buttons.size() == 3, "技能页面必须只配置右下三个战斗技能按钮")
	assert(panel.assignment_buttons[0].get_meta("skill_name", "") == "刺杀剑术", "技能按钮 1 没有读取人物快捷栏")
	assert(panel.assignment_buttons[1].get_meta("skill_name", "") == "半月弯刀", "技能按钮 2 没有读取人物快捷栏")
	assert(panel.assignment_buttons[2].get_meta("skill_name", "") == "烈火剑法", "技能按钮 3 没有读取人物快捷栏")

	var thrusting_index := -1
	for index in range(panel.skill_entries.size()):
		if str(panel.skill_entries[index].get("skillName", "")) == "刺杀剑术":
			thrusting_index = index
			break
	assert(thrusting_index >= 0, "技能面板缺少刺杀剑术")
	panel._on_skill_selected(thrusting_index)
	assert(panel.skill_name_label.text == "刺杀剑术", "选择技能后名称没有更新")
	assert("等级：" in panel.detail_label.text, "技能详情缺少等级")
	assert("熟练度：" in panel.detail_label.text, "技能详情缺少熟练度")
	assert("消耗：" in panel.detail_label.text, "技能详情缺少消耗")
	assert("冷却：" in panel.detail_label.text, "技能详情缺少冷却")
	assert("范围：" in panel.detail_label.text, "技能详情缺少范围")
	assert("warrior.thrusting" in panel.description_label.text, "技能详情缺少稳定技能 ID")
	assert(panel.skill_icon.texture != null, "正式战士技能没有显示技能素材")
	assert(is_equal_approx(panel._long_press_timer.wait_time, 0.48), "技能长按时间没有遵守触控规范")

	panel._open_assignment_popup_for(thrusting_index)
	assert(panel.assignment_popup.visible, "长按技能使用的分配弹窗没有打开")
	assert(panel.assignment_popup.get_meta("skill_id", "") == "warrior.thrusting", "分配弹窗没有保留稳定技能 ID")
	var assignment_requests: Array[Dictionary] = []
	panel.quick_slot_assignment_requested.connect(
		func(request: Dictionary) -> void: assignment_requests.append(request.duplicate(true))
	)
	var old_quick_slots := PlayerState.quick_slots.duplicate()
	panel._assign_selected_to_slot(1)
	assert(assignment_requests.size() == 1, "选择技能按钮后没有发出结构化分配请求")
	assert(assignment_requests[0].get("contract_id", "") == "ui.skill.quick_slot_assignment.v1", "技能分配契约 ID 错误")
	assert(assignment_requests[0].get("skill_id", "") == "warrior.thrusting", "技能分配请求技能 ID 错误")
	assert(assignment_requests[0].get("slot_index", -1) == 1, "技能分配请求槽位错误")
	assert(PlayerState.quick_slots == old_quick_slots, "UI 不应自行改写玩法层快捷栏")
	print("SKILL_GOTHIC_UI_PASS：公共 Theme、完整技能资料、三个快捷位与长按分配契约均正常")
	get_tree().quit(0)
