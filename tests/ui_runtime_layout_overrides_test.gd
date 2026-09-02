extends Node

const Loader := preload("res://scripts/ui_runtime_layout_overrides.gd")
const InventoryPanel := preload("res://scripts/inventory_panel.gd")
const MapPanel := preload("res://scripts/map_panel.gd")
const ShopPanel := preload("res://scripts/shop_panel.gd")
const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const CharacterHallScene := preload("res://scenes/character_select.tscn")
const SystemMenuPanel := preload("res://scripts/system_menu_panel.gd")
const ConfirmationPanel := preload("res://scripts/gothic_confirmation_panel.gd")
const CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"
const EXPECTED_HASH := "B39B32DB401534C41E042468E51A10FEF1CF90F6667A04BC61A8DB90C5C6641A"

func _ready() -> void:
	assert(FileAccess.file_exists(CONTRACT), "tracked UI layout contract missing")
	assert(FileAccess.get_sha256(CONTRACT).to_upper() == EXPECTED_HASH, "UI layout contract hash changed")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	assert(data is Dictionary and int(data.get("schemaVersion", 0)) == 3)
	var profiles: Dictionary = data.get("profiles", {})
	var inventory_nodes: Dictionary = profiles.get("inventory", {}).get("nodes", {})
	assert(inventory_nodes.size() == 40, "inventory profile must contain only stable authored layers")
	for saved_path: String in inventory_nodes.keys():
		assert(
			not saved_path.begins_with("BagPanel/InventoryScroll/ItemGrid/"),
			"inventory profile must not persist runtime-owned cells: %s" % saved_path
		)
	for profile_id in ["character_hall", "confirmation_dialog", "death_revival", "inventory", "map", "quest", "shop_buy", "shop_sell", "skill", "system_menu", "warehouse"]:
		assert(profiles.has(profile_id), "missing profile: %s" % profile_id)
		for saved_path: String in (profiles[profile_id] as Dictionary).get("nodes", {}).keys():
			assert(
				not saved_path.contains("@Label@"),
				"authored text layers require stable semantic paths: %s/%s" % [profile_id, saved_path]
			)
	var root := Control.new()
	root.name = "SystemMenuRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var root_size_before := root.size
	var root_anchors_before := Vector4(root.anchor_left, root.anchor_top, root.anchor_right, root.anchor_bottom)
	var modal := Control.new()
	modal.name = "SystemMenuModal"
	modal.size = Vector2(500, 608)
	root.add_child(modal)
	var title := Label.new()
	title.name = "MainTitle"
	title.text = "动态标题"
	modal.add_child(title)
	Loader.apply_profile(root, "system_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(root.size.is_equal_approx(root_size_before) and Vector4(root.anchor_left, root.anchor_top, root.anchor_right, root.anchor_bottom) == root_anchors_before, "profile application must not rewrite root full-rect geometry")
	assert(title.text == "动态标题", "runtime loader must never freeze calibrated text")
	var before := modal.get_global_rect()
	Loader.apply_profile(root, "system_menu")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(modal.get_global_rect().is_equal_approx(before), "repeated application must be idempotent")
	var transient := Control.new()
	add_child(transient)
	Loader.apply_profile(transient, "system_menu")
	transient.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var inventory := InventoryPanel.new()
	var map_panel := MapPanel.new()
	var shop := ShopPanel.new()
	var skill := SkillPanelScript.new()
	var character_hall := CharacterHallScene.instantiate() as Control
	var warehouse := WarehousePanel.new()
	var confirmation := ConfirmationPanel.new()
	add_child(inventory)
	add_child(map_panel)
	add_child(shop)
	add_child(skill)
	add_child(character_hall)
	add_child(warehouse)
	add_child(confirmation)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var runtime_stats_text := "runtime stats sentinel"
	var runtime_detail_text := "runtime detail sentinel"
	var runtime_summary_text := "runtime summary sentinel"
	var runtime_hint_text := "runtime hint sentinel"
	inventory.equipment_stats_label.text = runtime_stats_text
	inventory.detail_label.text = runtime_detail_text
	inventory.bag_summary_label.text = runtime_summary_text
	inventory.get_node("BagPanel/BagPagingHint").text = runtime_hint_text
	Loader.apply_profile(inventory, "inventory")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(inventory.equipment_stats_label.text == runtime_stats_text, "inventory runtime stats text was restored from stale profile")
	assert(inventory.detail_label.text == runtime_detail_text, "inventory runtime detail text was restored from stale profile")
	assert(inventory.bag_summary_label.text == runtime_summary_text, "inventory runtime summary text was restored from stale profile")
	assert(inventory.get_node("BagPanel/BagPagingHint").text == runtime_hint_text, "inventory runtime hint text was restored from stale profile")
	_assert_saved_local_rect(inventory, "inventory", "BagPanel")
	_assert_saved_local_rect(map_panel, "map", "MapListPanel")
	_assert_saved_local_rect(shop, "shop_sell", "GoodsPanel")
	_assert_saved_local_rect(shop, "shop_sell", "DetailPanel")
	Loader.apply_profile(skill, "skill")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(skill.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") == null, "retired duplicate skill frame was recreated")
	assert(skill.get_node_or_null("SkillDetailPanel/LearnButton") == null, "retired skill learn button was recreated")
	var skill_retired: Array = skill.get_meta("calibration_retired_paths", [])
	assert("SkillDetailPanel/SkillDetailV3Frame" in skill_retired and "SkillDetailPanel/LearnButton" in skill_retired)
	_assert_saved_local_rect(character_hall, "character_hall", "CenteredContent")
	_assert_saved_local_rect(confirmation, "confirmation_dialog", "ModalFrame")
	Loader.apply_profile(warehouse, "warehouse")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	for grid in [warehouse.stash_grid, warehouse.bag_grid]:
		var first_cell := (grid as GridContainer).get_child(0) as Control
		var sixth_cell := (grid as GridContainer).get_child(5) as Control
		var seventh_cell := (grid as GridContainer).get_child(6) as Control
		for cell in [first_cell, sixth_cell, seventh_cell]:
			var item_button := cell.get_node("ItemButton") as Button
			assert(item_button.position == Vector2.ZERO and item_button.size == WarehousePanel.ITEM_CELL_SIZE, "runtime旧八列数据覆盖了动态物品按钮局部矩形")
		assert(first_cell.position.y == sixth_cell.position.y, "runtime profile载入后首行不足六格")
		assert(seventh_cell.position.y > sixth_cell.position.y and seventh_cell.position.x == first_cell.position.x, "runtime profile载入后第七格没有换行")
	var retired_path := "BagPanel/BagPanelDecoration"
	var retired_entry: Dictionary = data["profiles"]["inventory"]["nodes"].get(retired_path, {})
	var retired_decoration := inventory.get_node_or_null(retired_path) as Control
	if bool(retired_entry.get("deleted", false)):
		assert(retired_decoration != null and not retired_decoration.visible, "saved deleted decoration was not hidden")
	var stats := inventory.get_node_or_null("AttributePanel/CharacterStats") as Control
	var stats_entry: Dictionary = data["profiles"]["inventory"]["nodes"].get("AttributePanel/CharacterStats", {})
	if stats != null and stats_entry.has("logicalFontSize"):
		assert(stats.get_theme_font_size("font_size") == int(stats_entry["logicalFontSize"]), "logical font size not restored")
	for stable_title_path: String in [
		"AttributePanel/AttributeTitle",
		"AttributePanel/ItemDetailTitle",
		"EquipmentPanel/EquipmentTitle",
		"BagPanel/BagTitle",
	]:
		_assert_saved_local_rect(inventory, "inventory", stable_title_path)
	var buy_button := shop.get_node_or_null("DetailPanel/BuyButton") as Button
	assert(buy_button != null and buy_button.size.is_equal_approx(Vector2(270, 51)), "购买按钮没有保持新的统一操作按钮尺寸")
	shop._set_trade_mode("buy")
	shop._set_trade_mode("sell")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_saved_local_rect(shop, "shop_sell", "GoodsPanel")
	var menu := SystemMenuPanel.new()
	add_child(menu)
	await get_tree().process_frame
	menu.show_settings_page()
	assert(not menu.main_page.visible and menu.settings_page.visible, "system settings switch restored hidden main page")
	print("UI_RUNTIME_LAYOUT_OVERRIDES_TEST_PASS profiles=9 hash=%s no_text_freeze idempotent" % EXPECTED_HASH)
	get_tree().quit(0)


func _assert_saved_local_rect(target: Control, profile_id: String, path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var profile: Dictionary = data["profiles"][profile_id]
	var expected: Array = profile["nodes"][path]["logicalRect"]
	var design: Array = profile["logicalDesignSize"]
	var sx := target.size.x / float(design[0]) if target.size.x > 0.0 else 1.0
	var sy := target.size.y / float(design[1]) if target.size.y > 0.0 else 1.0
	var control := target.get_node_or_null(NodePath(path)) as Control
	assert(control != null, "%s missing %s" % [profile_id, path])
	assert(control.position.is_equal_approx(Vector2(float(expected[0]) * sx, float(expected[1]) * sy)) and control.size.is_equal_approx(Vector2(float(expected[2]) * sx, float(expected[3]) * sy)), "%s saved rect mismatch" % path)
