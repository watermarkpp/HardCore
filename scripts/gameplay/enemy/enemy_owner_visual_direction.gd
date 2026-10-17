extends RefCounted

static func _direction16_for_line(from_world_px: Vector2, to_world_px: Vector2) -> int:
	var fx := to_world_px.x - from_world_px.x
	var fy := to_world_px.y - from_world_px.y
	if fx == 0.0:
		return 0 if fy < 0.0 else 8
	if fy == 0.0:
		return 12 if fx < 0.0 else 4
	var result := 0
	if fx > 0.0 and fy < 0.0:
		result = 4
		if -fy > fx / 4.0:
			result = 3
		if -fy > fx / 1.9:
			result = 2
		if -fy > fx * 1.4:
			result = 1
		if -fy > fx * 4.0:
			result = 0
	if fx > 0.0 and fy > 0.0:
		result = 4
		if fy > fx / 4.0:
			result = 5
		if fy > fx / 1.9:
			result = 6
		if fy > fx * 1.4:
			result = 7
		if fy > fx * 4.0:
			result = 8
	if fx < 0.0 and fy > 0.0:
		result = 12
		if fy > -fx / 4.0:
			result = 11
		if fy > -fx / 1.9:
			result = 10
		if fy > -fx * 1.4:
			result = 9
		if fy > -fx * 4.0:
			result = 8
	if fx < 0.0 and fy < 0.0:
		result = 12
		if -fy > -fx / 4.0:
			result = 13
		if -fy > -fx / 1.9:
			result = 14
		if -fy > -fx * 1.4:
			result = 15
		if -fy > -fx * 4.0:
			result = 0
	return result


