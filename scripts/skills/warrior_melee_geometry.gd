class_name WarriorMeleeGeometry
extends RefCounted

const CombatDirectionSpaceScript := preload(
	"res://scripts/skills/combat_direction_space.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

## Canonical warrior melee geometry. Every value is expressed in logical map
## tiles after the actor/enemy footpoints have been converted to fractional
## canonical tile coordinates. Screen pixels are deliberately not accepted.

const CONTRACT_ID := "gameplay.warrior.melee_geometry.ground_gu.v2"
const WILD_RUSH_CONTRACT_ID := "gameplay.warrior.wild_rush.atomic_ground_gu.v2"
const TARGET_COUNT_POLICY_ID := "gameplay.warrior.melee_target_count.v1"
const DIRECTION_SPACE_CONTRACT_ID := CombatDirectionSpaceScript.CONTRACT_ID
const FOOTPRINT_INTERSECTION_CONTRACT_ID := (
	"gameplay.warrior.melee_footprint_intersection.ground_gu_sat.v2"
)
const TARGET_FOOTPRINT_CONTRACT_ID := (
	WorldSpatialRulesScript.ACTOR_GROUND_FOOTPRINT_CONTRACT_ID
)
const UNLIMITED_TARGETS := -1

const SKILL_NORMAL := "normal"
const SKILL_FIRE := "fire"
const SKILL_HALF_MOON := "half_moon"
const SKILL_THRUST := "thrust"

const BASE_REACH_GU := {
	SKILL_NORMAL: 1.5,
	SKILL_FIRE: 1.5,
	SKILL_HALF_MOON: 1.5,
	SKILL_THRUST: 2.5,
}
const RANGE_BONUS_CAP_GU := {
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

const THRUST_PRIMARY_REACH_GU := 1.5
const THRUST_WIDTH_GU := 1.0
const HALF_MOON_RELATIVE_DIRECTION_OFFSETS: Array[int] = [7, 0, 1, 2]
const WILD_RUSH_TARGET_REACH_GU := 1.5
const WILD_RUSH_PUSH_DISTANCE_GU := 3.0
const WILD_RUSH_MAXIMUM_GRID_STEPS := 3
const EPSILON := 0.0001

# Versioned aliases for integration code pending GU field migration.
const BASE_REACH_TILES := BASE_REACH_GU
const RANGE_BONUS_CAP_TILES := RANGE_BONUS_CAP_GU
const THRUST_PRIMARY_REACH_TILES := THRUST_PRIMARY_REACH_GU
const THRUST_WIDTH_TILES := THRUST_WIDTH_GU
const WILD_RUSH_TARGET_REACH_TILES := WILD_RUSH_TARGET_REACH_GU
const WILD_RUSH_PUSH_DISTANCE_TILES := WILD_RUSH_MAXIMUM_GRID_STEPS

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
	return reach_gu(mode, range_bonus_tiles)


static func reach_gu(mode: String, range_bonus_gu := 0.0) -> float:
	var base := float(BASE_REACH_GU.get(mode, BASE_REACH_GU[SKILL_NORMAL]))
	var bonus_cap := float(RANGE_BONUS_CAP_GU.get(mode, 0.0))
	return base + clampf(float(range_bonus_gu), 0.0, bonus_cap)


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


static func canonical_ground_direction_gu(direction_index: int) -> Vector2:
	return CombatDirectionSpaceScript.canonical_ground_direction_gu(
		direction_index
	)


static func chebyshev_distance(origin: Vector2, target: Vector2) -> float:
	## Deprecated name retained while integration migrates. Result is Euclidean GU.
	return GroundUnitSpaceScript.distance_gu(origin, target)


static func is_single_target_in_reach(
	origin: Vector2,
	target: Vector2,
	mode: String,
	range_bonus_tiles := 0.0
) -> bool:
	return (
		GroundUnitSpaceScript.is_within_range_gu(
			origin,
			target,
			reach_gu(mode, range_bonus_tiles)
		)
		and GroundUnitSpaceScript.distance_gu(origin, target) > EPSILON
	)


static func is_single_target_in_reach_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	mode: String,
	range_bonus_gu := 0.0
) -> bool:
	return is_single_target_in_reach(
		origin_ground_gu, target_ground_gu, mode, range_bonus_gu
	)


static func line_coordinates(delta: Vector2, direction_index: int) -> Vector2:
	var forward := Vector2(facing_tile_step(direction_index))
	forward = forward.normalized()
	var side := Vector2(forward.y, -forward.x)
	return Vector2(delta.dot(forward), delta.dot(side))


static func line_coordinates_gu(
	delta_ground_gu: Vector2,
	direction_index: int
) -> Vector2:
	return line_coordinates(delta_ground_gu, direction_index)


static func thrust_slot(
	origin: Vector2,
	target: Vector2,
	direction_index: int,
	range_bonus_tiles := 0.0
) -> int:
	var coordinates := line_coordinates(target - origin, direction_index)
	if coordinates.x <= EPSILON:
		return 0
	if absf(coordinates.y) > THRUST_WIDTH_GU * 0.5 + EPSILON:
		return 0
	if coordinates.x > reach_tiles(SKILL_THRUST, range_bonus_tiles) + EPSILON:
		return 0
	return 1 if coordinates.x <= THRUST_PRIMARY_REACH_GU + EPSILON else 2


static func thrust_slot_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	return thrust_slot(
		origin_ground_gu, target_ground_gu, direction_index, range_bonus_gu
	)


static func target_footprint_polygon_fractional_tile(
	target_center: Vector2,
	collision_radius_world: float
) -> PackedVector2Array:
	## Compatibility call-shape: center is GU; the old horizontal screen radius is
	## converted once by WorldSpatialRules into the formal circular GU footprint.
	var polygon := PackedVector2Array()
	var combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			collision_radius_world
		)
	)
	for offset_ground_gu: Vector2 in (
		WorldSpatialRulesScript.actor_footprint_ground_polygon_gu(
			combat_radius_gu
		)
	):
		polygon.append(target_center + offset_ground_gu)
	return polygon


