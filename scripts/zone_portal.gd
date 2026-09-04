class_name ZonePortal
extends Node2D

var target_zone := "比奇城"
var target_map_id := -1
var display_name := "前往比奇城"
var portal_role := "travel"
var portal_data: Dictionary = {}


func setup(zone: String, label_text: String) -> void:
	target_zone = zone
	target_map_id = -1
	display_name = label_text
	portal_role = "return" if "返回" in label_text else "travel"
	portal_data.clear()


func setup_map(
	map_id: int,
	label_text: String,
	runtime_portal_data: Dictionary = {}
) -> void:
	target_map_id = map_id
	target_zone = ""
	display_name = label_text
	portal_role = "return" if "返回" in label_text else ("deeper" if "进入" in label_text or "前往" in label_text else "travel")
	portal_data = runtime_portal_data.duplicate(true)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("zone_content")
	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-90, -78)
	label.size = Vector2(180, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", _role_color().lightened(0.25))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	queue_redraw()


func interact(game: Node) -> void:
	if target_map_id >= 0:
		if not portal_data.is_empty() and game.has_method("travel_via_portal"):
			game.travel_via_portal(self, true)
		else:
			game.travel_to_map(target_map_id)
	else:
		game.change_zone(target_zone)


func interaction_text() -> String:
	return display_name


func _draw() -> void:
	var color := _role_color()
	draw_circle(Vector2.ZERO, 46.0, Color(color.r * 0.32, color.g * 0.32, color.b * 0.32, 0.54))
	draw_circle(Vector2.ZERO, 38.0, Color(color.r, color.g, color.b, 0.22))
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, color, 4.0)


func _role_color() -> Color:
	match portal_role:
		"return": return Color(0.42, 0.92, 0.56)
		"deeper": return Color(1.0, 0.66, 0.20)
	return Color(0.42, 0.83, 1.0)
