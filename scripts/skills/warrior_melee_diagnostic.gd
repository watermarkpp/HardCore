class_name WarriorMeleeDiagnostic
extends RefCounted

## Read-only explanation contract for warrior melee geometry. This module must
## never decide damage, mutate targets, or widen/narrow the canonical geometry.
## It mirrors WarriorMeleeGeometry so runtime instrumentation can report why a
## candidate was accepted or rejected without changing gameplay.

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CONTRACT_ID := "diagnostic.warrior.melee_candidate.ground_gu.v2"
const FOOTPRINT_CONTRACT_ID := "diagnostic.warrior.melee_footprint_candidate.ground_gu.v2"
const DIRECTION_AUDIT_CONTRACT_ID := "diagnostic.warrior.melee_direction_loop.v1"
const ANGLE_QUANTIZATION_AUDIT_CONTRACT_ID := (
	"diagnostic.warrior.melee_angle_quantization.v1"
)
const TARGET_ALIGNED_RELEASE_CONTRACT_ID := (
	"diagnostic.warrior.melee_target_aligned_release.v1"
)
const TARGET_ALIGNED_AXIS_AUDIT_CONTRACT_ID := (
	"diagnostic.warrior.melee_target_aligned_axis_audit.v1"
)

const RESULT_OK := "OK"
const RESULT_SAME_FOOTPOINT := "SAME_FOOTPOINT"
const RESULT_OUT_OF_RANGE := "OUT_OF_RANGE"
const RESULT_WRONG_FACING := "WRONG_FACING"
const RESULT_OUTSIDE_ATTACK_LANE := "OUTSIDE_ATTACK_LANE"
const RESULT_OUTSIDE_HALF_MOON_ARC := "OUTSIDE_HALF_MOON_ARC"
const RESULT_DIRECTION_INDEX_MISMATCH := "DIRECTION_INDEX_MISMATCH"
const RESULT_TARGET_ALIGNED_OK := "TARGET_ALIGNED_OK"
const RESULT_TARGET_ALIGNED_INELIGIBLE := "TARGET_ALIGNED_INELIGIBLE"

const SUPPORTED_MODES: Array[String] = [
	Geometry.SKILL_NORMAL,
	Geometry.SKILL_FIRE,
	Geometry.SKILL_HALF_MOON,
	Geometry.SKILL_THRUST,
]


