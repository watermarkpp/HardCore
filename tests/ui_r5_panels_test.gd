extends Node
## Uses the real installed panels, formatter, theme, and layout profiles.
## Runs only through the repository runner's isolated .godot/runtime_appdata.
const Inventory := preload("res://scripts/inventory_panel.gd")
const Warehouse := preload("res://scripts/warehouse_panel.gd")
const Shop := preload("res://scripts/shop_panel.gd")
const Menu := preload("res://scripts/system_menu_panel.gd")
const Loot := preload("res://scripts/loot_pickup.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
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
	expect(inventory.item_detail_presenter.debug_layout_valid(), "calibrated inventory has side space")
	expect(bag_region.grow(0.5).encloses(detail_rect), "inventory detail lies outside whole bag")
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
	expect(warehouse.item_detail_presenter.debug_layout_valid(), "warehouse left detail has space")
	expect(stash_region.grow(0.5).encloses(detail_rect), "stash detail left of whole viewport")
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
	expect(shop.item_detail_presenter.debug_layout_valid(), "shop detail has space")
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
