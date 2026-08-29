class_name MapEditorRuntimeCollisionGeometryService
extends RefCounted

const CONTRACT_ID := "map_editor_runtime_collision_geometry_v3"
const PHYSICS_SOURCE_ID := "published_blocked_cells_after_erasure_v1"
const ACTOR_BOUNDARY_CONTRACT_ID := "map_visible_ground_footprint_boundary_v4"
const PLAYER_FOOT_BOUNDARY_CONTRACT_ID := "map_player_foot_inside_visible_ground_v2"
const ELLIPSE_SEGMENTS := 32
const DEFAULT_BOUNDARY_MARGIN_GRID_STEPS := 8.0
const DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX := 18.0
const VISIBLE_BOUNDARY_PROJECTION_ITERATIONS := 32
const VISIBLE_BOUNDARY_EPSILON_PX := 0.01


static func map_inner_boundary_tile_polygon(
	design_size: Vector2i
) -> PackedVector2Array:
	# The v2 ground canvas contains the complete authored cell union.  Its
	# visible edge is therefore the logical vertex ring [0, design_size], which
	# is also the coordinate ring used by cell polygons and runtime actors.
	var minimum := Vector2.ZERO
	var maximum := Vector2(design_size)
	return PackedVector2Array([
		minimum,
		Vector2(maximum.x, minimum.y),
		maximum,
		Vector2(minimum.x, maximum.y),
	])


static func map_outer_boundary_tile_polygon(
	design_size: Vector2i,
	margin_grid_steps := DEFAULT_BOUNDARY_MARGIN_GRID_STEPS
) -> PackedVector2Array:
	var margin := maxf(0.0, margin_grid_steps)
	var minimum := Vector2.ZERO - Vector2.ONE * margin
	var maximum := (
		Vector2(design_size) + Vector2.ONE * margin
	)
	return PackedVector2Array([
		minimum,
		Vector2(maximum.x, minimum.y),
		maximum,
		Vector2(minimum.x, maximum.y),
	])


