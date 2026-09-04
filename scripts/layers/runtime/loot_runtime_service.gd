extends Node

const DROP_CONTRACT_ID := "monster.loot.dpv2_direct_baseline.v2"
const SMALL_MONSTER_CLASSIFICATION := "ordinary"
const SMALL_MONSTER_EQUIPMENT_DENOMINATOR_MULTIPLIER := 3
const SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER := 6
const ELITE_BOSS_SOLAR_DENOMINATOR_MULTIPLIER := 2
const ELITE_BOSS_CLASSIFICATIONS := {
	"elite": true,
	"boss": true,
}
const ELITE_BOSS_SOLAR_ITEM_IDS := {
	920014: true,
	920016: true,
}
const SMALL_MONSTER_SHENSHUI_ITEM_IDS := {
	910001: true,
	910002: true,
	910003: true,
	910004: true,
	910005: true,
	910006: true,
}
const FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID := {
	117: "布衣(男)",
	119: "轻型盔甲(男)",
	121: "中型盔甲(男)",
	123: "重盔甲(男)",
	125: "魔法长袍(男)",
	127: "灵魂战衣(男)",
	129: "战神盔甲(男)",
	131: "恶魔长袍(男)",
	133: "幽灵战衣(男)",
	141: "天魔神甲",
	143: "法神披风",
	145: "天尊道袍",
}

var _overflow_telemetry_by_monster_id: Dictionary = {}
var _lean_profile_by_monster_id: Dictionary = {}
var _lean_probability_by_key: Dictionary = {}
var _lean_reward_by_slot_uid: Dictionary = {}
var _lean_cache_misses := {"profile": 0, "probability": 0, "reward": 0}


func _lean_profile(monster_id: int) -> Dictionary:
	if not _lean_profile_by_monster_id.has(monster_id):
		_lean_cache_misses["profile"] = int(_lean_cache_misses.get("profile", 0)) + 1
		_lean_profile_by_monster_id[monster_id] = GameData.dpv2_direct_profile(monster_id)
	return _lean_profile_by_monster_id.get(monster_id, {})


func _lean_probability(monster_id: int, slot_uid: String) -> Dictionary:
	var production: Variant = GameData.dpv2_single_player_drop_boost.get("production", {})
	var boost_enabled := bool((production as Dictionary).get("enabled", false)) if production is Dictionary else false
	var scale := GameData.dpv2_active_global_drop_rate()
	var cache_key := "%d|%s|%s|%d|%d|%d" % [
		monster_id,
		slot_uid,
		str(scale.get("preset", "")),
		int(scale.get("numerator", 0)),
		int(scale.get("denominator", 0)),
		int(boost_enabled),
	]
	if not _lean_probability_by_key.has(cache_key):
		_lean_cache_misses["probability"] = int(_lean_cache_misses.get("probability", 0)) + 1
		_lean_probability_by_key[cache_key] = GameData.dpv2_effective_slot_probability(
			monster_id,
			slot_uid,
		)
	return _lean_probability_by_key.get(cache_key, {})


func _lean_reward(slot: Dictionary) -> Dictionary:
	var slot_uid := str(slot.get("slot_uid", ""))
	if slot_uid.is_empty():
		return GameData.dpv2_direct_resolve_slot_reward(slot)
	if not _lean_reward_by_slot_uid.has(slot_uid):
		_lean_cache_misses["reward"] = int(_lean_cache_misses.get("reward", 0)) + 1
		_lean_reward_by_slot_uid[slot_uid] = GameData.dpv2_direct_resolve_slot_reward(slot)
	return _lean_reward_by_slot_uid.get(slot_uid, {})


func clear_runtime_resolution_cache_for_test() -> void:
	_lean_profile_by_monster_id.clear()
	_lean_probability_by_key.clear()
	_lean_reward_by_slot_uid.clear()
	_lean_cache_misses = {"profile": 0, "probability": 0, "reward": 0}


func runtime_resolution_cache_debug_snapshot() -> Dictionary:
	return {
		"profile_count": _lean_profile_by_monster_id.size(),
		"probability_count": _lean_probability_by_key.size(),
		"reward_count": _lean_reward_by_slot_uid.size(),
		"misses": _lean_cache_misses.duplicate(true),
	}


