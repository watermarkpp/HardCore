extends Node

const DROP_CONTRACT_ID := "monster.loot.canonical_id_only.v1"


func roll_monster_drops(
	monster_id: int,
	rng: RandomNumberGenerator,
	maximum := 6
) -> Dictionary:
	var result := {
		"contract_id": DROP_CONTRACT_ID,
		"monster_id": monster_id,
		"configured": false,
		"reason": "",
		"source_entry_count": 0,
		"resolution_attempted_count": 0,
		"resolved_entry_count": 0,
		"items": [],
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
	var profile := GameData.get_canonical_monster_drop_profile(resolved_id)
	if profile.is_empty():
		result.reason = "drop_profile_missing_or_empty"
		return result
	var entries_value: Variant = profile.get("entries", [])
	if not entries_value is Array or entries_value.is_empty():
		result.reason = "drop_profile_missing_or_empty"
		return result
	var entries: Array = entries_value
	result.configured = true
	result.source_entry_count = entries.size()
	if rng == null:
		result.reason = "rng_missing"
		return result
	var limit := maxi(0, int(maximum))
	for raw_entry: Variant in entries:
		result.resolution_attempted_count += 1
		if not raw_entry is Dictionary:
			_append_rejection(result, -1, "drop_entry_invalid")
			continue
		var entry: Dictionary = raw_entry
		var denominator := _chance_denominator(str(entry.get("chance", "")))
		if denominator <= 0:
			_append_rejection(
				result,
				int(entry.get("line_number", -1)),
				"chance_token_invalid"
			)
			continue
		var item_resolution := GameData.resolve_canonical_drop_item(entry)
		if not bool(item_resolution.get("ok", false)):
			_append_rejection(
				result,
				int(entry.get("line_number", -1)),
				str(item_resolution.get("reason", "item_authority_unresolved"))
			)
			continue
		result.resolved_entry_count += 1
		if result.items.size() >= limit:
			continue
		if rng.randi_range(1, denominator) == 1:
			result.items.append(str(item_resolution.get("item_name", "")))
	return result


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
