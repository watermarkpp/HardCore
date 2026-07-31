class_name CircularTouchButton
extends Button


func _has_point(point: Vector2) -> bool:
	var radius := minf(size.x, size.y) * 0.5
	return point.distance_squared_to(size * 0.5) <= radius * radius
