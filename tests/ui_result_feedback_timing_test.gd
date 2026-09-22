extends Node

const UI := preload("res://scripts/gothic_ui_theme.gd")
const InventoryScript := preload("res://scripts/inventory_panel.gd")
const WarehouseScript := preload("res://scripts/warehouse_panel.gd")
const ShopScript := preload("res://scripts/shop_panel.gd")
const QuestScript := preload("res://scripts/quest_panel.gd")
const RevivalScript := preload("res://scripts/death_revival_panel.gd")
const MenuScript := preload("res://scripts/system_menu_panel.gd")

const SUCCESS_SECONDS := 0.20
const FAILURE_SECONDS := 0.30
# Observation windows allow frame-boundary timer dispatch, while rejecting the
# previous 1.0/0.45 durations. Check both persistence and eventual expiration.
const SUCCESS_EARLY_SECONDS := 0.08
const SUCCESS_LATE_SECONDS := 0.26
const FAILURE_EARLY_SECONDS := 0.18
const FAILURE_LATE_SECONDS := 0.36

var _host: Control
var _specs: Array[Dictionary] = []
var _warehouse_requests: Array[bool] = []
var _revival_requests: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.add_item("木剑")
	assert(not PlayerState.inventory.is_empty(), "selection fixture requires a real inventory item")
	_host = Control.new()
	_host.size = Vector2(1280.0, 720.0)
	add_child(_host)
	var inventory := InventoryScript.new()
	var warehouse := WarehouseScript.new()
	var shop := ShopScript.new()
	var quest := QuestScript.new()
	var revival := RevivalScript.new()
	var menu := MenuScript.new()
	for panel: Control in [inventory, warehouse, shop, quest, revival, menu]:
		_host.add_child(panel)
		panel.hide()
	# Finish real deferred builders/layouts before short timing measurements.
	for _frame: int in range(4):
		await get_tree().process_frame
	_specs = [
		_spec(inventory, inventory.auto_sort_button, "_show_inventory_action_result", "_clear_inventory_action_feedback", "_close", "inventory.sort"),
		_spec(warehouse, warehouse.sort_button, "_show_transfer_result", "_clear_transfer_feedback", "_close", "warehouse.sort"),
		_spec(shop, shop.buy_button, "_show_transaction_result_feedback", "_clear_transaction_feedback", "_close", "shop.buy"),
		_spec(quest, quest.action_button, "_show_action_result_feedback", "_clear_action_feedback", "_close", "quest.action", true),
		_spec(revival, revival.town_button, "_show_revival_result_feedback", "_clear_revival_feedback", "close_death_screen", "death.revival", true),
		_spec(menu, menu.settings_button, "_show_menu_action_result", "_clear_action_feedback", "close_menu", "system_menu.settings"),
	]
	for spec: Dictionary in _specs:
		var panel: Control = spec["panel"]
		panel.show()
		for _frame: int in range(2):
			await get_tree().process_frame
		await _assert_result_lifetime(spec, true)
		await _assert_result_lifetime(spec, false)
		await _assert_stale_timer_keeps_new_busy(spec)
		panel.hide()

	# Alternate result consumers must target their actual alternate buttons.
	quest.show()
	var abandon_spec := _spec(quest, quest.abandon_button, "_show_abandon_result_feedback", "_clear_action_feedback", "_close", "quest.abandon", true)
	await _assert_result_lifetime(abandon_spec, false)
	quest.hide()
	revival.show()
	var special_spec := _spec(revival, revival.special_button, "_show_revival_result_feedback", "_clear_revival_feedback", "close_death_screen", "death.revival", true)
	await _assert_result_lifetime(special_spec, false)
	revival.hide()

	await _assert_actual_selection_survives_result(inventory, warehouse, shop)
	await _assert_real_request_waits_for_receipt(warehouse, revival)
	await _assert_close_and_reopen_invalidates_old_receipt()
	await _assert_free_with_pending_receipts()

	# Dynamic reflection lets the pre-change source fail on actual delayed
	# feedback, rather than a parse error due to not-yet-added constants.
	var constants: Dictionary = (load("res://scripts/gothic_ui_theme.gd") as Script).get_script_constant_map()
	assert(constants.has("BUTTON_RESULT_SUCCESS_SECONDS"), "result durations need one shared theme authority")
	assert(constants.has("BUTTON_RESULT_FAILURE_SECONDS"))
	assert(is_equal_approx(float(constants["BUTTON_RESULT_SUCCESS_SECONDS"]), SUCCESS_SECONDS))
	assert(is_equal_approx(float(constants["BUTTON_RESULT_FAILURE_SECONDS"]), FAILURE_SECONDS))
	_host.free()
	print("UI_RESULT_FEEDBACK_TIMING_PASS panels=6 immediate=1 unified_durations=1 stale_busy=1 selection=1 pending_request=1 hide_free=1")
	get_tree().quit(0)


