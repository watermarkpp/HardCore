class_name PlayerGroundRuntimeDiagnosticOverlay
extends Node2D

const ACTOR_ORIGIN_COLOR := Color("#ff9f43")
const VISUAL_FOOT_COLOR := Color("#4de1ff")
const FOOTPRINT_COLOR := Color("#ff5c78")
const MAP_DIAMOND_COLOR := Color(0.55, 0.75, 1.0, 0.90)

var actor: Node2D


static func enabled_for_runtime() -> bool:
	# Coordinate probes belong only to Android debug acceptance packages. They
	# never enter release behavior, player saves, combat, or collision rules.
	return OS.get_name() == "Android" and OS.is_debug_build()


func setup(owner_actor: Node2D) -> void:
	actor = owner_actor
	z_index = 100
	z_as_relative = true
	y_sort_enabled = false
	show_behind_parent = false


func _ready() -> void:
	queue_redraw()


func coordinate_snapshot() -> Dictionary:
	if not is_instance_valid(actor):
		return {}
	return {
		"actorOrigin": Vector2.ZERO,
		"physicsFootCenter": Vector2.ZERO,
		"delta": Vector2.ZERO,
	}


func _draw() -> void:
	if not is_instance_valid(actor):
		return
	var center := Vector2.ZERO
	_draw_diamond(center, Vector2(32.0, 16.0), MAP_DIAMOND_COLOR, 1.5)
	_draw_ellipse(center, Vector2(18.0, 9.0), FOOTPRINT_COLOR, 2.0)
	_draw_cross(center, ACTOR_ORIGIN_COLOR, 18.0, 3.0)
	_draw_cross(center, VISUAL_FOOT_COLOR, 11.0, 3.0)
	var label_origin := Vector2(-48.0, 30.0)
	draw_rect(
		Rect2(label_origin + Vector2(-4.0, -14.0), Vector2(96.0, 19.0)),
		Color(0.02, 0.03, 0.04, 0.72),
		true,
	)
	draw_string(
		ThemeDB.fallback_font,
		label_origin,
		"PLAYER FOOT 0,0",
		HORIZONTAL_ALIGNMENT_LEFT,
		92.0,
		11,
		Color("#f4e2bd"),
	)


func _draw_cross(
	center: Vector2,
	color: Color,
	half_size: float,
	width: float,
) -> void:
	draw_line(
		center + Vector2(-half_size, 0.0),
		center + Vector2(half_size, 0.0),
		color,
		width,
		true,
	)
	draw_line(
		center + Vector2(0.0, -half_size),
		center + Vector2(0.0, half_size),
		color,
		width,
		true,
	)


func _draw_ellipse(
	center: Vector2,
	radii: Vector2,
	color: Color,
	width: float,
) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		)
	draw_polyline(points, color, width, true)


func _draw_diamond(
	center: Vector2,
	radii: Vector2,
	color: Color,
	width: float,
) -> void:
	draw_polyline(
		PackedVector2Array([
			center + Vector2(0.0, -radii.y),
			center + Vector2(radii.x, 0.0),
			center + Vector2(0.0, radii.y),
			center + Vector2(-radii.x, 0.0),
			center + Vector2(0.0, -radii.y),
		]),
		color,
		width,
		true,
	)