static func tile_polygon_world(
	tile_polygon: PackedVector2Array,
	design_size: Vector2i
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for tile_point: Vector2 in tile_polygon:
		result.append(
			MapEditorCoordinate.ground_position_gu_to_screen_position_px(
				tile_point, design_size
			)
		)
	return result


static func map_inner_boundary_world(
	design_size: Vector2i
) -> PackedVector2Array:
	return tile_polygon_world(
		map_inner_boundary_tile_polygon(design_size), design_size
	)


static func map_actor_boundary_world(
	design_size: Vector2i,
	_clearance_px := DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX
) -> PackedVector2Array:
	# The collision ring starts on the exact rendered-ground edge. CharacterBody2D
	# contributes its own foot ellipse, so the resulting contact position keeps
	# that complete ellipse on visible ground. Expanding this polygon by the
	# actor radius created a second coordinate system and allowed feet into black.
	return map_inner_boundary_world(design_size)


static func map_outer_boundary_world(
	design_size: Vector2i,
	clearance_px := DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX
) -> PackedVector2Array:
	var actor_boundary := map_actor_boundary_world(design_size, clearance_px)
	return _expand_convex_polygon(
		actor_boundary,
		DEFAULT_BOUNDARY_MARGIN_GRID_STEPS * MapEditorCoordinate.GROUND_TILE_SIZE_PX.y
	)


static func runtime_boundary_contains_world(
	world: Vector2,
	design_size: Vector2i,
	clearance_px := DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX
) -> bool:
	return Geometry2D.is_point_in_polygon(
		world, map_actor_boundary_world(design_size, clearance_px)
	)


static func default_player_foot_envelope_world() -> PackedVector2Array:
	# Only the foot contact ellipse is constrained to visible ground. The body,
	# hair, weapon and health bar may naturally overhang a sloped map edge.
	return WorldSpatialRules.actor_footprint_polygon_px(
		DEFAULT_ACTOR_BOUNDARY_CLEARANCE_PX
	)


static func project_player_foot_inside_boundary(
	world: Vector2,
	design_size: Vector2i
) -> Vector2:
	return project_world_envelope_inside_visible_boundary(
		world, design_size, default_player_foot_envelope_world()
	)


static func project_world_envelope_inside_visible_boundary(
	world: Vector2,
	design_size: Vector2i,
	envelope: PackedVector2Array
) -> Vector2:
	var boundary := map_inner_boundary_world(design_size)
	if boundary.size() < 3 or envelope.is_empty():
		return world
	var signed_area := _signed_area(boundary)
	var result := world
	for _iteration in VISIBLE_BOUNDARY_PROJECTION_ITERATIONS:
		var changed := false
		for edge_index in boundary.size():
			var following := (edge_index + 1) % boundary.size()
			var edge := boundary[following] - boundary[edge_index]
			var inward := Vector2(-edge.y, edge.x).normalized()
			if signed_area < 0.0:
				inward = -inward
			var minimum_margin := INF
			for offset: Vector2 in envelope:
				minimum_margin = minf(
					minimum_margin,
					inward.dot(result + offset - boundary[edge_index])
				)
			if minimum_margin < -VISIBLE_BOUNDARY_EPSILON_PX:
				result += inward * (
					-minimum_margin + VISIBLE_BOUNDARY_EPSILON_PX
				)
				changed = true
		if not changed:
			break
	return result


static func player_foot_inside_boundary(
	world: Vector2,
	design_size: Vector2i
) -> bool:
	return world_envelope_inside_visible_boundary(
		world, design_size, default_player_foot_envelope_world()
	)


static func world_envelope_inside_visible_boundary(
	world: Vector2,
	design_size: Vector2i,
	envelope: PackedVector2Array
) -> bool:
	var boundary := map_inner_boundary_world(design_size)
	if boundary.size() < 3 or envelope.is_empty():
		return true
	var signed_area := _signed_area(boundary)
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		var inward := Vector2(-edge.y, edge.x).normalized()
		if signed_area < 0.0:
			inward = -inward
		for offset: Vector2 in envelope:
			if (
				inward.dot(world + offset - boundary[edge_index])
				< -VISIBLE_BOUNDARY_EPSILON_PX
			):
				return false
	return true


static func _expand_convex_polygon(
	polygon: PackedVector2Array,
	distance: float
) -> PackedVector2Array:
	if polygon.size() < 3 or distance <= 0.0:
		return polygon
	var signed_area := 0.0
	for index in polygon.size():
		var following := (index + 1) % polygon.size()
		signed_area += _cross(polygon[index], polygon[following])
	var result := PackedVector2Array()
	for index in polygon.size():
		var previous := (index - 1 + polygon.size()) % polygon.size()
		var following := (index + 1) % polygon.size()
		var previous_edge := polygon[index] - polygon[previous]
		var next_edge := polygon[following] - polygon[index]
		var previous_normal := Vector2(
			previous_edge.y, -previous_edge.x
		).normalized()
		var next_normal := Vector2(next_edge.y, -next_edge.x).normalized()
		if signed_area < 0.0:
			previous_normal = -previous_normal
			next_normal = -next_normal
		var previous_line := polygon[index] + previous_normal * distance
		var next_line := polygon[index] + next_normal * distance
		var denominator := _cross(previous_edge, next_edge)
		if absf(denominator) <= 0.0001:
			result.append(polygon[index] + next_normal * distance)
			continue
		var ratio := _cross(next_line - previous_line, next_edge) / denominator
		result.append(previous_line + previous_edge * ratio)
	return result


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


static func _signed_area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for index in polygon.size():
		result += _cross(
			polygon[index],
			polygon[(index + 1) % polygon.size()]
		)
	return result


static func cell_center_world(cell: Vector2i, design_size: Vector2i) -> Vector2:
	return MapEditorCoordinate.grid_cell_to_screen_position_px(
		Vector2(cell), design_size
	)


static func blocked_cell_set(runtime_collision: Dictionary) -> Dictionary:
	var result := {}
	for raw_key: Variant in runtime_collision.get("blocked_tiles", []):
		var parts := str(raw_key).split(",")
		if parts.size() != 2:
			continue
		result["%d,%d" % [int(parts[0]), int(parts[1])]] = true
	return result


static func blocked_cell_runs(runtime_collision: Dictionary) -> Array[Rect2i]:
	var blocked_by_row := {}
	for key: String in blocked_cell_set(runtime_collision):
		var parts := key.split(",")
		var y := int(parts[1])
		var xs: Array = blocked_by_row.get(y, [])
		xs.append(int(parts[0]))
		blocked_by_row[y] = xs
	var rows: Array = blocked_by_row.keys()
	rows.sort()
	var result: Array[Rect2i] = []
	for raw_y: Variant in rows:
		var y := int(raw_y)
		var xs: Array = blocked_by_row[y]
		xs.sort()
		if xs.is_empty():
			continue
		var run_start := int(xs[0])
		var previous := run_start
		for index in range(1, xs.size() + 1):
			if index == xs.size() or int(xs[index]) != previous + 1:
				result.append(Rect2i(
					run_start, y, previous - run_start + 1, 1
				))
				if index < xs.size():
					run_start = int(xs[index])
			if index < xs.size():
				previous = int(xs[index])
	return result


static func runtime_collision_contains_world(
	runtime_collision: Dictionary,
	world: Vector2,
	design_size: Vector2i
) -> bool:
	return blocked_cells_contain_world(
		blocked_cell_set(runtime_collision), world, design_size
	)


static func blocked_cells_contain_world(
	blocked_cells: Dictionary,
	world: Vector2,
	design_size: Vector2i
) -> bool:
	if not runtime_boundary_contains_world(world, design_size):
		return true
	var cell := world_cell(world, design_size)
	return blocked_cells.has("%d,%d" % [cell.x, cell.y])


static func visible_ground_contains_tile(
	tile: Vector2,
	design_size: Vector2i
) -> bool:
	return (
		tile.x >= 0.0 and tile.y >= 0.0
		and tile.x < float(design_size.x)
		and tile.y < float(design_size.y)
	)


static func world_cell(world: Vector2, design_size: Vector2i) -> Vector2i:
	return MapEditorCoordinate.screen_position_px_to_grid_cell(
		world, design_size
	)


static func cell_polygon_world(
	cell: Vector2i,
	design_size: Vector2i
) -> PackedVector2Array:
	return MapEditorCoordinate.grid_cell_polygon_screen_px(cell, design_size)


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
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			minimum, design_size
		),
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			Vector2(maximum.x, minimum.y), design_size
		),
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
			maximum, design_size
		),
		MapEditorCoordinate.ground_position_gu_to_screen_position_px(
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
			result.append(
				MapEditorCoordinate.ground_position_gu_to_screen_position_px(
					Vector2(float(raw[0]), float(raw[1])), design_size
				)
			)
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
		result.append(
			MapEditorCoordinate.ground_position_gu_to_screen_position_px(
				tile_point, design_size
			)
		)
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
	var tile := MapEditorCoordinate.screen_position_px_to_ground_position_gu(
		world, design_size
	)
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