func possible_item_names_for_monster_ids(monster_ids: Array) -> Array[String]:
	var names: Array[String] = []
	var seen := {}
	for raw_id: Variant in monster_ids:
		var resolved_id := GameData.canonical_monster_id(int(raw_id))
		if resolved_id <= 0:
			continue
		var profile := _lean_profile(resolved_id)
		for raw_slot: Variant in profile.get("slots", []):
			if not raw_slot is Dictionary:
				continue
			# Map bootstrap already enumerates possible ground icons. Compile the
			# matching probability row here as well so the first death does not pay
			# the authoritative mirror-validation cost on the gameplay frame.
			_lean_probability(resolved_id, str(raw_slot.get("slot_uid", "")))
			var reward := _lean_reward(raw_slot)
			var item_name := (
				_drop_output_item_name(
					int(raw_slot.get("canonical_item_id", -1)),
					str(reward.get("item_name", "")),
				)
				if bool(reward.get("ok", false))
				else ""
			)
			if str(reward.get("kind", "")) == "gold" or item_name.is_empty() or seen.has(item_name):
				continue
			seen[item_name] = true
			names.append(item_name)
	names.sort()
	return names


func roll_monster_drops(
	monster_id: int,
	rng: RandomNumberGenerator,
	include_audit := true,
) -> Dictionary:
	var result := {
		"contract_id": DROP_CONTRACT_ID,
		"runtime_authority": {
			"authority_id": "dpv2.direct_baseline.v2",
			"schema": "hardcore.dpv2.direct_monster_drop_baseline.v2",
			"effective_probability_authority_id": "dpv2.single_player_drop_boost.v1",
			"effective_probability_schema": (
				"hardcore.dpv2.single_player_effective_probability.v1"
			),
			"identity_key": "canonical_monster_id",
			"fallback_forbidden": true,
			"probability_formula": (
				"SPB enabled: effective x required 1x; "
				+ "SPB disabled: base x global exactly once"
			),
		},
		"monster_id": monster_id,
		"canonical_monster_id": -1,
		"configured": false,
		"reason": "",
		"source_entry_count": 0,
		"resolution_attempted_count": 0,
		"resolved_entry_count": 0,
		"resolved_gold_count": 0,
		"drop_enabled_source_slots": 0,
		"drop_disabled_source_slots": 0,
		"reward_resolved_enabled_slots": 0,
		"probability_resolved_enabled_slots": 0,
		"rng_eligible_slots": 0,
		"rng_roll_count": 0,
		"successful_roll_count": 0,
		"ground_output_count": 0,
		"overflow_discarded_count": 0,
		"protected_overflow_count": 0,
		"all_resolved_slots_rng": false,
		"all_enabled_resolved_slots_rng_before_overflow": false,
		"ground_output_plus_discarded_equals_successful": true,
		"items": [],
		"gold_drops": [],
		"overflow_discarded": [],
		"rejected_entries": [],
		"attempts": [],
		"slot_attempts": [],
		"debug": [],
	}
	result["source_slot_gate"] = GameData.dpv2_source_slot_gate()
	if not GameData.is_dpv2_direct_baseline_loaded():
		result.reason = "dpv2_direct_baseline_unavailable"
		return result
	if not GameData.is_dpv2_single_player_drop_boost_loaded():
		result.reason = "spb_effective_probability_unavailable"
		return result
	var resolved_id := GameData.canonical_monster_id(monster_id)
	if resolved_id <= 0:
		result.reason = "invalid_monster_id"
		return result
	result.canonical_monster_id = resolved_id

	# The direct profile is joined by canonical_monster_id. Its display/profile
	# token is telemetry only and is never used to locate a runtime drop table.
	var profile := (
		GameData.dpv2_direct_profile(resolved_id)
		if include_audit
		else _lean_profile(resolved_id)
	)
	if profile.is_empty():
		result.reason = "dpv2_direct_profile_unresolved"
		return result
	result["direct_profile"] = {
		"canonical_monster_id": resolved_id,
		"drop_profile_id": str(profile.get("drop_profile_id", "")),
		"baseline_origin": str(profile.get("baseline_origin", "")),
	}
	var slots_value: Variant = profile.get("slots", [])
	if not slots_value is Array:
		result.reason = "dpv2_direct_slots_invalid"
		return result
	var slots: Array = slots_value
	result.configured = true
	result.source_entry_count = slots.size()
	if not bool(profile.get("drop_enabled", false)):
		result.reason = "drop_disabled"
		result.drop_disabled_source_slots = 0
		result.all_resolved_slots_rng = true
		result.all_enabled_resolved_slots_rng_before_overflow = true
		return result
	result.drop_enabled_source_slots = slots.size()
	if slots.is_empty():
		# An enabled profile with no direct slots is a valid zero-drop profile;
		# it is not allowed to consult any legacy catalog as a fallback.
		result.reason = ""
		result.all_resolved_slots_rng = true
		result.all_enabled_resolved_slots_rng_before_overflow = true
		return result
	if rng == null:
		result.reason = "rng_missing"
		return result

	# Resolve every slot before the first RNG draw. A missing/mismatched SPB row
	# fails the whole monster roll closed and therefore cannot consume a partial
	# RNG sequence before the error becomes visible.
	var resolved_slots: Array = []
	for raw_slot: Variant in slots:
		result.resolution_attempted_count += 1
		if not raw_slot is Dictionary:
			_append_rejection(result, {}, "dpv2_direct_slot_invalid")
			continue
		var slot: Dictionary = raw_slot
		var slot_uid := str(slot.get("slot_uid", ""))
		var probability := (
			GameData.dpv2_effective_slot_probability(resolved_id, slot_uid)
			if include_audit
			else _lean_probability(resolved_id, slot_uid)
		)
		if not bool(probability.get("ok", false)):
			_append_rejection(
				result,
				slot,
				str(probability.get("reason", "dpv2_direct_probability_invalid")),
			)
			continue
		result.probability_resolved_enabled_slots += 1
		var reward := (
			GameData.dpv2_direct_resolve_slot_reward(slot)
			if include_audit
			else _lean_reward(slot)
		)
		if not bool(reward.get("ok", false)):
			_append_rejection(
				result,
				slot,
				str(reward.get("reason", "dpv2_direct_reward_unresolved")),
			)
			continue
		if str(reward.get("kind", "")) == "gold":
			var final_gold_amount := int(probability.get("final_gold_amount", 0))
			if final_gold_amount <= 0:
				_append_rejection(result, slot, "spb_effective_gold_amount_invalid")
				continue
			reward = reward.duplicate(true)
			reward["gold_amount"] = final_gold_amount
		result.reward_resolved_enabled_slots += 1
		result.resolved_entry_count += 1
		result.rng_eligible_slots += 1
		var denominator := int(probability.get("final_denominator", 0))
		var numerator := int(probability.get("final_numerator", 0))
		if numerator <= 0 or denominator <= 0:
			_append_rejection(result, slot, "spb_effective_probability_invalid")
			result.reward_resolved_enabled_slots -= 1
			result.resolved_entry_count -= 1
			result.rng_eligible_slots -= 1
			result.probability_resolved_enabled_slots -= 1
			continue
		resolved_slots.append({
			"slot": slot,
			"probability": probability,
			"reward": reward,
		})
	if not result.rejected_entries.is_empty() or resolved_slots.size() != slots.size():
		result.reason = "spb_effective_probability_fail_closed"
		return result

	var successful_rewards: Array = []
	var monster_classification := GameData.canonical_monster_classification(resolved_id)
	for raw_resolved: Variant in resolved_slots:
		var resolved: Dictionary = raw_resolved
		var slot: Dictionary = resolved.get("slot", {})
		var probability: Dictionary = resolved.get("probability", {})
		var denominator_multiplier := _drop_denominator_multiplier(
			probability,
			monster_classification,
		)
		if include_audit and denominator_multiplier > 1:
			probability = _apply_drop_probability_policy(
				probability,
				monster_classification,
			)
		var reward: Dictionary = resolved.get("reward", {})
		var slot_uid := str(slot.get("slot_uid", ""))
		var denominator := (
			int(probability.get("final_denominator", 0))
			if include_audit and denominator_multiplier > 1
			else int(probability.get("final_denominator", 0)) * denominator_multiplier
		)
		var numerator := int(probability.get("final_numerator", 0))
		result.rng_roll_count += 1
		var draw := rng.randi_range(1, denominator)
		var success := draw <= numerator
		var attempt: Dictionary = {}
		if include_audit:
			attempt = _build_attempt(slot, probability, reward, draw, success)
			_record_attempt(result, attempt)
		if success:
			var successful_candidate := {
				"slot_uid": slot_uid,
				"canonical_item_id": int(probability.get("canonical_item_id", -1)),
				"reward": reward.duplicate(true),
				"policy": probability.duplicate(true),
			}
			if include_audit:
				successful_candidate["attempt"] = attempt
			successful_rewards.append(successful_candidate)
	result.successful_roll_count = successful_rewards.size()
	result.all_resolved_slots_rng = (
		result.rng_roll_count == result.resolved_entry_count
	)
	result.all_enabled_resolved_slots_rng_before_overflow = (
		result.rng_roll_count == result.rng_eligible_slots
		and result.rng_eligible_slots == result.probability_resolved_enabled_slots
		and result.probability_resolved_enabled_slots
			== result.reward_resolved_enabled_slots
		and result.rng_eligible_slots == result.resolved_entry_count
		and result.resolved_entry_count == slots.size()
	)
	var selection := _select_ground_rewards(
		successful_rewards,
		rng,
		GameData.dpv2_ground_slot_limit(),
	)
	for raw_selected: Variant in selection.get("selected", []):
		if not raw_selected is Dictionary:
			continue
		var selected: Dictionary = raw_selected
		var reward: Dictionary = selected.get("reward", {})
		if str(reward.get("kind", "")) == "gold":
			result.resolved_gold_count += 1
			result.gold_drops.append(int(reward.get("gold_amount", 0)))
		else:
			result.items.append(_drop_output_item_name(
				int(selected.get("canonical_item_id", -1)),
				str(reward.get("item_name", "")),
			))
	result.overflow_discarded = selection.get("discarded", [])
	result.ground_output_count = result.items.size() + result.gold_drops.size()
	result.overflow_discarded_count = result.overflow_discarded.size()
	result.protected_overflow_count = int(
		selection.get("protected_discarded_count", 0)
	)
	result.ground_output_plus_discarded_equals_successful = (
		result.ground_output_count + result.overflow_discarded_count
		== result.successful_roll_count
	)
	if include_audit:
		_sync_attempt_views(result)
	return result