static func target_footprint_polygon_ground_gu(
	target_center_ground_gu: Vector2,
	target_collision_radius_px: float
) -> PackedVector2Array:
	return target_footprint_polygon_fractional_tile(
		target_center_ground_gu, target_collision_radius_px
	)


static func attack_region_polygons(
	origin: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> Array[PackedVector2Array]:
	var resolved_mode := mode if mode in BASE_REACH_GU else SKILL_NORMAL
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


static func attack_region_polygons_ground_gu(
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> Array[PackedVector2Array]:
	return attack_region_polygons(
		origin_ground_gu, direction_index, mode, range_bonus_gu
	)


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


static func footprint_intersects_mode_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_collision_radius_px: float,
	direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> bool:
	return footprint_intersects_mode(
		origin_ground_gu,
		target_center_ground_gu,
		target_collision_radius_px,
		direction_index,
		mode,
		range_bonus_gu
	)


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


static func half_moon_footprint_relative_sector_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_collision_radius_px: float,
	attack_direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	return half_moon_footprint_relative_sector(
		origin_ground_gu,
		target_center_ground_gu,
		target_collision_radius_px,
		attack_direction_index,
		range_bonus_gu
	)


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
			THRUST_PRIMARY_REACH_GU
		),
		target_polygon
	):
		return 1
	if convex_polygons_intersect_inclusive(
		_thrust_region_polygon(
			origin,
			direction_index,
			THRUST_PRIMARY_REACH_GU,
			reach_tiles(SKILL_THRUST, range_bonus_tiles)
		),
		target_polygon
	):
		return 2
	return 0


static func thrust_footprint_slot_gu(
	origin_ground_gu: Vector2,
	target_center_ground_gu: Vector2,
	target_collision_radius_px: float,
	direction_index: int,
	range_bonus_gu := 0.0
) -> int:
	return thrust_footprint_slot(
		origin_ground_gu,
		target_center_ground_gu,
		target_collision_radius_px,
		direction_index,
		range_bonus_gu
	)


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
	var forward := Vector2(facing_tile_step(direction_index)).normalized()
	var side := Vector2(forward.y, -forward.x)
	var half_width := THRUST_WIDTH_GU * 0.5
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
	# Convex approximation of the exact Euclidean GU sector. Twenty-four arc
	# samples keep SAT deterministic while guaranteeing every direction has the
	# same formal radius; endpoints include the ±22.5° boundaries.
	var safe_reach_gu := maxf(0.0, reach)
	var center_angle := Vector2(facing_tile_step(direction_index)).angle()
	var polygon := PackedVector2Array([origin])
	const ARC_SEGMENTS := 24
	for index: int in range(ARC_SEGMENTS + 1):
		var weight := float(index) / float(ARC_SEGMENTS)
		var angle := lerpf(
			center_angle - PI / 8.0,
			center_angle + PI / 8.0,
			weight
		)
		polygon.append(origin + Vector2.from_angle(angle) * safe_reach_gu)
	return polygon


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


static func direction_index_for_ground_delta_gu(delta_ground_gu: Vector2) -> int:
	return CombatDirectionSpaceScript.direction_index_for_fractional_tile_delta(
		delta_ground_gu
	)


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


static func is_in_half_moon_arc_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	attack_direction_index: int,
	range_bonus_gu := 0.0
) -> bool:
	return is_in_half_moon_arc(
		origin_ground_gu,
		target_ground_gu,
		attack_direction_index,
		range_bonus_gu
	)


static func fire_can_begin(has_valid_target_in_reach: bool) -> bool:
	return has_valid_target_in_reach


static func fire_consumes_charge(resolution: String) -> bool:
	# A legal physical hit attempt consumes the charge whether it lands or MISSes.
	# Input rejection and pre-hit cancellation never consume it.
	return resolution in ["hit", "miss"]


static func wild_rush_target_is_adjacent(origin: Vector2, target: Vector2) -> bool:
	var distance := GroundUnitSpaceScript.distance_gu(origin, target)
	return (
		distance > EPSILON
		and GroundUnitSpaceScript.is_within_range_gu(
			origin,
			target,
			WILD_RUSH_TARGET_REACH_GU
		)
	)


static func wild_rush_direction_ground_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2
) -> Vector2:
	return GroundUnitSpaceScript.normalized_ground_direction(
		origin_ground_gu,
		target_ground_gu
	)


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
	return clampi(
		static_clear_distance_tiles,
		0,
		WILD_RUSH_MAXIMUM_GRID_STEPS
	)
