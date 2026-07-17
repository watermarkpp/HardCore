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
	assert(panel.quest_buttons.size() == GameData.bich_quest_count(), "任务列表没有完整显示六段比奇任务")
	assert(panel.current_quest_id == "bich_field_hunt", "任务面板没有默认选中当前任务")
	assert("比奇郊外的威胁" in panel.quest_name_label.text, "任务详情没有显示当前任务名称")
	assert("2/3" in panel.objective_label.text and "1/3" in panel.objective_label.text, "任务目标没有读取真实进度")
	assert("250金币" in panel.reward_label.text and "青铜剑" in panel.reward_label.text, "任务奖励没有读取玩法数据")
	assert("单机主线衔接设计" in panel.description_label.text and "C" in panel.description_label.text, "任务来源与可信度没有显示")
	assert(panel.action_button.disabled and panel.action_button.text == "任务进行中", "进行中任务不应重复接取或提交")
	panel._select_quest("bich_beginner_gear")
	assert(panel.action_button.disabled and panel.action_button.text == "奖励已领取", "已完成任务没有显示稳定只读状态")
	panel._select_quest("bich_orc_tomb")
	assert(panel.action_button.disabled and panel.action_button.text == "尚未解锁", "未来任务没有遵守前置任务锁定状态")
	panel._select_quest("bich_field_hunt")
	PlayerState.quest_states["bich_field_hunt"]["status"] = "ready"
	panel.refresh()
	assert(not panel.action_button.disabled and panel.action_button.text == "领取奖励", "完成目标后没有启用领取奖励按钮")
	print("QUEST_GOTHIC_UI_PASS：六段任务列表、真实目标进度、奖励、来源、锁定与领取状态均正常")
	get_tree().quit(0)
