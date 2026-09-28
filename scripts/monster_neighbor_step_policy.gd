class_name MonsterNeighborStepPolicy
extends RefCounted

## Pure M01A boundary for one classic eight-neighbor event.  Cell values are
## temporary derivatives of Ground GU; this policy stores no position.

const CONTRACT_ID := "monster.movement.neighbor_step.m01a.v1"
const AXIS_NEIGHBOR_DISTANCE_GU := 1.0
const DIAGONAL_NEIGHBOR_DISTANCE_GU := 1.4142135623730951
const MOVEMENT_EVENTS_PER_NEIGHBOR := 1
## Half of one 45-degree eight-way sector.  A direction remains on a Ground
## axis while its minor component is within tan(22.5 degrees) of the major
## component.  This prevents tiny projection/cell-centre residuals from
## turning a visually straight isometric diagonal into alternating Z steps.
const AXIS_SECTOR_MINOR_TO_MAJOR_RATIO := 0.41421356237309503

const NEIGHBOR_DELTAS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]


static func allowed_neighbors() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for neighbor: Vector2i in NEIGHBOR_DELTAS:
		result.append(neighbor)
	return result


static func is_valid_neighbor(neighbor: Variant) -> bool:
	if not neighbor is Vector2i:
		return false
	var candidate: Vector2i = neighbor
	return candidate != Vector2i.ZERO and abs(candidate.x) <= 1 and abs(candidate.y) <= 1


static func temporary_cell(position_ground_gu: Variant) -> Vector2i:
	if not _is_finite_ground_position(position_ground_gu):
		return Vector2i.ZERO
	var position: Vector2 = position_ground_gu
	return Vector2i(floori(position.x), floori(position.y))


static func cell_center_ground_gu(cell: Variant) -> Vector2:
	if not cell is Vector2i:
		return Vector2(INF, INF)
	var temporary_cell_value: Vector2i = cell
	return Vector2(
		float(temporary_cell_value.x) + 0.5,
		float(temporary_cell_value.y) + 0.5
	)


static func neighbor_target_ground_gu(
	position_ground_gu: Variant,
	neighbor: Variant
) -> Vector2:
	if not _is_finite_ground_position(position_ground_gu) or not is_valid_neighbor(neighbor):
		return Vector2(INF, INF)
	return cell_center_ground_gu(temporary_cell(position_ground_gu)) + Vector2(neighbor)


static func neighbor_target_from_cell(cell: Variant, neighbor: Variant) -> Vector2:
	if not cell is Vector2i or not is_valid_neighbor(neighbor):
		return Vector2(INF, INF)
	return cell_center_ground_gu(cell) + Vector2(neighbor)


static func desired_ground_direction(neighbor: Variant) -> Vector2:
	if not is_valid_neighbor(neighbor):
		return Vector2.ZERO
	return Vector2(neighbor).normalized()


## Deterministic nearest-sector mapping from a desired Ground direction to one
## of the eight classic neighbor cells.  Ground-axis directions project to the
## four isometric screen diagonals, so they must tolerate small lateral
## residuals instead of requiring one component to be exactly zero.
static func neighbor_for_desired_ground_direction(direction_ground_gu: Variant) -> Vector2i:
	if not _is_finite_ground_position(direction_ground_gu):
		return Vector2i.ZERO
	var direction: Vector2 = direction_ground_gu
	if direction.length_squared() <= 0.00000001:
		return Vector2i.ZERO
	var absolute := direction.abs()
	if absolute.y <= absolute.x * AXIS_SECTOR_MINOR_TO_MAJOR_RATIO:
		return Vector2i(_sign_component(direction.x), 0)
	if absolute.x <= absolute.y * AXIS_SECTOR_MINOR_TO_MAJOR_RATIO:
		return Vector2i(0, _sign_component(direction.y))
	return Vector2i(_sign_component(direction.x), _sign_component(direction.y))


static func neighbor_from_desired_ground_direction(direction_ground_gu: Variant) -> Vector2i:
	return neighbor_for_desired_ground_direction(direction_ground_gu)


