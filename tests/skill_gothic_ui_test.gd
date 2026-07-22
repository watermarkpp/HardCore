extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/skill_button_assignment_contract_v2.json"


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
	assert(contract.get("contractId", "") == "ui.skill.button_assignment.v2", "技能按钮分配契约 ID 不稳定")
	assert("Gameplay skill data owns" in str(contract.get("policy", "")), "技能交互模式必须由玩法技能数据负责")
	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	panel.set_skill_button_assignments({
		"center": ["刺杀剑术", "半月弯刀", "烈火剑法", "野蛮冲撞"],
		"attack_ring": ["野蛮冲撞", "烈火剑法", "刺杀剑术"],
	})
	await get_tree().process_frame

	assert(panel.size == Vector2(1208, 650), "技能面板没有使用既定横屏尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "技能面板没有使用公共哥特外框")
	assert(panel.get_node("SkillListPanel").theme_type_variation == "GothicInsetFrame", "技能列表没有使用公共内框")
	assert(panel.get_node("SkillDetailPanel").theme_type_variation == "GothicInsetFrame", "技能详情没有使用公共内框")
	assert(panel.get_node("AssignmentPanel").theme_type_variation == "GothicInsetFrame", "快捷技能配置没有使用公共内框")
	assert(panel.skill_entries.size() == 6 and panel.skill_buttons.size() == 6, "战士技能列表没有显示 6 项")
	assert(panel.assignment_buttons.size() == 7, "技能页面必须配置中央四槽与攻击环三槽")
	assert(panel.center_assignment_buttons.size() == 4, "中央技能槽数量不是 4")
	assert(panel.attack_ring_assignment_buttons.size() == 3, "攻击环技能槽数量不是 3")
	assert(panel.center_assignment_buttons[0].get_meta("stable_slot_id", "") == "hud.profession_skill.1", "中央技能槽稳定 ID 错误")
	assert(panel.center_assignment_buttons[3].get_meta("stable_slot_id", "") == "hud.profession_skill.4", "中央技能槽 4 稳定 ID 错误")
	assert(panel.attack_ring_assignment_buttons[0].get_meta("stable_slot_id", "") == "hud.attack_ring_skill.1", "攻击环技能槽稳定 ID 错误")
	assert(panel.attack_ring_assignment_buttons[2].get_meta("stable_slot_id", "") == "hud.attack_ring_skill.3", "攻击环技能槽 3 稳定 ID 错误")
	assert(panel.center_assignment_buttons[0].get_meta("skill_name", "") == "刺杀剑术", "中央技能槽 1 没有读取注入配置")
	assert(panel.attack_ring_assignment_buttons[0].get_meta("skill_name", "") == "野蛮冲撞", "攻击环技能槽 1 没有读取独立配置")
	assert(panel._skill_interaction_mode("刺杀剑术") == "toggle", "刺杀剑术应显示开关模式")
	assert(panel._skill_interaction_mode("半月弯刀") == "toggle", "半月弯刀应显示开关模式")
	assert(panel._skill_interaction_mode("烈火剑法") == "toggle", "烈火剑法应显示开关模式")
	assert(panel._skill_interaction_mode("魔法盾") == "toggle", "魔法盾应显示开关模式")
	assert(panel._skill_interaction_mode("火墙") == "click", "火墙应显示点击释放模式")
	assert(panel._skill_interaction_mode("雷电术") == "click", "雷电术应显示点击释放模式")

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
	assert("交互：开关" in panel.detail_label.text, "刺杀剑术详情没有显示开关模式")
	assert("warrior.thrusting" in panel.description_label.text, "技能详情缺少稳定技能 ID")
	assert(panel.skill_icon.texture != null, "正式战士技能没有显示技能素材")
	assert(is_equal_approx(panel._long_press_timer.wait_time, 0.48), "技能长按时间没有遵守触控规范")

	panel._open_assignment_popup_for(thrusting_index)
	assert(panel.assignment_popup.visible, "长按技能使用的分配弹窗没有打开")
	assert(panel.assignment_popup.get_meta("skill_id", "") == "warrior.thrusting", "分配弹窗没有保留稳定技能 ID")
	assert(panel.assignment_popup_buttons.size() == 7, "分配弹窗没有提供全部 7 个目标槽")
	var assignment_requests: Array[Dictionary] = []
	panel.skill_button_assignment_requested.connect(
		func(request: Dictionary) -> void: assignment_requests.append(request.duplicate(true))
	)
	var legacy_requests: Array[Dictionary] = []
	panel.quick_slot_assignment_requested.connect(
		func(request: Dictionary) -> void: legacy_requests.append(request.duplicate(true))
	)
	var old_quick_slots := PlayerState.quick_slots.duplicate()
	panel._assign_selected_to_target("center", 3)
	assert(assignment_requests.size() == 1, "选择技能按钮后没有发出结构化分配请求")
	assert(assignment_requests[0].get("contract_id", "") == "ui.skill.button_assignment.v2", "技能分配契约 ID 错误")
	assert(assignment_requests[0].get("skill_id", "") == "warrior.thrusting", "技能分配请求技能 ID 错误")
	assert(assignment_requests[0].get("slot_group", "") == "center", "中央技能分配请求分组错误")
	assert(assignment_requests[0].get("slot_index", -1) == 3, "中央技能分配请求槽位错误")
	assert(assignment_requests[0].get("slot_id", "") == "hud.profession_skill.4", "中央技能分配请求稳定槽位 ID 错误")
	assert(assignment_requests[0].get("interaction_mode", "") == "toggle", "技能分配请求没有携带开关模式")
	assert(legacy_requests.is_empty(), "中央技能槽不应误发旧攻击环契约")
	panel._assign_selected_to_target("attack_ring", 1)
	assert(assignment_requests.size() == 2, "攻击环技能槽没有发出新版分配请求")
	assert(assignment_requests[1].get("slot_id", "") == "hud.attack_ring_skill.2", "攻击环稳定槽位 ID 错误")
	assert(legacy_requests.size() == 1 and legacy_requests[0].get("slot_index", -1) == 1, "攻击环没有保留旧三槽兼容请求")
	assert(PlayerState.quick_slots == old_quick_slots, "UI 不应自行改写玩法层快捷栏")
	print("SKILL_GOTHIC_UI_PASS：中央4槽、攻击环3槽、技能交互模式与双版本分配契约均正常")
	get_tree().quit(0)
