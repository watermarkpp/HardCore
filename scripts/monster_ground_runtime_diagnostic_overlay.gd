class_name MonsterGroundRuntimeDiagnosticOverlay
extends Node2D

const LAB_DIRECTION_LABELS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const ACTOR_ORIGIN_COLOR := Color("#ff9f43")
const MANUAL_FOOT_COLOR := Color("#4de1ff")
const TARGET_RING_COLOR := Color("#ffd54f")
const FOOTPRINT_COLOR := Color("#ff5c78")
const MAP_DIAMOND_COLOR := Color(0.55, 0.75, 1.0, 0.90)

var actor: Node2D


static func enabled_for_runtime() -> bool:
	# This overlay is intentionally limited to Android debug exports. It never
	# enters release builds, desktop tests, normal editor sessions, or gameplay
	# data. The current diagnostic APK therefore observes production rendering
	# without changing targeting, collision, animation, AI, or saved state.
	return OS.get_name() == "Android" and OS.is_debug_build()


func setup(owner_actor: Node2D) -> void:
	actor = owner_actor
	z_index = 100
	z_as_relative = true
	y_sort_enabled = false
	show_behind_parent = false


func _ready() -> void:
	set_process(true)
	visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(actor):
		visible = false
		return
	visible = not actor._dying
	if visible:
		queue_redraw()


func coordinate_snapshot() -> Dictionary:
	if not is_instance_valid(actor) or actor.visual == null:
		return {}
	var visual: MonsterVisual = actor.visual
	var actor_origin := Vector2.ZERO
	var manual_foot := visual.position + visual.visual_foot_offset()
	var runtime_ring: Vector2 = actor.ground_indicator_center()
	var logical_direction := _logical_direction_index(
		visual.current_direction,
		str(visual.active_resources.get("direction_mode", "")),
	)
	return {
		"monsterId": actor.monster_id,
		"monsterName": actor.display_name,
		"action": visual.current_state,
		"logicalDirection": logical_direction,
		"directionLabel": LAB_DIRECTION_LABELS[logical_direction],
		"sourceDirectionRow": visual.current_direction,
		"frame": visual.current_frame,
		"actorOrigin": actor_origin,
		"manualVisualFoot": manual_foot,
		"runtimeTargetRing": runtime_ring,
		"manualMinusActor": manual_foot - actor_origin,
		"ringMinusActor": runtime_ring - actor_origin,
		"ringMinusManual": runtime_ring - manual_foot,
		"visualPosition": visual.position,
		"spritePosition": (
			visual.sprite.position
			if visual.sprite != null
			else Vector2.ZERO
		),
		"visualFootOffset": visual.visual_foot_offset(),
	}


func _draw() -> void:
	var snapshot := coordinate_snapshot()
	if snapshot.is_empty():
		return
	var actor_origin: Vector2 = snapshot.actorOrigin
	var manual_foot: Vector2 = snapshot.manualVisualFoot
	var runtime_ring: Vector2 = snapshot.runtimeTargetRing
	var manual_minus_actor: Vector2 = snapshot.manualMinusActor
	var ring_minus_actor: Vector2 = snapshot.ringMinusActor
	var ring_minus_manual: Vector2 = snapshot.ringMinusManual
	var physics_radii := Vector2(
		actor.collision_radius,
		actor.collision_radius * 0.5,
	)
	var target_radii: Vector2 = actor.ground_indicator_radii()

	_draw_diamond(actor_origin, Vector2(32.0, 16.0), MAP_DIAMOND_COLOR, 1.5)
	_draw_ellipse(actor_origin, physics_radii, FOOTPRINT_COLOR, 2.0)
	_draw_ellipse(runtime_ring, target_radii, TARGET_RING_COLOR, 2.5)
	if not manual_foot.is_equal_approx(runtime_ring):
		draw_line(manual_foot, runtime_ring, Color("#ff6b6b"), 2.0, true)
	_draw_cross(actor_origin, ACTOR_ORIGIN_COLOR, 14.0, 4.0)
	_draw_cross(manual_foot, MANUAL_FOOT_COLOR, 10.0, 3.0)
	_draw_cross(runtime_ring, TARGET_RING_COLOR, 6.0, 2.0)

	var compact_text := "#%d %s/%s f%d" % [
		int(snapshot.monsterId),
		str(snapshot.action),
		str(snapshot.directionLabel),
		int(snapshot.frame),
	]
	var compact_origin := Vector2(-54.0, actor.health_bar_anchor_y() - 32.0)
	draw_rect(
		Rect2(compact_origin + Vector2(-4.0, -14.0), Vector2(108.0, 19.0)),
		Color(0.02, 0.03, 0.04, 0.72),
		true,
	)
	draw_string(
		ThemeDB.fallback_font,
		compact_origin,
		compact_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		104.0,
		11,
		Color("#f4e2bd"),
	)
	if actor.is_targeted:
		var detail_text := (
			"#%d %s  %s/%s src%d f%d\n"
			+ "O=(%.1f,%.1f) F=(%.1f,%.1f) R=(%.1f,%.1f)\n"
			+ "F-O=(%+.1f,%+.1f) R-O=(%+.1f,%+.1f) R-F=(%+.1f,%+.1f)"
		) % [
			int(snapshot.monsterId),
			str(snapshot.monsterName),
			str(snapshot.action),
			str(snapshot.directionLabel),
			int(snapshot.sourceDirectionRow),
			int(snapshot.frame),
			actor_origin.x,
			actor_origin.y,
			manual_foot.x,
			manual_foot.y,
			runtime_ring.x,
			runtime_ring.y,
			manual_minus_actor.x,
			manual_minus_actor.y,
			ring_minus_actor.x,
			ring_minus_actor.y,
			ring_minus_manual.x,
			ring_minus_manual.y,
		]
		var detail_origin := Vector2(-122.0, -132.0)
		draw_rect(
			Rect2(detail_origin + Vector2(-5.0, -17.0), Vector2(244.0, 58.0)),
			Color(0.02, 0.03, 0.04, 0.88),
			true,
		)
		draw_multiline_string(
			ThemeDB.fallback_font,
			detail_origin,
			detail_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			-1,
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


func _logical_direction_index(source_row: int, direction_mode: String) -> int:
	if direction_mode == "mir2_north_first":
		return wrapi(source_row + 4, 0, 8)
	return wrapi(source_row, 0, 8)