func _spec(panel: Control, button: Button, result_method: String, clear_method: String, close_method: String, group: String, scalar := false) -> Dictionary:
	assert(button != null and button.is_inside_tree(), "%s must use a constructed real button" % group)
	return {"panel": panel, "button": button, "result": result_method, "clear": clear_method, "close": close_method, "group": group, "scalar": scalar}


func _present(spec: Dictionary, success: bool) -> void:
	var panel: Control = spec["panel"]
	var button: Button = spec["button"]
	panel.call(str(spec["clear"]))
	# Revival selects town/special from the initiating button's existing cue.
	UI.set_button_feedback(button, UI.BUTTON_FEEDBACK_BUSY, str(spec["group"]))
	if bool(spec["scalar"]):
		panel.call(str(spec["result"]), success)
	else:
		panel.call(str(spec["result"]), button, success, str(spec["group"]))


func _assert_result_lifetime(spec: Dictionary, success: bool) -> void:
	var panel: Control = spec["panel"]
	var button: Button = spec["button"]
	panel.call(str(spec["clear"]))
	var original_style := button.get_theme_stylebox("normal")
	var original_rect := button.get_rect()
	var original_minimum := button.custom_minimum_size
	var original_disabled := button.disabled
	var expected := UI.BUTTON_FEEDBACK_SUCCESS if success else UI.BUTTON_FEEDBACK_FAILURE
	_present(spec, success)
	# Deliberately no await: the transaction result has already arrived.
	_assert_state(button, expected, "%s synchronous receipt" % spec["group"])
	_assert_layout_and_availability(button, original_rect, original_minimum, original_disabled)
	var result_style := button.get_theme_stylebox("normal")
	assert(button.get_theme_stylebox("disabled") == result_style, "disabled buttons must still display their received result")
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert(is_equal_approx(original_style.get_content_margin(side), result_style.get_content_margin(side)), "result cue moved button content")
	var early := SUCCESS_EARLY_SECONDS if success else FAILURE_EARLY_SECONDS
	var late := SUCCESS_LATE_SECONDS if success else FAILURE_LATE_SECONDS
	await get_tree().create_timer(early).timeout
	_assert_state(button, expected, "%s before expiration" % spec["group"])
	await get_tree().create_timer(late - early).timeout
	_assert_state(button, UI.BUTTON_FEEDBACK_NORMAL, "%s expired result" % spec["group"])
	assert(button.get_theme_stylebox("normal") == original_style, "result expiry did not restore the original style")
	_assert_layout_and_availability(button, original_rect, original_minimum, original_disabled)


func _assert_stale_timer_keeps_new_busy(spec: Dictionary) -> void:
	var panel: Control = spec["panel"]
	var button: Button = spec["button"]
	_present(spec, false)
	_assert_state(button, UI.BUTTON_FEEDBACK_FAILURE, "old result must actually have started its timer")
	# The real new-operation sequence invalidates the old receipt serial, then
	# installs the next BUSY cue on the same actual button.
	panel.call(str(spec["clear"]))
	UI.set_button_feedback(button, UI.BUTTON_FEEDBACK_BUSY, str(spec["group"]))
	await get_tree().create_timer(FAILURE_LATE_SECONDS).timeout
	_assert_state(button, UI.BUTTON_FEEDBACK_BUSY, "%s old timer erased a newer operation" % spec["group"])
	panel.call(str(spec["clear"]))


