class_name HUDResourceOrb
extends Control

const LIQUID_RADIUS_RATIO := 0.49
const REFERENCE_DIAMETER := 93.0
const REFERENCE_FONT_SIZE := 15

@export var liquid_color := Color("9e1623"):
	set(value):
		liquid_color = value
		queue_redraw()
@export var resource_name := "生命"

var current_value := 0
var maximum_value := 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("stable_id", "ui.hud.resource_orb.metal_mask_fit.v2")
	set_meta("liquid_radius_ratio", LIQUID_RADIUS_RATIO)
	queue_redraw()


func set_values(current: int, maximum: int) -> void:
	var next_current := maxi(0, current)
	var next_maximum := maxi(1, maximum)
	if current_value == next_current and maximum_value == next_maximum:
		return
	current_value = next_current
	maximum_value = next_maximum
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * LIQUID_RADIUS_RATIO
	var ratio := clampf(float(current_value) / float(maximum_value), 0.0, 1.0)
	draw_circle(center, radius, Color(0.018, 0.012, 0.012, 0.98))
	draw_circle(center, radius - 2.0, liquid_color.darkened(0.67))
	var top_y := center.y + radius - ratio * radius * 2.0
	for y in range(int(ceil(top_y)), int(floor(center.y + radius)) + 1):
		var dy := float(y) - center.y
		var half_width := sqrt(maxf(0.0, radius * radius - dy * dy))
		var depth := clampf((float(y) - top_y) / maxf(1.0, radius * 2.0), 0.0, 1.0)
		var row_color := liquid_color.lightened(0.17 * (1.0 - depth))
		draw_line(Vector2(center.x - half_width, y), Vector2(center.x + half_width, y), row_color, 2.0)
	draw_arc(center, radius - 1.0, 0.0, TAU, 64, Color(0.78, 0.62, 0.40, 0.65), 2.0, true)
	draw_arc(center - Vector2(radius * 0.16, radius * 0.18), radius * 0.46, 3.45, 5.18, 24, Color(1, 1, 1, 0.23), 3.0, true)
	var font := ThemeDB.fallback_font
	var value_text := "%d/%d" % [current_value, maximum_value]
	var label_text := "%s\n%s" % [resource_name, value_text]
	var text_scale := minf(size.x, size.y) / REFERENCE_DIAMETER
	var font_size := maxi(1, roundi(REFERENCE_FONT_SIZE * text_scale))
	draw_multiline_string(font, Vector2(text_scale, center.y - 6 * text_scale), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 2.0 * text_scale, font_size, -1, Color(0.02, 0.01, 0.01, 0.95))
	draw_multiline_string(font, Vector2(0, center.y - 7 * text_scale), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, -1, Color("f4dfbf"))
