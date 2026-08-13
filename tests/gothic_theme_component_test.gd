extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const MANIFEST_PATH := "res://assets/ui/gothic_theme/v1/sample/component_manifest.json"


func _ready() -> void:
	var theme := GothicUIThemeScript.build()
	for variation in ["GothicModalFrame", "GothicTitleBar", "GothicInsetFrame", "GothicTabFrame"]:
		assert(theme.has_stylebox("panel", variation), "%s 缺少公共Panel样式" % variation)
	for variation in ["GothicComponentButton", "GothicComponentSelectedButton", "GothicWarehouseThinButton", "GothicSkillConfigCompactButton", "GothicComponentTabButton", "GothicComponentSlotButton", "GothicComponentSelectedSlotButton", "GothicEquipmentSlotButton", "GothicSelectedEquipmentSlotButton", "GothicComponentShopCard", "GothicComponentSelectedShopCard", "GothicComponentCloseButton"]:
		assert(theme.has_stylebox("normal", variation), "%s 缺少normal样式" % variation)
		assert(theme.has_stylebox("pressed", variation), "%s 缺少pressed样式" % variation)
		assert(theme.has_stylebox("disabled", variation), "%s 缺少disabled样式" % variation)
	assert(FileAccess.file_exists(MANIFEST_PATH))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(manifest is Dictionary and manifest.get("revision", "").begins_with("v5-"))
	assert(manifest.get("components", []).size() >= 16)
	_assert_single_ring_contract(theme, manifest)
	_assert_main_hud_styles_preserved(theme)
	for entry: Variant in manifest.get("components", []):
		var image_path := "res://assets/ui/gothic_theme/v1/sample/%s" % entry.get("file", "")
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
		assert(image.get_pixel(0, 0).a < 0.04, "%s 的透明角未清理干净" % entry.get("id", ""))
	_assert_shop_card_contract(manifest)
	_assert_v3_fill_geometry()
	print("GOTHIC_THEME_COMPONENT_TEST_PASS：10类公共组件、透明角、商品卡安全区与Theme状态样式均通过")
	get_tree().quit(0)

func _assert_v3_fill_geometry() -> void:
	for bounds in [Vector2(129, 117), Vector2(340, 220), Vector2(492, 360), Vector2(900, 600)]:
		var inner := GothicFrameFillScript.v3_inner_rect_for_size(bounds)
		assert(inner.position.x >= 0.0 and inner.position.y >= 0.0)
		assert(inner.end.x <= bounds.x and inner.end.y <= bounds.y)
		assert(inner.size.x > 0.0 and inner.size.y > 0.0, "v3 fill collapsed at %s" % bounds)
		# The code fill must leave the measured 31/26 safety band intact.
		assert(is_equal_approx(inner.position.x, minf(31.0, bounds.x * 0.5)))
		assert(is_equal_approx(inner.position.y, minf(26.0, bounds.y * 0.5)))


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
	assert(inset_style.texture.resource_path.ends_with("inset_frame_v3.png"))
	assert(inset_style.texture.get_width() == 604 and inset_style.texture.get_height() == 327)
	assert(inset_style.texture_margin_left == 64 and inset_style.texture_margin_right == 64)
	assert(inset_style.texture_margin_top == 58 and inset_style.texture_margin_bottom == 58)
	assert(64 * 2 >= 120 and 58 * 2 >= 80)
	var button_style := theme.get_stylebox("normal", "GothicComponentButton") as AdaptiveButtonStyleBoxScript
	assert(button_style.compact.texture.resource_path.ends_with("button_compact_normal_v4.png"))
	assert(button_style.standard.texture.resource_path.ends_with("button_standard_normal_v4.png"))
	assert(button_style.wide.texture.resource_path.ends_with("button_wide_normal_v4.png"))
	assert(button_style.choose(Rect2(0,0,120,48)) == button_style.compact)
	assert(button_style.choose(Rect2(0,0,160,48)) == button_style.compact)
	assert(button_style.choose(Rect2(0,0,260,56)) == button_style.standard)
	assert(button_style.choose(Rect2(0,0,440,56)) == button_style.wide)
	var warehouse_style := theme.get_stylebox("normal", "GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
	var skill_config_style := theme.get_stylebox("normal", "GothicSkillConfigCompactButton") as AdaptiveButtonStyleBoxScript
	assert(warehouse_style.square_texture.resource_path == skill_config_style.square_texture.resource_path)
	assert(warehouse_style.shortwide_texture.resource_path == skill_config_style.shortwide_texture.resource_path)
	assert(warehouse_style.widesmall_texture.resource_path == skill_config_style.widesmall_texture.resource_path)
	assert(warehouse_style.selected_small_kind(Rect2(0, 0, 96, 48)) == &"shortwide")
	assert(warehouse_style.shortwide_texture.resource_path.ends_with("button_shortwide_normal_v5.png"))
	for state in ["pressed"]:
		var skill_state := theme.get_stylebox(state, "GothicSkillConfigCompactButton") as AdaptiveButtonStyleBoxScript
		var warehouse_state := theme.get_stylebox(state, "GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
		assert(warehouse_state.square_texture.resource_path == skill_state.square_texture.resource_path)
		assert(warehouse_state.shortwide_texture.resource_path == skill_state.shortwide_texture.resource_path)
		assert(warehouse_state.widesmall_texture.resource_path == skill_state.widesmall_texture.resource_path)
	var warehouse_disabled := theme.get_stylebox("disabled", "GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
	assert(warehouse_disabled.square_texture.resource_path.ends_with("button_square_normal_v5.png"))
	assert(warehouse_disabled.shortwide_texture.resource_path.ends_with("button_shortwide_normal_v5.png"))
	assert(warehouse_disabled.widesmall_texture.resource_path.ends_with("button_widesmall_normal_v5.png"))
	var square_style := theme.get_stylebox("normal", "GothicSkillConfigCompactButton") as AdaptiveButtonStyleBoxScript
	assert(square_style.square_texture.resource_path.ends_with("button_square_normal_v5.png"))
	assert(square_style.small_family and not square_style.force_square)
	for bounds in [Vector2(104,82), Vector2(108,60), Vector2(108,40)]:
		var rect := Rect2(Vector2.ZERO, bounds)
		var kind := square_style.selected_small_kind(rect)
		var expected := &"square" if bounds == Vector2(104,82) else (&"shortwide" if bounds == Vector2(108,60) else &"widesmall")
		assert(kind == expected)
		var draw_rect := square_style.selected_small_draw_rect(rect)
		var fill := square_style.selected_small_fill_rect(rect)
		assert(draw_rect == rect and fill.size.x > 0 and fill.size.y > 0)
		assert(fill.position.x >= rect.position.x and fill.end.x <= rect.end.x)
		assert(square_style.square_fill_style(fill).corner_radius_top_left > 0)


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