func _assert_actual_selection_survives_result(inventory: InventoryPanel, warehouse: WarehousePanel, shop: ShopPanel) -> void:
	inventory.show()
	_present(_specs[0], false)
	inventory._select_inventory_item(0)
	assert(inventory.selected_inventory_indices.has(0), "real inventory selection was not established")
	var inventory_refs: Array = inventory.selected_inventory_refs.duplicate(true)
	warehouse.show()
	_present(_specs[1], false)
	warehouse._select_item("bag", 0)
	assert(warehouse.selected_bag_indices.has(0), "real warehouse bag selection was not established")
	var warehouse_refs: Array = warehouse.selected_bag_refs.duplicate(true)
	shop.show()
	_present(_specs[2], false)
	shop._set_trade_mode("sell")
	var selected_tab_style := shop.sell_tab_button.get_theme_stylebox("normal")
	assert(shop.sell_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton")
	await get_tree().create_timer(FAILURE_LATE_SECONDS).timeout
	assert(inventory.selected_inventory_indices.has(0) and inventory.selected_inventory_refs == inventory_refs, "receipt expiry discarded new inventory selection")
	assert(warehouse.selected_bag_indices.has(0) and warehouse.selected_bag_refs == warehouse_refs, "receipt expiry discarded new warehouse selection")
	assert(shop._trade_mode == "sell" and shop.sell_tab_button.get_theme_stylebox("normal") == selected_tab_style, "old buy timer replaced the newly selected sell tab")
	inventory.hide()
	warehouse.hide()
	shop.hide()


func _assert_real_request_waits_for_receipt(warehouse: WarehousePanel, revival: DeathRevivalPanel) -> void:
	warehouse.open_panel()
	warehouse.warehouse_sort_requested.connect(func() -> void: _warehouse_requests.append(true))
	# Start through the actual button connection while an older timer remains.
	# Deliver no authority receipt until after the full pending-state wait.
	_present(_specs[1], true)
	warehouse.sort_button.pressed.emit()
	assert(_warehouse_requests.size() == 1, "real warehouse request was not dispatched")
	_assert_state(warehouse.sort_button, UI.BUTTON_FEEDBACK_BUSY, "warehouse request pending")
	revival.open_death_screen({
		"death_id": "feedback-timing-pending",
		"revival_options": [{"option_slot": "town", "method_id": "revive.nearest_town", "enabled": true, "countdown_seconds": 0}],
	})
	revival.revival_requested.connect(func(request: Dictionary) -> void: _revival_requests.append(request.duplicate(true)))
	_present(_specs[4], false)
	revival.town_button.pressed.emit()
	assert(_revival_requests.size() == 1 and revival._revival_request_locked)
	assert(_revival_requests[0].get("method_id", "") == "revive.nearest_town")
	_assert_state(revival.town_button, UI.BUTTON_FEEDBACK_TRANSITION, "revival transition pending")
	await get_tree().create_timer(FAILURE_LATE_SECONDS + 0.10).timeout
	_assert_state(warehouse.sort_button, UI.BUTTON_FEEDBACK_BUSY, "result duration must not time out a real pending request")
	_assert_state(revival.town_button, UI.BUTTON_FEEDBACK_TRANSITION, "result duration must not time out a real pending transition")
	assert(revival._revival_request_locked and revival.town_button.disabled, "result timer unlocked a still-pending revival")
	revival.town_button.pressed.emit()
	assert(_revival_requests.size() == 1, "pending revival admitted a duplicate request")
	warehouse.apply_sort_result({"success": true, "message": "completed by authority"})
	_assert_state(warehouse.sort_button, UI.BUTTON_FEEDBACK_SUCCESS, "actual warehouse result receipt")
	revival.apply_revival_result({"success": false, "message": "destination unavailable"})
	_assert_state(revival.town_button, UI.BUTTON_FEEDBACK_FAILURE, "actual revival failure receipt")
	assert(not revival._revival_request_locked and not revival.town_button.disabled)
	await get_tree().create_timer(FAILURE_LATE_SECONDS).timeout
	_assert_state(warehouse.sort_button, UI.BUTTON_FEEDBACK_NORMAL, "warehouse receipt expired")
	_assert_state(revival.town_button, UI.BUTTON_FEEDBACK_NORMAL, "revival receipt expired")
	warehouse.hide()
	revival.close_death_screen()


func _assert_close_and_reopen_invalidates_old_receipt() -> void:
	for spec: Dictionary in _specs:
		var panel: Control = spec["panel"]
		var button: Button = spec["button"]
		panel.show()
		_present(spec, false)
		panel.call(str(spec["close"]))
		assert(not panel.visible, "formal close did not hide its panel")
		panel.show()
		# Reopening may immediately start another operation. Preserve the
		# owner's existing clear-before-start contract rather than inventing one.
		panel.call(str(spec["clear"]))
		UI.set_button_feedback(button, UI.BUTTON_FEEDBACK_BUSY, str(spec["group"]))
	await get_tree().create_timer(FAILURE_LATE_SECONDS).timeout
	for spec: Dictionary in _specs:
		_assert_state(spec["button"], UI.BUTTON_FEEDBACK_BUSY, "closed receipt erased a reopened operation")
		var panel: Control = spec["panel"]
		panel.call(str(spec["clear"]))
		panel.hide()


func _assert_free_with_pending_receipts() -> void:
	var weak_panels: Array[WeakRef] = []
	for spec: Dictionary in _specs:
		var panel: Control = spec["panel"]
		panel.show()
		_present(spec, false)
		weak_panels.append(weakref(panel))
		panel.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(FAILURE_LATE_SECONDS).timeout
	for weak_panel: WeakRef in weak_panels:
		assert(weak_panel.get_ref() == null, "pending feedback timer retained its freed panel")
	_specs.clear()


func _assert_state(button: Button, expected: StringName, context: String) -> void:
	var actual: StringName = button.get_meta(UI.BUTTON_FEEDBACK_META_STATE, UI.BUTTON_FEEDBACK_NORMAL)
	assert(actual == expected, "%s: expected=%s actual=%s" % [context, expected, actual])
	if expected not in [UI.BUTTON_FEEDBACK_SUCCESS, UI.BUTTON_FEEDBACK_FAILURE]:
		return
	var expected_color: Color = UI.BUTTON_SUCCESS_FILL if expected == UI.BUTTON_FEEDBACK_SUCCESS else UI.BUTTON_FAILURE_FILL
	var style := button.get_theme_stylebox("normal")
	if style is AdaptiveButtonStyleBox:
		assert(style.feedback_style != null and style.feedback_style.bg_color.is_equal_approx(expected_color), "%s metadata changed without its actual result style" % context)
		if style.feedback_layered:
			assert(not style.feedback_background_styles.is_empty())
			for background: StyleBoxTexture in style.feedback_background_styles.values():
				assert(background.modulate_color.is_equal_approx(expected_color), "%s actual feedback texture tint differs" % context)
	elif style is StyleBoxFlat:
		assert(style.bg_color.is_equal_approx(expected_color), "%s metadata changed without its actual result style" % context)
	else:
		assert(false, "%s missing actual result style" % context)


func _assert_layout_and_availability(button: Button, rect: Rect2, minimum: Vector2, disabled: bool) -> void:
	assert(button.get_rect().is_equal_approx(rect), "feedback changed the button's authored layout")
	assert(button.custom_minimum_size == minimum)
	assert(button.disabled == disabled, "result feedback changed transaction availability")
