class_name WarriorMeleeGeometry
extends RefCounted

## Canonical warrior melee geometry. Every value is expressed in logical map
## tiles after the actor/enemy footpoints have been converted to fractional
## canonical tile coordinates. Screen pixels are deliberately not accepted.

const CONTRACT_ID := "gameplay.warrior.melee_geometry.fractional_tile.v1"
const WILD_RUSH_CONTRACT_ID := "gameplay.warrior.wild_rush.atomic_tile_push.v1"
const TARGET_COUNT_POLICY_ID := "gameplay.warrior.melee_target_count.v1"
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
	return FACING_TILE_STEPS[posmod(direction_index, FACING_TILE_STEPS.size())]


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


static func direction_index_for_tile_delta(delta: Vector2) -> int:
	if delta.length_squared() <= EPSILON * EPSILON:
		return 0
	# Quantize in the same 64x32 isometric projection used by the character
	# visual. The common 16px factor is cancelled, leaving only the 2:1 aspect;
	# no screen distance enters gameplay geometry.
	var projected_direction := Vector2(
		(delta.x - delta.y) * 2.0,
		delta.x + delta.y
	)
	return wrapi(
		int(round((projected_direction.angle() - PI / 2.0) / (TAU / 8.0))),
		0,
		8
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
