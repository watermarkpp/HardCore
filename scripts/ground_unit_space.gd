class_name GroundUnitSpace
extends RefCounted

## Cross-system unit and projection contract. Gameplay distances live in the
## Euclidean ground plane (GU). Screen pixels are accepted only at this explicit
## projection boundary.

const CONTRACT_ID := "combat.unit.gu_gs_px.v1"
const PROJECTION_CONTRACT_ID := "world.ground_projection.iso_64x32.v1"
const TILE_SIZE_PX := Vector2(64.0, 32.0)
const HALF_TILE_SIZE_PX := TILE_SIZE_PX * 0.5
const AXIS_NEIGHBOR_COST_GU := 1.0
const DIAGONAL_NEIGHBOR_COST_GU := sqrt(2.0)
const EPSILON_GU := 0.0001


static func ground_delta_gu_to_screen_delta_px(ground_delta_gu: Vector2) -> Vector2:
	return Vector2(
		(ground_delta_gu.x - ground_delta_gu.y) * HALF_TILE_SIZE_PX.x,
		(ground_delta_gu.x + ground_delta_gu.y) * HALF_TILE_SIZE_PX.y
	)


static func screen_delta_px_to_ground_delta_gu(screen_delta_px: Vector2) -> Vector2:
	var horizontal := screen_delta_px.x / HALF_TILE_SIZE_PX.x
	var vertical := screen_delta_px.y / HALF_TILE_SIZE_PX.y
	return Vector2(
		(horizontal + vertical) * 0.5,
		(vertical - horizontal) * 0.5
	)


static func distance_squared_gu(origin_ground_gu: Vector2, target_ground_gu: Vector2) -> float:
	return origin_ground_gu.distance_squared_to(target_ground_gu)


static func distance_gu(origin_ground_gu: Vector2, target_ground_gu: Vector2) -> float:
	return origin_ground_gu.distance_to(target_ground_gu)


static func is_within_range_gu(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	range_gu: float
) -> bool:
	var safe_range_gu := maxf(0.0, range_gu)
	var inclusive_range_gu := safe_range_gu + EPSILON_GU
	return (
		distance_squared_gu(origin_ground_gu, target_ground_gu)
		<= inclusive_range_gu * inclusive_range_gu
	)


static func normalized_ground_direction(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	fallback_ground_direction := Vector2.DOWN
) -> Vector2:
	var delta_ground_gu := target_ground_gu - origin_ground_gu
	if delta_ground_gu.length_squared() > EPSILON_GU * EPSILON_GU:
		return delta_ground_gu.normalized()
	if fallback_ground_direction.length_squared() > EPSILON_GU * EPSILON_GU:
		return fallback_ground_direction.normalized()
	return Vector2.DOWN


static func endpoint_ground_gu(
	origin_ground_gu: Vector2,
	direction_ground: Vector2,
	effect_length_gu: float
) -> Vector2:
	var safe_length_gu := maxf(0.0, effect_length_gu)
	if direction_ground.length_squared() <= EPSILON_GU * EPSILON_GU:
		return origin_ground_gu
	return origin_ground_gu + direction_ground.normalized() * safe_length_gu


static func desired_ground_motion_gu(
	direction_ground: Vector2,
	speed_gu_per_sec: float,
	delta_seconds: float
) -> Vector2:
	if direction_ground.length_squared() <= EPSILON_GU * EPSILON_GU:
		return Vector2.ZERO
	return (
		direction_ground.normalized()
		* maxf(0.0, speed_gu_per_sec)
		* maxf(0.0, delta_seconds)
	)


static func desired_screen_velocity_px_per_sec(
	direction_ground: Vector2,
	speed_gu_per_sec: float
) -> Vector2:
	if direction_ground.length_squared() <= EPSILON_GU * EPSILON_GU:
		return Vector2.ZERO
	return ground_delta_gu_to_screen_delta_px(
		direction_ground.normalized() * maxf(0.0, speed_gu_per_sec)
	)


static func actual_ground_motion_gu_from_screen_positions(
	before_screen_position_px: Vector2,
	after_screen_position_px: Vector2
) -> Vector2:
	return screen_delta_px_to_ground_delta_gu(
		after_screen_position_px - before_screen_position_px
	)


static func path_step_cost_gu(step: Vector2i) -> float:
	var absolute := step.abs()
	if absolute == Vector2i.ZERO:
		return 0.0
	if absolute.x > 1 or absolute.y > 1:
		return Vector2(step).length()
	return DIAGONAL_NEIGHBOR_COST_GU if absolute.x == 1 and absolute.y == 1 else AXIS_NEIGHBOR_COST_GU