func _drop_output_item_name(canonical_item_id: int, original_name: String) -> String:
	return str(FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID.get(
		canonical_item_id,
		original_name,
	))


func _apply_drop_probability_policy(
	probability: Dictionary,
	monster_classification: String,
) -> Dictionary:
	var multiplier := _drop_denominator_multiplier(
		probability,
		monster_classification,
	)
	if multiplier == 1:
		return probability
	var adjusted := _apply_denominator_multiplier(
		probability,
		multiplier,
	)
	if adjusted == probability:
		return probability
	if monster_classification == SMALL_MONSTER_CLASSIFICATION:
		var reason := (
			"small_monster_shenshui_denominator_x6"
			if multiplier == SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
			else "small_monster_equipment_denominator_x3"
		)
		adjusted["pre_small_monster_numerator"] = int(
			probability.get("final_numerator", 0)
		)
		adjusted["pre_small_monster_denominator"] = int(
			probability.get("final_denominator", 0)
		)
		adjusted["small_monster_denominator_multiplier"] = multiplier
		adjusted["small_monster_probability_policy"] = reason
		adjusted["drop_denominator_policy"] = reason
	else:
		adjusted["elite_boss_solar_denominator_multiplier"] = multiplier
		adjusted["elite_boss_solar_probability_policy"] = (
			"elite_boss_solar_consumable_denominator_x2"
		)
		adjusted["drop_denominator_policy"] = (
			"elite_boss_solar_consumable_denominator_x2"
		)
	adjusted["drop_denominator_multiplier"] = multiplier
	return adjusted


