extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame

	for signal_name: StringName in [
		&"shop_sell_quotes_requested",
		&"shop_sell_requested",
		&"quest_abandon_requested",
		&"warehouse_sort_requested",
	]:
		assert(hud.has_signal(signal_name), "HUD 缺少玩法请求桥接信号：%s" % signal_name)
	for method_name: StringName in [
		&"set_shop_sell_quotes",
		&"apply_shop_sell_result",
		&"apply_quest_abandon_result",
		&"apply_warehouse_sort_result",
	]:
		assert(hud.has_method(method_name), "HUD 缺少玩法结果回填入口：%s" % method_name)

	var quote_requests: Array = []
	var sell_requests: Array = []
	var abandon_requests: Array = []
	var sort_request_count := [0]
	hud.shop_sell_quotes_requested.connect(func(items: Array) -> void: quote_requests.append(items.duplicate(true)))
	hud.shop_sell_requested.connect(func(request: Dictionary) -> void: sell_requests.append(request.duplicate(true)))
	hud.quest_abandon_requested.connect(func(quest_id: String) -> void: abandon_requests.append(quest_id))
	hud.warehouse_sort_requested.connect(func() -> void: sort_request_count[0] += 1)

	hud._ensure_shop_panel()
	hud._ensure_shop_panel()
	hud._ensure_quest_panel()
	hud._ensure_quest_panel()
	hud._ensure_warehouse_panel()
	hud._ensure_warehouse_panel()
	hud.shop_panel.sell_quotes_requested.emit([{"quote_key": "inventory:0"}])
	hud.shop_panel.sell_requested.emit({"quote_id": "quote:test:001"})
	hud.quest_panel.abandon_requested.emit("bich_field_hunt")
	hud.warehouse_panel.warehouse_sort_requested.emit()
	assert(quote_requests.size() == 1 and quote_requests[0][0].quote_key == "inventory:0", "HUD 没有单次转发出售报价请求")
	assert(sell_requests.size() == 1 and sell_requests[0].quote_id == "quote:test:001", "HUD 没有单次转发出售请求")
	assert(abandon_requests == ["bich_field_hunt"], "HUD 没有单次转发任务放弃请求")
	assert(sort_request_count[0] == 1, "HUD 没有单次转发仓库整理请求")

	hud.set_shop_sell_quotes({"inventory:0": {"sellable": true, "unit_price": 10}})
	assert(hud.shop_panel._sell_quotes.has("inventory:0"), "HUD 没有回填权威出售报价")
	hud.apply_shop_sell_result({"success": false, "message": "出售被拒绝"})
	assert("出售被拒绝" in hud.shop_panel.detail_label.text, "HUD 没有回填出售结果")
	hud.apply_quest_abandon_result({"success": false, "message": "任务不可放弃"})
	assert(hud.quest_panel.status_label.text == "任务不可放弃", "HUD 没有回填任务放弃结果")
	hud.apply_warehouse_sort_result({"success": true, "message": "仓库已整理"})
	assert(hud.warehouse_panel.transfer_detail_label.text == "仓库已整理", "HUD 没有回填仓库整理结果")

	print("HUD_UI_ACTION_BRIDGE_PASS：出售、任务放弃与仓库整理请求/结果桥接均正常")
	get_tree().quit(0)
