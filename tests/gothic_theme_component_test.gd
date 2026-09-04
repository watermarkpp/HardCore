extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const MANIFEST_PATH := "res://assets/ui/gothic_theme/v1/sample/component_manifest.json"
var _verified_layer_pairs: Dictionary = {}


func _ready() -> void:
	var build_started := Time.get_ticks_usec()
	var theme := GothicUIThemeScript.build()
	var cold_build_ms := float(Time.get_ticks_usec() - build_started) / 1000.0
	assert(cold_build_ms < 1000.0, "cold full Gothic theme build regressed: %.3f ms" % cold_build_ms)
	print("GOTHIC_FULL_THEME_COLD_BUILD_MS=%.3f" % cold_build_ms)
	assert(GothicUIThemeScript.build() == theme, "full Gothic theme must be shared after its first build")
	for variation in ["GothicModalFrame", "GothicTitleBar", "GothicInsetFrame", "GothicTabFrame"]:
		assert(theme.has_stylebox("panel", variation), "%s 缺少公共Panel样式" % variation)
	for variation in ["GothicComponentButton", "GothicComponentSelectedButton", "GothicWarehouseThinButton", "GothicSkillConfigCompactButton", "GothicComponentTabButton", "GothicComponentSlotButton", "GothicComponentSelectedSlotButton", "GothicEquipmentSlotButton", "GothicSelectedEquipmentSlotButton", "GothicComponentShopCard", "GothicComponentSelectedShopCard", "GothicComponentCloseButton", "GothicCharacterProfileButton", "GothicCharacterSelectedProfileButton", "GothicCharacterProfessionButton", "GothicCharacterSelectedProfessionButton", "GothicCharacterLaunchButton"]:
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
	_assert_shop_card_inventory_feedback(theme)
	_assert_button_interaction_feedback(theme)
	_assert_character_feedback(theme)
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
	var original_fill_colors := {
		&"GothicArtToggleFill": Color(0.19, 0.08, 0.16, 0.82),
		&"GothicArtNavFill": Color(0.055, 0.11, 0.16, 0.82),
		&"GothicArtBagFill": Color(0.17, 0.085, 0.025, 0.82),
		&"GothicArtAttackFill": Color(0.30, 0.018, 0.018, 0.90),
	}
	for fill_variation: StringName in original_fill_colors:
		var fill := theme.get_stylebox("panel", fill_variation) as StyleBoxFlat
		assert(fill != null, "Main HUD fill is missing: %s" % fill_variation)
		assert(fill.bg_color.is_equal_approx(original_fill_colors[fill_variation]), "Main HUD original fill changed: %s" % fill_variation)
	var transparent_hover := theme.get_stylebox("hover", "GothicTransparentButton") as StyleBoxFlat
	var transparent_pressed := theme.get_stylebox("pressed", "GothicTransparentButton") as StyleBoxFlat
	assert(transparent_hover != null and transparent_pressed != null)
	assert(transparent_hover.bg_color.a == 0.0 and transparent_hover.border_color.a == 0.0)
	assert(transparent_pressed.bg_color.a == 0.0 and transparent_pressed.border_color.a == 0.0)
	assert(transparent_pressed.shadow_size == 0 and transparent_pressed.shadow_color.a == 0.0, "transparent HUD press state retained the synthetic dark-red shadow")


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


func _assert_shop_card_inventory_feedback(theme: Theme) -> void:
	for state in ["normal", "pressed", "focus", "disabled"]:
		var inventory_style := theme.get_stylebox(state, "GothicComponentSlotButton") as StyleBoxFlat
		var shop_style := theme.get_stylebox(state, "GothicComponentShopCard") as StyleBoxFlat
		assert(shop_style != null and inventory_style != null)
		assert(shop_style.bg_color == inventory_style.bg_color, "交易卡%s背景没有复用背包格" % state)
		assert(shop_style.border_color == inventory_style.border_color, "交易卡%s边框没有复用背包格" % state)
		assert(shop_style.border_width_left == inventory_style.border_width_left, "交易卡%s边宽没有复用背包格" % state)
	var shop_normal := theme.get_stylebox("normal", "GothicComponentShopCard") as StyleBoxFlat
	var shop_hover := theme.get_stylebox("hover", "GothicComponentShopCard") as StyleBoxFlat
	assert(shop_hover.bg_color == shop_normal.bg_color and shop_hover.border_color == shop_normal.border_color, "交易卡触摸结束后仍会遗留hover边框")
	var selected_inventory := theme.get_stylebox("normal", "GothicComponentSelectedSlotButton") as StyleBoxFlat
	var selected_shop := theme.get_stylebox("normal", "GothicComponentSelectedShopCard") as StyleBoxFlat
	assert(selected_shop.bg_color == selected_inventory.bg_color and selected_shop.border_color == selected_inventory.border_color, "交易卡选中态没有复用背包格高亮")