func _apply_small_monster_probability_policy(
	probability: Dictionary,
	monster_classification: String,
) -> Dictionary:
	var multiplier := _small_monster_denominator_multiplier(
		probability,
		monster_classification,
	)
	if multiplier == 1:
		return probability
	var adjusted := _apply_denominator_multiplier(probability, multiplier)
	if adjusted == probability:
		return probability
	var reason := (
		"small_monster_shenshui_denominator_x6"
		if multiplier == SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
		else "small_monster_equipment_denominator_x3"
	)
	adjusted["pre_small_monster_numerator"] = int(
		probability.get("final_numerator", 0)
	)
	adjusted["pre_small_monster_denominator"] = int(
		probability.get("final_denominator", 0)
	)
	adjusted["small_monster_denominator_multiplier"] = multiplier
	adjusted["small_monster_probability_policy"] = reason
	return adjusted


func _apply_denominator_multiplier(
	probability: Dictionary,
	multiplier: int,
) -> Dictionary:
	var numerator := int(probability.get("final_numerator", 0))
	var denominator := int(probability.get("final_denominator", 0))
	if numerator <= 0 or denominator <= 0 or multiplier <= 1:
		return probability
	var adjusted := probability.duplicate(true)
	adjusted["final_denominator"] = denominator * multiplier
	adjusted["probability_denominator"] = denominator * multiplier
	adjusted["final_probability"] = (
		float(numerator) / float(denominator * multiplier)
	)
	return adjusted


