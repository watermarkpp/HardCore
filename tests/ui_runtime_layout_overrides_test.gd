extends Node

const Loader := preload("res://scripts/ui_runtime_layout_overrides.gd")
const InventoryPanel := preload("res://scripts/inventory_panel.gd")
const MapPanel := preload("res://scripts/map_panel.gd")
const ShopPanel := preload("res://scripts/shop_panel.gd")
const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const CharacterHallScene := preload("res://scenes/character_select.tscn")
const SystemMenuPanel := preload("res://scripts/system_menu_panel.gd")
const CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"
const EXPECTED_HASH := "5CB454AD13D75B43F24FF78949E7E9E9AB945E4BA4E12096717B6C7DE8397D36"

func _ready() -> void:
	assert(FileAccess.file_exists(CONTRACT), "tracked UI layout contract missing")
	assert(FileAccess.get_sha256(CONTRACT).to_upper() == EXPECTED_HASH, "UI layout contract hash changed")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	assert(data is Dictionary and int(data.get("schemaVersion", 0)) == 3)
	var profiles: Dictionary = data.get("profiles", {})
	for profile_id in ["character_hall", "inventory", "map", "quest", "shop_buy", "shop_sell", "skill", "system_menu", "warehouse"]:
		assert(profiles.has(profile_id), "missing profile: %s" % profile_id)
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
	add_child(inventory)
	add_child(map_panel)
	add_child(shop)
	add_child(skill)
	add_child(character_hall)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_saved_local_rect(inventory, "inventory", "BagPanel")
	_assert_saved_local_rect(map_panel, "map", "MapListPanel")
	_assert_saved_local_rect(shop, "shop_buy", "GoodsPanel")
	Loader.apply_profile(skill, "skill")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(skill.get_node_or_null("SkillDetailPanel/SkillDetailV3Frame") == null, "retired duplicate skill frame was recreated")
	assert(skill.get_node_or_null("SkillDetailPanel/LearnButton") == null, "retired skill learn button was recreated")
	var skill_retired: Array = skill.get_meta("calibration_retired_paths", [])
	assert("SkillDetailPanel/SkillDetailV3Frame" in skill_retired and "SkillDetailPanel/LearnButton" in skill_retired)
	_assert_saved_local_rect(character_hall, "character_hall", "CenteredContent")
	var retired_path := "BagPanel/BagPanelDecoration"
	var retired_entry: Dictionary = data["profiles"]["inventory"]["nodes"].get(retired_path, {})
	var retired_decoration := inventory.get_node_or_null(retired_path) as Control
	if bool(retired_entry.get("deleted", false)):
		assert(retired_decoration != null and not retired_decoration.visible, "saved deleted decoration was not hidden")
	var stats := inventory.get_node_or_null("AttributePanel/CharacterStats") as Control
	var stats_entry: Dictionary = data["profiles"]["inventory"]["nodes"].get("AttributePanel/CharacterStats", {})
	if stats != null and stats_entry.has("logicalFontSize"):
		assert(stats.get_theme_font_size("font_size") == int(stats_entry["logicalFontSize"]), "logical font size not restored")
	var buy_button := shop.get_node_or_null("DetailPanel/BuyButton") as Button
	assert(buy_button != null and buy_button.size.x >= 326.0 and buy_button.size.y >= 58.0, "button minimum clamp blocked saved size")
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