func _assert_button_interaction_feedback(theme: Theme) -> void:
	# A real Button must expose every transient state through the public Theme,
	# while persistent selection is represented by the selected variation rather
	# than a hidden global timer or a second node layered on the layout.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		assert(theme.has_stylebox(state, "Button"), "基础 Button 缺少 %s 状态" % state)
		assert(theme.has_stylebox(state, "GothicComponentButton"), "公共按钮缺少 %s 状态" % state)
	var button := Button.new()
	button.theme = theme
	button.theme_type_variation = &"GothicComponentButton"
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(260, 56)
	var minimum_before := button.custom_minimum_size
	button.set_pressed_no_signal(true)
	assert(button.button_pressed, "真实 Button 无法保持 toggle 选中态")
	var regular_normal := button.get_theme_stylebox("normal")
	var regular_pressed := button.get_theme_stylebox("pressed")
	assert(regular_normal != null and regular_pressed != null and regular_normal != regular_pressed, "normal/pressed 没有可区分的视觉状态")
	var selected := Button.new()
	selected.theme = theme
	selected.theme_type_variation = &"GothicComponentSelectedButton"
	var selected_style := theme.get_stylebox("normal", &"GothicComponentSelectedButton") as AdaptiveButtonStyleBoxScript
	assert(selected_style != null and selected_style.has_feedback(), "持久选中变体没有代码高亮层")
	assert(selected_style != theme.get_stylebox("normal", &"GothicComponentButton"), "持久选中态与普通态复用了同一框体")
	assert(selected_style.compact.texture.resource_path.ends_with("button_compact_normal_v4.png"), "持久选中态必须复用正常暗金框体")
	var pressed_style := theme.get_stylebox("pressed", &"GothicComponentButton") as AdaptiveButtonStyleBoxScript
	assert(pressed_style != null and pressed_style.has_feedback(), "按下态没有代码高亮层")
	for variation in [&"GothicComponentButton", &"GothicComponentSelectedButton", &"GothicSkillConfigCompactButton", &"GothicWarehouseThinButton"]:
		var adaptive_pressed := theme.get_stylebox("pressed", variation) as AdaptiveButtonStyleBoxScript
		assert(adaptive_pressed != null and adaptive_pressed.feedback_layered, "%s must preserve its source frame in layered feedback" % variation)
		assert(adaptive_pressed.feedback_background_styles.size() > 0 and adaptive_pressed.feedback_frame_styles.size() > 0, "%s layered feedback cache missing" % variation)
		if variation in [&"GothicComponentButton", &"GothicComponentSelectedButton"]:
			assert(adaptive_pressed.compact.texture.resource_path.ends_with("button_compact_normal_v4.png"), "%s pressed state must preserve the normal source frame" % variation)
		else:
			assert(adaptive_pressed.square_texture.resource_path.ends_with("button_square_normal_v5.png"), "%s pressed state must preserve the normal source frame" % variation)
		for layer_key: String in adaptive_pressed.feedback_background_styles:
			var background := adaptive_pressed.feedback_background_styles[layer_key] as StyleBoxTexture
			var frame := adaptive_pressed.feedback_frame_styles[layer_key] as StyleBoxTexture
			assert(background.texture.resource_path.ends_with("_feedback_mask_v1.png"), "%s must use a precomputed feedback mask" % variation)
			assert(frame.texture.resource_path.ends_with("_frame_only_v1.png"), "%s must use a precomputed source frame" % variation)
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION, "entry")
	assert(button.get_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE, "") == GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION)
	assert(button.get_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_GROUP, "") == "entry")
	assert(button.has_theme_stylebox_override("normal"), "transition 反馈没有接管 normal 状态")
	assert(button.custom_minimum_size == minimum_before, "反馈状态修改了按钮校准尺寸")
	GothicUIThemeScript.clear_button_feedback(button)
	assert(not button.has_theme_stylebox_override("normal"), "清除反馈后残留 normal 覆盖")
	assert(not button.has_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE), "清除反馈后残留状态元数据")
	assert(GothicUIThemeScript.feedback_state_is_persistent(GothicUIThemeScript.BUTTON_FEEDBACK_SELECTED))
	assert(not GothicUIThemeScript.feedback_state_is_persistent(GothicUIThemeScript.BUTTON_FEEDBACK_BUSY))
	assert(GothicUIThemeScript.feedback_state_is_transient(GothicUIThemeScript.BUTTON_FEEDBACK_BUSY))
	for transient_state in [GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS, GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE]:
		GothicUIThemeScript.set_button_feedback(button, transient_state)
		assert(button.get_meta(GothicUIThemeScript.BUTTON_FEEDBACK_META_STATE, "") == transient_state)
		assert(button.has_theme_stylebox_override("normal"), "%s 反馈没有接管 normal 状态" % transient_state)
		GothicUIThemeScript.clear_button_feedback(button)
	button.free()
	selected.free()


