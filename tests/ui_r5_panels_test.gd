extends Node
## Uses the real installed panels, formatter, theme, and layout profiles.
## Runs only through the repository runner's isolated .godot/runtime_appdata.
const Inventory := preload("res://scripts/inventory_panel.gd")
const Warehouse := preload("res://scripts/warehouse_panel.gd")
const Shop := preload("res://scripts/shop_panel.gd")
const Menu := preload("res://scripts/system_menu_panel.gd")
const Loot := preload("res://scripts/loot_pickup.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const Guard := preload("res://scripts/ui_selection_dismiss_guard.gd")
var failures: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.inventory = [{"name": "太阳水", "count": 3}, {"name": "太阳水", "count": 2}]
	PlayerState.warehouse_inventory = [{"name": "太阳水", "count": 1}]
	var inventory := Inventory.new()
	add_child(inventory)
	await inventory.wait_until_runtime_ready()
	await get_tree().process_frame
	inventory._select_inventory_item(0)
	expect(inventory.selected_inventory_indices.size() == 1, "inventory single selection")
	expect(inventory.item_detail_presenter.visible, "inventory detail visible")
	await get_tree().process_frame
	var bag_region: Rect2 = inventory._ui_detail_region({})["region"]
	var detail_rect := Rect2(inventory.item_detail_presenter.position, inventory.item_detail_presenter.size)
	expect(inventory.item_detail_presenter.debug_layout_valid() and inventory.item_detail_presenter.modulate.a == 1.0, "calibrated inventory has side space (alpha 1, not just visible)")
	expect(bag_region.grow(0.5).encloses(detail_rect), "inventory detail lies outside whole bag")
	# R5-R1 边界（第九节滚动合同）：长正文在 presenter 用尽合法布局手段后由
	# presenter 统一管理为正文区纵向滚动；标题稳定、全文相等、末行可达、
	# scroll_active 真实反映、无横向滚动、字体合同不变。
	var expected_long_body := "追加属性：攻击 +5\n".repeat(80)
	inventory.item_detail_presenter.show_text("长属性测试", expected_long_body, {"presentation_zone": "inventory"})
	await get_tree().process_frame
	expect(inventory.item_detail_presenter.debug_layout_valid() and inventory.item_detail_presenter.modulate.a == 1.0, "long body keeps usable space")
	expect(inventory.item_detail_presenter.detail_label.text == expected_long_body, "long body keeps full text equality")
	expect(inventory.item_detail_presenter.title_label.text == "长属性测试", "long body keeps the full title")
	expect(inventory.item_detail_presenter.title_label.get_theme_font_size("font_size") == 20, "long body keeps title 20")
	expect(inventory.item_detail_presenter.detail_label.get_theme_font_size("normal_font_size") == 14, "long body keeps body 14")
	expect(inventory.item_detail_presenter.detail_label.scroll_active, "extreme body engages presenter-managed body scroll")
	expect(float(inventory.item_detail_presenter.detail_label.get_content_width()) <= float(inventory.item_detail_presenter.detail_label.size.x) + 0.5, "long body wraps with no horizontal overflow")
	var dock_after_show := Rect2(inventory.item_detail_presenter.position, inventory.item_detail_presenter.size)
	inventory.item_detail_presenter.detail_label.scroll_to_line(40)
	await get_tree().process_frame
	expect(inventory.item_detail_presenter.detail_label.get_v_scroll_bar().value > 0.0, "body actually scrolled")
	expect(Rect2(inventory.item_detail_presenter.position, inventory.item_detail_presenter.size).is_equal_approx(dock_after_show), "scrolling body does not move the dock")
	inventory.item_detail_presenter.detail_label.scroll_to_line(79)
	await get_tree().process_frame
	var long_vbar: ScrollBar = inventory.item_detail_presenter.detail_label.get_v_scroll_bar()
	# RichTextLabel 的滚动条 max_value 为全文高度，真实末端 = max - page。
	expect(long_vbar.value >= long_vbar.max_value - long_vbar.page - 0.5, "long body last line is reachable at scroll end")
	var inv_snapshot: Dictionary = inventory.item_detail_presenter.debug_layout_snapshot()
	print("UI_R5_EVIDENCE case=inventory_long_body panel=inventory profile=static-bag settled=%s rect=%s scroll_active=%s body_width=%.1f body_content=%.1f body_label=%.1f" % [
		inv_snapshot.get("valid"), inv_snapshot.get("rect"), inv_snapshot.get("scroll_active"),
		float(inventory.item_detail_presenter.detail_label.get_content_width()),
		float(inventory.item_detail_presenter.detail_label.get_content_height()),
		float(inventory.item_detail_presenter.detail_label.size.y)])
	inventory._select_inventory_item(1)
	expect(inventory.selected_inventory_indices.size() == 2, "multi-selection retained")
	inventory._select_inventory_item(1)
	expect(inventory.selected_inventory_indices.size() == 1, "toggle only clicked selection")
	inventory._ui_dismiss_selection()
	expect(inventory.selected_inventory_refs.is_empty() and inventory.selected_inventory_indices.is_empty(), "inventory clears indices and semantic refs")
	expect(inventory.selected_equipment_slot.is_empty() and inventory.selected_equipment_ref.is_empty(), "equipment selection clears with inventory")
	expect(not inventory.item_detail_presenter.visible and inventory.discard_button.disabled, "empty selection disables discard and hides detail")
	inventory.item_detail_presenter.show_message("不满足使用条件。")
	inventory.refresh()
	expect(inventory.item_detail_presenter.is_message_active(), "normal message survives unrelated refresh")
	inventory._ui_dismiss_selection()
	inventory.refresh()
	expect(not inventory.item_detail_presenter.visible, "cleared message does not reappear")
	inventory.hide()

	var warehouse := Warehouse.new()
	add_child(warehouse)
	await warehouse.wait_until_runtime_ready()
	await get_tree().process_frame
	warehouse._select_item("stash", 0)
	await get_tree().process_frame
	var stash_region: Rect2 = warehouse._ui_detail_region({"side": "stash"})["region"]
	detail_rect = Rect2(warehouse.item_detail_presenter.position, warehouse.item_detail_presenter.size)
	expect(warehouse.item_detail_presenter.debug_layout_valid() and warehouse.item_detail_presenter.modulate.a == 1.0, "warehouse left detail has space (alpha 1, not just visible)")
	expect(stash_region.grow(0.5).encloses(detail_rect), "stash detail left of whole viewport")
	var stash_grid_rect: Rect2 = Dock.rect_in(warehouse, warehouse.get_node("StashSection/StashScroll"))
	expect(stash_region.end.x <= stash_grid_rect.position.x + 0.5, "stash detail region stays left of warehouse grid")
	# R5-R1 边界：仓库背包格侧详情停靠背包格右侧，不覆盖任一格
	var bag_side_spec: Dictionary = warehouse._ui_detail_region({"side": "bag"})
	var bag_side_region: Rect2 = bag_side_spec["region"]
	var bag_side_expanded: Rect2 = bag_side_spec.get("expanded_region", bag_side_region)
	var bag_grid_rect: Rect2 = Dock.rect_in(warehouse, warehouse.get_node("BagSection/BagScroll"))
	expect(bag_side_region.size.x > 100.0 and bag_side_region.size.y > 80.0, "warehouse bag side has dock space")
	expect(bag_side_region.position.x >= bag_grid_rect.end.x - 0.5, "bag-side region starts right of warehouse bag grid")
	var expected_bag_body := "属性：防御 +5\n".repeat(60)
	warehouse.item_detail_presenter.show_text("仓库背包侧", expected_bag_body, {"side": "bag"})
	await get_tree().process_frame
	detail_rect = Rect2(warehouse.item_detail_presenter.position, warehouse.item_detail_presenter.size)
	expect(warehouse.item_detail_presenter.debug_layout_valid() and warehouse.item_detail_presenter.modulate.a == 1.0, "bag-side detail is real visible and layout valid")
	expect(warehouse.item_detail_presenter.detail_label.text == expected_bag_body, "bag-side long body keeps full text equality")
	expect(warehouse.item_detail_presenter.title_label.text == "仓库背包侧", "bag-side long body keeps the full title")
	expect(warehouse.item_detail_presenter.detail_label.scroll_active, "bag-side extreme body engages presenter-managed scroll")
	expect(float(warehouse.item_detail_presenter.detail_label.get_content_width()) <= float(warehouse.item_detail_presenter.detail_label.size.x) + 0.5, "bag-side long body wraps with no horizontal overflow")
	expect(bag_side_expanded.grow(0.5).encloses(detail_rect), "bag-side detail docks right of bag grid (expanded legal region)")
	expect(not detail_rect.intersects(bag_grid_rect) and not detail_rect.intersects(stash_grid_rect), "bag-side detail covers neither grid")
	var wh_snapshot: Dictionary = warehouse.item_detail_presenter.debug_layout_snapshot()
	print("UI_R5_EVIDENCE case=warehouse_bag_long_body panel=warehouse profile=static-bag settled=%s rect=%s scroll_active=%s body_width=%.1f body_content=%.1f body_label=%.1f" % [
		wh_snapshot.get("valid"), wh_snapshot.get("rect"), wh_snapshot.get("scroll_active"),
		float(warehouse.item_detail_presenter.detail_label.get_content_width()),
		float(warehouse.item_detail_presenter.detail_label.get_content_height()),
		float(warehouse.item_detail_presenter.detail_label.size.y)])
	warehouse._ui_dismiss_selection()
	expect(not detail_rect.intersects(Dock.rect_in(warehouse, warehouse.withdraw_button)), "withdraw remains unobscured")
	warehouse._select_item("bag", 0)
	expect(warehouse.selected_stash_indices.is_empty() and warehouse.selected_bag_indices.size() == 1, "source side switch preserves single authority")
	warehouse._select_item("bag", 1)
	expect(warehouse.selected_bag_indices.size() == 2, "warehouse batch selection retained")
	warehouse._ui_dismiss_selection()
	expect(warehouse.selected_bag_refs.is_empty() and warehouse.selected_stash_refs.is_empty() and warehouse.selected_ref.is_empty(), "warehouse clears every semantic ref")
	warehouse.refresh()
	expect(not warehouse.item_detail_presenter.visible, "warehouse refresh does not resurrect detail")
	warehouse.hide()

	var shop := Shop.new()
	add_child(shop)
	shop.open_for("R5 测试商店", [{"name": "太阳水", "pack_count": 1}], {"supports_repair": false})
	shop.set_buy_quotes([{"stock_index": 0, "valid": true, "unit_price": 100, "total_price": 100, "pack_count": 1}])
	await get_tree().process_frame
	shop._select_shop_item(0)
	await get_tree().process_frame
	var shop_region: Rect2 = shop._ui_detail_region({})["region"]
	detail_rect = Rect2(shop.item_detail_presenter.position, shop.item_detail_presenter.size)
	expect(shop.item_detail_presenter.debug_layout_valid() and shop.item_detail_presenter.modulate.a == 1.0, "shop detail has space (alpha 1, not just visible)")
	expect(shop_region.grow(0.5).encloses(detail_rect), "shop item stays in designated detail region")
	expect(absf(detail_rect.get_center().x - shop_region.get_center().x) < 1.0, "shop detail horizontally centered")
	expect(not detail_rect.intersects(Dock.rect_in(shop, shop.buy_button)), "shop buy button remains unobscured")
	shop._select_shop_item(0)
	expect(shop._selected_buy_index == -1 and not shop.item_detail_presenter.visible, "repeated buy item click toggles off")
	shop.apply_buy_result({"success": true, "message": "购买成功。"})
	await get_tree().process_frame
	expect(shop.item_detail_presenter.visible and shop.item_detail_presenter.title_label.text == "提示", "buy result reopens correctly titled presenter")
	expect(shop.item_detail_presenter.detail_label.text.contains("购买成功"), "buy result body retained")
	shop._set_trade_mode("sell")
	var quotes := {}
	for index in range(PlayerState.inventory.size()):
		quotes[shop.sell_quote_key(index, PlayerState.inventory[index])] = {"sellable": true, "unit_price": 50, "max_quantity": 3}
	shop.set_sell_quotes(quotes)
	shop._select_sell_item(0)
	await get_tree().process_frame
	detail_rect = Rect2(shop.item_detail_presenter.position, shop.item_detail_presenter.size)
	expect(not detail_rect.intersects(Dock.rect_in(shop, shop.sell_quantity_row)), "sell quantity row unobscured")
	expect(not detail_rect.intersects(Dock.rect_in(shop, shop.sell_quantity_button)), "sell action unobscured")
	shop._select_sell_item(0)
	expect(not shop.item_detail_presenter.visible, "last sale deselection hides detail")
	shop._ui_show_shop_message("金币不足。")
	shop._ui_dismiss_selection()
	await get_tree().process_frame
	expect(not shop.item_detail_presenter.visible and shop._selected_sell_indices.is_empty(), "shop clear removes selection and necessary message only on demand")

	# —— R5-R1 边界：稀有出售确认窗口与清选观察器 ——
	# 原报告误称 panels 用例覆盖确认分支；此处补上真实覆盖并纠正报告。
	var shop_guard := Guard.new()
	add_child(shop_guard)
	shop_guard.register_scope(shop)
	shop._select_sell_item(0)
	var rare_quotes := {}
	for index in range(PlayerState.inventory.size()):
		rare_quotes[shop.sell_quote_key(index, PlayerState.inventory[index])] = {"sellable": true, "unit_price": 50, "max_quantity": 3, "requires_confirmation": true}
	shop.set_sell_quotes(rare_quotes)
	shop._request_sell_batch()
	expect(shop.sell_confirmation.visible, "rare sale opens real confirmation with confirm/cancel buttons")
	expect(shop.sell_confirmation.confirm_button.text == "确认出售" and shop.sell_confirmation.cancel_button.text == "取消", "confirmation keeps explicit confirm/cancel buttons")
	var shop_blank: Vector2 = shop.get_global_transform_with_canvas() * Vector2(30, 30)
	shop_guard._begin(0, shop_blank)
	shop_guard._end(0, shop_blank, false)
	await get_tree().process_frame
	expect(not shop._selected_sell_indices.is_empty(), "confirmation window protects selection from blank tap")
	expect(shop.sell_confirmation.visible, "confirmation stays open after blank tap")
	var sell_requests: Array[Dictionary] = []
	shop.sell_requested.connect(func(request: Dictionary) -> void: sell_requests.append(request.duplicate(true)))
	shop.sell_confirmation.confirm_button.pressed.emit()
	await get_tree().process_frame
	expect(sell_requests.size() == 1 and not shop.sell_confirmation.visible, "confirm button still issues the real sale request")
	shop._request_sell_batch()
	expect(shop.sell_confirmation.visible, "confirmation reopens for the cancel path")
	shop.sell_confirmation.cancel_button.pressed.emit()
	expect(not shop.sell_confirmation.visible and shop._pending_sell_request.is_empty(), "cancel closes without auto confirming")
	expect(not shop._selected_sell_indices.is_empty(), "cancel keeps the selection")
	shop_guard.queue_free()
	shop.hide()

	var menu := Menu.new()
	add_child(menu)
	menu.set_audio_levels(0.37, 0.64)
	expect(menu.music_slider != null and menu.sfx_slider != null, "two real sliders constructed")
	expect(menu.music_status_label.text == "37%" and menu.sfx_status_label.text == "64%", "numeric display is not boolean enabled state")
	var requests: Array[Dictionary] = []
	menu.audio_setting_changed.connect(func(request: Dictionary) -> void: requests.append(request))
	menu.music_slider.value = 25
	expect(requests.size() == 1 and requests[0].get("contract_id") == "ui.audio.setting.v2", "slider emits v2 once")
	if not requests.is_empty():
		expect(is_equal_approx(float(requests[0].get("value", -1)), 0.25), "slider emits linear 0..1 level")
	menu.hide()

	var pickup := Loot.new()
	pickup.icon_sprite = Sprite2D.new()
	pickup.add_child(pickup.icon_sprite)
	pickup.icon_sprite.position = Vector2(0, -5)
	for tick in range(120):
		pickup.manager_visual_tick(0.016)
	expect(pickup.icon_sprite.position == Vector2(0, -5), "ground icon stays stationary across ticks")
	pickup.free()
	menu.queue_free()
	shop.queue_free()
	warehouse.queue_free()
	inventory.queue_free()
	await get_tree().process_frame
	for failure: String in failures:
		push_error("UI_R5_PANELS: " + failure)
	print("UI_R5_PANELS_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
