class_name TaoistSupportPolicy
extends RefCounted

## Pure strategy contract for Taoist friendly-target selection
## (skills.taoist.support_targeting.v1). Candidate pool is the caster plus
## alive, owned SummonActors. HP-fraction comparisons use integer
## cross-multiplication so they never depend on float precision. Tie-break
## order is fixed: self first, then closer ground distance, then stable
## instance id.

const Targeting := preload(
	"res://scripts/skills/taoist_friendly_targeting.gd"
)

const CONTRACT_ID := "skills.taoist.support_targeting.v1"
const DEFAULT_HEAL_RANGE_GU := 9.0

const REASON_NO_FRIENDLY_CANDIDATES := "no_friendly_candidates"
const REASON_ALL_FRIENDLY_TARGETS_FULL_HP := "all_friendly_targets_full_hp"
const REASON_NO_INJURED_FRIENDLY_TARGET_IN_RANGE := (
	"no_injured_friendly_target_in_range"
)


static func make_candidate(
	instance_id: int,
	is_self: bool,
	current_hp: int,
	max_hp: int,
	ground_position_gu: Vector2,
	level := 1,
	actor_kind := "summon"
) -> Dictionary:
	return {
		"instance_id": int(instance_id),
		"is_self": bool(is_self),
		"current_hp": maxi(0, int(current_hp)),
		"max_hp": maxi(1, int(max_hp)),
		"ground_position_gu": ground_position_gu,
		"level": maxi(1, int(level)),
		"actor_kind": "self" if bool(is_self) else str(actor_kind),
	}


static func normalize_candidates(raw_candidates: Variant) -> Array[Dictionary]:
	## Accepts only alive candidates (current_hp > 0) with a usable max_hp,
	## position and stable instance id.
	var result: Array[Dictionary] = []
	if not raw_candidates is Array:
		return result
	for raw_value: Variant in raw_candidates:
		if not raw_value is Dictionary:
			continue
		var raw: Dictionary = raw_value
		if int(raw.get("instance_id", 0)) <= 0:
			continue
		if int(raw.get("max_hp", 0)) <= 0:
			continue
		var current_hp := int(raw.get("current_hp", 0))
		if current_hp <= 0:
			continue
		if not raw.has("ground_position_gu"):
			continue
		var position: Variant = raw.get("ground_position_gu", Vector2.ZERO)
		if not position is Vector2:
			continue
		result.append(make_candidate(
			int(raw.get("instance_id", 0)),
			bool(raw.get("is_self", false)),
			current_hp,
			int(raw.get("max_hp", 1)),
			position,
			int(raw.get("level", 1)),
			str(raw.get("actor_kind", "summon"))
		))
	return result


static func injured_candidates(
	candidates: Array,
	center_ground_gu: Vector2,
	range_gu: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		if int(candidate.get("max_hp", 1)) <= int(candidate.get("current_hp", 0)):
			continue
		if Targeting.within_range_gu(candidate, center_ground_gu, range_gu):
			result.append(candidate)
	return result


static func select_heal_target(
	candidates: Array,
	center_ground_gu: Vector2,
	range_gu := DEFAULT_HEAL_RANGE_GU
) -> Dictionary:
	var normalized := normalize_candidates(candidates)
	if normalized.is_empty():
		return {
			"valid": false,
			"contract_id": CONTRACT_ID,
			"reason": REASON_NO_FRIENDLY_CANDIDATES,
			"center_ground_gu": center_ground_gu,
			"range_gu": range_gu,
			"candidate_count": 0,
		}
	var injured := injured_candidates(normalized, center_ground_gu, range_gu)
	if injured.is_empty():
		var any_injured := false
		for candidate: Dictionary in normalized:
			if int(candidate.get("max_hp", 1)) > int(candidate.get("current_hp", 0)):
				any_injured = true
				break
		var reason := (
			REASON_ALL_FRIENDLY_TARGETS_FULL_HP
			if not any_injured
			else REASON_NO_INJURED_FRIENDLY_TARGET_IN_RANGE
		)
		return {
			"valid": false,
			"contract_id": CONTRACT_ID,
			"reason": reason,
			"center_ground_gu": center_ground_gu,
			"range_gu": range_gu,
			"candidate_count": normalized.size(),
		}
	var best: Dictionary = {}
	var best_missing := 0
	var best_max_hp := 1
	for candidate: Dictionary in injured:
		var missing := int(candidate.get("max_hp", 1)) - int(
			candidate.get("current_hp", 0)
		)
		var candidate_max_hp := int(candidate.get("max_hp", 1))
		var better := false
		if best.is_empty():
			better = true
		else:
			## Cross-multiplied missing-fraction comparison (exact integers).
			if missing * best_max_hp > best_missing * candidate_max_hp:
				better = true
			elif missing * best_max_hp == best_missing * candidate_max_hp:
				better = _tie_break_wins(
					candidate,
					best,
					center_ground_gu
				)
		if better:
			best = candidate
			best_missing = missing
			best_max_hp = candidate_max_hp
	return {
		"valid": true,
		"contract_id": CONTRACT_ID,
		"reason": "",
		"center_ground_gu": center_ground_gu,
		"range_gu": range_gu,
		"selected": best,
		"injured_count": injured.size(),
		"candidate_count": normalized.size(),
	}


static func _tie_break_wins(
	candidate: Dictionary,
	current_best: Dictionary,
	center_ground_gu: Vector2
) -> bool:
	var candidate_is_self := bool(candidate.get("is_self", false))
	var best_is_self := bool(current_best.get("is_self", false))
	if candidate_is_self != best_is_self:
		return candidate_is_self
	var candidate_distance := Targeting.distance_squared_gu(
		candidate,
		center_ground_gu
	)
	var best_distance := Targeting.distance_squared_gu(
		current_best,
		center_ground_gu
	)
	if candidate_distance < best_distance:
		return true
	if is_equal_approx(candidate_distance, best_distance):
		return (
			int(candidate.get("instance_id", 0))
			< int(current_best.get("instance_id", 0))
		)
	return false
