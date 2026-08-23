class_name TaoistFriendlyTargeting
extends RefCounted

## Pure friendly-area geometry contract for the Taoist support layer.
## Grid membership is defined in integer tile coordinates (floor of the
## continuous Ground GU position) so 3x3 / 7x7 areas are exact and stable
## across float movement.

const CONTRACT_ID := "skills.taoist.friendly_area_geometry.v1"
const EPSILON_GU := 0.0001


static func grid_tile(ground_position_gu: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(ground_position_gu.x)),
		int(floor(ground_position_gu.y))
	)


static func exact_square_cells(
	center_tile: Vector2i,
	size: int
) -> Array[Vector2i]:
	## Exact width x height square centered on center_tile. A 3x3 area yields
	## exactly 9 cells including the center.
	var cells: Array[Vector2i] = []
	var width := maxi(1, size)
	var height := maxi(1, size)
	var min_x := -int(floor(float(width - 1) / 2.0))
	var min_y := -int(floor(float(height - 1) / 2.0))
	for y in range(min_y, min_y + height):
		for x in range(min_x, min_x + width):
			cells.append(center_tile + Vector2i(x, y))
	return cells


static func chebyshev_area_cells(
	center_tile: Vector2i,
	radius: int
) -> Array[Vector2i]:
	## Exact Chebyshev (max-norm) square area. radius=3 -> exactly 49 cells.
	var cells: Array[Vector2i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			cells.append(center_tile + Vector2i(x, y))
	return cells


static func candidates_in_cells(
	candidates: Array,
	center_ground_gu: Vector2,
	cells: Array
) -> Array[Dictionary]:
	var cell_set: Dictionary = {}
	for raw_cell: Variant in cells:
		if raw_cell is Vector2i:
			cell_set[raw_cell] = true
	var result: Array[Dictionary] = []
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		var position: Variant = candidate.get("ground_position_gu", Vector2.ZERO)
		if not position is Vector2:
			continue
		if cell_set.has(grid_tile(position)):
			result.append(candidate)
	return result


static func within_range_gu(
	candidate: Dictionary,
	center_ground_gu: Vector2,
	range_gu: float
) -> bool:
	var position: Variant = candidate.get("ground_position_gu", Vector2.ZERO)
	if not position is Vector2:
		return false
	return (position as Vector2).distance_to(center_ground_gu) <= (
		maxf(0.0, range_gu) + EPSILON_GU
	)


static func distance_squared_gu(
	candidate: Dictionary,
	center_ground_gu: Vector2
) -> float:
	var position: Variant = candidate.get("ground_position_gu", Vector2.ZERO)
	if not position is Vector2:
		return INF
	return (position as Vector2).distance_squared_to(center_ground_gu)