func _drop_denominator_multiplier(
	probability: Dictionary,
	monster_classification: String,
) -> int:
	var small_monster_multiplier := _small_monster_denominator_multiplier(
		probability,
		monster_classification,
	)
	if small_monster_multiplier > 1:
		return small_monster_multiplier
	var item_id := int(probability.get("canonical_item_id", -1))
	if (
		ELITE_BOSS_CLASSIFICATIONS.has(monster_classification)
		and ELITE_BOSS_SOLAR_ITEM_IDS.has(item_id)
	):
		return ELITE_BOSS_SOLAR_DENOMINATOR_MULTIPLIER
	return 1


func _small_monster_denominator_multiplier(
	probability: Dictionary,
	monster_classification: String,
) -> int:
	if monster_classification != SMALL_MONSTER_CLASSIFICATION:
		return 1
	var item_id := int(probability.get("canonical_item_id", -1))
	if SMALL_MONSTER_SHENSHUI_ITEM_IDS.has(item_id):
		return SMALL_MONSTER_SHENSHUI_DENOMINATOR_MULTIPLIER
	if item_id > 0 and GameData.canonical_item_kind(item_id) == "equipment":
		return SMALL_MONSTER_EQUIPMENT_DENOMINATOR_MULTIPLIER
	return 1


