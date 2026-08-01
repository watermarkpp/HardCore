class_name WarriorMeleeGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## Canonical warrior melee geometry. Every value is expressed in logical map
## tiles after the actor/enemy footpoints have been converted to fractional
## canonical tile coordinates. Screen pixels are deliberately not accepted.

const CONTRACT_ID := "gameplay.warrior.melee_geometry.fractional_tile.v1"
const WILD_RUSH_CONTRACT_ID := "gameplay.warrior.wild_rush.atomic_tile_push.v1"
const TARGET_COUNT_POLICY_ID := "gameplay.warrior.melee_target_count.v1"
const DIRECTION_SPACE_CONTRACT_ID := CombatDirectionSpaceScript.CONTRACT_ID
const FOOTPRINT_INTERSECTION_CONTRACT_ID := (
	"gameplay.warrior.melee_footprint_intersection.iso_polygon_sat.v1"
)
const TARGET_FOOTPRINT_CONTRACT_ID := WorldSpatialRulesScript.ACTOR_FOOTPRINT_CONTRACT_ID
const UNLIMITED_TARGETS := -1

const SKILL_NORMAL := "normal"
const SKILL_FIRE := "fire"
const SKILL_HALF_MOON := "half_moon"
const SKILL_THRUST := "thrust"

const BASE_REACH_TILES := {
	SKILL_NORMAL: 1.5,
	SKILL_FIRE: 1.5,
	SKILL_HALF_MOON: 1.5,
	SKILL_THRUST: 2.5,
}
const RANGE_BONUS_CAP_TILES := {
	SKILL_NORMAL: 1.0,
	SKILL_FIRE: 1.0,
	SKILL_HALF_MOON: 0.5,
	SKILL_THRUST: 1.0,
}
const MAXIMUM_TARGETS := {
	SKILL_NORMAL: 1,
	SKILL_FIRE: 1,
	SKILL_HALF_MOON: UNLIMITED_TARGETS,
	SKILL_THRUST: UNLIMITED_TARGETS,
}

const THRUST_PRIMARY_REACH_TILES := 1.5
const THRUST_WIDTH_TILES := 1.0
const HALF_MOON_RELATIVE_DIRECTION_OFFSETS: Array[int] = [7, 0, 1, 2]
const WILD_RUSH_TARGET_REACH_TILES := 1.5
const WILD_RUSH_PUSH_DISTANCE_TILES := 3
const EPSILON := 0.0001

# ArtSpec/screen-facing order: S, SW, W, NW, N, NE, E, SE. The values are
# steps in canonical map-tile coordinates, not screen-space vectors.
const FACING_TILE_STEPS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
]


static func reach_tiles(mode: String, range_bonus_tiles := 0.0) -> float:
	var base := float(BASE_REACH_TILES.get(mode, BASE_REACH_TILES[SKILL_NORMAL]))
	var bonus_cap := float(RANGE_BONUS_CAP_TILES.get(mode, 0.0))
	return base + clampf(float(range_bonus_tiles), 0.0, bonus_cap)


static func maximum_targets(mode: String) -> int:
	return int(MAXIMUM_TARGETS.get(mode, 1))


static func has_finite_target_limit(mode: String) -> bool:
	return maximum_targets(mode) != UNLIMITED_TARGETS


static func target_count_policy(mode: String) -> Dictionary:
	var limit := maximum_targets(mode)
	return {
		"contract_id": TARGET_COUNT_POLICY_ID,
		"mode": mode,
		"maximum_targets": limit,
		"unlimited_within_geometry": limit == UNLIMITED_TARGETS,
	}


static func facing_tile_step(direction_index: int) -> Vector2i:
	return CombatDirectionSpaceScript.canonical_tile_step(direction_index)


static func chebyshev_distance(origin: Vector2, target: Vector2) -> float:
	var delta := target - origin
	return maxf(absf(delta.x), absf(delta.y))


static func is_single_target_in_reach(
	origin: Vector2,
	target: Vector2,
	mode: String,
	range_bonus_tiles := 0.0
) -> bool:
	return (
		chebyshev_distance(origin, target) <= reach_tiles(mode, range_bonus_tiles) + EPSILON
		and chebyshev_distance(origin, target) > EPSILON
	)


static func line_coordinates(delta: Vector2, direction_index: int) -> Vector2:
	var forward := Vector2(facing_tile_step(direction_index))
	var side := Vector2(forward.y, -forward.x)
	var divisor := forward.length_squared()
	return Vector2(delta.dot(forward) / divisor, delta.dot(side) / divisor)


static func thrust_slot(
	origin: Vector2,
	target: Vector2,
	direction_index: int,
	range_bonus_tiles := 0.0
) -> int:
	var coordinates := line_coordinates(target - origin, direction_index)
	if coordinates.x <= EPSILON:
		return 0
	if absf(coordinates.y) > THRUST_WIDTH_TILES * 0.5 + EPSILON:
		return 0
	if coordinates.x > reach_tiles(SKILL_THRUST, range_bonus_tiles) + EPSILON:
		return 0
	return 1 if coordinates.x <= THRUST_PRIMARY_REACH_TILES + EPSILON else 2


