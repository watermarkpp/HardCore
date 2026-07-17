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
	panel.open_for("比奇老兵")
	await get_tree().process_frame
	assert(panel.size == Vector2(1020, 636), "任务面板没有使用既定横屏底板尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "任务面板没有复用公共哥特外框")
	assert(panel.get_node("QuestListPanel").theme_type_variation == "GothicInsetFrame", "任务列表没有复用公共内框")
	assert(panel.get_node("QuestDetailPanel").theme_type_variation == "GothicInsetFrame", "任务详情没有复用公共内框")
	assert(panel.get_node("QuestDetailPanel/RewardsPanel").theme_type_variation == "GothicInfoPanel", "任务奖励没有使用简洁公共信息框")
	var rewards_title := panel.get_node("QuestDetailPanel/RewardsPanel/RewardsTitle") as Label
	assert(rewards_title.text == "任务奖励：" and rewards_title.position.y < panel.reward_label.position.y, "任务奖励标题没有上移、补冒号或与奖励内容对齐")
	assert(panel.quest_buttons.size() == GameData.bich_quest_count(), "任务列表没有完整显示六段比奇任务")
	var first_number := panel.quest_buttons[0].get_node("QuestNumber") as Label
	assert(first_number.vertical_alignment == VERTICAL_ALIGNMENT_CENTER and first_number.size.y == QuestPanel.QUEST_CARD_SIZE.y, "任务编号没有在卡片内垂直居中")
	assert(panel.current_quest_id == "bich_field_hunt", "任务面板没有默认选中当前任务")
	assert("比奇郊外的威胁" in panel.quest_name_label.text, "任务详情没有显示当前任务名称")
	assert("2/3" in panel.objective_label.text and "1/3" in panel.objective_label.text, "任务目标没有读取真实进度")
	assert("250金币" in panel.reward_label.text and "青铜剑" in panel.reward_label.text, "任务奖励没有读取玩法数据")
	assert("单机主线衔接设计" in panel.description_label.text and "C" in panel.description_label.text, "任务来源与可信度没有显示")
	assert(panel.action_button.disabled and panel.action_button.text == "任务进行中", "进行中任务不应重复接取或提交")
	assert(panel.abandon_button.visible and panel.abandon_button.position.x < panel.action_button.position.x, "进行中任务左侧没有放弃任务按钮")
	var abandon_requests: Array[String] = []
	panel.abandon_requested.connect(func(quest_id: String) -> void: abandon_requests.append(quest_id))
	panel._request_abandon()
	assert(panel._pending_abandon_quest_id == "bich_field_hunt", "放弃任务没有进入确认流程")
	panel._confirm_abandon()
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
	panel.open_for("比奇老兵")
	assert(panel.current_quest_id == "bich_beginner_gear", "未接任务没有默认选中当前可接任务")
	assert(not panel.action_button.disabled and panel.action_button.text == "接受任务", "点击未接受任务没有切换为接受任务按钮")
	assert(not panel.abandon_button.visible, "未接受任务不应显示放弃任务按钮")
	panel._act()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(str(PlayerState.quest_states.get("bich_beginner_gear", {}).get("status", "")) == "active", "接受任务按钮没有调用现有任务接取接口")
	assert(panel.action_button.disabled and panel.action_button.text == "任务进行中" and panel.abandon_button.visible, "接受后没有切换为进行中与放弃任务按钮")
	print("QUEST_GOTHIC_UI_PASS：编号居中、奖励对齐、接取切换、放弃请求、六段状态与真实任务数据均正常")
	get_tree().quit(0)