static func explain_candidate(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	attack_direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> Dictionary:
	var resolved_mode := mode if mode in SUPPORTED_MODES else Geometry.SKILL_NORMAL
	var normalized_attack_direction := posmod(attack_direction_index, 8)
	var delta_ground_gu := target_ground_gu - origin_ground_gu
	var distance_gu := GroundUnitSpaceScript.distance_gu(
		origin_ground_gu, target_ground_gu
	)
	var has_target_direction := delta_ground_gu.length_squared() > Geometry.EPSILON * Geometry.EPSILON
	var target_direction := (
		Geometry.direction_index_for_ground_delta_gu(delta_ground_gu) if has_target_direction else -1
	)
	var line := Geometry.line_coordinates_gu(delta_ground_gu, normalized_attack_direction)
	var effective_reach_gu := Geometry.reach_gu(resolved_mode, range_bonus_gu)
	var slot := Geometry.thrust_slot(
		origin_ground_gu,
		target_ground_gu,
		normalized_attack_direction,
		range_bonus_gu
	)
	var relative_sector := -1
	if resolved_mode == Geometry.SKILL_HALF_MOON and has_target_direction:
		## Use the same continuous GU fan as the runtime candidate gate. The old
		## 8-way direction index would incorrectly admit the removed +90 sector.
		relative_sector = Geometry.half_moon_footprint_relative_sector_gu(
			origin_ground_gu,
			target_ground_gu,
			0.0,
			normalized_attack_direction,
			range_bonus_gu,
		)
	elif has_target_direction:
		relative_sector = Geometry.half_moon_relative_sector(
			normalized_attack_direction,
			target_direction,
		)
	var result_code := _result_code(
		resolved_mode,
		distance_gu,
		effective_reach_gu,
		normalized_attack_direction,
		target_direction,
		line,
		relative_sector
	)
	return {
		"contract_id": CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"target_count_policy_id": Geometry.TARGET_COUNT_POLICY_ID,
		"result_code": result_code,
		"accepted": result_code == RESULT_OK,
		"requested_mode": mode,
		"mode": resolved_mode,
		"origin_ground_gu": _vector2_json(origin_ground_gu),
		"target_ground_gu": _vector2_json(target_ground_gu),
		"ground_delta_gu": _vector2_json(delta_ground_gu),
		"distance_gu": distance_gu,
		"attack_direction_index": normalized_attack_direction,
		"target_direction_index": target_direction,
		"has_target_direction": has_target_direction,
		"canonical_attack_grid_step": _vector2i_json(
			Geometry.facing_tile_step(normalized_attack_direction)
		),
		"forward_gu": line.x,
		"lateral_gu": line.y,
		"thrust_slot": slot,
		"half_moon_relative_sector": relative_sector,
		"half_moon_allowed_relative_sectors": Array(
			Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS
		),
		"base_reach_gu": float(Geometry.BASE_REACH_GU[resolved_mode]),
		"requested_range_bonus_gu": float(range_bonus_gu),
		"effective_reach_gu": effective_reach_gu,
		"thrust_primary_reach_gu": Geometry.THRUST_PRIMARY_REACH_GU,
		"attack_lane_width_gu": Geometry.THRUST_WIDTH_GU,
		"maximum_targets": Geometry.maximum_targets(resolved_mode),
		"unlimited_targets_within_geometry": not Geometry.has_finite_target_limit(
			resolved_mode
		),
	}


static func explain_footprint_candidate(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	target_combat_radius_gu: float,
	attack_direction_index: int,
	mode: String,
	range_bonus_gu := 0.0
) -> Dictionary:
	## Reports the historical footpoint-only decision beside the authoritative
	## footprint-area intersection. Runtime instrumentation can therefore prove
	## when an unchanged attack area reaches a monster body even though its centre
	## footpoint remains just outside the old point test.
	var point_result := explain_candidate(
		origin_ground_gu,
		target_ground_gu,
		attack_direction_index,
		mode,
		range_bonus_gu
	)
	var resolved_mode := str(point_result.get("mode", Geometry.SKILL_NORMAL))
	var normalized_attack_direction := posmod(attack_direction_index, 8)
	var footprint_accepted := Geometry.footprint_intersects_mode_gu(
		origin_ground_gu,
		target_ground_gu,
		target_combat_radius_gu,
		normalized_attack_direction,
		resolved_mode,
		range_bonus_gu
	)
	var footprint_slot := (
		Geometry.thrust_footprint_slot_gu(
			origin_ground_gu,
			target_ground_gu,
			target_combat_radius_gu,
			normalized_attack_direction,
			range_bonus_gu
		)
		if resolved_mode == Geometry.SKILL_THRUST
		else 0
	)
	var footprint_half_moon_relative_sector := (
		Geometry.half_moon_footprint_relative_sector_gu(
			origin_ground_gu,
			target_ground_gu,
			target_combat_radius_gu,
			normalized_attack_direction,
			range_bonus_gu
		)
		if resolved_mode == Geometry.SKILL_HALF_MOON
		else -1
	)
	var target_polygon := Geometry.target_footprint_polygon_ground_gu(
		target_ground_gu,
		target_combat_radius_gu
	)
	var attack_polygons := Geometry.attack_region_polygons_ground_gu(
		origin_ground_gu,
		normalized_attack_direction,
		resolved_mode,
		range_bonus_gu
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
		"target_combat_radius_gu": maxf(0.0, target_combat_radius_gu),
		"target_footprint_vertex_count": target_polygon.size(),
		"target_footprint_polygon_ground_gu": _polygon_json(target_polygon),
		"attack_region_polygon_count": attack_polygons.size(),
		"attack_region_polygons_ground_gu": _polygons_json(attack_polygons),
	}, true)
	return result


