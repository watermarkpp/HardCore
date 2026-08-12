class_name GothicFrameFill
extends Control

enum ShapeMode {
	CHAMFERED,
	ROUNDED_INNER,
	## Inner opening of inset_frame_v3.png.  This is deliberately code drawn:
	## the v3 texture has a transparent centre and must never be used as a fill.
	V3_INNER,
}

## Code-drawn fill shared by framed UI layers. V3_INNER follows the measured
## inner alpha edge of inset_frame_v3 (31 px horizontal, 26 px vertical at the
## source size). Drawing beneath the frame hides the seam without filling the
## transparent exterior corner triangles.
@export var fill_enabled := true:
	set(value):
		fill_enabled = value
		queue_redraw()
@export var fill_color := Color(0.018, 0.014, 0.012, 0.94):
	set(value):
		fill_color = value
		queue_redraw()
@export var shape_mode := ShapeMode.CHAMFERED:
	set(value):
		shape_mode = value
		queue_redraw()
@export_range(0.0, 32.0, 0.5) var outer_inset := 4.0:
	set(value):
		outer_inset = value
		queue_redraw()
@export_range(0.0, 48.0, 0.5) var corner_cut := 12.0:
	set(value):
		corner_cut = value
		queue_redraw()
@export var content_insets := Vector4.ZERO:
	set(value):
		content_insets = value
		queue_redraw()
@export_range(0.0, 96.0, 0.5) var corner_radius := 42.0:
	set(value):
		corner_radius = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()
func _draw() -> void:
	if not fill_enabled:
		return
	if shape_mode == ShapeMode.ROUNDED_INNER or shape_mode == ShapeMode.V3_INNER:
		var fill_rect := Rect2(
			Vector2(content_insets.x, content_insets.y),
			size - Vector2(content_insets.x + content_insets.z, content_insets.y + content_insets.w),
		)
		if fill_rect.size.x <= 0.0 or fill_rect.size.y <= 0.0:
			return
		var style := StyleBoxFlat.new()
		style.bg_color = fill_color
		var radius := corner_radius
		if shape_mode == ShapeMode.V3_INNER:
			# The source frame's inner opening is x=31..573, y=26..300.
			# Keep the fill inside that opening at every scale, including tiny
			# panels where the radius must collapse with the available space.
			radius = minf(radius, minf(fill_rect.size.x, fill_rect.size.y) * 0.5)
		style.set_corner_radius_all(int(round(radius)))
		style.anti_aliasing = true
		draw_style_box(style, fill_rect)
	else:
		var polygon := polygon_for_size(size, outer_inset, corner_cut)
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, fill_color)


static func polygon_for_size(bounds: Vector2, inset: float, cut: float) -> PackedVector2Array:
	var safe_inset := clampf(inset, 0.0, minf(bounds.x, bounds.y) * 0.5)
	var max_cut := maxf(0.0, minf(bounds.x, bounds.y) * 0.5 - safe_inset)
	var safe_cut := clampf(cut, 0.0, max_cut)
	var left := safe_inset
	var top := safe_inset
	var right := maxf(left, bounds.x - safe_inset)
	var bottom := maxf(top, bounds.y - safe_inset)
	return PackedVector2Array([
		Vector2(left + safe_cut, top),
		Vector2(right - safe_cut, top),
		Vector2(right, top + safe_cut),
		Vector2(right, bottom - safe_cut),
		Vector2(right - safe_cut, bottom),
		Vector2(left + safe_cut, bottom),
		Vector2(left, bottom - safe_cut),
		Vector2(left, top + safe_cut),
	])

## Deterministic geometry contract used by the v3 frame tests and preview tools.
static func v3_inner_rect_for_size(bounds: Vector2, insets := Vector4(31, 26, 31, 26)) -> Rect2:
	var left := clampf(insets.x, 0.0, bounds.x * 0.5)
	var top := clampf(insets.y, 0.0, bounds.y * 0.5)
	var right := clampf(insets.z, 0.0, bounds.x * 0.5)
	var bottom := clampf(insets.w, 0.0, bounds.y * 0.5)
	return Rect2(Vector2(left, top), Vector2(maxf(0.0, bounds.x - left - right), maxf(0.0, bounds.y - top - bottom)))
