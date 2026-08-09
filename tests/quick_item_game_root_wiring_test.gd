extends Node

const GameHUD := preload("res://scripts/hud.gd")


class FakeHud extends GameHUD:
	var received_assignments: Array = []
	var messages: Array[String] = []

	func set_item_quick_slots(assignments: Array) -> void:
		received_assignments = assignments.duplicate()

	func show_message(message: String, seconds := 2.0) -> void:
		messages.append(message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats()
	PlayerState.add_item("太阳水", 2)

	var game: Node = load("res://scripts/game_root.gd").new()
	var fake_hud := FakeHud.new()
	game.hud = fake_hud
	game._wire_item_quick_slots_hud()
	# 裸实例没有 player，需显式打开输入门才能验证使用动作。
	game._player_input_enabled = true
	assert(
		fake_hud.get_signal_connection_count("item_quick_slot_assignment_requested") == 1,
		"assignment signal 未连接"
	)
	assert(
		fake_hud.get_signal_connection_count("item_quick_slot_use_requested") == 1,
		"use signal 未连接"
	)
	assert(fake_hud.received_assignments == ["", "", "", ""], "HUD 未收到初始快捷物品快照")
	assert(
		PlayerState.quick_item_slots_changed.is_connected(game._sync_item_quick_slots_to_hud),
		"quick_item_slots_changed 未连接 HUD 同步"
	)
	# 重复接线幂等
	game._wire_item_quick_slots_hud()
	assert(
		fake_hud.get_signal_connection_count("item_quick_slot_assignment_requested") == 1
		and fake_hud.get_signal_connection_count("item_quick_slot_use_requested") == 1,
		"重复接线产生重复连接"
	)

	# 绑定信号 → PlayerState + HUD 同步 + 可见提示
	fake_hud.item_quick_slot_assignment_requested.emit(0, "太阳水")
	assert(PlayerState.quick_item_slots[0] == "太阳水", "assignment 未写入 PlayerState")
	assert(fake_hud.received_assignments[0] == "太阳水", "绑定后 HUD 未同步")
	assert(fake_hud.messages.size() == 1, "绑定成功未提示")

	# 非法绑定拒绝并提示
	fake_hud.item_quick_slot_assignment_requested.emit(1, "木剑")
	assert(PlayerState.quick_item_slots[1].is_empty(), "非法绑定未被拒绝")
	assert(fake_hud.messages.size() == 2, "非法绑定未提示")

	# PlayerState 信号生命周期同步
	fake_hud.received_assignments = []
	PlayerState.quick_item_slots_changed.emit({
		"contract_id": PlayerState.QUICK_ITEM_SLOTS_CONTRACT_ID,
		"slot_index": 0,
		"item_name": "太阳水",
		"slots": PlayerState.quick_item_slots.duplicate(),
	})
	assert(fake_hud.received_assignments == ["太阳水", "", "", ""], "signal 未同步 HUD 快照")

	# consumable/scroll 成功走既有信号链，不重复成功提示
	var messages_before := fake_hud.messages.size()
	fake_hud.item_quick_slot_use_requested.emit(0, "太阳水")
	assert(PlayerState.item_count("太阳水") == 1, "快捷使用未消耗")
	assert(fake_hud.messages.size() == messages_before, "consumable 成功不应重复提示")

	# expected mismatch / 空槽必须可见失败提示
	fake_hud.item_quick_slot_use_requested.emit(0, "回城卷")
	assert(PlayerState.item_count("太阳水") == 1, "expected mismatch 不应消耗")
	assert(fake_hud.messages.size() == messages_before + 1, "expected mismatch 未提示")
	fake_hud.item_quick_slot_use_requested.emit(3, "")
	assert(fake_hud.messages.size() == messages_before + 2, "空槽使用未提示")

	# skill_book 成功必须可见提示
	PlayerState.add_item("基本剑术", 1)
	fake_hud.item_quick_slot_assignment_requested.emit(1, "基本剑术")
	messages_before = fake_hud.messages.size()
	fake_hud.item_quick_slot_use_requested.emit(1, "基本剑术")
	assert(PlayerState.is_skill_learned("基本剑术"), "快捷技能书未学习")
	assert(fake_hud.messages.size() == messages_before + 1, "技能书成功未提示")

	# gameplay_input_is_enabled 约束使用动作
	var messages_gated := fake_hud.messages.size()
	game._player_input_enabled = false
	fake_hud.item_quick_slot_use_requested.emit(0, "太阳水")
	assert(PlayerState.item_count("太阳水") == 1, "输入门关闭时未阻止快捷使用")
	assert(fake_hud.messages.size() == messages_gated, "输入门关闭时不应提示")
	game._player_input_enabled = true

	# 合并态真实 HUD：接口存在，_wire 后连接建立并收到快照
	var real_hud := GameHUD.new()
	assert(
		real_hud.has_signal("item_quick_slot_assignment_requested")
		and real_hud.has_signal("item_quick_slot_use_requested")
		and real_hud.has_method("set_item_quick_slots"),
		"合并态 GameHUD 缺少快捷物品接口"
	)
	game.hud = real_hud
	game._wire_item_quick_slots_hud()
	assert(
		real_hud.get_signal_connection_count("item_quick_slot_assignment_requested") == 1
		and real_hud.get_signal_connection_count("item_quick_slot_use_requested") == 1,
		"合并态真实 HUD 接口未连接"
	)
	var merged_hud := FakeHud.new()
	game.hud = merged_hud
	game._wire_item_quick_slots_hud()
	assert(
		merged_hud.received_assignments == PlayerState.quick_item_slots_snapshot(),
		"合并态 HUD 未收到快捷物品快照"
	)
	print("QUICK_ITEM_GAME_ROOT_WIRING_PASS")
	get_tree().quit(0)
