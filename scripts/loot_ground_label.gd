class_name LootGroundLabel
extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

const COLOR_BY_KIND := {
	"currency": Color("f3cb62"),
	"quest_item": Color("e99752"),
	"equipment": Color("91c7ef"),
	"skill_book": Color("c197ef"),
	"consumable": Color("8bcf8c"),
	"material": Color("d8b884"),
}

var frame: Panel
var item_label: Label
var feedback_data: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = GothicUIThemeScript.build()
	frame = Panel.new()
	frame.name = "GroundLabelFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	item_label = Label.new()
	item_label.name = "ItemName"
	item_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_label.add_theme_font_size_override("font_size", 13)
	item_label.add_theme_color_override("font_outline_color", Color(0.01, 0.005, 0.003, 1.0))
	item_label.add_theme_constant_override("outline_size", 1)
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item_label)
	if not feedback_data.is_empty():
		_apply_data()


func setup(data: Dictionary) -> void:
	feedback_data = data.duplicate(true)
	var item_name := str(feedback_data.get("item_name", "未知物品"))
	var count := maxi(1, int(feedback_data.get("count", 1)))
	var suffix := " ×%d" % count if count > 1 else ""
	var estimated_width := clampi((item_name.length() + suffix.length()) * 14 + 16, 64, 180)
	size = Vector2(estimated_width, 24)
	if is_node_ready():
		_apply_data()


func _apply_data() -> void:
	var item_name := str(feedback_data.get("item_name", "未知物品"))
	var count := maxi(1, int(feedback_data.get("count", 1)))
	var suffix := " ×%d" % count if count > 1 else ""
	var item_kind := str(feedback_data.get("item_kind", "material"))
	var emphasis := str(feedback_data.get("emphasis", "normal"))
	item_label.text = "%s%s" % [item_name, suffix]
	item_label.add_theme_color_override(
		"font_color",
		Color("ffd37f") if emphasis in ["rare", "boss", "high_value"] else COLOR_BY_KIND.get(item_kind, Color("dfccb0"))
	)
	frame.theme_type_variation = "GothicLootRareGroundPanel" if emphasis in ["rare", "boss", "high_value"] else "GothicLootGroundPanel"
	frame.set_meta("stable_id", "loot.ground_label")
	frame.set_meta("item_kind", item_kind)
	frame.set_meta("emphasis", emphasis)
