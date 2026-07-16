class_name IsoFootprintGeometry
extends RefCounted

const HALF_TILE := Vector2i(32, 16)


static func logical_canvas_size(footprint_tiles: Vector2i) -> Vector2i:
	var axis_sum := footprint_tiles.x + footprint_tiles.y
	return Vector2i(axis_sum * HALF_TILE.x, axis_sum * HALF_TILE.y)


static func logical_diamond(footprint_tiles: Vector2i) -> PackedVector2Array:
	var size := logical_canvas_size(footprint_tiles)
	return PackedVector2Array([
		Vector2(footprint_tiles.y * HALF_TILE.x, 0),
		Vector2(size.x, footprint_tiles.x * HALF_TILE.y),
		Vector2(footprint_tiles.x * HALF_TILE.x, size.y),
		Vector2(0, footprint_tiles.y * HALF_TILE.y),
	])


static func contains_logical_point(point: Vector2, footprint_tiles: Vector2i) -> bool:
	return Geometry2D.is_point_in_polygon(point, logical_diamond(footprint_tiles))


static func default_anchor_px(footprint_tiles: Vector2i) -> Vector2i:
	var size := logical_canvas_size(footprint_tiles)
	return Vector2i(size.x / 2, size.y / 2)
