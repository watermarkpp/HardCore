class_name WarriorMeleeDiagnostic
extends RefCounted

## Read-only explanation contract for warrior melee geometry. This module must
## never decide damage, mutate targets, or widen/narrow the canonical geometry.
## It mirrors WarriorMeleeGeometry so runtime instrumentation can report why a
## candidate was accepted or rejected without changing gameplay.

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")

const CONTRACT_ID := "diagnostic.warrior.melee_candidate.v1"
const FOOTPRINT_CONTRACT_ID := "diagnostic.warrior.melee_footprint_candidate.v1"
const DIRECTION_AUDIT_CONTRACT_ID := "diagnostic.warrior.melee_direction_loop.v1"
const ANGLE_QUANTIZATION_AUDIT_CONTRACT_ID := (
	"diagnostic.warrior.melee_angle_quantization.v1"
)

const RESULT_OK := "OK"
const RESULT_SAME_FOOTPOINT := "SAME_FOOTPOINT"
const RESULT_OUT_OF_RANGE := "OUT_OF_RANGE"
const RESULT_WRONG_FACING := "WRONG_FACING"
const RESULT_OUTSIDE_ATTACK_LANE := "OUTSIDE_ATTACK_LANE"
const RESULT_OUTSIDE_HALF_MOON_ARC := "OUTSIDE_HALF_MOON_ARC"
const RESULT_DIRECTION_INDEX_MISMATCH := "DIRECTION_INDEX_MISMATCH"

const SUPPORTED_MODES: Array[String] = [
	Geometry.SKILL_NORMAL,
	Geometry.SKILL_FIRE,
	Geometry.SKILL_HALF_MOON,
	Geometry.SKILL_THRUST,
]


