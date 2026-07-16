class_name RouteBeacon
extends Node2D

var target_position := Vector2.ZERO
var route_label := "继续前进"
var _pulse := 0.0


func setup(origin: Vector2, target: Vector2, label_text: String) -> void:
	global_position = origin
	target_position = target
	route_label = label_text


func _ready() -> void:
	add_to_group("zone_content")
	add_to_group("route_guidance")
	var label := Label.new()
	label.text = route_label
	label.position = Vector2(-110, 45)
	label.size = Vector2(220, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func direction_to_target() -> Vector2:
	return global_position.direction_to(target_position)


func _draw() -> void:
	var direction := direction_to_target()
	var side := direction.orthogonal()
	var pulse_radius := 27.0 + sin(_pulse * 4.0) * 4.0
	draw_arc(Vector2.ZERO, pulse_radius, 0.0, TAU, 40, Color(1.0, 0.66, 0.18, 0.76), 3.0)
	draw_line(direction * 15.0, direction * 66.0, Color(1.0, 0.74, 0.24, 0.92), 5.0)
	var tip := direction * 78.0
	draw_colored_polygon(PackedVector2Array([tip, direction * 58.0 + side * 11.0, direction * 58.0 - side * 11.0]), Color(1.0, 0.72, 0.20, 0.95))
