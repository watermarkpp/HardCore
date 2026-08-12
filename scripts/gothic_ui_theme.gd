class_name GothicUITheme
extends RefCounted

const GothicModalLayoutScript := preload("res://scripts/gothic_modal_layout.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")

const COMPONENT_ROOT := "res://assets/ui/gothic_theme/v1/sample"
const COMPONENT_V3_ROOT := COMPONENT_ROOT
const COMPONENT_MODAL_FRAME := preload(COMPONENT_ROOT + "/modal_frame.png")
const COMPONENT_TITLE_BAR := preload(COMPONENT_ROOT + "/title_bar.png")
const COMPONENT_INSET_FRAME := preload(COMPONENT_ROOT + "/inset_frame_single_v2.png")
const COMPONENT_TAB_FRAME := preload(COMPONENT_ROOT + "/tab_frame_single_v2.png")
const COMPONENT_BUTTON_NORMAL := preload(COMPONENT_ROOT + "/button_normal_single_v2.png")
const COMPONENT_BUTTON_PRESSED := preload(COMPONENT_ROOT + "/button_pressed_single_v2.png")
const COMPONENT_BUTTON_DISABLED := preload(COMPONENT_ROOT + "/button_disabled_single_v2.png")
const BUTTON_COMPACT_V4 := preload(COMPONENT_V3_ROOT + "/button_compact_normal_v4.png")
const BUTTON_STANDARD_V4 := preload(COMPONENT_V3_ROOT + "/button_standard_normal_v4.png")
const BUTTON_WIDE_V4 := preload(COMPONENT_V3_ROOT + "/button_wide_normal_v4.png")
const BUTTON_SQUARE_V5 := preload(COMPONENT_V3_ROOT + "/button_square_normal_v5.png")
const BUTTON_SHORTWIDE_V5 := preload(COMPONENT_V3_ROOT + "/button_shortwide_normal_v5.png")
const BUTTON_WIDESMALL_V5 := preload(COMPONENT_V3_ROOT + "/button_widesmall_normal_v5.png")
const COMPONENT_INSET_FRAME_V3 := preload(COMPONENT_V3_ROOT + "/inset_frame_v3.png")
const BUTTON_V3_PATCH := Vector4(34, 8, 34, 8)
const COMPONENT_ITEM_SLOT := preload(COMPONENT_ROOT + "/item_slot_single_v2.png")
const COMPONENT_SHOP_CARD := preload(COMPONENT_ROOT + "/shop_card_single_v2.png")
const COMPONENT_CLOSE_RING := preload(COMPONENT_ROOT + "/close_ring_single_v2.png")

const IRON := Color("181513")
const IRON_HOVER := Color("2b2119")
const IRON_PRESSED := Color("100d0c")
const BRONZE := Color("8d6940")
const BRONZE_BRIGHT := Color("c59a61")
const PARCHMENT := Color("ead8b7")
const MUTED := Color("a99479")
const BLOOD := Color("6e1519")
const MANA := Color("173d79")
const MODAL_CONTENT_SAFE_INSET := GothicModalLayoutScript.FRAME_SAFE_INSET


