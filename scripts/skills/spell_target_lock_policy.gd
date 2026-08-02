class_name SpellTargetLockPolicy
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CONTRACT_ID := "combat.spell_lock.euclidean_gu.v2"
const LOCK_RANGE_GU := 12.0


static func distance_gu(origin_ground_gu: Vector2, target_ground_gu: Vector2) -> float:
	return GroundUnitSpaceScript.distance_gu(origin_ground_gu, target_ground_gu)


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
		if (
			not raw_candidate.has("origin_ground_gu")
			or not raw_candidate.has("target_ground_gu")
		):
			continue
		if (
			not raw_candidate["origin_ground_gu"] is Vector2
			or not raw_candidate["target_ground_gu"] is Vector2
		):
			continue
		var candidate := raw_candidate.duplicate(true)
		var origin_ground_gu: Vector2 = candidate["origin_ground_gu"]
		var target_ground_gu: Vector2 = candidate["target_ground_gu"]
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
