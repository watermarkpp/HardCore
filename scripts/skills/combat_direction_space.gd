class_name CombatDirectionSpace
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

## Canonical bridge between the 64x32 isometric world plane, fractional map
## tiles, and the eight direction rows used by combat/character visuals.
## Direction selection happens in tile space. World projection is applied only
## after the canonical direction index has been selected.

const CONTRACT_ID := "gameplay.professions.combat_direction_space.ground_gu_8dir.v2"
const LEGACY_CONTRACT_ID := "gameplay.professions.combat_direction_space.iso_64x32_tile_8dir.v1"
const TILE_SIZE_WORLD := GroundUnitSpaceScript.TILE_SIZE_PX
const HALF_TILE_WORLD := GroundUnitSpaceScript.HALF_TILE_SIZE_PX
const EPSILON := 0.0001

# Stable direction/visual-row order: S, SW, W, NW, N, NE, E, SE.
const DIRECTION_NAMES: Array[String] = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const CANONICAL_TILE_STEPS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
]


static func world_delta_to_fractional_tile_delta(world_delta: Vector2) -> Vector2:
	# Versioned compatibility alias. Fractional tile coordinates are numerically
	# identical to GU coordinates under the formal 64x32 projection.
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(world_delta)


static func fractional_tile_delta_to_world_delta(tile_delta: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(tile_delta)


static func screen_delta_px_to_ground_delta_gu(screen_delta_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_delta_px)


static func ground_delta_gu_to_screen_delta_px(ground_delta_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_delta_gu)


static func direction_index_for_fractional_tile_delta(tile_delta: Vector2) -> int:
	if tile_delta.length_squared() <= EPSILON * EPSILON:
		return 0
	# Canonical tile step S=(1,1) starts at PI/4. Each following visual row
	# advances by an exact 45 degrees in tile space.
	return wrapi(
		int(round((tile_delta.angle() - PI / 4.0) / (TAU / 8.0))),
		0,
		8
	)


static func direction_index_for_world_delta(world_delta: Vector2) -> int:
	return direction_index_for_fractional_tile_delta(
		world_delta_to_fractional_tile_delta(world_delta)
	)


static func canonical_tile_step(direction_index: int) -> Vector2i:
	return CANONICAL_TILE_STEPS[posmod(direction_index, CANONICAL_TILE_STEPS.size())]


static func canonical_ground_direction_gu(direction_index: int) -> Vector2:
	return Vector2(canonical_tile_step(direction_index)).normalized()


static func projected_world_direction(direction_index: int) -> Vector2:
	return ground_delta_gu_to_screen_delta_px(
		canonical_ground_direction_gu(direction_index)
	).normalized()


static func resolve_world_delta(world_delta: Vector2) -> Dictionary:
	var effective_world_delta := world_delta
	if effective_world_delta.length_squared() <= EPSILON * EPSILON:
		effective_world_delta = Vector2.DOWN
	var ground_delta_gu := screen_delta_px_to_ground_delta_gu(effective_world_delta)
	var direction_index := direction_index_for_fractional_tile_delta(ground_delta_gu)
	return {
		"contract_id": CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"source_world_delta": effective_world_delta,
		"source_screen_delta_px": effective_world_delta,
		"ground_delta_gu": ground_delta_gu,
		"fractional_tile_delta": ground_delta_gu,
		"direction_index": direction_index,
		"visual_direction_index": direction_index,
		"direction_name": DIRECTION_NAMES[direction_index],
		"canonical_tile_step": canonical_tile_step(direction_index),
		"canonical_ground_direction_gu": canonical_ground_direction_gu(direction_index),
		"projected_world_direction": projected_world_direction(direction_index),
		"projected_screen_direction_px": projected_world_direction(direction_index),
	}
