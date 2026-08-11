extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const MANIFEST_PATH := "res://assets/ui/gothic_theme/v1/sample/component_manifest.json"


func _ready() -> void:
	var theme := GothicUIThemeScript.build()
	for variation in ["GothicModalFrame", "GothicTitleBar", "GothicInsetFrame", "GothicTabFrame"]:
		assert(theme.has_stylebox("panel", variation), "%s 缺少公共Panel样式" % variation)
	for variation in ["GothicComponentButton", "GothicComponentSelectedButton", "GothicComponentTabButton", "GothicComponentSlotButton", "GothicComponentSelectedSlotButton", "GothicEquipmentSlotButton", "GothicSelectedEquipmentSlotButton", "GothicComponentShopCard", "GothicComponentSelectedShopCard", "GothicComponentCloseButton"]:
		assert(theme.has_stylebox("normal", variation), "%s 缺少normal样式" % variation)
		assert(theme.has_stylebox("pressed", variation), "%s 缺少pressed样式" % variation)
		assert(theme.has_stylebox("disabled", variation), "%s 缺少disabled样式" % variation)
	assert(FileAccess.file_exists(MANIFEST_PATH))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(manifest is Dictionary and manifest.get("status", "") == "pending_system_screenshot_review")
	assert(manifest.get("components", []).size() == 10, "公共Theme样板必须包含10类组件")
	_assert_single_ring_contract(theme, manifest)
	_assert_main_hud_styles_preserved(theme)
	for entry: Variant in manifest.get("components", []):
		var image_path := "res://assets/ui/gothic_theme/v1/sample/%s" % entry.get("file", "")
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
		assert(image.get_pixel(0, 0).a < 0.04, "%s 的透明角未清理干净" % entry.get("id", ""))
	_assert_shop_card_contract(manifest)
	print("GOTHIC_THEME_COMPONENT_TEST_PASS：10类公共组件、透明角、商品卡安全区与Theme状态样式均通过")
	get_tree().quit(0)


func _assert_single_ring_contract(theme: Theme, manifest: Dictionary) -> void:
	var contract: Dictionary = manifest.get("frameContract", {})
	assert(int(contract.get("modalRingCount", 0)) == 2)
	assert(int(contract.get("titleRingCount", -1)) == 0)
	assert(int(contract.get("insetRingCount", 0)) == 1)
	assert(int(contract.get("buttonRingCount", 0)) == 1)
	for component: Variant in manifest.get("components", []):
		if component.get("id", "") == "ui.theme.gothic.v1.modal_frame":
			assert(int(component.get("ringCount", 0)) == 2 and component.get("policy", "") == "preserved")
		elif component.get("id", "") == "ui.theme.gothic.v1.title_bar":
			assert(int(component.get("ringCount", -1)) == 0)
		elif component.has("ringCount"):
			assert(int(component.get("ringCount", 0)) == 1, "%s must use one ring" % component.get("id", ""))
	for variation in ["GothicComponentSlotButton", "GothicComponentSelectedSlotButton", "GothicEquipmentSlotButton", "GothicSelectedEquipmentSlotButton", "GothicPanelTransparentButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := theme.get_stylebox(state, variation)
			if style is StyleBoxFlat:
				assert(style.border_width_left <= 1, "%s.%s reintroduced a thick border" % [variation, state])
	var inset_style := theme.get_stylebox("panel", "GothicInsetFrame") as StyleBoxTexture
	assert(inset_style.texture.resource_path.ends_with("inset_frame_single_v2.png"))
	var button_style := theme.get_stylebox("normal", "GothicComponentButton") as StyleBoxTexture
	assert(button_style.texture.resource_path.ends_with("button_normal_single_v2.png"))


func _assert_main_hud_styles_preserved(theme: Theme) -> void:
	var expected := {
		"GothicUtilityButton": [2, 2, 3],
		"GothicSkillButton": [3, 3, 4],
		"GothicAttackButton": [4, 4, 5],
		"GothicItemButton": [1, 2, 2],
		"GothicTransparentButton": [0, 1, 2],
	}
	for variation: String in expected:
		var widths: Array = expected[variation]
		for index in range(3):
			var state: String = ["normal", "hover", "pressed"][index]
			var style := theme.get_stylebox(state, variation) as StyleBoxFlat
			assert(style.border_width_left == int(widths[index]), "Main HUD style changed: %s.%s" % [variation, state])


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
