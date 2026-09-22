extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.quest_states = {
		"bich_beginner_gear": {
			"status": "claimed",
			"progress": {"稻草人": 3},
		},
		"bich_field_hunt": {
			"status": "active",
			"progress": {"钉耙猫": 2, "半兽人": 1},
		},
	}
	var panel := QuestPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("老兵")
	await get_tree().process_frame
	assert(panel.npc_display_name == "老兵", "任务NPC仍带地区前缀")
	for quest: Dictionary in GameData.get_bich_quests():
		assert(str(quest.get("npc", "")) == "老兵", "任务委托人没有合并为老兵")
	assert(panel.size == Vector2(1020, 636), "任务面板没有使用既定横屏底板尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "任务面板没有复用公共哥特外框")
	assert(panel.get_node("QuestListPanel").theme_type_variation == "GothicInsetFrame", "任务列表没有复用公共内框")
	assert(panel.get_node("QuestDetailPanel").theme_type_variation == "GothicInsetFrame", "任务详情没有复用公共内框")
	var list_scroll := panel.get_node("QuestListPanel/QuestListScroll") as ScrollContainer
	assert(not list_scroll.get_theme_stylebox("panel") is StyleBoxEmpty, "任务人物列表没有恢复公共滚动区细框")
	var divider := panel.get_node("QuestDetailPanel/StoryDivider") as HSeparator
	assert(divider.get_meta("calibration_layer", "") == "quest_story_divider", "任务详情横线仍无法独立选中")
	var rewards_panel := panel.get_node("QuestDetailPanel/RewardsPanel") as Panel
	assert(rewards_panel.theme_type_variation == "GothicInfoPanel", "任务奖励没有使用简洁公共信息框")
	assert(rewards_panel.get_meta("calibration_layer", "") == "quest_rewards_panel", "任务奖励外框没有暴露为可校准层")
	var rewards_title := panel.get_node("QuestDetailPanel/RewardsPanel/RewardsTitle") as Label
	assert(rewards_title.text == "任务奖励：", "任务奖励标题缺少正式文案或冒号")
	assert(panel.quest_buttons.size() == GameData.bich_quest_count(), "任务列表没有完整显示六段比奇任务")
	for index in range(panel.quest_buttons.size()):
		var card := panel.quest_buttons[index]
		assert(card.position.x == 0.0 and card.position.y == index * (QuestPanel.QUEST_CARD_SIZE.y + QuestPanel.QUEST_CARD_SEPARATION), "任务卡没有按六段主线顺序完整排列")
	var stable_quest_paths: Array[String] = []
	for quest_button: Button in panel.quest_buttons:
		var quest_id := str(quest_button.get_meta("quest_id", ""))
		assert(quest_button.name == "QuestCard_%s" % quest_id, "任务卡没有使用稳定节点名: %s" % quest_button.name)
		stable_quest_paths.append(str(panel.get_path_to(quest_button)))
	panel.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(UIRuntimeLayoutOverrides.profile_is_ready(panel, "quest"), "任务面板没有完成最新人工存档布局加载")
	var saved_contract := JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ui/manual_layout_overrides.json")) as Dictionary
	var saved_action: Array = saved_contract.get("profiles", {}).get("quest", {}).get("nodes", {}).get("QuestDetailPanel/ActionButton", {}).get("logicalRect", [])
	var saved_divider: Array = saved_contract.get("profiles", {}).get("quest", {}).get("nodes", {}).get("QuestDetailPanel/StoryDivider", {}).get("logicalRect", [])
	assert(saved_action.size() == 4, "任务面板人工存档缺少操作按钮布局")
	assert(saved_divider.size() == 4, "任务面板人工存档缺少详情分隔线布局")
	assert(panel.action_button.position.is_equal_approx(Vector2(float(saved_action[0]), float(saved_action[1]))) and panel.action_button.size.is_equal_approx(Vector2(float(saved_action[2]), float(saved_action[3]))), "任务状态刷新覆盖了人工存档的操作按钮布局")
	assert(divider.position.is_equal_approx(Vector2(float(saved_divider[0]), float(saved_divider[1]))) and divider.size.is_equal_approx(Vector2(float(saved_divider[2]), float(saved_divider[3]))), "任务页代码覆盖了人工存档的详情分隔线布局")
	var protected_profile_rects := _protected_quest_rects(panel)
	UIRuntimeLayoutOverrides.apply_profile(panel, "quest")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(UIRuntimeLayoutOverrides.profile_is_ready(panel, "quest"), "任务 profile 重放后没有重新进入 ready")
	_assert_protected_quest_rects(panel, protected_profile_rects, "profile 重放")
	for _toggle_index in range(3):
		panel._set_abandon_available(false)
		panel._set_abandon_available(true)
		panel._on_runtime_layout_profile_applied("quest")
	_assert_protected_quest_rects(panel, protected_profile_rects, "放弃任务状态切换")
	var rebuilt_quest_paths: Array[String] = []
	for quest_button: Button in panel.quest_buttons:
		rebuilt_quest_paths.append(str(panel.get_path_to(quest_button)))
	assert(rebuilt_quest_paths == stable_quest_paths, "任务卡刷新后节点路径发生漂移")
	var first_number := panel.quest_buttons[0].get_node("QuestNumber") as Label
	assert(first_number.vertical_alignment == VERTICAL_ALIGNMENT_CENTER and first_number.size.y == QuestPanel.QUEST_CARD_SIZE.y, "任务编号没有在卡片内垂直居中")
	assert(first_number.position == Vector2(12, 0) and first_number.size.x == 34.0, "任务编号位置发生变化")
	var first_name := panel.quest_buttons[0].get_node("QuestName") as Label
	var first_state := panel.quest_buttons[0].get_node("QuestState") as Label
	assert(first_name.position.x == 0.0 and first_name.size.x == QuestPanel.QUEST_CARD_SIZE.x and first_name.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "任务名称没有相对整个按钮框左右居中")
	assert(first_state.position.x == 0.0 and first_state.size.x == QuestPanel.QUEST_CARD_SIZE.x and first_state.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "任务状态没有相对整个按钮框左右居中")
	assert(panel.current_quest_id == "bich_field_hunt", "任务面板没有默认选中当前任务")
	assert("比奇郊外的威胁" in panel.quest_name_label.text, "任务详情没有显示当前任务名称")
	assert("2/3" in panel.objective_label.text and "1/3" in panel.objective_label.text, "任务目标没有读取真实进度")
	assert("250金币" in panel.reward_label.text and "青铜剑" in panel.reward_label.text, "任务奖励没有读取玩法数据")
	assert("单机主线衔接设计" in panel.description_label.text and "C" in panel.description_label.text, "任务来源与可信度没有显示")
	assert(panel.action_button.disabled and panel.action_button.text == "任务进行中", "进行中任务不应重复接取或提交")
	assert(panel.status_label.text.is_empty(), "进行中状态不应在按钮左侧重复显示文字")
	assert(panel.abandon_button.visible and panel.abandon_button.position.x < panel.action_button.position.x, "进行中任务左侧没有放弃任务按钮")
	var saved_action_font := int(saved_contract.get("profiles", {}).get("quest", {}).get("nodes", {}).get("QuestDetailPanel/ActionButton", {}).get("logicalFontSize", 0))
	assert(panel.action_button.get_theme_font_size("font_size") == saved_action_font and panel.abandon_button.get_theme_font_size("font_size") == saved_action_font, "任务操作按钮没有统一采用人工校准字号")
	assert(is_equal_approx(panel.abandon_button.position.y, panel.action_button.position.y), "放弃任务与任务进行中没有处于同一纵坐标")
	assert(is_equal_approx(panel.abandon_button.size.y, panel.action_button.size.y), "放弃任务与任务进行中控件高度不一致")
	assert(is_equal_approx(panel.abandon_button.custom_minimum_size.y, panel.action_button.size.y), "放弃任务的最小高度没有恢复到错乱前的布局合同")
	assert(is_equal_approx(panel.abandon_button.position.x + panel.abandon_button.size.x + QuestPanel.ACTION_ROW_GAP, panel.action_button.position.x), "放弃任务没有按固定间距位于任务进行中左侧")
	var abandon_requests: Array[String] = []
	panel.abandon_requested.connect(func(quest_id: String) -> void: abandon_requests.append(quest_id))
	panel._request_abandon()
	assert(panel._pending_abandon_quest_id == "bich_field_hunt", "放弃任务没有进入确认流程")
	assert(panel.abandon_confirmation.visible, "放弃任务没有打开公共确认组件")
	assert(panel.abandon_confirmation.get_meta("stable_id", "") == "ui.confirmation.dialog", "任务没有复用公共确认组件")
	panel.abandon_confirmation.cancel_button.pressed.emit()
	assert(panel._pending_abandon_quest_id.is_empty() and abandon_requests.is_empty(), "取消放弃后仍保留待处理任务")
	panel._request_abandon()
	panel.abandon_confirmation.confirm_button.pressed.emit()
	assert(abandon_requests == ["bich_field_hunt"], "确认放弃后没有向玩法层发送稳定任务ID")
	panel._select_quest("bich_beginner_gear")
	assert(panel.action_button.disabled and panel.action_button.text == "奖励已领取", "已完成任务没有显示稳定只读状态")
	panel._select_quest("bich_orc_tomb")
	assert(panel.action_button.disabled and panel.action_button.text == "尚未解锁", "未来任务没有遵守前置任务锁定状态")
	panel._select_quest("bich_field_hunt")
	PlayerState.quest_states["bich_field_hunt"]["status"] = "ready"
	panel.refresh()
	assert(not panel.action_button.disabled and panel.action_button.text == "领取奖励", "完成目标后没有启用领取奖励按钮")
	PlayerState.reset_progress()
	panel.open_for("老兵")
	var refresh_before_burst := panel._refresh_execution_count
	for _burst_index in range(4):
		PlayerState.quests_changed.emit()
	assert(panel._refresh_execution_count == refresh_before_burst, "任务信号 burst 在同帧重复刷新")
	await get_tree().process_frame
	assert(panel._refresh_execution_count == refresh_before_burst + 1, "任务信号 burst 未合并为一次刷新")
	assert(panel._layout_apply_count == 1, "任务面板重复打开/刷新重复应用布局")
	assert(panel.current_quest_id == "bich_beginner_gear", "未接任务没有默认选中当前可接任务")
	assert(not panel.action_button.disabled and panel.action_button.text == "接受任务", "点击未接受任务没有切换为接受任务按钮")
	assert(panel.status_label.text.is_empty(), "可接任务不应在接受按钮左侧重复显示尚未接受")
	assert(not panel.abandon_button.visible, "未接受任务不应显示放弃任务按钮")
	panel._act()
	assert(panel.action_button.theme_type_variation == "GothicQuestActionGemButton", "任务操作按钮没有保留已验收的有宝石框")
	assert(panel.action_button.get_meta("gothic_feedback_state", "") == "busy", "接取任务的忙碌反馈没有完整保留一个渲染帧")
	await get_tree().process_frame
	assert(panel.action_button.get_meta("gothic_feedback_state", "") == "success", "接取任务成功没有进入一秒成功反馈")
	await get_tree().process_frame
	assert(str(PlayerState.quest_states.get("bich_beginner_gear", {}).get("status", "")) == "active", "接受任务按钮没有调用现有任务接取接口")
	assert(panel.action_button.disabled and panel.action_button.text == "任务进行中" and panel.abandon_button.visible, "接受后没有切换为进行中与放弃任务按钮")
	print("QUEST_GOTHIC_UI_PASS：profile 几何稳定、放弃按钮实机有效高度补偿、接取切换与真实任务数据均正常")
	get_tree().quit(0)


func _protected_quest_rects(panel: QuestPanel) -> Dictionary:
	var result := {}
	for path: String in [
		"QuestListPanel",
		"QuestListPanel/QuestListScroll",
		"QuestDetailPanel",
		"QuestDetailPanel/QuestName",
		"QuestDetailPanel/QuestMeta",
		"QuestDetailPanel/DescriptionLabel",
		"QuestDetailPanel/ObjectiveTitle",
		"QuestDetailPanel/ObjectiveDetail",
		"QuestDetailPanel/RewardsPanel",
		"QuestDetailPanel/StatusLabel",
		"QuestDetailPanel/StoryDivider",
		"QuestDetailPanel/ActionButton",
	]:
		result[path] = (panel.get_node(path) as Control).get_rect()
	return result


func _assert_protected_quest_rects(panel: QuestPanel, expected: Dictionary, context: String) -> void:
	for path: String in expected:
		var actual := (panel.get_node(path) as Control).get_rect()
		assert(actual.is_equal_approx(expected[path] as Rect2), "%s 扰动了任务关键矩形 %s：%s != %s" % [context, path, actual, expected[path]])
