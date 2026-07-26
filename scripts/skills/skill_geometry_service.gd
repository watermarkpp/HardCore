class_name SkillGeometryService
extends RefCounted


static func normalized_facing(value: Vector2i) -> Vector2i:
	if value == Vector2i.ZERO:
		return Vector2i.DOWN
	return Vector2i(signi(value.x), signi(value.y))


static func cells(definition: Dictionary, origin: Vector2i, facing: Vector2i, target_tile := Vector2i.ZERO) -> Array[Vector2i]:
	var geometry: Dictionary = definition.get("geometry", {})
	var shape := str(geometry.get("shape", "none"))
	var direction := normalized_facing(facing)
	var center := target_tile if target_tile != Vector2i.ZERO else origin
	var result: Array[Vector2i] = []
	match shape:
		"line":
			for distance in range(1, int(geometry.get("length_tiles", 1)) + 1):
				result.append(origin + direction * distance)
		"square":
			var width := int(geometry.get("width_tiles", 1))
			var height := int(geometry.get("height_tiles", 1))
			var min_x := -int(floor(float(width - 1) / 2.0))
			var min_y := -int(floor(float(height - 1) / 2.0))
			for y in range(min_y, min_y + height):
				for x in range(min_x, min_x + width):
					result.append(center + Vector2i(x, y))
		"adjacent_ring":
			for y in range(-1, 2):
				for x in range(-1, 2):
					if x != 0 or y != 0:
						result.append(origin + Vector2i(x, y))
		"chebyshev_ring":
			var radius := int(geometry.get("radius_tiles", 1))
			for y in range(-radius, radius + 1):
				for x in range(-radius, radius + 1):
					if x != 0 or y != 0:
						result.append(origin + Vector2i(x, y))
		"chebyshev_area":
			var radius := int(geometry.get("radius_tiles", 1))
			for y in range(-radius, radius + 1):
				for x in range(-radius, radius + 1):
					result.append(center + Vector2i(x, y))
		"project_canonical_four_target_arc":
			var left := Vector2i(direction.y, -direction.x)
			result = [origin + direction, origin + left, origin - left, origin - direction]
		_:
			if shape not in ["none", "none_until_next_melee_hit", "targeted", "targeted_light", "projectile", "sky_strike_targeted", "random_valid_map_destination", "nearest_valid_adjacent_tile", "line_push", "hexagon_boundary_approximated_on_8dir_grid"]:
				push_warning("未实现的技能几何形状：%s" % shape)
	return result
