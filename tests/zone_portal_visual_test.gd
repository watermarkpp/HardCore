extends Node


func _ready() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/zone_portal.gd")
	assert(not source.is_empty(), "zone_portal.gd must be readable")
	var draw_start := source.find("func _draw()")
	var role_color_start := source.find("func _role_color()")
	assert(draw_start >= 0 and role_color_start > draw_start, "portal draw section is missing")
	var draw_source := source.substr(draw_start, role_color_start - draw_start)
	assert("draw_polyline" not in draw_source, "portal direction chevron must stay removed")
	assert("draw_arc" in draw_source, "portal boundary marker must remain visible")
	print("ZONE_PORTAL_VISUAL_PASS: entrance marker retained without direction chevron")
	get_tree().quit()