func _build_attempt(
	slot: Dictionary,
	probability: Dictionary,
	reward: Dictionary,
	draw: int,
	success: bool,
) -> Dictionary:
	var attempt := {
		"slot_uid": str(slot.get("slot_uid", "")),
		"canonical_monster_id": int(probability.get("canonical_monster_id", -1)),
		"canonical_item_id": int(probability.get("canonical_item_id", -1)),
		"gold_amount": int(probability.get("gold_amount", -1)),
		"base_gold_amount": int(probability.get("base_gold_amount", -1)),
		"effective_gold_amount": int(
			probability.get("effective_gold_amount", -1)
		),
		"final_gold_amount": int(probability.get("final_gold_amount", -1)),
		"reward_kind": str(probability.get("reward_kind", reward.get("kind", ""))),
		"item_name": str(reward.get("item_name", "")),
		"base_numerator": int(probability.get("base_numerator", 0)),
		"base_denominator": int(probability.get("base_denominator", 0)),
		"base_probability": float(probability.get("base_probability", 0.0)),
		"spb_enabled": bool(probability.get("spb_enabled", false)),
		"spb_selected_source": str(probability.get("spb_selected_source", "")),
		"boost_policy": str(probability.get("boost_policy", "")),
		"boost_reason_code": str(probability.get("boost_reason_code", "")),
		"boost_formula_reason_code": str(
			probability.get("boost_formula_reason_code", "")
		),
		"boost_multiplier_numerator": int(
			probability.get("boost_multiplier_numerator", 0)
		),
		"boost_multiplier_denominator": int(
			probability.get("boost_multiplier_denominator", 0)
		),
		"ceiling_numerator": int(probability.get("ceiling_numerator", 0)),
		"ceiling_denominator": int(probability.get("ceiling_denominator", 0)),
		"ceiling_applied": bool(probability.get("ceiling_applied", false)),
		"effective_numerator": int(probability.get("effective_numerator", 0)),
		"effective_denominator": int(probability.get("effective_denominator", 0)),
		"effective_probability": float(
			probability.get("effective_probability", 0.0)
		),
		"global_preset": str(probability.get("global_preset", "")),
		"global_scale_numerator": int(probability.get("global_scale_numerator", 0)),
		"global_scale_denominator": int(probability.get("global_scale_denominator", 0)),
		"global_scale": float(probability.get("global_scale", 0.0)),
		"final_numerator": int(probability.get("final_numerator", 0)),
		"final_denominator": int(probability.get("final_denominator", 0)),
		"final_probability": float(probability.get("final_probability", 0.0)),
		"probability_numerator": int(probability.get("final_numerator", 0)),
		"probability_denominator": int(probability.get("final_denominator", 0)),
		"small_monster_probability_policy": str(
			probability.get("small_monster_probability_policy", "")
		),
		"small_monster_denominator_multiplier": int(
			probability.get("small_monster_denominator_multiplier", 1)
		),
		"elite_boss_solar_probability_policy": str(
			probability.get("elite_boss_solar_probability_policy", "")
		),
		"elite_boss_solar_denominator_multiplier": int(
			probability.get("elite_boss_solar_denominator_multiplier", 1)
		),
		"drop_denominator_policy": str(
			probability.get("drop_denominator_policy", "")
		),
		"drop_denominator_multiplier": int(
			probability.get("drop_denominator_multiplier", 1)
		),
		"draw": draw,
		"draw_success": success,
		"success": success,
		"overflow": "pending" if success else "not_applicable",
		"overflow_discarded": false,
		"protected_drop": bool(probability.get("protected_drop", false)),
		"protected_overflow": false,
		"overflow_priority": int(probability.get("overflow_priority", 0)),
		"baseline_origin": str(probability.get("baseline_origin", "")),
		"source_provenance_id": str(probability.get("source_provenance_id", "")),
	}
	return attempt


func _record_attempt(result: Dictionary, attempt: Dictionary) -> void:
	result.attempts.append(attempt)
	result.slot_attempts.append(attempt.duplicate(true))
	result.debug.append(attempt.duplicate(true))


func _sync_attempt_views(result: Dictionary) -> void:
	# Selection annotates the authoritative attempt in place. Refresh the two
	# compatibility/debug views after overflow so no view can report stale
	# pending state.
	result.slot_attempts.clear()
	result.debug.clear()
	for raw_attempt: Variant in result.attempts:
		if raw_attempt is Dictionary:
			result.slot_attempts.append((raw_attempt as Dictionary).duplicate(true))
			result.debug.append((raw_attempt as Dictionary).duplicate(true))


func _select_ground_rewards(
	successful_rewards: Array,
	rng: RandomNumberGenerator,
	maximum_ground_slots: int,
) -> Dictionary:
	var result := {
		"selected": [],
		"discarded": [],
		"protected_discarded_count": 0,
	}
	var limit := maxi(0, maximum_ground_slots)
	var protected_groups: Dictionary = {}
	var ordinary_groups: Dictionary = {}
	for raw_candidate: Variant in successful_rewards:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		var policy: Dictionary = candidate.get("policy", {})
		var priority := int(policy.get("overflow_priority", 0))
		var groups: Dictionary = (
			protected_groups if bool(policy.get("protected_drop", false))
			else ordinary_groups
		)
		if not groups.has(priority):
			groups[priority] = []
		(groups[priority] as Array).append(candidate)
	var protected_priorities: Array = protected_groups.keys()
	protected_priorities.sort()
	protected_priorities.reverse()
	for raw_priority: Variant in protected_priorities:
		var protected_group: Array = protected_groups.get(int(raw_priority), [])
		_consume_group(
			result,
			protected_group.duplicate(false),
			rng,
			limit,
		)
	var ordinary_priorities: Array = ordinary_groups.keys()
	ordinary_priorities.sort()
	ordinary_priorities.reverse()
	for raw_priority: Variant in ordinary_priorities:
		var ordinary_group: Array = ordinary_groups.get(int(raw_priority), [])
		_consume_group(
			result,
			ordinary_group.duplicate(false),
			rng,
			limit,
		)
	return result


