extends Node
## Real panels; no business mutation is permitted by presentation closure.
@export var zone_filter := ""
var current_zone := ""
var failures: Array[String] = []
var checks := 0
var hud
var host: Control
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func frames(n := 3) -> void:
	for i in range(n):
		await get_tree().process_frame
func state() -> Array:
	return [PlayerState.inventory.duplicate(true), PlayerState.equipment.duplicate(true), PlayerState.warehouse_inventory.duplicate(true), PlayerState.gold]
func empty_selection(p, domain: String) -> bool:
	match domain:
		"inventory":
			return p.selected_inventory_index == -1 and p.selected_inventory_indices.is_empty() and p.selected_inventory_refs.is_empty() and p.selected_inventory_ref.is_empty() and p.selected_equipment_slot.is_empty() and p.selected_equipment_ref.is_empty()
		"warehouse":
			return p.selected_bag_indices.is_empty() and p.selected_stash_indices.is_empty() and p.selected_bag_refs.is_empty() and p.selected_stash_refs.is_empty() and p.selected_ref.is_empty()
		"shop":
			return p._selected_buy_index == -1 and p._selected_sell_index == -1 and p._selected_sell_indices.is_empty() and p._sell_quantities.is_empty() and p.item_list.get_selected_items().is_empty()
	return false
func pick(p, domain: String) -> void:
	match domain:
		"inventory":
			if current_zone == "inventory_equipment": p._select_equipment_slot("武器")
			else: p._select_inventory_item(0)
		"warehouse": p._select_item("stash" if current_zone == "warehouse_stash" else "bag", 0)
		"shop":
			if current_zone == "shop_sell": p._select_sell_item(0)
			else: p._select_shop_item(0)
func event_at(button: BaseButton, pressed: bool, finger: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.pressed = pressed
	event.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	button.get_viewport().push_input(event, true)

func _run() -> void:
	if not GameData.ensure_loaded():
		get_tree().quit(1); return
	host = Control.new()
	host.size = get_viewport().get_visible_rect().size
	add_child(host)
	for zone: String in ["inventory_bag", "inventory_equipment", "warehouse_bag", "warehouse_stash", "shop_buy", "shop_sell"]:
		if not zone_filter.is_empty() and zone != zone_filter:
			continue
		current_zone = zone
		var domain: String = zone.split("_")[0]
		PlayerState.reset_progress(false)
		PlayerState.level = 60
		PlayerState.recalculate_stats(false)
		var received: Dictionary = PlayerState.add_item("木剑", 1)
		check(bool(received.get("success", false)), zone+" fixture receive failed")
		if zone == "inventory_equipment":
			var result: Dictionary = PlayerState.equip_inventory_index_result(0, "武器")
			check(bool(result.get("success", false)), "fixture equip failed")
		elif zone == "warehouse_stash":
			PlayerState.warehouse_inventory = PlayerState.inventory.duplicate(true)
			PlayerState.inventory = [] # isolated display fixture, not transfer proof
		var script: Script = load("res://scripts/%s_panel.gd" % domain)
		var p = script.new()
		host.add_child(p)
		await frames(6)
		if domain == "shop":
			var context: Dictionary = GameData.merchant_context("general")
			p.buy_quotes_requested.connect(func(stock: Array) -> void: p.set_buy_quotes(PlayerState.shop_buy_quotes(stock, context)))
			p.sell_quotes_requested.connect(func(items: Array) -> void: p.set_sell_quotes(PlayerState.shop_sell_quotes(items)))
			p.open_for("R3关闭选择测试", [{"name": "木剑", "pack_count": 1, "merchant_context": context, "merchant_id": context.get("merchant_id", "")}], context)
			if zone == "shop_sell": p._set_trade_mode("sell")
		elif domain == "warehouse": p.open_panel()
		else: p.show()
		if p.has_method("refresh"):
			p.refresh()
		await frames(3)
		for route: String in ["close_button", "direct_hide", "ancestor_hide", "canvas_layer_hide"]:
			pick(p, domain)
			await frames(2)
			check(not empty_selection(p, domain), domain+" failed to establish selection")
			var before := state()
			var session = p.get_node_or_null("R3SelectionLifecycle")
			check(session != null, domain+" lifecycle missing")
			var epoch_before := int(session.get("epoch")) if session != null else -1
			var layer: CanvasLayer
			match route:
				"close_button": p._close()
				"direct_hide": p.hide()
				"ancestor_hide": host.hide()
				"canvas_layer_hide":
					layer = CanvasLayer.new()
					add_child(layer)
					p.reparent(layer)
					p.show()
					await frames(2)
					pick(p, domain)
					layer.hide()
			await frames(2)
			check(empty_selection(p, domain), domain+" retained semantic selection on "+route)
			check(state() == before, domain+" close mutated business state")
			if route == "ancestor_hide": host.show()
			elif route == "canvas_layer_hide":
				layer.show()
				p.reparent(host)
				layer.queue_free()
			else: p.show()
			await frames(4)
			check(empty_selection(p, domain), domain+" reopened with old selection")
			check(p.item_detail_presenter == null or not p.item_detail_presenter.visible, domain+" stale detail after reopen")
			if session != null:
				check(not bool(session.call("allows_presentation", epoch_before)), domain+" previous session still accepted")
		var first: BaseButton
		if domain == "inventory":
			first = p.equipment_buttons["武器"] if zone == "inventory_equipment" else p._bag_cells[0].get_child(0) as BaseButton
		elif domain == "warehouse":
			var cells: Array = p._stash_cells if zone == "warehouse_stash" else p._bag_cells
			first = cells[0].get_node("ItemButton") as BaseButton
		else: first = p.goods_buttons[0]
		p._ui_dismiss_selection()
		var gesture = first.get_node_or_null("HCActivationOnce")
		var old_count := int(gesture.accepted_count) if gesture != null else -1
		event_at(first, true, 7)
		p.hide()
		p.show()
		await frames(2)
		event_at(first, false, 7) # old UP must not become a new-session click
		await frames(2)
		check(empty_selection(p, domain), domain+" stale UP restored selection")
		if gesture != null:
			check(int(gesture.accepted_count) == old_count, domain+" stale gesture committed")
		event_at(first, true, 8)
		event_at(first, false, 8)
		await frames(2)
		check(not empty_selection(p, domain), domain+" fresh tap failed after reopen")
		p._ui_dismiss_selection()
		# Transaction locks belong to authority, not visual dismissal.
		if domain == "shop":
			p._buy_request_locked = true
			var serial: int = int(p._buy_lock_serial)
			p.hide(); p.show()
			check(p._buy_request_locked and p._buy_lock_serial == serial, "close released buy lock")
			p._buy_request_locked = false
		p.queue_free()
		await frames()
	check(checks > 0, "empty close test selection")
	var path := "user://r3_close_selection_%s.json" % (zone_filter if not zone_filter.is_empty() else "all")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  ")); f.close()
	else: failures.append("evidence write failed")
	for e in failures: push_error(e)
	print("R3_CLOSE_SELECTION_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)
