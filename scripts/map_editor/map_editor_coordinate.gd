class_name MapEditorCoordinate
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const HALF_TILE_W := 32.0
const HALF_TILE_H := 16.0
const GROUND_COORDINATE_CONTRACT_ID := "isometric_cell_center_64x32_v1"
const GROUND_TILE_SIZE_PX := Vector2(64.0, 32.0)


static func origin_px(design_size: Vector2i) -> Vector2:
	return Vector2(design_size.y * HALF_TILE_W, HALF_TILE_H)


static func ground_image_size(design_size: Vector2i) -> Vector2i:
	return Vector2i((design_size.x + design_size.y) * int(HALF_TILE_W), (design_size.x + design_size.y) * int(HALF_TILE_H))


static func tile_to_ground_px(tile: Vector2, design_size: Vector2i) -> Vector2:
	var origin := origin_px(design_size)
	return Vector2(origin.x + (tile.x - tile.y) * HALF_TILE_W, origin.y + (tile.x + tile.y) * HALF_TILE_H)


static func cell_center_to_ground_px(cell: Vector2, design_size: Vector2i) -> Vector2:
	return tile_to_ground_px(cell + Vector2(0.5, 0.5), design_size)


static func cell_texture_rect_ground_px(cell: Vector2, design_size: Vector2i) -> Rect2:
	return Rect2(
		cell_center_to_ground_px(cell, design_size) - GROUND_TILE_SIZE_PX * 0.5,
		GROUND_TILE_SIZE_PX
	)


static func cell_polygon_ground_px(cell: Vector2i, design_size: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		tile_to_ground_px(Vector2(cell), design_size),
		tile_to_ground_px(Vector2(cell + Vector2i(1, 0)), design_size),
		tile_to_ground_px(Vector2(cell + Vector2i(1, 1)), design_size),
		tile_to_ground_px(Vector2(cell + Vector2i(0, 1)), design_size),
	])


static func ground_px_to_tile(ground_px: Vector2, design_size: Vector2i) -> Vector2:
	var relative := ground_px - origin_px(design_size)
	return Vector2(
		(relative.y / HALF_TILE_H + relative.x / HALF_TILE_W) * 0.5,
		(relative.y / HALF_TILE_H - relative.x / HALF_TILE_W) * 0.5,
	)


static func ground_px_to_cell(ground_px: Vector2, design_size: Vector2i) -> Vector2i:
	var lattice := ground_px_to_tile(ground_px, design_size)
	return Vector2i(floori(lattice.x), floori(lattice.y))


static func ground_px_to_grid_vertex(ground_px: Vector2, design_size: Vector2i) -> Vector2i:
	var lattice := ground_px_to_tile(ground_px, design_size)
	return Vector2i(roundi(lattice.x), roundi(lattice.y))


static func contains_grid_vertex(vertex: Vector2i, design_size: Vector2i) -> bool:
	return vertex.x >= 0 and vertex.y >= 0 and vertex.x <= design_size.x and vertex.y <= design_size.y


static func tile_to_world(tile: Vector2, design_size: Vector2i) -> Vector2:
	return ground_position_gu_to_screen_position_px(tile, design_size)


static func ground_position_gu_to_screen_position_px(
	ground_position_gu: Vector2,
	design_size: Vector2i
) -> Vector2:
	var center := (Vector2(design_size) - Vector2.ONE) * 0.5
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_position_gu - center
	)


static func cell_center_to_world(cell: Vector2, design_size: Vector2i) -> Vector2:
	return tile_to_world(cell + Vector2(0.5, 0.5), design_size)


static func cell_polygon_world(
	cell: Vector2i,
	design_size: Vector2i
) -> PackedVector2Array:
	return PackedVector2Array([
		tile_to_world(Vector2(cell), design_size),
		tile_to_world(Vector2(cell + Vector2i(1, 0)), design_size),
		tile_to_world(Vector2(cell + Vector2i(1, 1)), design_size),
		tile_to_world(Vector2(cell + Vector2i(0, 1)), design_size),
	])


static func world_to_tile(world: Vector2, design_size: Vector2i) -> Vector2:
	return screen_position_px_to_ground_position_gu(world, design_size)


static func screen_position_px_to_ground_position_gu(
	screen_position_px: Vector2,
	design_size: Vector2i
) -> Vector2:
	var center := (Vector2(design_size) - Vector2.ONE) * 0.5
	return center + GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_position_px
	)


static func ground_delta_gu_to_screen_delta_px(
	ground_delta_gu: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_delta_gu
	)


static func screen_delta_px_to_ground_delta_gu(
	screen_delta_px: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		screen_delta_px
	)


static func path_step_cost_gu(step: Vector2i) -> float:
	return GroundUnitSpaceScript.path_step_cost_gu(step)


static func world_to_cell(world: Vector2, design_size: Vector2i) -> Vector2i:
	var tile := world_to_tile(world, design_size)
	return Vector2i(floori(tile.x), floori(tile.y))


static func contains_tile(tile: Vector2, design_size: Vector2i) -> bool:
	return tile.x >= 0.0 and tile.y >= 0.0 and tile.x < design_size.x and tile.y < design_size.y


static func chunk_grid_for_ground_px(ground_px: Vector2, chunk_size: Vector2i) -> Vector2i:
	return Vector2i(floori(ground_px.x / chunk_size.x), floori(ground_px.y / chunk_size.y))


static func chunk_local_px(ground_px: Vector2, chunk_size: Vector2i) -> Vector2:
	var chunk := chunk_grid_for_ground_px(ground_px, chunk_size)
	return ground_px - Vector2(chunk * chunk_size)
