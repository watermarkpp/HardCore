extends Node

const DROP_CONTRACT_ID := "monster.loot.canonical_id_only.v1"


func roll_monster_drops(
	monster_id: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var result := {
		"contract_id": DROP_CONTRACT_ID,
		"monster_id": monster_id,
		"configured": false,
		"reason": "",
		"source_entry_count": 0,
		"resolution_attempted_count": 0,
		"resolved_entry_count": 0,
		"resolved_gold_count": 0,
		"rng_roll_count": 0,
		"successful_roll_count": 0,
		"ground_output_count": 0,
		"overflow_discarded_count": 0,
		"protected_overflow_count": 0,
		"all_resolved_slots_rng": false,
		"items": [],
		"gold_drops": [],
		"overflow_discarded": [],
		"rejected_entries": [],
	}
	var resolved_id := GameData.canonical_monster_id(monster_id)
	if resolved_id <= 0:
		result.reason = "invalid_monster_id"
		return result
	var monster := GameData.get_canonical_monster_entry(resolved_id, "runtime")
	if monster.is_empty():
		var catalog_entry := GameData.get_canonical_monster_entry(
			resolved_id, "catalog"
		)
		var closure := GameData.canonical_monster_runtime_drop_closure(
			resolved_id
		)
		if (
			not catalog_entry.is_empty()
			and bool(catalog_entry.get("runtime_allowed", false))
			and str(closure.get("reason", "")) == "drop_items_unresolved"
		):
			result.reason = "drop_items_unresolved"
		else:
			result.reason = "monster_not_runtime_allowed"
		return result
	var monster_drop_state := GameData.dpv2_monster_drop_state(resolved_id)
	if monster_drop_state.is_empty():
		result.reason = "monster_role_authority_unresolved"
		return result
	if not bool(monster_drop_state.get("drop_enabled", false)):
		result.configured = true
		result.reason = "drop_disabled"
		result.all_resolved_slots_rng = true
		return result
	var profile := GameData.get_canonical_monster_drop_profile(resolved_id)
	if profile.is_empty():
		# A legal no-drop entity: canonical policy does not require a non-empty
		# table, or a valid exemption applies. This is not a runtime error.
		var drop_policy: Dictionary = monster.get("drop_policy", {})
		var requires_non_empty := bool(
			drop_policy.get("hostile_requires_non_empty", false)
		)
		var exemption_value: Variant = drop_policy.get("exemption", null)
		var exemption_valid := (
			exemption_value is Dictionary
			and bool(exemption_value.get("allowed", false))
			and not str(exemption_value.get("reason", "")).is_empty()
		)
		if not requires_non_empty or exemption_valid:
			result.configured = true
			result.reason = ""
			result.source_entry_count = 0
			result.all_resolved_slots_rng = true
			return result
		result.reason = "drop_profile_missing_or_empty"
		return result
	var entries_value: Variant = profile.get("entries", [])
	if not entries_value is Array or entries_value.is_empty():
		var drop_policy: Dictionary = monster.get("drop_policy", {})
		var requires_non_empty := bool(
			drop_policy.get("hostile_requires_non_empty", false)
		)
		var exemption_value: Variant = drop_policy.get("exemption", null)
		var exemption_valid := (
			exemption_value is Dictionary
			and bool(exemption_value.get("allowed", false))
			and not str(exemption_value.get("reason", "")).is_empty()
		)
		if not requires_non_empty or exemption_valid:
			result.configured = true
			result.reason = ""
			result.source_entry_count = 0
			result.all_resolved_slots_rng = true
			return result
		result.reason = "drop_profile_missing_or_empty"
		return result
	var entries: Array = entries_value
	result.configured = true
	result.source_entry_count = entries.size()
	if rng == null:
		result.reason = "rng_missing"
		return result
	var successful_rewards: Array = []
	for raw_entry: Variant in entries:
		result.resolution_attempted_count += 1
		if not raw_entry is Dictionary:
			_append_rejection(result, -1, "drop_entry_invalid")
			continue
		var entry: Dictionary = raw_entry
		var reward := GameData.resolve_canonical_drop_reward(entry)
		if not bool(reward.get("ok", false)):
			_append_rejection(
				result,
				int(entry.get("line_number", -1)),
				str(reward.get("reason", "item_authority_unresolved"))
			)
			continue
		var policy := GameData.dpv2_resolve_reward_policy(resolved_id, reward)
		if not bool(policy.get("ok", false)):
			_append_rejection(
				result,
				int(entry.get("line_number", -1)),
				str(policy.get("reason", "drop_probability_authority_invalid"))
			)
			continue
		result.resolved_entry_count += 1
		result.rng_roll_count += 1
		var numerator := int(policy.get("probability_numerator", 0))
		var denominator := int(policy.get("probability_denominator", 0))
		if rng.randi_range(1, denominator) <= numerator:
			successful_rewards.append({
				"line_number": int(entry.get("line_number", -1)),
				"reward": reward.duplicate(true),
				"policy": policy.duplicate(true),
			})
	result.successful_roll_count = successful_rewards.size()
	result.all_resolved_slots_rng = (
		result.rng_roll_count == result.resolved_entry_count
	)
	var selection := _select_ground_rewards(
		successful_rewards,
		rng,
		GameData.dpv2_ground_slot_limit()
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
			result.items.append(str(reward.get("item_name", "")))
	result.overflow_discarded = selection.get("discarded", [])
	result.ground_output_count = (
		result.items.size() + result.gold_drops.size()
	)
	result.overflow_discarded_count = result.overflow_discarded.size()
	result.protected_overflow_count = int(
		selection.get("protected_discarded_count", 0)
	)
	return result


func _select_ground_rewards(
	successful_rewards: Array,
	rng: RandomNumberGenerator,
	maximum_ground_slots: int
) -> Dictionary:
	var result := {
		"selected": [],
		"discarded": [],
		"protected_discarded_count": 0,
	}
	var limit := maxi(0, maximum_ground_slots)
	var groups := {}
	for raw_candidate: Variant in successful_rewards:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		var policy: Dictionary = candidate.get("policy", {})
		var priority := int(policy.get("overflow_priority", 0))
		if not groups.has(priority):
			groups[priority] = []
		(groups[priority] as Array).append(candidate)
	var priorities: Array = groups.keys()
	priorities.sort()
	priorities.reverse()
	for raw_priority: Variant in priorities:
		var group: Array = groups.get(int(raw_priority), []).duplicate(true)
		_shuffle_candidates(group, rng)
		for raw_candidate: Variant in group:
			if result.selected.size() < limit:
				result.selected.append(raw_candidate)
			else:
				result.discarded.append(raw_candidate)
				var policy: Dictionary = raw_candidate.get("policy", {})
				if bool(policy.get("protected_drop", false)):
					result.protected_discarded_count += 1
	return result


func _shuffle_candidates(candidates: Array, rng: RandomNumberGenerator) -> void:
	if rng == null:
		return
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary: Variant = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary


func _chance_denominator(token: String) -> int:
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


func _append_rejection(result: Dictionary, line_number: int, reason: String) -> void:
	result.rejected_entries.append({
		"line_number": line_number,
		"reason": reason,
	})
