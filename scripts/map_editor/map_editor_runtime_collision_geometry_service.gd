class_name MapEditorRuntimeCollisionGeometryService
extends RefCounted

const CONTRACT_ID := "map_editor_runtime_collision_geometry_v1"
const ELLIPSE_SEGMENTS := 32


static func cell_center_world(cell: Vector2i, design_size: Vector2i) -> Vector2:
	return MapEditorCoordinate.cell_center_to_world(Vector2(cell), design_size)


static func world_cell(world: Vector2, design_size: Vector2i) -> Vector2i:
	return MapEditorCoordinate.world_to_cell(world, design_size)


static func cell_polygon_world(
	cell: Vector2i,
	design_size: Vector2i
) -> PackedVector2Array:
	return MapEditorCoordinate.cell_polygon_world(cell, design_size)


static func rect_tile_bounds(rect: Array) -> Rect2:
	if rect.size() != 4:
		return Rect2()
	return Rect2(
		float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])
	)


static func rect_polygon_world(
	rect: Array,
	design_size: Vector2i
) -> PackedVector2Array:
	var bounds := rect_tile_bounds(rect)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return PackedVector2Array()
	var minimum := bounds.position
	var maximum := bounds.end
	return PackedVector2Array([
		MapEditorCoordinate.tile_to_world(minimum, design_size),
		MapEditorCoordinate.tile_to_world(
			Vector2(maximum.x, minimum.y), design_size
		),
		MapEditorCoordinate.tile_to_world(maximum, design_size),
		MapEditorCoordinate.tile_to_world(
			Vector2(minimum.x, maximum.y), design_size
		),
	])


static func polygon_world(
	points: Array,
	design_size: Vector2i
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for raw: Variant in points:
		if raw is Array and raw.size() == 2:
			result.append(MapEditorCoordinate.tile_to_world(
				Vector2(float(raw[0]), float(raw[1])), design_size
			))
	return result


static func ellipse_polygon_world(
	rect: Array,
	design_size: Vector2i,
	segments := ELLIPSE_SEGMENTS
) -> PackedVector2Array:
	var bounds := rect_tile_bounds(rect)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return PackedVector2Array()
	var center := bounds.position + bounds.size * 0.5
	var radius := bounds.size * 0.5
	var result := PackedVector2Array()
	for index in range(maxi(8, segments)):
		var angle := TAU * float(index) / float(maxi(8, segments))
		var tile_point := center + Vector2(
			cos(angle) * radius.x, sin(angle) * radius.y
		)
		result.append(MapEditorCoordinate.tile_to_world(tile_point, design_size))
	return result


static func manual_shape_polygon_world(
	manual: Dictionary,
	design_size: Vector2i
) -> PackedVector2Array:
	var data: Dictionary = manual.get("data", {})
	match str(manual.get("shape", "")):
		"cell":
			var raw_cell: Array = data.get("cell", data.get("tile", []))
			if raw_cell.size() == 2:
				return cell_polygon_world(
					Vector2i(int(raw_cell[0]), int(raw_cell[1])), design_size
				)
		"rect":
			return rect_polygon_world(data.get("rect", []), design_size)
		"ellipse":
			return ellipse_polygon_world(data.get("rect", []), design_size)
		"polygon":
			return polygon_world(data.get("points", []), design_size)
	return PackedVector2Array()


static func tile_shape_contains_world(
	manual: Dictionary,
	world: Vector2,
	design_size: Vector2i
) -> bool:
	var tile := MapEditorCoordinate.world_to_tile(world, design_size)
	var data: Dictionary = manual.get("data", {})
	match str(manual.get("shape", "")):
		"cell":
			var raw_cell: Array = data.get("cell", data.get("tile", []))
			return (
				raw_cell.size() == 2
				and Vector2i(floori(tile.x), floori(tile.y))
				== Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			)
		"rect":
			return rect_tile_bounds(data.get("rect", [])).has_point(tile)
		"ellipse":
			var bounds := rect_tile_bounds(data.get("rect", []))
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				return false
			var normalized := (tile - (bounds.position + bounds.size * 0.5)) / (
				bounds.size * 0.5
			)
			return normalized.length_squared() <= 1.0
		"polygon":
			return Geometry2D.is_point_in_polygon(
				tile, _tile_polygon(data.get("points", []))
			)
	return false


static func _tile_polygon(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for raw: Variant in points:
		if raw is Array and raw.size() == 2:
			result.append(Vector2(float(raw[0]), float(raw[1])))
	return result
