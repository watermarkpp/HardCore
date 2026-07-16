class_name MobileLayout
extends RefCounted


static func safe_margins(window_size: Vector2, safe_rect: Rect2, logical_size: Vector2) -> Vector4:
	if window_size.x <= 0.0 or window_size.y <= 0.0 or safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return Vector4.ZERO
	var left := maxf(0.0, safe_rect.position.x / window_size.x * logical_size.x)
	var top := maxf(0.0, safe_rect.position.y / window_size.y * logical_size.y)
	var right_pixels := maxf(0.0, window_size.x - safe_rect.end.x)
	var bottom_pixels := maxf(0.0, window_size.y - safe_rect.end.y)
	var right := right_pixels / window_size.x * logical_size.x
	var bottom := bottom_pixels / window_size.y * logical_size.y
	return Vector4(left, top, right, bottom)


static func apply_display_safe_area(control: Control, viewport: Viewport) -> void:
	var logical_size := viewport.get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe_rect := Rect2(DisplayServer.get_display_safe_area())
	var margins := safe_margins(window_size, safe_rect, logical_size)
	control.offset_left = margins.x
	control.offset_top = margins.y
	control.offset_right = -margins.z
	control.offset_bottom = -margins.w