func _consume_group(
	result: Dictionary,
	group: Array,
	rng: RandomNumberGenerator,
	limit: int,
) -> void:
	var remaining: int = limit - result.selected.size()
	if remaining <= 0:
		_append_discarded_group(result, group)
		return
	# Same protected/priority ties are unbiased only when the group crosses the
	# cap. Fitting groups preserve source order and consume no extra RNG.
	if group.size() > remaining:
		_shuffle_candidates(group, rng)
	for raw_candidate: Variant in group:
		if not raw_candidate is Dictionary:
			continue
		if result.selected.size() < limit:
			result.selected.append(raw_candidate)
			_mark_selected(raw_candidate)
		else:
			_append_discarded(result, raw_candidate)


func _append_discarded_group(result: Dictionary, group: Array) -> void:
	for raw_candidate: Variant in group:
		if raw_candidate is Dictionary:
			_append_discarded(result, raw_candidate)


func _mark_selected(candidate: Dictionary) -> void:
	var attempt: Variant = candidate.get("attempt", {})
	if not attempt is Dictionary:
		return
	attempt["overflow"] = "selected"
	attempt["overflow_discarded"] = false
	attempt["protected_overflow"] = false


func _append_discarded(result: Dictionary, candidate: Dictionary) -> void:
	result.discarded.append(candidate)
	var policy: Dictionary = candidate.get("policy", {})
	var protected := bool(policy.get("protected_drop", false))
	var attempt: Variant = candidate.get("attempt", {})
	if attempt is Dictionary:
		attempt["overflow"] = "discarded"
		attempt["overflow_discarded"] = true
		attempt["protected_overflow"] = protected
	if protected:
		result.protected_discarded_count += 1


func _shuffle_candidates(candidates: Array, rng: RandomNumberGenerator) -> void:
	if rng == null:
		return
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary: Variant = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary


func _chance_denominator(token: String) -> int:
	# Retained for the historical source-audit probe only. Production rolls
	# never parse chance tokens; V2 slots carry exact numerator/denominator.
	var parts := token.split("/", false)
	if parts.size() != 2 or parts[0] != "1":
		return -1
	var denominator_token := str(parts[1])
	if denominator_token.is_empty():
		return -1
	for index in range(denominator_token.length()):
		var codepoint := denominator_token.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return -1
	var denominator := int(denominator_token)
	return denominator if denominator > 0 else -1


func record_overflow_telemetry(monster_id: int, drop_roll: Dictionary) -> Dictionary:
	var overflow_discarded_count := int(
		drop_roll.get("overflow_discarded_count", 0)
	)
	if overflow_discarded_count <= 0:
		return {}
	var resolved_id := GameData.canonical_monster_id(monster_id)
	if resolved_id <= 0:
		return {}
	var key := str(resolved_id)
	var aggregate: Dictionary = _overflow_telemetry_by_monster_id.get(key, {
		"monster_id": resolved_id,
		"death_count": 0,
		"successful_roll_count": 0,
		"ground_output_count": 0,
		"overflow_discarded_count": 0,
		"protected_overflow_count": 0,
	})
	aggregate["death_count"] = int(aggregate.get("death_count", 0)) + 1
	for field: String in [
		"successful_roll_count",
		"ground_output_count",
		"overflow_discarded_count",
		"protected_overflow_count",
	]:
		aggregate[field] = int(aggregate.get(field, 0)) + int(
			drop_roll.get(field, 0)
		)
	_overflow_telemetry_by_monster_id[key] = aggregate
	return aggregate.duplicate(true)


func overflow_telemetry_snapshot() -> Dictionary:
	return _overflow_telemetry_by_monster_id.duplicate(true)


func clear_overflow_telemetry() -> void:
	_overflow_telemetry_by_monster_id.clear()


func _append_rejection(
	result: Dictionary,
	slot: Dictionary,
	reason: String,
) -> void:
	result.rejected_entries.append({
		"line_number": -1,
		"slot_uid": str(slot.get("slot_uid", "")),
		"canonical_item_id": int(slot.get("canonical_item_id", -1)),
		"gold_amount": int(slot.get("gold_amount", -1)),
		"reason": reason,
		"baseline_origin": str(slot.get("baseline_origin", "")),
		"source_provenance_id": str(slot.get("source_provenance_id", "")),
	})
