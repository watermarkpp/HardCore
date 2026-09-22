class_name UILevelUpPreview
extends Node2D

## Pure level-up presentation. This node owns no progression state or gameplay
## signal wiring; a calibration or runtime owner supplies the anchor/playback.
const CONTRACT_ID := "ui.preview.level_up_foot_glow.v1"
const DURATION_SECONDS := 1.35
const RING_COUNT := 3
const FLAME_PETAL_COUNT := 8
const DRAW_POINT_COUNT := 48
const GROUND_PROJECTION_Y := 0.34
const FLAME_SIZE_SCALE := 0.75
const RENDER_PASS_FRONT := 0
const RENDER_PASS_BACK := 1

const OUTER_GLOW := Color("7b4a1f")
const BRONZE_GLOW := Color("c18a3b")
const GOLD_GLOW := Color("f1c875")
const FLAME_AMBER_GLOW := Color("d9973f")
const FLAME_CORE_GLOW := Color("fff0c2")

signal playback_started
signal playback_paused
signal playback_finished

var _elapsed_seconds := 0.0
var _playing := false
var _anchor := Vector2.ZERO
var _draw_polygon_attempts := 0
var _draw_polygon_skips := 0
var _draw_triangle_count := 0
var _drawn_petal_count := 0
var _render_pass := RENDER_PASS_FRONT
var _is_layer_clone := false
var _layer_split_enabled := false
var _back_layer: UILevelUpPreview


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("stable_id", CONTRACT_ID)
	set_meta("preview_only", true)
	set_meta("gameplay_event_source", "none")
	visible = false
	if _is_layer_clone:
		# The back pass is a sibling of the actor's body, not a child of the
		# front pass. This makes show_behind_parent place only the back petals
		# behind the actual actor while the owner remains on actor z=0.
		show_behind_parent = true
		set_process(false)
	else:
		_ensure_back_layer()
	queue_redraw()


func _ensure_back_layer() -> void:
	var parent := get_parent()
	if not parent is CanvasItem:
		return
	_layer_split_enabled = true
	_back_layer = UILevelUpPreview.new()
	_back_layer.name = "%sBackLayer" % name
	_back_layer._is_layer_clone = true
	_back_layer._render_pass = RENDER_PASS_BACK
	_back_layer._layer_split_enabled = true
	_back_layer.z_index = z_index
	_back_layer.z_as_relative = z_as_relative
	_back_layer.set_meta("render_domain", "actor_y_sort")
	_back_layer.set_meta("draw_order", "before_actor_body")
	parent.add_child(_back_layer)
	_back_layer.set_meta("stable_id", "%s.back" % CONTRACT_ID)


func _sync_back_layer() -> void:
	if not is_instance_valid(_back_layer):
		return
	_back_layer._mirror_playback_state(self)
	_back_layer.z_index = z_index
	_back_layer.z_as_relative = z_as_relative
	_back_layer.queue_redraw()


func _mirror_playback_state(source: UILevelUpPreview) -> void:
	_elapsed_seconds = source._elapsed_seconds
	_playing = source._playing
	_anchor = source._anchor
	position = source.position
	visible = source.visible


func _exit_tree() -> void:
	if not _is_layer_clone and is_instance_valid(_back_layer):
		_back_layer.queue_free()


func replay(anchor: Vector2 = Vector2.INF) -> void:
	if anchor.is_finite():
		set_anchor(anchor)
	_elapsed_seconds = 0.0
	_playing = true
	visible = true
	_sync_back_layer()
	playback_started.emit()
	queue_redraw()


func set_anchor(anchor: Vector2) -> void:
	if anchor.is_finite():
		_anchor = anchor
		position = anchor
		if is_instance_valid(_back_layer):
			_back_layer.set_anchor(anchor)


func play() -> void:
	if _elapsed_seconds >= DURATION_SECONDS:
		_elapsed_seconds = 0.0
	_playing = true
	visible = true
	_sync_back_layer()
	playback_started.emit()
	queue_redraw()


func pause() -> void:
	if not _playing:
		return
	_playing = false
	_sync_back_layer()
	playback_paused.emit()
	queue_redraw()


func reset() -> void:
	_elapsed_seconds = 0.0
	_playing = false
	visible = false
	_sync_back_layer()
	queue_redraw()


func is_playing() -> bool:
	return _playing


func progress() -> float:
	return clampf(_elapsed_seconds / DURATION_SECONDS, 0.0, 1.0)