static func build() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", PARCHMENT)
	result.set_color("font_shadow_color", "Label", Color(0.02, 0.01, 0.01, 0.95))
	result.set_constant("shadow_offset_x", "Label", 2)
	result.set_constant("shadow_offset_y", "Label", 2)
	result.set_color("default_color", "RichTextLabel", PARCHMENT)
	result.set_color("font_color", "PopupMenu", PARCHMENT)
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	result.set_stylebox("panel", "ScrollContainer", _flat(Color(0.008, 0.007, 0.006, 0.72), Color(0.28, 0.20, 0.13, 0.62), 1, 8))
	result.set_stylebox("panel", "PopupMenu", _flat(Color(0.025, 0.018, 0.014, 0.98), BRONZE, 2, 8))
	result.set_stylebox("hover", "PopupMenu", _flat(Color(0.22, 0.08, 0.035, 0.96), BRONZE_BRIGHT, 1, 5))
	result.set_stylebox("separator", "PopupMenu", _flat(Color(0.18, 0.09, 0.04, 0.78), Color.TRANSPARENT, 0, 0))
	result.set_type_variation("GothicSectionTitle", "Label")
	result.set_color("font_color", "GothicSectionTitle", Color("f0c77f"))
	result.set_font_size("font_size", "GothicSectionTitle", 20)
	result.set_type_variation("GothicMutedLabel", "Label")
	result.set_color("font_color", "GothicMutedLabel", MUTED)
	result.set_font_size("font_size", "GothicMutedLabel", 14)
	result.set_type_variation("GothicDetailText", "RichTextLabel")
	result.set_color("default_color", "GothicDetailText", Color("d8c8ae"))
	result.set_font_size("normal_font_size", "GothicDetailText", 15)
	result.set_type_variation("GothicSearchField", "LineEdit")
	result.set_stylebox("normal", "GothicSearchField", _flat(Color(0.02, 0.016, 0.014, 0.96), Color(0.42, 0.31, 0.20, 0.92), 2, 8))
	result.set_stylebox("focus", "GothicSearchField", _flat(Color(0.035, 0.024, 0.018, 0.98), BRONZE_BRIGHT, 2, 8))
	result.set_stylebox("read_only", "GothicSearchField", _flat(Color(0.014, 0.012, 0.011, 0.90), Color(0.24, 0.19, 0.15, 0.9), 1, 8))
	result.set_color("font_color", "GothicSearchField", PARCHMENT)
	result.set_color("font_placeholder_color", "GothicSearchField", MUTED.darkened(0.12))
	result.set_color("caret_color", "GothicSearchField", BRONZE_BRIGHT)
	result.set_font_size("font_size", "GothicSearchField", 16)
	result.set_type_variation("GothicContentToggle", "CheckButton")
	result.set_stylebox("normal", "GothicContentToggle", _flat(Color(0.018, 0.015, 0.014, 0.86), Color(0.38, 0.28, 0.19, 0.8), 1, 8))
	result.set_stylebox("hover", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE, 1, 8))
	result.set_stylebox("pressed", "GothicContentToggle", _flat(Color(0.14, 0.065, 0.025, 0.96), BRONZE_BRIGHT, 1, 8))
	result.set_stylebox("focus", "GothicContentToggle", _flat(Color(0.09, 0.055, 0.028, 0.92), BRONZE_BRIGHT, 1, 8))
	result.set_color("font_color", "GothicContentToggle", PARCHMENT)
	result.set_color("font_hover_color", "GothicContentToggle", Color.WHITE)
	result.set_color("font_pressed_color", "GothicContentToggle", Color("ffe2ad"))
	result.set_font_size("font_size", "GothicContentToggle", 14)
	result.set_type_variation("GothicInfoPanel", "Panel")
	result.set_stylebox("panel", "GothicInfoPanel", _flat(Color(0.025, 0.02, 0.018, 0.88), Color(0.42, 0.31, 0.20, 0.92), 1, 16))
	result.set_type_variation("GothicTargetPanel", "Panel")
	result.set_stylebox("panel", "GothicTargetPanel", _flat(Color(0.035, 0.018, 0.015, 0.91), Color(0.58, 0.34, 0.20, 0.96), 2, 18))
	result.set_type_variation("GothicSkillDisc", "Panel")
	result.set_stylebox("panel", "GothicSkillDisc", _flat(Color(0.08, 0.055, 0.045, 0.97), BRONZE, 3, 36))
	result.set_type_variation("GothicArtPanelFill", "Panel")
	result.set_stylebox("panel", "GothicArtPanelFill", _flat(Color(0.018, 0.016, 0.015, 0.86), Color.TRANSPARENT, 0, 14))
	result.set_type_variation("GothicArtToggleFill", "Panel")
	result.set_stylebox("panel", "GothicArtToggleFill", _flat(Color(0.19, 0.08, 0.16, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtNavFill", "Panel")
	result.set_stylebox("panel", "GothicArtNavFill", _flat(Color(0.055, 0.11, 0.16, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtBagFill", "Panel")
	result.set_stylebox("panel", "GothicArtBagFill", _flat(Color(0.17, 0.085, 0.025, 0.82), Color.TRANSPARENT, 0, 12))
	result.set_type_variation("GothicArtCircleFill", "Panel")
	result.set_stylebox("panel", "GothicArtCircleFill", _flat(Color(0.018, 0.022, 0.022, 0.88), Color.TRANSPARENT, 0, 40))
	result.set_type_variation("GothicArtAttackFill", "Panel")
	result.set_stylebox("panel", "GothicArtAttackFill", _flat(Color(0.30, 0.018, 0.018, 0.90), Color.TRANSPARENT, 0, 60))
	result.set_type_variation("GothicArtItemFill", "Panel")
	result.set_stylebox("panel", "GothicArtItemFill", _flat(Color(0.018, 0.015, 0.014, 0.94), Color.TRANSPARENT, 0, 7))
	result.set_type_variation("GothicModalSurface", "Panel")
	result.set_stylebox("panel", "GothicModalSurface", _flat(Color(0.018, 0.014, 0.012, 0.94), Color.TRANSPARENT, 0, 24))
	result.set_type_variation("GothicModalScrim", "Panel")
	result.set_stylebox("panel", "GothicModalScrim", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	var modal_frame_style := _texture(COMPONENT_MODAL_FRAME, Vector4(112, 96, 112, 96), 0)
	modal_frame_style.content_margin_left = MODAL_CONTENT_SAFE_INSET.x
	modal_frame_style.content_margin_top = MODAL_CONTENT_SAFE_INSET.y
	modal_frame_style.content_margin_right = MODAL_CONTENT_SAFE_INSET.z
	modal_frame_style.content_margin_bottom = MODAL_CONTENT_SAFE_INSET.w
	result.set_type_variation("GothicModalFrame", "Panel")
	result.set_stylebox("panel", "GothicModalFrame", modal_frame_style)
	result.set_type_variation("GothicModalFrameOverlay", "Panel")
	result.set_stylebox("panel", "GothicModalFrameOverlay", modal_frame_style)
	result.set_type_variation("GothicTitleBar", "Panel")
	result.set_stylebox("panel", "GothicTitleBar", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	result.set_type_variation("GothicInsetFrame", "Panel")
	result.set_stylebox("panel", "GothicInsetFrame", GothicFrameFactoryScript.create_inset_frame_style_v3())
	result.set_type_variation("GothicTabFrame", "Panel")
	result.set_stylebox("panel", "GothicTabFrame", _texture(COMPONENT_TAB_FRAME, Vector4(22, 18, 22, 18), 14))
	result.set_type_variation("GothicEquipmentSlotCaption", "Panel")
	result.set_stylebox("panel", "GothicEquipmentSlotCaption", _flat(Color(0.035, 0.024, 0.018, 0.98), Color(0.52, 0.37, 0.21, 0.96), 1, 3))
	result.set_type_variation("GothicLootGroundPanel", "Panel")
	result.set_stylebox("panel", "GothicLootGroundPanel", _flat(Color(0.13, 0.13, 0.125, 0.68), Color(0.58, 0.56, 0.52, 0.62), 1, 4))
	result.set_type_variation("GothicLootRareGroundPanel", "Panel")
	result.set_stylebox("panel", "GothicLootRareGroundPanel", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.76, 0.56, 0.30, 0.78), 1, 4))
	result.set_type_variation("GothicLootToastPanel", "Panel")
	result.set_stylebox("panel", "GothicLootToastPanel", _flat(Color(0.13, 0.13, 0.125, 0.68), Color(0.58, 0.56, 0.52, 0.62), 1, 4))
	result.set_type_variation("GothicLootErrorPanel", "Panel")
	result.set_stylebox("panel", "GothicLootErrorPanel", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.73, 0.38, 0.31, 0.76), 1, 4))
	result.set_type_variation("GothicLootRareBanner", "Panel")
	result.set_stylebox("panel", "GothicLootRareBanner", _flat(Color(0.13, 0.13, 0.125, 0.72), Color(0.76, 0.56, 0.30, 0.78), 1, 4))
	_apply_button_variation(result, "GothicUtilityButton", _flat(IRON, BRONZE, 2, 13), _flat(IRON_HOVER, BRONZE_BRIGHT, 2, 13), _flat(IRON_PRESSED, BRONZE_BRIGHT, 3, 13))
	_apply_button_variation(result, "GothicSkillButton", _flat(Color(0.08, 0.055, 0.045, 0.96), BRONZE, 3, 36), _flat(Color(0.18, 0.09, 0.05, 0.98), BRONZE_BRIGHT, 3, 36), _flat(Color(0.28, 0.07, 0.04, 1.0), Color("f0bd70"), 4, 36))
	_apply_button_variation(result, "GothicAttackButton", _flat(Color(0.24, 0.035, 0.035, 0.96), BRONZE, 4, 60), _flat(Color(0.38, 0.055, 0.04, 1.0), BRONZE_BRIGHT, 4, 60), _flat(Color(0.52, 0.08, 0.035, 1.0), Color("ffd08a"), 5, 60))
	_apply_button_variation(result, "GothicItemButton", _flat(Color(0.018, 0.015, 0.014, 0.86), Color(0.55, 0.39, 0.22, 0.22), 1, 5), _flat(Color(0.16, 0.09, 0.045, 0.88), BRONZE_BRIGHT, 2, 5), _flat(Color(0.25, 0.11, 0.04, 0.92), Color("e6b56f"), 2, 5))
	_apply_button_variation(result, "GothicHUDItemHitButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), _flat(Color(0.18, 0.09, 0.045, 0.18), Color.TRANSPARENT, 0, 7), _flat(Color(0.30, 0.11, 0.04, 0.24), Color.TRANSPARENT, 0, 7))
	_apply_button_variation(result, "GothicTransparentButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), _flat(Color(0.45, 0.22, 0.06, 0.12), Color(0.85, 0.66, 0.38, 0.55), 1, 9), _flat(Color(0.55, 0.12, 0.04, 0.20), BRONZE_BRIGHT, 2, 9))
	_apply_button_variation(result, "GothicPanelTransparentButton", _flat(Color.TRANSPARENT, Color(0.46, 0.33, 0.21, 0.86), 1, 9), _flat(Color(0.16, 0.08, 0.04, 0.72), BRONZE_BRIGHT, 1, 9), _flat(Color(0.26, 0.08, 0.035, 0.82), BRONZE_BRIGHT, 1, 9))
	result.set_stylebox("disabled", "GothicPanelTransparentButton", _flat(Color(0.035, 0.03, 0.028, 0.68), Color(0.24, 0.22, 0.20, 0.72), 1, 9))
	_apply_adaptive_button(result, "GothicComponentButton")
	_apply_adaptive_button(result, "GothicComponentSelectedButton")
	# 仓库操作按钮与技能典籍列表共用同一套已验收的 v4 金铜按钮。
	_apply_adaptive_button(result, "GothicWarehouseThinButton")
	_apply_skill_config_compact_button(result)
	_apply_texture_button_variation(result, "GothicComponentTabButton", COMPONENT_TAB_FRAME, COMPONENT_TAB_FRAME, COMPONENT_TAB_FRAME, Vector4(22, 18, 22, 18), 14)
	_apply_slot_button_variation(result, "GothicComponentSlotButton", false)
	_apply_slot_button_variation(result, "GothicComponentSelectedSlotButton", true)
	_apply_equipment_slot_button_variation(result, "GothicEquipmentSlotButton", false)
	_apply_equipment_slot_button_variation(result, "GothicSelectedEquipmentSlotButton", true)
	# Shop cards have a fixed icon/text split and scale as one cohesive asset.
	_apply_texture_button_variation(result, "GothicComponentShopCard", COMPONENT_SHOP_CARD, COMPONENT_SHOP_CARD, COMPONENT_BUTTON_DISABLED, Vector4.ZERO, 12)
	_apply_selected_shop_card_variation(result)
	# Circular controls keep their source aspect and are never nine-slice stretched.
	_apply_texture_button_variation(result, "GothicComponentCloseButton", COMPONENT_CLOSE_RING, COMPONENT_CLOSE_RING, COMPONENT_CLOSE_RING, Vector4.ZERO, 8)
	return result


static func modal_content_safe_rect(panel_size: Vector2) -> Rect2:
	return GothicModalLayoutScript.safe_rect(panel_size)


static func add_modal_frame_overlay(parent: Control) -> Panel:
	var overlay := Panel.new()
	overlay.name = "ModalFrameOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.theme_type_variation = "GothicModalFrameOverlay"
	parent.add_child(overlay)
	return overlay


static func _apply_button_variation(theme: Theme, variation: StringName, normal: StyleBox, hover: StyleBox, pressed: StyleBox) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("focus", variation, hover)
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_outline_color", variation, Color(0.03, 0.015, 0.01, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_texture_button_variation(theme: Theme, variation: StringName, normal_texture: Texture2D, pressed_texture: Texture2D, disabled_texture: Texture2D, margins: Vector4, content_margin: float) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, _texture(normal_texture, margins, content_margin))
	theme.set_stylebox("hover", variation, _texture(normal_texture, margins, content_margin))
	theme.set_stylebox("pressed", variation, _texture(pressed_texture, margins, content_margin))
	theme.set_stylebox("focus", variation, _texture(pressed_texture, margins, content_margin))
	theme.set_stylebox("disabled", variation, _texture(disabled_texture, margins, content_margin))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24))
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)

static func _apply_adaptive_button(theme: Theme, variation: StringName) -> void:
	theme.set_type_variation(variation, "Button")
	var n := AdaptiveButtonStyleBoxScript.new().configure(BUTTON_COMPACT_V4, BUTTON_STANDARD_V4, BUTTON_WIDE_V4)
	var p := AdaptiveButtonStyleBoxScript.new().configure(preload(COMPONENT_V3_ROOT + "/button_compact_pressed_v4.png"), preload(COMPONENT_V3_ROOT + "/button_standard_pressed_v4.png"), preload(COMPONENT_V3_ROOT + "/button_wide_pressed_v4.png"))
	var d := AdaptiveButtonStyleBoxScript.new().configure(preload(COMPONENT_V3_ROOT + "/button_compact_disabled_v4.png"), preload(COMPONENT_V3_ROOT + "/button_standard_disabled_v4.png"), preload(COMPONENT_V3_ROOT + "/button_wide_disabled_v4.png"))
	theme.set_stylebox("normal", variation, n); theme.set_stylebox("hover", variation, n); theme.set_stylebox("focus", variation, n)
	theme.set_stylebox("pressed", variation, p); theme.set_stylebox("disabled", variation, d)
	theme.set_color("font_color", variation, PARCHMENT); theme.set_color("font_hover_color", variation, Color.WHITE); theme.set_color("font_pressed_color", variation, Color("ffe2ad")); theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24)); theme.set_constant("outline_size", variation, 3)

static func _apply_skill_config_compact_button(theme: Theme) -> void:
	var variation := &"GothicSkillConfigCompactButton"
	theme.set_type_variation(variation, "Button")
	var n := AdaptiveButtonStyleBoxScript.new().configure_small(BUTTON_SQUARE_V5, BUTTON_SHORTWIDE_V5, BUTTON_WIDESMALL_V5)
	var p := AdaptiveButtonStyleBoxScript.new().configure_small(preload(COMPONENT_V3_ROOT + "/button_square_pressed_v5.png"), preload(COMPONENT_V3_ROOT + "/button_shortwide_pressed_v5.png"), preload(COMPONENT_V3_ROOT + "/button_widesmall_pressed_v5.png"))
	var d := AdaptiveButtonStyleBoxScript.new().configure_small(preload(COMPONENT_V3_ROOT + "/button_square_disabled_v5.png"), preload(COMPONENT_V3_ROOT + "/button_shortwide_disabled_v5.png"), preload(COMPONENT_V3_ROOT + "/button_widesmall_disabled_v5.png"))
	theme.set_stylebox("normal", variation, n); theme.set_stylebox("hover", variation, n); theme.set_stylebox("focus", variation, n)
	theme.set_stylebox("pressed", variation, p); theme.set_stylebox("disabled", variation, d)
	theme.set_color("font_color", variation, PARCHMENT); theme.set_color("font_hover_color", variation, Color.WHITE); theme.set_color("font_pressed_color", variation, Color("ffe2ad")); theme.set_color("font_disabled_color", variation, MUTED.darkened(0.24)); theme.set_constant("outline_size", variation, 3)



static func _apply_slot_button_variation(theme: Theme, variation: StringName, selected: bool) -> void:
	theme.set_type_variation(variation, "Button")
	var normal := _slot_box(Color("21150d"), Color("bd8644"), 1) if selected else _slot_box(Color("0c0a09"), Color("594532"), 1)
	var hover := _slot_box(Color("18110c"), Color("9a7044"), 1)
	var pressed := _slot_box(Color("26160c"), Color("d3a15e"), 1)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("focus", variation, hover)
	theme.set_stylebox("disabled", variation, _slot_box(Color("090807"), Color("332a22"), 1))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_hover_color", variation, Color.WHITE)
	theme.set_color("font_pressed_color", variation, Color("ffe2ad"))
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_equipment_slot_button_variation(theme: Theme, variation: StringName, selected: bool) -> void:
	theme.set_type_variation(variation, "Button")
	var normal := _equipment_slot_box(Color("21150d"), Color("c18a49"), 1) if selected else _equipment_slot_box(Color("0b0a09"), Color("72583b"), 1)
	var hover := _equipment_slot_box(Color("15100c"), Color("a77a46"), 1)
	var pressed := _equipment_slot_box(Color("25150b"), Color("d8a25b"), 1)
	theme.set_stylebox("normal", variation, normal)
	theme.set_stylebox("hover", variation, hover)
	theme.set_stylebox("pressed", variation, pressed)
	theme.set_stylebox("focus", variation, hover)
	theme.set_stylebox("disabled", variation, _equipment_slot_box(Color("080706"), Color("352b22"), 1))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _apply_selected_shop_card_variation(theme: Theme) -> void:
	var variation := &"GothicComponentSelectedShopCard"
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, _texture(COMPONENT_SHOP_CARD, Vector4.ZERO, 12, Color("ffd7a2")))
	theme.set_stylebox("hover", variation, _texture(COMPONENT_SHOP_CARD, Vector4.ZERO, 12, Color("ffe5bd")))
	theme.set_stylebox("pressed", variation, _texture(COMPONENT_SHOP_CARD, Vector4.ZERO, 12, Color("ffbe72")))
	theme.set_stylebox("focus", variation, _texture(COMPONENT_SHOP_CARD, Vector4.ZERO, 12, Color("ffe5bd")))
	theme.set_stylebox("disabled", variation, _texture(COMPONENT_SHOP_CARD, Vector4.ZERO, 12, Color(0.52, 0.48, 0.44, 0.76)))
	theme.set_color("font_color", variation, PARCHMENT)
	theme.set_color("font_outline_color", variation, Color(0.025, 0.012, 0.008, 1.0))
	theme.set_constant("outline_size", variation, 3)


static func _equipment_slot_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _flat(background, border, width, 1)
	style.anti_aliasing = false
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.78)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _slot_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _flat(background, border, width, 2)
	style.anti_aliasing = false
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _flat(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


static func _texture(texture: Texture2D, margins: Vector4, content_margin: float, modulate := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulate
	style.draw_center = true
	style.set_texture_margin(SIDE_LEFT, margins.x)
	style.set_texture_margin(SIDE_TOP, margins.y)
	style.set_texture_margin(SIDE_RIGHT, margins.z)
	style.set_texture_margin(SIDE_BOTTOM, margins.w)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style
