class_name CombatDirectionSpace
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

## Canonical bridge between formal ground GU, screen PX and the eight rows used
## by combat/character visuals. Direction selection happens in GU. Screen
## projection is presentation-only and is applied after the direction index is
## fixed.

const CONTRACT_ID := "gameplay.professions.combat_direction_space.ground_gu_8dir.v3"
const EPSILON_GU := 0.0001

# Stable direction/visual-row order: S, SW, W, NW, N, NE, E, SE.
const DIRECTION_NAMES: Array[String] = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const CANONICAL_GRID_STEPS: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
]


static func screen_delta_px_to_ground_delta_gu(screen_delta_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_delta_px)


static func ground_delta_gu_to_screen_delta_px(ground_delta_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_delta_gu)


static func direction_index_for_ground_delta_gu(ground_delta_gu: Vector2) -> int:
	if ground_delta_gu.length_squared() <= EPSILON_GU * EPSILON_GU:
		return 0
	# Canonical GU step S=(1,1) starts at PI/4. Each following visual row
	# advances by an exact 45 degrees in ground space.
	return wrapi(
		int(round((ground_delta_gu.angle() - PI / 4.0) / (TAU / 8.0))),
		0,
		8
	)


static func direction_index_for_screen_delta_px(screen_delta_px: Vector2) -> int:
	return direction_index_for_ground_delta_gu(
		screen_delta_px_to_ground_delta_gu(screen_delta_px)
	)


static func canonical_grid_step(direction_index: int) -> Vector2i:
	return CANONICAL_GRID_STEPS[
		posmod(direction_index, CANONICAL_GRID_STEPS.size())
	]


static func canonical_ground_direction_gu(direction_index: int) -> Vector2:
	return Vector2(canonical_grid_step(direction_index)).normalized()


static func projected_screen_direction_px(direction_index: int) -> Vector2:
	return ground_delta_gu_to_screen_delta_px(
		canonical_ground_direction_gu(direction_index)
	).normalized()


static func resolve_screen_delta_px(screen_delta_px: Vector2) -> Dictionary:
	var effective_screen_delta_px := screen_delta_px
	if effective_screen_delta_px.length_squared() <= EPSILON_GU * EPSILON_GU:
		effective_screen_delta_px = Vector2.DOWN
	var ground_delta_gu := screen_delta_px_to_ground_delta_gu(
		effective_screen_delta_px
	)
	var direction_index := direction_index_for_ground_delta_gu(ground_delta_gu)
	return {
		"contract_id": CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"source_screen_delta_px": effective_screen_delta_px,
		"ground_delta_gu": ground_delta_gu,
		"direction_index": direction_index,
		"visual_direction_index": direction_index,
		"direction_name": DIRECTION_NAMES[direction_index],
		"canonical_grid_step": canonical_grid_step(direction_index),
		"canonical_ground_direction_gu": canonical_ground_direction_gu(
			direction_index
		),
		"projected_screen_direction_px": projected_screen_direction_px(
			direction_index
		),
	}
