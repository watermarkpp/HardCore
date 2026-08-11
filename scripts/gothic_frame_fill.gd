class_name GothicFrameFill
extends Control

enum ShapeMode {
	CHAMFERED,
	ROUNDED_INNER,
}

## Code-drawn fill shared by framed UI layers. It follows the generated
## single-ring frame's preserved 18 px corner region: the visible outer edge
## begins 4 px inside the control and the diagonal reaches the straight edge
## 12 px later. Drawing beneath the frame hides the seam without filling the
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
	if shape_mode == ShapeMode.ROUNDED_INNER:
		var fill_rect := Rect2(
			Vector2(content_insets.x, content_insets.y),
			size - Vector2(content_insets.x + content_insets.z, content_insets.y + content_insets.w),
		)
		if fill_rect.size.x <= 0.0 or fill_rect.size.y <= 0.0:
			return
		var style := StyleBoxFlat.new()
		style.bg_color = fill_color
		style.set_corner_radius_all(int(round(minf(corner_radius, minf(fill_rect.size.x, fill_rect.size.y) * 0.5))))
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
