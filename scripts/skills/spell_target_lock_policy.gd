class_name SpellTargetLockPolicy
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CONTRACT_ID := "combat.spell_lock.euclidean_gu.v2"
const LOCK_RANGE_GU := 12.0
# Compatibility alias for old integration code. Its value is now GU, never GS
# or a Chebyshev radius.
const LOCK_RANGE_TILES := LOCK_RANGE_GU


static func distance_gu(origin_ground_gu: Vector2, target_ground_gu: Vector2) -> float:
	return GroundUnitSpaceScript.distance_gu(origin_ground_gu, target_ground_gu)


static func chebyshev_distance(origin_tile: Vector2, target_tile: Vector2) -> float:
	## Deprecated call-shape retained for the integration migration. Inputs are
	## formal GU coordinates and the result is Euclidean GU.
	return distance_gu(origin_tile, target_tile)


static func is_within_lock_range(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2
) -> bool:
	return GroundUnitSpaceScript.is_within_range_gu(
		origin_ground_gu,
		target_ground_gu,
		LOCK_RANGE_GU
	)


static func ordered_candidates(raw_candidates: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_candidate: Dictionary in raw_candidates:
		var candidate := raw_candidate.duplicate(true)
		var origin_ground_gu: Vector2 = candidate.get(
			"origin_ground_gu", candidate.get("origin_tile", Vector2.ZERO)
		)
		var target_ground_gu: Vector2 = candidate.get(
			"target_ground_gu", candidate.get("target_tile", Vector2.ZERO)
		)
		var distance_squared_gu := GroundUnitSpaceScript.distance_squared_gu(
			origin_ground_gu,
			target_ground_gu
		)
		if not is_within_lock_range(origin_ground_gu, target_ground_gu):
			continue
		candidate["contract_id"] = CONTRACT_ID
		candidate["unit_contract_id"] = GroundUnitSpaceScript.CONTRACT_ID
		candidate["origin_ground_gu"] = origin_ground_gu
		candidate["target_ground_gu"] = target_ground_gu
		candidate["distance_squared_gu"] = distance_squared_gu
		candidate["distance_gu"] = sqrt(distance_squared_gu)
		result.append(candidate)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance_squared_gu := float(a.get("distance_squared_gu", INF))
		var b_distance_squared_gu := float(b.get("distance_squared_gu", INF))
		if not is_equal_approx(a_distance_squared_gu, b_distance_squared_gu):
			return a_distance_squared_gu < b_distance_squared_gu
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	return result


static func spell_range_allows_target(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	maximum_range_gu: float
) -> bool:
	if maximum_range_gu <= 0.0:
		return true
	return GroundUnitSpaceScript.is_within_range_gu(
		origin_ground_gu,
		target_ground_gu,
		maximum_range_gu
	)


static func attack_range_allows_target(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	maximum_range_gu := 10.0
) -> bool:
	return GroundUnitSpaceScript.is_within_range_gu(
		origin_ground_gu,
		target_ground_gu,
		maximum_range_gu
	)
