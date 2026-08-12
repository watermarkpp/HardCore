extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/skill_button_assignment_contract_v3.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 40
	PlayerState.learned_skills = {
		"基本剑术": 3,
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"野蛮冲撞": 3,
		"烈火剑法": 3,
	}
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary)
	assert(contract.get("contractId", "") == "ui.skill.button_assignment.v3")
	assert(contract.get("assignmentInput", {}).get("groups", {}).get("attack", {}).get("count", 0) == 1)
	assert(contract.get("assignmentInput", {}).get("groups", {}).get("attack_ring", {}).get("count", 0) == 6)
	assert(contract.get("assignmentInput", {}).get("excludedInteractionModes", []) == ["passive"])

	var panel := SkillPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("技能导师")
	panel.set_skill_button_assignments(
		{
			"attack": [""],
			"attack_ring": ["刺杀剑术", "半月弯刀", "烈火剑法", "野蛮冲撞", "", ""],
		},
		{
			"warrior.thrusting": "toggle",
			"warrior.half_moon": "toggle",
			"warrior.fire_sword": "toggle",
		},
	)
	await get_tree().process_frame

	assert(panel.size == Vector2(1208, 650))
	assert(panel.theme_type_variation == "GothicModalFrame")
	assert(panel.center_assignment_buttons.is_empty(), "已取消的中央四技能槽仍然存在")
	assert(panel.attack_assignment_buttons.size() == 1)
	assert(panel.attack_ring_assignment_buttons.size() == 6)
	assert(panel.assignment_buttons.size() == 7)
	assert(panel.assignment_popup_buttons.size() == 7)
	assert(panel.attack_assignment_buttons[0].get_meta("stable_slot_id", "") == "hud.attack.primary")
	for index in range(6):
		assert(
			panel.attack_ring_assignment_buttons[index].get_meta("stable_slot_id", "")
			== "hud.attack_ring_skill.%d" % (index + 1)
		)
	assert(panel._skill_interaction_mode("刺杀剑术") == "toggle")
	assert(panel._skill_interaction_mode("半月弯刀") == "toggle")
	assert(panel._skill_interaction_mode("烈火剑法") == "toggle")
	assert(panel._skill_interaction_mode("野蛮冲撞") == "click")

	var basic_index := _skill_index(panel, "基本剑术")
	assert(basic_index >= 0, "基本剑术没有保留在技能列表")
	panel._on_skill_selected(basic_index)
	assert(panel.skill_buttons[basic_index].get_meta("assignment_eligible", true) == false)
	assert(panel.get_node("AssignmentPanel/AssignmentHint").text != "")
	panel._open_assignment_popup_for(basic_index)
	assert(not panel.assignment_popup.visible, "被动技能错误进入技能绑定弹窗")

	var thrusting_index := _skill_index(panel, "刺杀剑术")
	assert(thrusting_index >= 0)
	panel._on_skill_selected(thrusting_index)
	panel._open_assignment_popup_for(thrusting_index)
	assert(panel.assignment_popup.visible)
	assert(panel.assignment_popup.get_meta("skill_id", "") == "warrior.thrusting")

	var requests: Array[Dictionary] = []
	var legacy_requests: Array[Dictionary] = []
	panel.skill_button_assignment_requested.connect(
		func(request: Dictionary) -> void: requests.append(request.duplicate(true))
	)
	panel.quick_slot_assignment_requested.connect(
		func(request: Dictionary) -> void: legacy_requests.append(request.duplicate(true))
	)
	panel._assign_selected_to_target("attack", 0)
	assert(requests.size() == 1)
	assert(requests[0].contract_id == "ui.skill.button_assignment.v3")
	assert(requests[0].slot_group == "attack" and requests[0].slot_id == "hud.attack.primary")
	assert(requests[0].interaction_mode == "toggle")
	assert(legacy_requests.is_empty(), "V3绑定错误重复发送旧三槽请求")

	panel._open_assignment_popup_for(thrusting_index)
	panel._assign_selected_to_target("attack_ring", 5)
	assert(requests.size() == 2)
	assert(requests[1].slot_group == "attack_ring" and requests[1].slot_index == 5)
	assert(requests[1].slot_id == "hud.attack_ring_skill.6")

	panel._request_clear_target("attack", 0)
	panel._request_clear_target("attack_ring", 5)
	assert(requests.size() == 4)
	assert(requests[2].clear and requests[2].slot_id == "hud.attack.primary")
	assert(requests[2].skill_name.is_empty() and requests[2].interaction_mode == "empty")
	assert(requests[3].clear and requests[3].slot_id == "hud.attack_ring_skill.6")
	assert(panel.get_node("AssignmentPanel/ClearAttackSkillSlot").get_meta("assignment_action", "") == "clear")
	assert(panel.get_node("AssignmentPanel/ClearAttackRingSkillSlot_6").get_meta("assignment_action", "") == "clear")
	# The final card must be fully exposed at the mathematical maximum scroll
	# position for every profession; this guards against profession-specific
	# card-count/layout clipping without naming a particular skill.
	for profession in ["战士", "法师", "道士"]:
		PlayerState.profession = profession
		panel.open_for("技能导师")
		await get_tree().process_frame
		await get_tree().process_frame
		var scroll := panel.get_node("SkillListPanel/SkillListScroll") as ScrollContainer
		var cards := panel.get_node("SkillListPanel/SkillListScroll/SkillCards") as Control
		assert(cards.get_child_count() > 0, "%s 技能列表为空" % profession)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var last_card := cards.get_child(cards.get_child_count() - 1) as Control
		var visible_rect := scroll.get_global_rect()
		if scroll.get_h_scroll_bar().visible:
			visible_rect.size.y -= scroll.get_h_scroll_bar().size.y
		var last_rect := last_card.get_global_rect()
		assert(last_rect.position.y >= visible_rect.position.y - 1.0, "%s 末项顶部被裁切" % profession)
		assert(last_rect.end.y <= visible_rect.end.y + 1.0, "%s 末项底部被裁切" % profession)

	print("SKILL_GOTHIC_UI_PASS: 攻击主键、六环槽、被动过滤与可逆清空请求均通过")
	get_tree().quit(0)


func _skill_index(panel: SkillPanel, skill_name: String) -> int:
	for index in range(panel.skill_entries.size()):
		if str(panel.skill_entries[index].get("skillName", "")) == skill_name:
			return index
	return -1