func _assert_character_feedback(theme: Theme) -> void:
	for variation in [&"GothicCharacterSelectedProfileButton", &"GothicCharacterSelectedProfessionButton"]:
		for state in [&"normal", &"hover", &"focus", &"pressed"]:
			var style := theme.get_stylebox(state, variation) as AdaptiveButtonStyleBoxScript
			assert(style != null and style.feedback_layered, "character selected feedback must use the source-derived interior layer")
			assert(style.feedback_style.bg_color != Color.TRANSPARENT, "character selected feedback must provide an internal background")
			assert(style.feedback_background_styles.size() > 0 and style.feedback_frame_styles.size() > 0, "character selected feedback must cache background and frame-only layers")
			assert(style.feedback_style.border_color == Color.TRANSPARENT, "character selected feedback must not add a border over the source frame")
			_assert_source_frame_preserved(style)
	var launch_pressed := theme.get_stylebox("pressed", &"GothicCharacterLaunchButton") as AdaptiveButtonStyleBoxScript
	assert(launch_pressed != null, "character launch transition style must exist")
	assert(launch_pressed.feedback_layered, "opaque wide frame must draw transition feedback through cached layers")
	assert(launch_pressed.feedback_style.bg_color != Color.TRANSPARENT, "character launch transition must provide an internal background")
	assert(launch_pressed.wide != null and launch_pressed.wide.modulate_color == Color.WHITE, "character launch frame must remain unmodulated")
	assert(launch_pressed.feedback_background_styles.size() > 0 and launch_pressed.feedback_frame_styles.size() > 0, "character launch transition must cache background and frame-only layers")
	assert(launch_pressed.feedback_style.border_color == Color.TRANSPARENT, "character launch transition must not add a border over the source frame")
	_assert_source_frame_preserved(launch_pressed)


func _assert_source_frame_preserved(style: AdaptiveButtonStyleBoxScript) -> void:
	for key: String in style.feedback_frame_styles:
		var source_texture := ResourceLoader.load(key) as Texture2D
		var frame_style := style.feedback_frame_styles[key] as StyleBoxTexture
		var background_style := style.feedback_background_styles[key] as StyleBoxTexture
		assert(source_texture != null and frame_style != null and background_style != null)
		var layer_pair_key := "%s|%s|%s" % [key, frame_style.texture.resource_path, background_style.texture.resource_path]
		if _verified_layer_pairs.has(layer_pair_key):
			continue
		_verified_layer_pairs[layer_pair_key] = true
		assert(frame_style.modulate_color == Color.WHITE, "source frame layer must remain unmodulated for %s" % key)
		assert(background_style.modulate_color == style.feedback_style.bg_color, "feedback mask runtime color differs for %s" % key)
		var source := source_texture.get_image()
		var frame := frame_style.texture.get_image()
		var background := background_style.texture.get_image()
		assert(source.get_size() == frame.get_size() and frame.get_size() == background.get_size())
		var frame_pixels := 0
		var interior_pixels := 0
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var source_pixel := source.get_pixel(x, y)
				var frame_pixel := frame.get_pixel(x, y)
				var background_pixel := background.get_pixel(x, y)
				if frame_pixel.a > 0.01:
					frame_pixels += 1
					assert(frame_pixel.is_equal_approx(source_pixel), "source frame pixel changed for %s" % key)
				if background_pixel.a > 0.01:
					interior_pixels += 1
					assert(background_pixel.r > 0.99 and background_pixel.g > 0.99 and background_pixel.b > 0.99, "feedback asset must remain a white alpha mask for %s" % key)
					assert(frame_pixel.a <= 0.01, "feedback interior overlaps source frame for %s" % key)
		assert(frame_pixels > 0 and interior_pixels > 0, "layer split produced an empty frame or interior for %s" % key)
