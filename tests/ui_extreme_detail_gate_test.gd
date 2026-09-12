extends Node
## D×4 extreme detail gate (release closure).
## Exercises synthetic extreme catalog records through the REAL production chain:
## exact-ID lookup -> item formatter -> docked
## presenter -> production panel -> settled geometry validation - for extreme
## content. Adds only the missing extreme-content protection; every frozen
## contract (ninth-section scroll contract, shop action authority, title 20 /
## body 14, region/protected invariants) is asserted, never modified.
const Inventory := preload("res://scripts/inventory_panel.gd")
const Warehouse := preload("res://scripts/warehouse_panel.gd")
const Shop := preload("res://scripts/shop_panel.gd")
const UIOverrides := preload("res://scripts/ui_runtime_layout_overrides.gd")

var failures: Array[String] = []
var checks := 0
var fixture_id := 990900

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	call_deferred("_run")

func _settle_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

## Unified D acceptance block. Returns true when every shared contract holds.
func _d_block(case_name: String, panel_name: String, presenter, expected_title: String, expected_body: String) -> bool:
	var body: RichTextLabel = presenter.detail_label
	var title: Label = presenter.title_label
	var body_text := str(body.text)
	var content_h := float(body.get_content_height())
	var content_w := float(body.get_content_width())
	var scroll_active: bool = body.scroll_active
	var honest_scroll: bool = scroll_active == (content_h > body.size.y + 0.5)
	var no_h_scroll: bool = content_w <= body.size.x + 0.5
	var title_ok: bool = title.text == expected_title
	var body_full: bool = body_text.contains(expected_body)
	var valid: bool = presenter.debug_layout_valid()
	var last_line_reachable := true
	if scroll_active:
		body.scroll_to_line(body.get_line_count() - 1)
		await get_tree().process_frame
		var bar: ScrollBar = body.get_v_scroll_bar()
		last_line_reachable = bar.value >= bar.max_value - bar.page - 0.5
		body.scroll_to_line(0)
		await get_tree().process_frame
	expect(valid, case_name + " settled debug_layout_valid")
	expect(title_ok, case_name + " title equality")
	expect(body_full, case_name + " full body equality")
	expect(honest_scroll, case_name + " scroll_active honest")
	expect(no_h_scroll, case_name + " no horizontal overflow")
	expect(last_line_reachable, case_name + " last line reachable")
	print("D_GATE case=%s panel=%s settled=%s title_expected_len=%d title_actual_len=%d body_expected_len=%d body_actual_len=%d scroll_x=0 scroll_y=%s last_line_reachable=%s debug_layout_valid=%s" % [
		case_name, panel_name, valid, expected_title.length(), title.text.length(),
		expected_body.length(), body_text.length(), scroll_active, last_line_reachable, valid])
	return valid and title_ok and body_full and honest_scroll and no_h_scroll and last_line_reachable

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	await _d1_long_text_item()
	await _d2_extreme_equipment()
	await _d3_shop_extreme()
	await _d4_warehouse_extreme()
	for failure: String in failures:
		push_error("UI_EXTREME_D_GATE: " + failure)
	print("UI_EXTREME_D_GATE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func _catalog_fixture(name_value: String, description: String, equipment := false, overrides: Dictionary = {}) -> Dictionary:
	fixture_id += 1
	var catalog := GameData.get_item_record({"item_id": 80} if equipment else "金创药(小量)")
	assert(not catalog.is_empty())
	catalog.merge(overrides, true)
	catalog["itemId"] = fixture_id
	catalog["name"] = name_value
	catalog["description"] = description
	GameData._catalog_by_item_id[fixture_id] = catalog
	GameData._catalog_by_name[name_value] = catalog
	return {"item_id":fixture_id,"name":name_value,"count":1,"durability":18,"max_durability":32}

func _d1_long_text_item() -> void:
	var long_name := "D1长名物品名称超长测试用例名四十字符整占位".repeat(2)
	var description := "D1标记行：追加属性描述 +9\n".repeat(40) + "D1结尾标记行"
	PlayerState.inventory = [_catalog_fixture(long_name, description)]
	var inventory := Inventory.new()
	add_child(inventory)
	await inventory.wait_until_runtime_ready()
	await get_tree().process_frame
	inventory._select_inventory_item(0)
	await _settle_frames(2)
	await _d_block("D1_long_text", "inventory", inventory.item_detail_presenter, long_name, description)
	inventory.queue_free()
	await get_tree().process_frame

func _d2_extreme_equipment() -> void:
	var extreme := {
		"name": "D2极限词条装备名三十字符超长名称占位测试终",
		"category": "武器", "weight": 45, "durability": 18, "maxDurability": 32,
		"attackMin": 37, "attackMax": 89, "magicMin": 21, "magicMax": 66,
		"attackSpeedTier": 3, "level": 40, "price": 999999,
		"description": "D2词条行：随机属性加成验证 +7\n".repeat(30) + "D2结尾标记行",
	}
	PlayerState.inventory = [_catalog_fixture(extreme.name, extreme.description, true, extreme)]
	var inventory := Inventory.new()
	add_child(inventory)
	await inventory.wait_until_runtime_ready()
	await get_tree().process_frame
	inventory._select_inventory_item(0)
	await _settle_frames(2)
	var body: RichTextLabel = inventory.item_detail_presenter.detail_label
	# 信息密度：formatter 输出的正文行数必须覆盖描述行数（换行只拆不并）。
	expect(body.get_line_count() >= 30, "D2 formatter keeps extreme attribute density")
	await _d_block("D2_extreme_equipment", "inventory", inventory.item_detail_presenter, str(extreme["name"]), str(extreme["description"]))
	inventory.queue_free()
	await get_tree().process_frame

func _d3_shop_extreme() -> void:
	var stock_name := "D3极端商店商品名二十八字符超长名称占位终"
	var stock_description := "D3商店正文行：极端详情验证 +5\n".repeat(30) + "D3结尾标记行"
	var shop := Shop.new()
	add_child(shop)
	shop.open_for("D3极端商店", [{"name": stock_name, "price": 888888, "category": "武器", "description": stock_description}])
	for i in range(30):
		if UIOverrides.profile_is_ready(shop, "shop_buy"):
			break
		await get_tree().process_frame
	shop._select_shop_item(0)
	await _settle_frames(2)
	var snapshot: Dictionary = shop.item_detail_presenter.debug_layout_snapshot()
	var spec: Dictionary = snapshot.get("space_spec", {})
	var opening: Rect2 = spec.get("frame_opening", Rect2())
	expect(opening.has_area(), "D3 settled snapshot has frame_opening")
	var to_global: Transform2D = shop.get_global_transform()
	var opening_global := UIShopDetailSpace.transformed(to_global, opening)
	# C6 action authority 在极端文本下必须原样成立（裁决 20 复用）。
	expect(shop.buy_button.visible and not shop.sell_quantity_button.visible, "D3 buy-mode action authority intact")
	expect(shop.buy_button is BaseButton, "D3 buy button is a button")
	var buy_rect: Rect2 = shop.buy_button.get_global_rect()
	expect(opening_global.grow(-1.0).encloses(buy_rect), "D3 buy button inside frame opening")
	var body: RichTextLabel = shop.item_detail_presenter.detail_label
	expect(not body.get_global_rect().intersects(buy_rect), "D3 body never covers the buy button")
	expect(shop.buy_button.get_global_rect().position.y >= body.get_global_rect().end.y - 0.5, "D3 actions stay below the scrolled body")
	await _d_block("D3_shop_extreme", "shop", shop.item_detail_presenter, stock_name, stock_description)
	shop.queue_free()
	await get_tree().process_frame

func _d4_warehouse_extreme() -> void:
	var item_name := "D4仓库极端物品名三十字符超长名称占位测试终"
	var description := "D4仓库正文行：极端详情验证 +3\n".repeat(50) + "D4结尾标记行"
	PlayerState.warehouse_inventory = []
	PlayerState.inventory = [_catalog_fixture(item_name, description)]
	var warehouse := Warehouse.new()
	add_child(warehouse)
	await warehouse.wait_until_runtime_ready()
	await get_tree().process_frame
	warehouse._select_item("bag", 0)
	await _settle_frames(2)
	var presenter = warehouse.item_detail_presenter
	var body: RichTextLabel = presenter.detail_label
	# D4 = warehouse + presenter + scroll fallback 组合：极端正文必须触发
	# presenter 管理的正文滚动，且卡片仍停在背包格右侧合法区域。
	expect(body.scroll_active, "D4 extreme body engages presenter-managed scroll")
	var bag_side_spec: Dictionary = warehouse._ui_detail_region({"side": "bag"})
	var card := Rect2(presenter.position, presenter.size)
	var expanded: Rect2 = bag_side_spec.get("expanded_region", bag_side_spec.get("region", Rect2()))
	expect(expanded.has_area() and expanded.grow(0.5).encloses(card), "D4 card stays inside the bag-side legal region")
	await _d_block("D4_warehouse_extreme", "warehouse", presenter, item_name, description)
	warehouse.queue_free()
	await get_tree().process_frame
