extends "res://scripts/zone_portal.gd"
func interact(_game: Node) -> void: push_error("Source-only Portal interaction invoked on Main shell")
func _ready() -> void:
	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-90, _label_offset_y())
	label.size = Vector2(180, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", _role_color().lightened(0.25))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	queue_redraw()