static func explain_candidate(
	origin_fractional_tile: Vector2,
	target_fractional_tile: Vector2,
	attack_direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> Dictionary:
	var resolved_mode := mode if mode in SUPPORTED_MODES else Geometry.SKILL_NORMAL
	var normalized_attack_direction := posmod(attack_direction_index, 8)
	var delta := target_fractional_tile - origin_fractional_tile
	var distance := Geometry.chebyshev_distance(origin_fractional_tile, target_fractional_tile)
	var has_target_direction := delta.length_squared() > Geometry.EPSILON * Geometry.EPSILON
	var target_direction := (
		Geometry.direction_index_for_tile_delta(delta) if has_target_direction else -1
	)
	var line := Geometry.line_coordinates(delta, normalized_attack_direction)
	var effective_reach := Geometry.reach_tiles(resolved_mode, range_bonus_tiles)
	var slot := Geometry.thrust_slot(
		origin_fractional_tile,
		target_fractional_tile,
		normalized_attack_direction,
		range_bonus_tiles
	)
	var relative_sector := (
		Geometry.half_moon_relative_sector(normalized_attack_direction, target_direction)
		if has_target_direction
		else -1
	)
	var result_code := _result_code(
		resolved_mode,
		distance,
		effective_reach,
		normalized_attack_direction,
		target_direction,
		line,
		relative_sector
	)
	return {
		"contract_id": CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"target_count_policy_id": Geometry.TARGET_COUNT_POLICY_ID,
		"result_code": result_code,
		"accepted": result_code == RESULT_OK,
		"requested_mode": mode,
		"mode": resolved_mode,
		"origin_fractional_tile": _vector2_json(origin_fractional_tile),
		"target_fractional_tile": _vector2_json(target_fractional_tile),
		"tile_delta": _vector2_json(delta),
		"chebyshev_distance_tiles": distance,
		"attack_direction_index": normalized_attack_direction,
		"target_direction_index": target_direction,
		"has_target_direction": has_target_direction,
		"canonical_attack_tile_step": _vector2i_json(
			Geometry.facing_tile_step(normalized_attack_direction)
		),
		"forward_tiles": line.x,
		"lateral_tiles": line.y,
		"thrust_slot": slot,
		"half_moon_relative_sector": relative_sector,
		"half_moon_allowed_relative_sectors": Array(
			Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS
		),
		"base_reach_tiles": float(Geometry.BASE_REACH_TILES[resolved_mode]),
		"requested_range_bonus_tiles": float(range_bonus_tiles),
		"effective_reach_tiles": effective_reach,
		"thrust_primary_reach_tiles": Geometry.THRUST_PRIMARY_REACH_TILES,
		"attack_lane_width_tiles": Geometry.THRUST_WIDTH_TILES,
		"maximum_targets": Geometry.maximum_targets(resolved_mode),
		"unlimited_targets_within_geometry": not Geometry.has_finite_target_limit(
			resolved_mode
		),
	}


static func explain_footprint_candidate(
	origin_fractional_tile: Vector2,
	target_fractional_tile: Vector2,
	target_collision_radius_world: float,
	attack_direction_index: int,
	mode: String,
	range_bonus_tiles := 0.0
) -> Dictionary:
	## Reports the historical footpoint-only decision beside the authoritative
	## footprint-area intersection. Runtime instrumentation can therefore prove
	## when an unchanged attack area reaches a monster body even though its centre
	## footpoint remains just outside the old point test.
	var point_result := explain_candidate(
		origin_fractional_tile,
		target_fractional_tile,
		attack_direction_index,
		mode,
		range_bonus_tiles
	)
	var resolved_mode := str(point_result.get("mode", Geometry.SKILL_NORMAL))
	var normalized_attack_direction := posmod(attack_direction_index, 8)
	var footprint_accepted := Geometry.footprint_intersects_mode(
		origin_fractional_tile,
		target_fractional_tile,
		target_collision_radius_world,
		normalized_attack_direction,
		resolved_mode,
		range_bonus_tiles
	)
	var footprint_slot := (
		Geometry.thrust_footprint_slot(
			origin_fractional_tile,
			target_fractional_tile,
			target_collision_radius_world,
			normalized_attack_direction,
			range_bonus_tiles
		)
		if resolved_mode == Geometry.SKILL_THRUST
		else 0
	)
	var footprint_half_moon_relative_sector := (
		Geometry.half_moon_footprint_relative_sector(
			origin_fractional_tile,
			target_fractional_tile,
			target_collision_radius_world,
			normalized_attack_direction,
			range_bonus_tiles
		)
		if resolved_mode == Geometry.SKILL_HALF_MOON
		else -1
	)
	var target_polygon := Geometry.target_footprint_polygon_fractional_tile(
		target_fractional_tile,
		target_collision_radius_world
	)
	var attack_polygons := Geometry.attack_region_polygons(
		origin_fractional_tile,
		normalized_attack_direction,
		resolved_mode,
		range_bonus_tiles
	)
	var result := point_result.duplicate(true)
	result.merge({
		"contract_id": FOOTPRINT_CONTRACT_ID,
		"footprint_intersection_contract_id": Geometry.FOOTPRINT_INTERSECTION_CONTRACT_ID,
		"target_footprint_contract_id": Geometry.TARGET_FOOTPRINT_CONTRACT_ID,
		"point_candidate_contract_id": CONTRACT_ID,
		"point_result_code": str(point_result.get("result_code", "")),
		"point_accepted": bool(point_result.get("accepted", false)),
		"footprint_result_code": (
			RESULT_OK
			if footprint_accepted
			else str(point_result.get("result_code", RESULT_OUT_OF_RANGE))
		),
		"footprint_accepted": footprint_accepted,
		"accepted": footprint_accepted,
		"result_code": (
			RESULT_OK
			if footprint_accepted
			else str(point_result.get("result_code", RESULT_OUT_OF_RANGE))
		),
		"point_thrust_slot": int(point_result.get("thrust_slot", 0)),
		"footprint_thrust_slot": footprint_slot,
		"footprint_half_moon_relative_sector": footprint_half_moon_relative_sector,
		"target_collision_radius_world": maxf(0.0, target_collision_radius_world),
		"target_footprint_vertex_count": target_polygon.size(),
		"target_footprint_polygon_fractional_tile": _polygon_json(target_polygon),
		"attack_region_polygon_count": attack_polygons.size(),
		"attack_region_polygons_fractional_tile": _polygons_json(attack_polygons),
	}, true)
	return result


static func audit_direction(screen_direction_index: int) -> Dictionary:
	var normalized_screen_direction := posmod(screen_direction_index, 8)
	var tile_step := Geometry.facing_tile_step(normalized_screen_direction)
	var tile_delta := Vector2(tile_step)
	var projected_screen_vector := _project_tile_delta(tile_delta)
	var world_direction := Geometry.direction_index_for_tile_delta(tile_delta)
	var projected_screen_direction := _direction_index_for_projected_screen_delta(
		projected_screen_vector
	)
	var matches := (
		normalized_screen_direction == world_direction
		and normalized_screen_direction == projected_screen_direction
	)
	return {
		"contract_id": DIRECTION_AUDIT_CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"requested_screen_direction_index": screen_direction_index,
		"screen_direction_index": normalized_screen_direction,
		"world_direction_index": world_direction,
		"canonical_tile_step": _vector2i_json(tile_step),
		"projected_screen_vector": _vector2_json(projected_screen_vector),
		"projected_screen_direction_index": projected_screen_direction,
		"round_trip_matches": matches,
		"result_code": RESULT_OK if matches else RESULT_DIRECTION_INDEX_MISMATCH,
	}


static func audit_all_directions() -> Dictionary:
	var directions: Array[Dictionary] = []
	var consistent := true
	for direction_index in range(8):
		var audit := audit_direction(direction_index)
		directions.append(audit)
		consistent = consistent and bool(audit["round_trip_matches"])
	return {
		"contract_id": DIRECTION_AUDIT_CONTRACT_ID,
		"direction_order": ["S", "SW", "W", "NW", "N", "NE", "E", "SE"],
		"direction_count": directions.size(),
		"consistent": consistent,
		"directions": directions,
	}


static func audit_fractional_tile_delta(fractional_tile_delta: Vector2) -> Dictionary:
	## Compares the current project's 2:1-projected screen-angle quantizer with
	## the alternative 45-degree quantizer measured directly in canonical tile
	## space. It is deliberately read-only: neither result is selected here.
	var projected_world_vector := _project_tile_delta(fractional_tile_delta)
	var projected_screen_direction := _direction_index_for_projected_screen_delta(
		projected_world_vector
	)
	var tile_space_direction := Geometry.direction_index_for_tile_delta(fractional_tile_delta)
	var matches := projected_screen_direction == tile_space_direction
	var projected_world_direction := (
		projected_world_vector.normalized()
		if projected_world_vector.length_squared() > Geometry.EPSILON * Geometry.EPSILON
		else Vector2.ZERO
	)
	return {
		"contract_id": ANGLE_QUANTIZATION_AUDIT_CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"active_direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"fractional_tile_delta": _vector2_json(fractional_tile_delta),
		"has_direction": (
			fractional_tile_delta.length_squared()
			> Geometry.EPSILON * Geometry.EPSILON
		),
		"projected_screen_45_direction_index": projected_screen_direction,
		"tile_space_45_direction_index": tile_space_direction,
		"quantizers_match": matches,
		"projected_screen_canonical_tile_step": _vector2i_json(
			Geometry.facing_tile_step(projected_screen_direction)
		),
		"tile_space_canonical_tile_step": _vector2i_json(
			Geometry.facing_tile_step(tile_space_direction)
		),
		"projected_world_vector": _vector2_json(projected_world_vector),
		"projected_world_direction": _vector2_json(projected_world_direction),
	}


static func _result_code(
	mode: String,
	distance: float,
	reach: float,
	attack_direction_index: int,
	target_direction_index: int,
	line: Vector2,
	half_moon_relative_sector: int
) -> String:
	if distance <= Geometry.EPSILON:
		return RESULT_SAME_FOOTPOINT
	if distance > reach + Geometry.EPSILON:
		return RESULT_OUT_OF_RANGE
	match mode:
		Geometry.SKILL_THRUST:
			if line.x <= Geometry.EPSILON:
				return RESULT_WRONG_FACING
			if absf(line.y) > Geometry.THRUST_WIDTH_TILES * 0.5 + Geometry.EPSILON:
				return RESULT_OUTSIDE_ATTACK_LANE
		Geometry.SKILL_HALF_MOON:
			if half_moon_relative_sector not in Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
				return RESULT_OUTSIDE_HALF_MOON_ARC
		_:
			if target_direction_index != attack_direction_index:
				return RESULT_WRONG_FACING
	return RESULT_OK


static func _project_tile_delta(tile_delta: Vector2) -> Vector2:
	return Vector2(
		(tile_delta.x - tile_delta.y) * 2.0,
		tile_delta.x + tile_delta.y
	)


static func _direction_index_for_projected_screen_delta(screen_delta: Vector2) -> int:
	if screen_delta.length_squared() <= Geometry.EPSILON * Geometry.EPSILON:
		return 0
	return wrapi(
		int(round((screen_delta.angle() - PI / 2.0) / (TAU / 8.0))),
		0,
		8
	)


static func _vector2_json(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector2i_json(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _polygon_json(polygon: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Vector2 in polygon:
		result.append(_vector2_json(point))
	return result


static func _polygons_json(polygons: Array[PackedVector2Array]) -> Array:
	var result: Array = []
	for polygon: PackedVector2Array in polygons:
		result.append(_polygon_json(polygon))
	return result