static func target_footprint_polygon_fractional_tile(
	target_center: Vector2,
	collision_radius_world: float
) -> PackedVector2Array:
	## Replays the exact 16-vertex 2:1 physics footprint around the authoritative
	## actor/global-position footpoint, then converts those local world offsets to
	## canonical fractional-tile space. No sprite bounds or calibration offsets
	## are involved in combat eligibility.
	var polygon := PackedVector2Array()
	for world_offset: Vector2 in WorldSpatialRulesScript.actor_footprint_polygon(
		maxf(0.0, collision_radius_world)
	):
		polygon.append(
			target_center
			+ CombatDirectionSpaceScript.world_delta_to_fractional_tile_delta(
				world_offset
			)
		)
	return polygon


static func attack_region_polygons(
	origin: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> Array[PackedVector2Array]:
	var resolved_mode := mode if mode in BASE_REACH_TILES else SKILL_NORMAL
	var result: Array[PackedVector2Array] = []
	if resolved_mode == SKILL_THRUST:
		result.append(_thrust_region_polygon(
			origin,
			direction_index,
			0.0,
			reach_tiles(SKILL_THRUST, range_bonus_tiles)
		))
		return result
	if resolved_mode == SKILL_HALF_MOON:
		for relative_direction: int in HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
			result.append(direction_sector_polygon(
				origin,
				posmod(direction_index + relative_direction, 8),
				reach_tiles(SKILL_HALF_MOON, range_bonus_tiles)
			))
		return result
	result.append(direction_sector_polygon(
		origin,
		direction_index,
		reach_tiles(resolved_mode, range_bonus_tiles)
	))
	return result


static func footprint_intersects_mode(
	origin: Vector2,
	target_center: Vector2,
	target_collision_radius_world: float,
	direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> bool:
	var target_polygon := target_footprint_polygon_fractional_tile(
		target_center,
		target_collision_radius_world
	)
	for attack_polygon: PackedVector2Array in attack_region_polygons(
		origin,
		direction_index,
		mode,
		range_bonus_tiles
	):
		if convex_polygons_intersect_inclusive(attack_polygon, target_polygon):
			return true
	return false


static func footprint_intersects_direction_sector(
	origin: Vector2,
	target_center: Vector2,
	target_collision_radius_world: float,
	direction_index: int,
	reach: float
) -> bool:
	return convex_polygons_intersect_inclusive(
		direction_sector_polygon(origin, direction_index, reach),
		target_footprint_polygon_fractional_tile(
			target_center,
			target_collision_radius_world
		)
	)


static func half_moon_footprint_relative_sector(
	origin: Vector2,
	target_center: Vector2,
	target_collision_radius_world: float,
	attack_direction_index: int,
	range_bonus_tiles := 0.0
) -> int:
	var reach := reach_tiles(SKILL_HALF_MOON, range_bonus_tiles)
	# Primary damage remains the facing sector. If an ellipse straddles the
	# primary/secondary boundary, primary wins deterministically and the caller
	# must not add the same target to a secondary list.
	if footprint_intersects_direction_sector(
		origin,
		target_center,
		target_collision_radius_world,
		attack_direction_index,
		reach
	):
		return 0
	for relative_direction: int in HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
		if relative_direction == 0:
			continue
		if footprint_intersects_direction_sector(
			origin,
			target_center,
			target_collision_radius_world,
			posmod(attack_direction_index + relative_direction, 8),
			reach
		):
			return relative_direction
	return -1


static func thrust_footprint_slot(
	origin: Vector2,
	target_center: Vector2,
	target_collision_radius_world: float,
	direction_index: int,
	range_bonus_tiles := 0.0
) -> int:
	var target_polygon := target_footprint_polygon_fractional_tile(
		target_center,
		target_collision_radius_world
	)
	# Test the primary segment first. A body straddling the 1.5-tile boundary is
	# assigned once to slot 1, so integration cannot apply both damage bands.
	if convex_polygons_intersect_inclusive(
		_thrust_region_polygon(
			origin,
			direction_index,
			0.0,
			THRUST_PRIMARY_REACH_TILES
		),
		target_polygon
	):
		return 1
	if convex_polygons_intersect_inclusive(
		_thrust_region_polygon(
			origin,
			direction_index,
			THRUST_PRIMARY_REACH_TILES,
			reach_tiles(SKILL_THRUST, range_bonus_tiles)
		),
		target_polygon
	):
		return 2
	return 0


static func convex_polygons_intersect_inclusive(
	first: PackedVector2Array,
	second: PackedVector2Array
) -> bool:
	## Deterministic convex SAT. Boundary contact is an intersection; EPSILON is
	## scaled by the tested axis length so the tolerance remains in tile units.
	if first.size() < 3 or second.size() < 3:
		return false
	for polygon: PackedVector2Array in [first, second]:
		for index in range(polygon.size()):
			var edge := polygon[(index + 1) % polygon.size()] - polygon[index]
			if edge.length_squared() <= EPSILON * EPSILON:
				continue
			var axis := Vector2(-edge.y, edge.x)
			var first_projection := _project_polygon(first, axis)
			var second_projection := _project_polygon(second, axis)
			var projection_epsilon := EPSILON * axis.length()
			if (
				first_projection.y < second_projection.x - projection_epsilon
				or second_projection.y < first_projection.x - projection_epsilon
			):
				return false
	return true


static func _thrust_region_polygon(
	origin: Vector2,
	direction_index: int,
	start_forward: float,
	end_forward: float
) -> PackedVector2Array:
	var forward := Vector2(facing_tile_step(direction_index))
	var side := Vector2(forward.y, -forward.x)
	var half_width := THRUST_WIDTH_TILES * 0.5
	return PackedVector2Array([
		origin + forward * start_forward - side * half_width,
		origin + forward * end_forward - side * half_width,
		origin + forward * end_forward + side * half_width,
		origin + forward * start_forward + side * half_width,
	])


static func direction_sector_polygon(
	origin: Vector2,
	direction_index: int,
	reach: float
) -> PackedVector2Array:
	# A point was historically accepted when it was inside the Chebyshev range
	# square and quantized to this 45-degree tile-space sector. Clipping that same
	# square by the two sector boundary half-planes produces the identical attack
	# area, now suitable for footprint intersection.
	var center_angle := Vector2(facing_tile_step(direction_index)).angle()
	var lower_boundary := Vector2.from_angle(center_angle - PI / 8.0)
	var upper_boundary := Vector2.from_angle(center_angle + PI / 8.0)
	var polygon := PackedVector2Array([
		origin + Vector2(-reach, -reach),
		origin + Vector2(reach, -reach),
		origin + Vector2(reach, reach),
		origin + Vector2(-reach, reach),
	])
	polygon = _clip_polygon_to_half_plane(
		polygon,
		Vector2(-lower_boundary.y, lower_boundary.x),
		origin
	)
	return _clip_polygon_to_half_plane(
		polygon,
		Vector2(upper_boundary.y, -upper_boundary.x),
		origin
	)


static func _clip_polygon_to_half_plane(
	polygon: PackedVector2Array,
	normal: Vector2,
	plane_origin: Vector2
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty():
		return result
	for index in range(polygon.size()):
		var current := polygon[index]
		var previous := polygon[posmod(index - 1, polygon.size())]
		var current_distance := normal.dot(current - plane_origin)
		var previous_distance := normal.dot(previous - plane_origin)
		var current_inside := current_distance >= -EPSILON
		var previous_inside := previous_distance >= -EPSILON
		if current_inside != previous_inside:
			var denominator := previous_distance - current_distance
			if absf(denominator) > EPSILON * EPSILON:
				var weight := clampf(previous_distance / denominator, 0.0, 1.0)
				result.append(previous.lerp(current, weight))
		if current_inside:
			result.append(current)
	return result


static func _project_polygon(polygon: PackedVector2Array, axis: Vector2) -> Vector2:
	var minimum := polygon[0].dot(axis)
	var maximum := minimum
	for index in range(1, polygon.size()):
		var projection := polygon[index].dot(axis)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)


static func direction_index_for_tile_delta(delta: Vector2) -> int:
	return CombatDirectionSpaceScript.direction_index_for_fractional_tile_delta(delta)


static func half_moon_relative_sector(attack_direction_index: int, target_direction_index: int) -> int:
	return posmod(target_direction_index - attack_direction_index, 8)


static func is_in_half_moon_arc(
	origin: Vector2,
	target: Vector2,
	attack_direction_index: int,
	range_bonus_tiles := 0.0
) -> bool:
	if not is_single_target_in_reach(origin, target, SKILL_HALF_MOON, range_bonus_tiles):
		return false
	var target_direction := direction_index_for_tile_delta(target - origin)
	return half_moon_relative_sector(attack_direction_index, target_direction) in HALF_MOON_RELATIVE_DIRECTION_OFFSETS


static func fire_can_begin(has_valid_target_in_reach: bool) -> bool:
	return has_valid_target_in_reach


static func fire_consumes_charge(resolution: String) -> bool:
	# A legal physical hit attempt consumes the charge whether it lands or MISSes.
	# Input rejection and pre-hit cancellation never consume it.
	return resolution in ["hit", "miss"]


static func wild_rush_target_is_adjacent(origin: Vector2, target: Vector2) -> bool:
	var distance := chebyshev_distance(origin, target)
	return distance > EPSILON and distance <= WILD_RUSH_TARGET_REACH_TILES + EPSILON


static func wild_rush_direction_step(origin: Vector2, target: Vector2) -> Vector2i:
	return facing_tile_step(direction_index_for_tile_delta(target - origin))


static func wild_rush_resolved_distance(
	static_clear_distance_tiles: int,
	dynamic_blocker_in_corridor: bool
) -> int:
	# Another monster anywhere in the complete three-tile corridor cancels the
	# whole displacement. Static geometry instead truncates the coupled movement
	# at the final valid tile before the obstacle.
	if dynamic_blocker_in_corridor:
		return 0
	return clampi(static_clear_distance_tiles, 0, WILD_RUSH_PUSH_DISTANCE_TILES)