static func audit_direction(screen_direction_index: int) -> Dictionary:
	var normalized_screen_direction := posmod(screen_direction_index, 8)
	var grid_step := Geometry.facing_tile_step(normalized_screen_direction)
	var ground_delta_gu := Vector2(grid_step).normalized()
	var projected_screen_vector_px := _project_ground_delta_gu(ground_delta_gu)
	var world_direction := Geometry.direction_index_for_ground_delta_gu(ground_delta_gu)
	var projected_screen_direction := _direction_index_for_projected_screen_delta(
		projected_screen_vector_px
	)
	var matches := (
		normalized_screen_direction == world_direction
		and normalized_screen_direction == projected_screen_direction
	)
	return {
		"contract_id": DIRECTION_AUDIT_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"requested_screen_direction_index": screen_direction_index,
		"screen_direction_index": normalized_screen_direction,
		"world_direction_index": world_direction,
		"canonical_grid_step": _vector2i_json(grid_step),
		"canonical_ground_direction_gu": _vector2_json(ground_delta_gu),
		"projected_screen_vector_px": _vector2_json(projected_screen_vector_px),
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
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"direction_order": ["S", "SW", "W", "NW", "N", "NE", "E", "SE"],
		"direction_count": directions.size(),
		"consistent": consistent,
		"directions": directions,
	}


static func audit_ground_delta_gu(ground_delta_gu: Vector2) -> Dictionary:
	## Compares the current project's 2:1-projected screen-angle quantizer with
	## the alternative 45-degree quantizer measured directly in canonical tile
	## space. It is deliberately read-only: neither result is selected here.
	var projected_screen_vector_px := _project_ground_delta_gu(ground_delta_gu)
	var projected_screen_direction := _direction_index_for_projected_screen_delta(
		projected_screen_vector_px
	)
	var ground_space_direction := Geometry.direction_index_for_ground_delta_gu(
		ground_delta_gu
	)
	var matches := projected_screen_direction == ground_space_direction
	var projected_screen_direction_px := (
		projected_screen_vector_px.normalized()
		if projected_screen_vector_px.length_squared() > Geometry.EPSILON * Geometry.EPSILON
		else Vector2.ZERO
	)
	return {
		"contract_id": ANGLE_QUANTIZATION_AUDIT_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"geometry_contract_id": Geometry.CONTRACT_ID,
		"active_direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"ground_delta_gu": _vector2_json(ground_delta_gu),
		"has_direction": (
			ground_delta_gu.length_squared()
			> Geometry.EPSILON * Geometry.EPSILON
		),
		"projected_screen_45_direction_index": projected_screen_direction,
		"ground_space_45_direction_index": ground_space_direction,
		"quantizers_match": matches,
		"projected_screen_canonical_grid_step": _vector2i_json(
			Geometry.facing_tile_step(projected_screen_direction)
		),
		"ground_space_canonical_grid_step": _vector2i_json(
			Geometry.facing_tile_step(ground_space_direction)
		),
		"projected_screen_vector_px": _vector2_json(projected_screen_vector_px),
		"projected_screen_direction_px": _vector2_json(projected_screen_direction_px),
	}


