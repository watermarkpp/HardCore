class_name GothicUITheme
extends RefCounted

const IRON := Color("181513")
const IRON_HOVER := Color("2b2119")
const IRON_PRESSED := Color("100d0c")
const BRONZE := Color("8d6940")
const BRONZE_BRIGHT := Color("c59a61")
const PARCHMENT := Color("ead8b7")
const MUTED := Color("a99479")
const BLOOD := Color("6e1519")
const MANA := Color("173d79")


static func build() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", PARCHMENT)
	result.set_color("font_shadow_color", "Label", Color(0.02, 0.01, 0.01, 0.95))
	result.set_constant("shadow_offset_x", "Label", 2)
	result.set_constant("shadow_offset_y", "Label", 2)
	result.set_type_variation("GothicInfoPanel", "Panel")
	result.set_stylebox("panel", "GothicInfoPanel", _flat(Color(0.025, 0.02, 0.018, 0.88), Color(0.42, 0.31, 0.20, 0.92), 2, 16))
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
	_apply_button_variation(result, "GothicUtilityButton", _flat(IRON, BRONZE, 2, 13), _flat(IRON_HOVER, BRONZE_BRIGHT, 2, 13), _flat(IRON_PRESSED, BRONZE_BRIGHT, 3, 13))
	_apply_button_variation(result, "GothicSkillButton", _flat(Color(0.08, 0.055, 0.045, 0.96), BRONZE, 3, 36), _flat(Color(0.18, 0.09, 0.05, 0.98), BRONZE_BRIGHT, 3, 36), _flat(Color(0.28, 0.07, 0.04, 1.0), Color("f0bd70"), 4, 36))
	_apply_button_variation(result, "GothicAttackButton", _flat(Color(0.24, 0.035, 0.035, 0.96), BRONZE, 4, 60), _flat(Color(0.38, 0.055, 0.04, 1.0), BRONZE_BRIGHT, 4, 60), _flat(Color(0.52, 0.08, 0.035, 1.0), Color("ffd08a"), 5, 60))
	_apply_button_variation(result, "GothicItemButton", _flat(Color(0.018, 0.015, 0.014, 0.86), Color(0.55, 0.39, 0.22, 0.22), 1, 5), _flat(Color(0.16, 0.09, 0.045, 0.88), BRONZE_BRIGHT, 2, 5), _flat(Color(0.25, 0.11, 0.04, 0.92), Color("e6b56f"), 2, 5))
	_apply_button_variation(result, "GothicTransparentButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0), _flat(Color(0.45, 0.22, 0.06, 0.12), Color(0.85, 0.66, 0.38, 0.55), 1, 9), _flat(Color(0.55, 0.12, 0.04, 0.20), BRONZE_BRIGHT, 2, 9))
	return result


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
