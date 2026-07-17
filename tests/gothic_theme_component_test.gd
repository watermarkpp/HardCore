extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const MANIFEST_PATH := "res://assets/ui/gothic_theme/v1/sample/component_manifest.json"


func _ready() -> void:
	var theme := GothicUIThemeScript.build()
	for variation in ["GothicModalFrame", "GothicTitleBar", "GothicInsetFrame", "GothicTabFrame"]:
		assert(theme.has_stylebox("panel", variation), "%s 缺少公共Panel样式" % variation)
	for variation in ["GothicComponentButton", "GothicComponentSelectedButton", "GothicComponentTabButton", "GothicComponentSlotButton", "GothicComponentSelectedSlotButton", "GothicEquipmentSlotButton", "GothicSelectedEquipmentSlotButton", "GothicComponentShopCard", "GothicComponentCloseButton"]:
		assert(theme.has_stylebox("normal", variation), "%s 缺少normal样式" % variation)
		assert(theme.has_stylebox("pressed", variation), "%s 缺少pressed样式" % variation)
		assert(theme.has_stylebox("disabled", variation), "%s 缺少disabled样式" % variation)
	assert(FileAccess.file_exists(MANIFEST_PATH))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(manifest is Dictionary and manifest.get("status", "") == "awaiting_user_review")
	assert(manifest.get("components", []).size() == 10, "公共Theme样板必须包含10类组件")
	for entry: Variant in manifest.get("components", []):
		var image_path := "res://assets/ui/gothic_theme/v1/sample/%s" % entry.get("file", "")
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
		assert(image.get_pixel(0, 0).a < 0.04, "%s 的透明角未清理干净" % entry.get("id", ""))
	_assert_shop_card_contract(manifest)
	print("GOTHIC_THEME_COMPONENT_TEST_PASS：10类公共组件、透明角、商品卡安全区与Theme状态样式均通过")
	get_tree().quit(0)


func _assert_shop_card_contract(manifest: Dictionary) -> void:
	var shop_card: Dictionary = {}
	for component: Variant in manifest.get("components", []):
		if component.get("id", "") == "ui.theme.gothic.v1.shop_card":
			shop_card = component
			break
	assert(not shop_card.is_empty(), "Shop card safe-area contract is missing")
	var source_size: Array = shop_card.get("size", [])
	assert(source_size.size() == 2 and int(source_size[0]) == 640 and int(source_size[1]) == 161, "Shop card source size must preserve its reviewed fixed aspect")
	assert(shop_card.get("stretchPolicy", "") == "fixed-aspect")
	var icon_safe_rect: Array = shop_card.get("iconSafeRectNormalized", [])
	var information_safe_rect: Array = shop_card.get("informationSafeRectNormalized", [])
	assert(icon_safe_rect.size() == 4 and information_safe_rect.size() == 4)
	assert(icon_safe_rect[0] + icon_safe_rect[2] < information_safe_rect[0], "Shop icon and information safe areas must not overlap")