func advance_preview(delta_seconds: float) -> void:
	if not _playing:
		return
	_elapsed_seconds += maxf(0.0, delta_seconds)
	if _elapsed_seconds >= DURATION_SECONDS:
		_elapsed_seconds = DURATION_SECONDS
		_playing = false
		playback_finished.emit()
	_sync_back_layer()
	queue_redraw()


func playback_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"stable_id": str(get_meta("stable_id", "")),
		"preview_only": bool(get_meta("preview_only", false)),
		"gameplay_event_source": str(get_meta("gameplay_event_source", "")),
		"anchor": _anchor,
		"visible": visible,
		"playing": _playing,
		"progress": progress(),
	}


func draw_safety_snapshot() -> Dictionary:
	var polygon_attempts := _draw_polygon_attempts
	var polygon_skips := _draw_polygon_skips
	var triangle_count := _draw_triangle_count
	var petals_drawn := _drawn_petal_count
	var front_petals := _drawn_petal_count if _render_pass == RENDER_PASS_FRONT else 0
	var back_petals := _drawn_petal_count if _render_pass == RENDER_PASS_BACK else 0
	if is_instance_valid(_back_layer):
		var back_snapshot := _back_layer.draw_safety_snapshot()
		polygon_attempts += int(back_snapshot.get("polygon_attempts", 0))
		polygon_skips += int(back_snapshot.get("invalid_polygon_skips", 0))
		triangle_count += int(back_snapshot.get("triangles_drawn", 0))
		petals_drawn += int(back_snapshot.get("petals_drawn", 0))
		front_petals += int(back_snapshot.get("front_petals", 0))
		back_petals += int(back_snapshot.get("back_petals", 0))
	return {
		"polygon_attempts": polygon_attempts,
		"invalid_polygon_skips": polygon_skips,
		"triangles_drawn": triangle_count,
		"petals_drawn": petals_drawn,
		"front_petals": front_petals,
		"back_petals": back_petals,
	}


func _process(delta: float) -> void:
	advance_preview(delta)


func _draw() -> void:
	_draw_polygon_attempts = 0
	_draw_polygon_skips = 0
	_draw_triangle_count = 0
	_drawn_petal_count = 0
	if not visible:
		return
	var t := progress()
	var fade_in := smoothstep(0.0, 0.12, t)
	var fade_out := 1.0 - smoothstep(0.78, 1.0, t)
	var alpha := fade_in * fade_out
	if alpha <= 0.0:
		return

	if _render_pass == RENDER_PASS_BACK:
		for petal_index in range(FLAME_PETAL_COUNT):
			_draw_flame_petal(petal_index, t, alpha)
		return

	# The lower ring is deliberately elliptical: it reads as light contacting a
	# ground plane beneath a sprite rather than a flat UI circle.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.34))
	for ring_index in range(RING_COUNT):
		var ring_phase := clampf(t * 1.35 - float(ring_index) * 0.14, 0.0, 1.0)
		var ring_radius := lerpf(24.0, 78.0, ease(ring_phase, 0.72))
		var ring_alpha := alpha * (0.62 - float(ring_index) * 0.13) * (1.0 - ring_phase * 0.58)
		draw_arc(
			Vector2.ZERO,
			ring_radius,
			0.0,
			TAU,
			DRAW_POINT_COUNT,
			Color(BRONZE_GLOW, ring_alpha),
			maxf(1.0, 3.2 - float(ring_index) * 0.8),
			true,
		)
	# A dim outer bloom grounds the brighter rune without a large opaque disc.
	draw_circle(Vector2.ZERO, lerpf(20.0, 43.0, t), Color(OUTER_GLOW, alpha * 0.08))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# The old orbiting shards and four-point rune deliberately do not return:
	# those hard segments read as a flat symbol in an oblique game view. Each
	# petal starts on the same projected ground ellipse as the preserved ring,
	# then rises as layered translucent flame shapes.
	for petal_index in range(FLAME_PETAL_COUNT):
		_draw_flame_petal(petal_index, t, alpha)


func petal_depth_pass(petal_index: int, t: float) -> String:
	return "back" if _petal_ground_base(petal_index, clampf(t, 0.0, 1.0)).y < 0.0 else "front"


func _petal_angle(petal_index: int, t: float) -> float:
	var phase := float(petal_index) / float(FLAME_PETAL_COUNT)
	return TAU * phase - t * TAU * 0.10 + sin(phase * TAU * 3.0) * 0.10