static func explain_target_aligned_release(
	release_geometry: Dictionary,
	mode: String,
	coordinate_context: Dictionary,
	terrain_blocked := false,
	range_bonus_gu := 0.0
) -> Dictionary:
	## Read-only explanation of the target-aligned continuous release contract.
	## Mirrors WarriorMeleeGeometry.target_aligned_melee_release_plan_ground_gu
	## so instrumentation can prove eligibility, axis source and snapshot reuse
	## without ever deciding damage or mutating candidates.
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		release_geometry,
		mode,
		coordinate_context,
		range_bonus_gu,
		terrain_blocked
	)
	var eligible := bool(plan.get("target_axis_eligible", false))
	var raw_snapshot: Variant = plan.get("skill_footprint_snapshot")
	var snapshot_shape := ""
	var snapshot_id := ""
	if raw_snapshot is Dictionary:
		snapshot_shape = str(
			(raw_snapshot as Dictionary).get("shape_type", "")
		)
		snapshot_id = str(
			(raw_snapshot as Dictionary).get("snapshot_id", "")
		)
	var continuous_axis_ground_gu := (
		plan.get("continuous_axis_ground_gu", Vector2.ZERO) as Vector2
	)
	return {
		"contract_id": TARGET_ALIGNED_RELEASE_CONTRACT_ID,
		"geometry_contract_id": (
			Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		),
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"requested_mode": mode,
		"mode": str(plan.get("mode", Geometry.SKILL_NORMAL)),
		"target_axis_eligible": eligible,
		"ineligible_reason": str(plan.get("ineligible_reason", "")),
		"result_code": (
			RESULT_TARGET_ALIGNED_OK
			if eligible
			else RESULT_TARGET_ALIGNED_INELIGIBLE
		),
		"origin_ground_gu": _vector2_json(
			plan.get("origin_ground_gu", Vector2.ZERO)
		),
		"continuous_axis_ground_gu": _vector2_json(
			continuous_axis_ground_gu
		),
		"locked_target_ground_gu_at_release": _vector2_json(
			plan.get("locked_target_ground_gu_at_release", Vector2.ZERO)
		),
		"locked_target_instance_id": int(
			plan.get("locked_target_instance_id", 0)
		),
		"visual_direction_index": int(
			plan.get("visual_direction_index", -1)
		),
		"visual_direction_contract_id": str(
			plan.get("visual_direction_contract_id", "")
		),
		"snapshot_built": raw_snapshot is Dictionary,
		"snapshot_id": snapshot_id,
		"snapshot_shape_type": snapshot_shape,
		"terrain_blocked": bool(plan.get("terrain_blocked", false)),
		"range_bonus_gu": float(plan.get("range_bonus_gu", range_bonus_gu)),
	}


static func audit_target_aligned_axis(
	origin_ground_gu: Vector2,
	locked_target_ground_gu: Vector2
) -> Dictionary:
	## Machine-checkable audit: the continuous release axis must equal the
	## locked-target ground direction while the character visual index remains
	## the 8-direction quantization of that same delta.
	var delta_ground_gu := locked_target_ground_gu - origin_ground_gu
	var has_direction := (
		delta_ground_gu.length_squared()
		> Geometry.EPSILON * Geometry.EPSILON
	)
	var continuous_axis_ground_gu := (
		delta_ground_gu.normalized() if has_direction else Vector2.ZERO
	)
	var quantized_direction_index := (
		Geometry.direction_index_for_ground_delta_gu(delta_ground_gu)
		if has_direction
		else -1
	)
	var quantized_axis_ground_gu := (
		Geometry.canonical_ground_direction_gu(quantized_direction_index)
		if has_direction
		else Vector2.ZERO
	)
	return {
		"contract_id": TARGET_ALIGNED_AXIS_AUDIT_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"geometry_contract_id": (
			Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		),
		"direction_space_contract_id": Geometry.DIRECTION_SPACE_CONTRACT_ID,
		"origin_ground_gu": _vector2_json(origin_ground_gu),
		"locked_target_ground_gu": _vector2_json(locked_target_ground_gu),
		"ground_delta_gu": _vector2_json(delta_ground_gu),
		"has_direction": has_direction,
		"continuous_axis_ground_gu": _vector2_json(
			continuous_axis_ground_gu
		),
		"quantized_direction_index": quantized_direction_index,
		"quantized_axis_ground_gu": _vector2_json(quantized_axis_ground_gu),
		"continuous_matches_quantized": (
			has_direction
			and continuous_axis_ground_gu.is_equal_approx(
				quantized_axis_ground_gu
			)
		),
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
			if absf(line.y) > Geometry.THRUST_WIDTH_GU * 0.5 + Geometry.EPSILON:
				return RESULT_OUTSIDE_ATTACK_LANE
		Geometry.SKILL_HALF_MOON:
			if half_moon_relative_sector not in Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
				return RESULT_OUTSIDE_HALF_MOON_ARC
		_:
			if target_direction_index != attack_direction_index:
				return RESULT_WRONG_FACING
	return RESULT_OK


static func _project_ground_delta_gu(ground_delta_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		ground_delta_gu
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
