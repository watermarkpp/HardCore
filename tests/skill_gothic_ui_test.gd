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
	assert("active_charge" in contract.get("assignmentInput", {}).get("interactionModes", []), "技能按钮契约没有声明主动充能模式")
	var fire_charge_contract: Dictionary = contract.get("runtimeStateDisplay", {}).get("fireSwordCharge", {})
	assert(fire_charge_contract.get("stableSkillId", "") == "warrior.fire_sword", "烈火 UI 没有绑定稳定技能 ID")
	assert(fire_charge_contract.get("armedField", "") == "fire_armed", "烈火 UI 没有绑定一次性充能状态")
	assert(fire_charge_contract.get("cooldownRemainingField", "") == "fire_ready_remaining_ms", "烈火 UI 没有绑定冷却剩余状态")
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
	assert(panel.assignment_scrim.theme_type_variation == "GothicModalScrim", "快捷技能弹窗遮罩没有使用透明的公共模态拦截层")
	assert(panel.assignment_scrim.mouse_filter == Control.MOUSE_FILTER_STOP, "快捷技能弹窗遮罩没有阻止点击穿透")
	var scrim_style := panel.assignment_scrim.get_theme_stylebox("panel")
	assert(scrim_style is StyleBoxFlat and is_zero_approx(scrim_style.bg_color.a), "全屏点击拦截层不应绘制超出弹窗外框的实体背景")
	assert(panel.assignment_popup.theme_type_variation == "GothicModalFrame", "快捷技能弹窗没有复用公共 Gothic 外框")
	var popup_surface: Panel = panel.assignment_popup.get_node("PopupSurface")
	assert(popup_surface.theme_type_variation == "GothicModalSurface", "快捷技能弹窗缺少足够遮蔽典籍页面的内背景")
	assert(popup_surface.position == Vector2.ZERO, "快捷技能弹窗实体背景没有从外框原点开始")
	assert(popup_surface.size == panel.assignment_popup.size, "快捷技能弹窗实体背景范围与外框不一致")
	assert(popup_surface.get_global_rect().is_equal_approx(panel.assignment_popup.get_global_rect()), "快捷技能弹窗实体背景越过外框边界")
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
	panel.set_skill_button_assignments({}, {"warrior.fire_sword": "toggle"})
	assert(panel._skill_interaction_mode("烈火剑法") == "active_charge", "烈火剑法必须忽略陈旧开关注入并显示主动充能")
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

	var fire_index := -1
	for index in range(panel.skill_entries.size()):
		if str(panel.skill_entries[index].get("skillName", "")) == "烈火剑法":
			fire_index = index
			break
	assert(fire_index >= 0, "技能面板缺少烈火剑法")
	panel._on_skill_selected(fire_index)
	assert("交互：充能" in panel.detail_label.text, "烈火详情仍显示为开关而非主动充能")

	panel._open_assignment_popup_for(thrusting_index)
	assert(panel.assignment_popup.visible, "长按技能使用的分配弹窗没有打开")
	assert(panel.assignment_scrim.visible, "技能配置弹窗打开时没有显示模态遮罩")
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

	var replacement_skills := ["野蛮冲撞", "烈火剑法", "半月弯刀", "刺杀剑术"]
	for slot_index in range(4):
		var replacement_index := -1
		for index in range(panel.skill_entries.size()):
			if str(panel.skill_entries[index].get("skillName", "")) == replacement_skills[slot_index]:
				replacement_index = index
				break
		assert(replacement_index >= 0, "四槽置换测试缺少已学技能：%s" % replacement_skills[slot_index])
		panel._open_assignment_popup_for(replacement_index)
		# 弹窗打开后即锁定待配置技能，后续刷新或选择变化不得串到别的技能。
		panel.selected_skill_index = (replacement_index + 1) % panel.skill_entries.size()
		panel._assign_selected_to_target("center", slot_index)
		var request: Dictionary = assignment_requests.back()
		assert(request.get("skill_name", "") == replacement_skills[slot_index], "中央快捷槽置换丢失弹窗锁定的技能")
		if replacement_skills[slot_index] == "烈火剑法":
			assert(request.get("interaction_mode", "") == "active_charge", "烈火快捷槽请求不得回退到开关模式")
		assert(request.get("slot_index", -1) == slot_index, "中央快捷槽置换发送了错误槽位")
		assert(request.get("slot_id", "") == "hud.profession_skill.%d" % (slot_index + 1), "中央快捷槽置换稳定 ID 错误")
		assert(not panel.assignment_popup.visible and not panel.assignment_scrim.visible, "置换完成后模态弹窗未正确关闭")
	assert(assignment_requests.size() == 6, "四个中央快捷槽没有逐一发出置换请求")
	assert(PlayerState.quick_slots == old_quick_slots, "四槽置换 UI 不应绕过玩法接口直接改写状态")
	print("SKILL_GOTHIC_UI_PASS：中央4槽、攻击环3槽、技能交互模式与双版本分配契约均正常")
	get_tree().quit(0)