func _petal_ground_base(petal_index: int, t: float) -> Vector2:
	var angle := _petal_angle(petal_index, t)
	var radial := Vector2(cos(angle), sin(angle))
	var petal_wave := sin(float(petal_index) * 1.91 + t * TAU * 1.35)
	var ground_radius := lerpf(11.0, 34.0, ease(t, 0.72)) + petal_wave * 2.0
	return _project_ground(radial * ground_radius)


func _draw_flame_petal(petal_index: int, t: float, alpha: float) -> void:
	var angle := _petal_angle(petal_index, t)
	var radial := Vector2(cos(angle), sin(angle))
	var tangent := Vector2(-radial.y, radial.x)
	var petal_wave := sin(float(petal_index) * 1.91 + t * TAU * 1.35)
	var lean_wave := cos(float(petal_index) * 2.43 - t * TAU * 0.75)
	var ground_base := _petal_ground_base(petal_index, t)
	var behind_body := ground_base.y < 0.0
	if _layer_split_enabled:
		var expected_back := _render_pass == RENDER_PASS_BACK
		if behind_body != expected_back:
			return
	_drawn_petal_count += 1
	# The base follows the oblique ground plane; the flame body itself uses a
	# fixed screen-horizontal width and rises in screen Y instead of orbiting as
	# a flat circle around the actor.
	var ground_width := FLAME_SIZE_SCALE * lerpf(12.0, 7.0, ease(t, 0.55)) * (0.90 + absf(lean_wave) * 0.16)
	var rise := FLAME_SIZE_SCALE * lerpf(24.0, 60.0, ease(t, 0.82)) * (0.92 + absf(petal_wave) * 0.12)
	var ground_drift := _project_ground(tangent * lerpf(1.5, 7.0, ease(t, 0.68))) * lean_wave
	var flame_base := ground_base + ground_drift
	var tip_lean := clampf(
		tangent.x * lerpf(3.0, 8.0, ease(t, 0.66)) + petal_wave * 1.5,
		-ground_width * 0.16,
		ground_width * 0.16,
	)
	var outer_shape := _flame_layer_polygon(flame_base, ground_width, rise, tip_lean)
	_draw_if_triangulatable(outer_shape, Color(FLAME_AMBER_GLOW, alpha * 0.24))

	var middle_shape := _flame_layer_polygon(
		flame_base + Vector2(0.0, -rise * 0.06),
		ground_width * 0.70,
		rise * 0.88,
		tip_lean * 0.85,
	)
	_draw_if_triangulatable(middle_shape, Color(GOLD_GLOW, alpha * 0.44))

	var core_shape := _flame_layer_polygon(
		flame_base + Vector2(0.0, -rise * 0.02),
		ground_width * 0.42,
		rise * 0.73,
		tip_lean * 0.65,
	)
	_draw_if_triangulatable(core_shape, Color(FLAME_CORE_GLOW, alpha * 0.72))


func _flame_layer_polygon(
	base: Vector2,
	width: float,
	rise: float,
	tip_lean: float,
) -> PackedVector2Array:
	# The tip is clamped inside the shoulder span so this five-point flame is a
	# convex, always-triangulatable silhouette at every progress sample.
	var shoulder_width := width * 0.68
	var shoulder_y := -rise * 0.42
	var tip_x := clampf(tip_lean, -width * 0.16, width * 0.16)
	return PackedVector2Array([
		base + Vector2(-width, 0.0),
		base + Vector2(-shoulder_width, shoulder_y),
		base + Vector2(tip_x, -rise),
		base + Vector2(shoulder_width, shoulder_y),
		base + Vector2(width, 0.0),
	])


func _draw_if_triangulatable(polygon: PackedVector2Array, color: Color) -> void:
	_draw_polygon_attempts += 1
	var triangle_indices := Geometry2D.triangulate_polygon(polygon)
	if triangle_indices.size() < 3 or triangle_indices.size() % 3 != 0:
		_draw_polygon_skips += 1
		return
	_draw_triangle_count += triangle_indices.size() / 3
	# Fade each convex flame to transparent at its boundary. Solid polygon
	# fills read as spikes; a soft luminous core reads as rising light.
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	center /= float(polygon.size())
	var edge := Color(color, 0.0)
	for index in range(polygon.size()):
		draw_primitive(
			PackedVector2Array([center, polygon[index], polygon[(index + 1) % polygon.size()]]),
			PackedColorArray([color, edge, edge]),
			PackedVector2Array()
		)


func _project_ground(point: Vector2) -> Vector2:
	return Vector2(point.x, point.y * GROUND_PROJECTION_Y)


func ease(value: float, curve: float) -> float:
	return pow(clampf(value, 0.0, 1.0), curve)