## Convert an already selected waypoint into axis/diagonal locomotion legs.
## Keep its exact position (including fractional coordinates); never snap an
## actor onto a tile centre. Each returned leg is checked with the caller's
## existing full-footprint terrain authority before the step is committed.
static func eight_way_path(origin: Vector2, destination: Vector2, clear := Callable()) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not origin.is_finite() or not destination.is_finite():
		return result
	var whole := destination - origin
	if whole.length_squared() <= 0.0000000001:
		return result
	if absf(whole.x) <= 0.000001 or absf(whole.y) <= 0.000001 or absf(absf(whole.x) - absf(whole.y)) <= 0.000001:
		if not clear.is_valid() or clear.call(origin, destination):
			result.append(destination)
		return result
	var pending: Array = [[origin, destination, 0]]
	while not pending.is_empty():
		var part: Array = pending.pop_back()
		var a: Vector2 = part[0]
		var b: Vector2 = part[1]
		var offset := b - a
		if offset.length_squared() <= 0.0000000001:
			continue
		var absolute := offset.abs()
		var diagonal := offset.sign() * minf(absolute.x, absolute.y)
		var neighbor := neighbor_for_desired_ground_direction(offset)
		var first := diagonal if neighbor.x != 0 and neighbor.y != 0 else offset - diagonal
		var accepted := false
		for corner: Vector2 in [a + first, b - first]:
			if not clear.is_valid() or (clear.call(a, corner) and clear.call(corner, b)):
				if a.distance_squared_to(corner) > 0.0000000001:
					result.append(corner)
				if corner.distance_squared_to(b) > 0.0000000001:
					result.append(b)
				accepted = true
				break
		if accepted:
			continue
		# A clear oblique corridor can require a shorter staircase. Bisection
		# stays within the original leg, is bounded, and never bypasses clearance.
		if int(part[2]) >= 5 or result.size() + pending.size() >= 64 or not clear.call(a, b):
			return PackedVector2Array()
		var middle := (a + b) * 0.5
		pending.append([middle, b, int(part[2]) + 1])
		pending.append([a, middle, int(part[2]) + 1])
	return result


static func motion_follows_direction(actual: Vector2, intended: Vector2) -> bool:
	if actual.length_squared() <= 0.00000001:
		return true
	if intended.length_squared() <= 0.00000001:
		return false
	var axis := intended.normalized()
	return actual.dot(axis) >= -0.00001 and absf(actual.cross(axis)) <= 0.00002


static func neighbor_distance_gu(neighbor: Variant) -> float:
	if not is_valid_neighbor(neighbor):
		return -1.0
	return Vector2(neighbor).length()


static func build_neighbor_step(
	position_ground_gu: Variant,
	neighbor: Variant
) -> Dictionary:
	var valid_position := _is_finite_ground_position(position_ground_gu)
	var valid_neighbor := is_valid_neighbor(neighbor)
	if not valid_position or not valid_neighbor:
		return {
			"contract_id": CONTRACT_ID,
			"valid": false,
			"movement_events": 0,
			"reason": "invalid_ground_position" if not valid_position else "invalid_neighbor",
		}

	var position: Vector2 = position_ground_gu
	var candidate_neighbor: Vector2i = neighbor
	var cell := temporary_cell(position)
	var center := cell_center_ground_gu(cell)
	var target := neighbor_target_from_cell(cell, candidate_neighbor)
	var displacement := target - center
	var direction := desired_ground_direction(candidate_neighbor)
	var distance := displacement.length()
	return {
		"contract_id": CONTRACT_ID,
		"valid": true,
		"temporary_cell": cell,
		"cell_center_ground_gu": center,
		"neighbor": candidate_neighbor,
		"neighbor_delta": candidate_neighbor,
		"target_ground_gu": target,
		"neighbor_target_ground_gu": target,
		"displacement_ground_gu": displacement,
		"desired_direction_ground_gu": direction,
		"direction_ground_gu": direction,
		"distance_gu": distance,
		"movement_events": MOVEMENT_EVENTS_PER_NEIGHBOR,
	}


static func build_step(position_ground_gu: Variant, neighbor: Variant) -> Dictionary:
	return build_neighbor_step(position_ground_gu, neighbor)


static func _is_finite_ground_position(value: Variant) -> bool:
	if not value is Vector2:
		return false
	var position: Vector2 = value
	return position.is_finite()


static func _sign_component(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0
