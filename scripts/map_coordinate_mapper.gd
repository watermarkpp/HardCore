class_name MapCoordinateMapper
extends RefCounted

# 经典客户端地砖采用64×32菱形；每个MAP逻辑格对应一个固定等距步长。
const CELL_HALF_WIDTH := 32.0
const CELL_HALF_HEIGHT := 16.0


static func source_to_world(source_coordinate: Vector2, source_size: Vector2i) -> Vector2:
	var center := (Vector2(source_size) - Vector2.ONE) * 0.5
	var local := source_coordinate - center
	return Vector2(
		(local.x - local.y) * CELL_HALF_WIDTH,
		(local.x + local.y) * CELL_HALF_HEIGHT,
	)


static func world_to_source(world_position: Vector2, source_size: Vector2i) -> Vector2:
	var horizontal := world_position.x / CELL_HALF_WIDTH
	var vertical := world_position.y / CELL_HALF_HEIGHT
	var center := (Vector2(source_size) - Vector2.ONE) * 0.5
	return center + Vector2((horizontal + vertical) * 0.5, (vertical - horizontal) * 0.5)


static func source_delta_to_world(source_delta: Vector2) -> Vector2:
	return Vector2(
		(source_delta.x - source_delta.y) * CELL_HALF_WIDTH,
		(source_delta.x + source_delta.y) * CELL_HALF_HEIGHT,
	)


static func world_delta_to_source(world_delta: Vector2) -> Vector2:
	var horizontal := world_delta.x / CELL_HALF_WIDTH
	var vertical := world_delta.y / CELL_HALF_HEIGHT
	return Vector2((horizontal + vertical) * 0.5, (vertical - horizontal) * 0.5)


static func contains_source(source_coordinate: Vector2, source_size: Vector2i) -> bool:
	return source_coordinate.x >= 0.0 and source_coordinate.y >= 0.0 and source_coordinate.x < source_size.x and source_coordinate.y < source_size.y


static func world_corners(source_size: Vector2i) -> PackedVector2Array:
	var maximum := Vector2(source_size - Vector2i.ONE)
	return PackedVector2Array([
		source_to_world(Vector2.ZERO, source_size),
		source_to_world(Vector2(maximum.x, 0), source_size),
		source_to_world(maximum, source_size),
		source_to_world(Vector2(0, maximum.y), source_size),
	])


static func world_bounds(source_size: Vector2i) -> Rect2:
	var corners := world_corners(source_size)
	var minimum := corners[0]
	var maximum := corners[0]
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


static func compact_candidate_to_source(compact_position: Vector2, source_size: Vector2i, margin_ratio := 0.06) -> Vector2i:
	# 将旧样板[-650,650]×[-350,350]的位置展开到原MAP；仅用于缺MapInfo时的C级候选。
	var normalized := Vector2(
		clampf((compact_position.x + 650.0) / 1300.0, 0.0, 1.0),
		clampf((compact_position.y + 350.0) / 700.0, 0.0, 1.0),
	)
	var margin := Vector2(source_size) * margin_ratio
	var maximum := Vector2(source_size - Vector2i.ONE) - margin
	return Vector2i((margin + normalized * (maximum - margin)).round())
