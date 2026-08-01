class_name CombatDirectionSpace
extends RefCounted

## Canonical bridge between the 64x32 isometric world plane, fractional map
## tiles, and the eight direction rows used by combat/character visuals.
## Direction selection happens in tile space. World projection is applied only
## after the canonical direction index has been selected.

const CONTRACT_ID := "gameplay.professions.combat_direction_space.iso_64x32_tile_8dir.v1"
const TILE_SIZE_WORLD := Vector2(64.0, 32.0)
const HALF_TILE_WORLD := TILE_SIZE_WORLD * 0.5
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
	var horizontal := world_delta.x / HALF_TILE_WORLD.x
	var vertical := world_delta.y / HALF_TILE_WORLD.y
	return Vector2(
		(horizontal + vertical) * 0.5,
		(vertical - horizontal) * 0.5
	)


static func fractional_tile_delta_to_world_delta(tile_delta: Vector2) -> Vector2:
	return Vector2(
		(tile_delta.x - tile_delta.y) * HALF_TILE_WORLD.x,
		(tile_delta.x + tile_delta.y) * HALF_TILE_WORLD.y
	)


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


static func projected_world_direction(direction_index: int) -> Vector2:
	return fractional_tile_delta_to_world_delta(
		Vector2(canonical_tile_step(direction_index))
	).normalized()


static func resolve_world_delta(world_delta: Vector2) -> Dictionary:
	var effective_world_delta := world_delta
	if effective_world_delta.length_squared() <= EPSILON * EPSILON:
		effective_world_delta = Vector2.DOWN
	var tile_delta := world_delta_to_fractional_tile_delta(effective_world_delta)
	var direction_index := direction_index_for_fractional_tile_delta(tile_delta)
	return {
		"contract_id": CONTRACT_ID,
		"source_world_delta": effective_world_delta,
		"fractional_tile_delta": tile_delta,
		"direction_index": direction_index,
		"visual_direction_index": direction_index,
		"direction_name": DIRECTION_NAMES[direction_index],
		"canonical_tile_step": canonical_tile_step(direction_index),
		"projected_world_direction": projected_world_direction(direction_index),
	}
