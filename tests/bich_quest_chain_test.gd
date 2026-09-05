extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 6
	PlayerState.recalculate_stats()
	assert(PlayerState.max_inventory_weight() >= 60, "比奇任务奖励夹具负重不足")
	assert(GameData.bich_quest_count() == 6, "比奇主线必须包含六段")
	var quests := GameData.get_bich_quests()
	assert(quests[0].get("confidence", "") == "B", "初级装备任务必须保持经典改编B标记")
	for index in range(1, quests.size()):
		assert(quests[index].get("confidence", "") == "C" and quests[index].get("sourceType", "") == "单机主线衔接设计", "后续衔接任务不得冒充官服原任务")
		assert(quests[index].get("prerequisite", "") == quests[index - 1].get("id", ""), "任务前置链断裂")
	for quest: Variant in quests:
		for map_id: Variant in quest.get("targetMapIds", []):
			assert(not GameData.get_map_by_id(int(map_id)).is_empty(), "%s引用了不存在的地图%d" % [quest.get("name", ""), int(map_id)])
		for reward: Variant in quest.get("rewards", {}).get("items", []):
			assert(not GameData.get_item_record(str(reward.get("name", ""))).is_empty(), "%s奖励物品不在运行目录" % quest.get("name", ""))

	assert(PlayerState.accept_quest("bich_field_hunt") == "前置任务尚未完成", "不得越过前置任务")
	for quest: Variant in quests:
		var quest_id := str(quest.get("id", ""))
		assert(PlayerState.current_bich_quest_id() == quest_id, "当前任务顺序错误")
		assert("已接受任务" in PlayerState.accept_quest(quest_id), "任务接受失败：%s" % quest_id)
		var kills: Dictionary = quest.get("objectives", {}).get("kills", {})
		for objective_name: String in kills.keys():
			var monster_name := objective_name.trim_suffix("*") + ("3" if objective_name.ends_with("*") else "")
			for count in range(int(kills[objective_name])):
				PlayerState.record_kill(monster_name)
		assert(PlayerState.quest_states[quest_id].get("status", "") == "ready", "任务目标完成后没有进入可领取状态：%s" % quest_id)
		var gold_before := PlayerState.gold
		assert("已领取" in PlayerState.claim_quest(quest_id), "领取失败：%s" % quest_id)
		assert(PlayerState.gold == gold_before + int(quest.get("rewards", {}).get("gold", 0)), "金币奖励错误：%s" % quest_id)
		var inventory_after := JSON.stringify(PlayerState.inventory)
		var gold_after := PlayerState.gold
		assert(PlayerState.claim_quest(quest_id) == "奖励已经领取", "奖励防重复失效：%s" % quest_id)
		assert(PlayerState.gold == gold_after and JSON.stringify(PlayerState.inventory) == inventory_after, "重复领取改变了奖励状态：%s" % quest_id)
	assert(PlayerState.current_bich_quest_id().is_empty(), "尸王任务完成后主线没有结束")
	assert(PlayerState.has_item("攻杀剑术") and PlayerState.has_item("基本剑术"), "战士技能书闭环奖励缺失")

	PlayerState.quest_states = {"beginner_gear": {"status": "active", "progress": 3}}
	PlayerState._migrate_quest_states()
	assert(not PlayerState.quest_states.has("beginner_gear"), "旧任务ID没有清理")
	assert(PlayerState.quest_states.get("bich_beginner_gear", {}).get("status", "") == "ready", "旧初级装备任务迁移丢失进度")

	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var tracker: Label = game.hud.get_node("MobileSafeRoot").find_child("QuestTracker", true, false)
	assert(tracker != null and "初级装备任务" in tracker.text and "可接" in tracker.text, "移动端任务追踪未显示当前可接任务")
	game.hud.open_quest("老兵")
	var panel: QuestPanel = game.hud.quest_panel
	assert(panel.visible and panel.current_quest_id == "bich_beginner_gear", "老兵没有打开当前任务")
	assert("经典任务改编" in panel.description_label.text and "B" in panel.description_label.text, "任务面板没有显示来源等级")

	print("BICH_QUEST_CHAIN_PASS：六段前置、复合击杀、前缀目标、原子奖励、防重复、旧存档迁移与移动追踪正确")
	get_tree().quit(0)
