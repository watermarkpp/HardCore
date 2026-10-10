extends Node

const DROP_CONTRACT_ID := "monster.loot.dpv2_direct_baseline.v2"
const BossMaterialDropResolverScript := preload("res://scripts/drop/boss_material_drop_resolver.gd")
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

# V5 trace is opt-in and debug-build-only. It never fabricates actor IDs.
var _v5_trace_enabled := OS.has_feature("debug") and OS.get_environment("HARDCORE_DPV2_TRACE") == "1"
var _v5_roll_sequence := 0
var _user_additions := preload("res://scripts/drop/user_drop_additions_v81.gd").new()
# User spreadsheet authority (v1): the compiled sheet is the sole production
# probability source.  Its E column already contains every historical factor
# (SPB, V5, denominator policy, v80/v81, global 1x, gold x5), so downstream
# probability stages are retired for compiled monsters. Historical probability
# replay lives under tests/helpers; the retained v81 addition object owns only
# the Fate Blade item identity and reward path here.
var _sheet_authority := preload("res://scripts/drop/user_loot_sheet_provider.gd").new()
var _overflow_telemetry_by_monster_id: Dictionary = {}
var _lean_profile_by_monster_id: Dictionary = {}
var _lean_probability_by_key: Dictionary = {}
var _lean_reward_by_slot_uid: Dictionary = {}
var _lean_cache_misses := {"profile": 0, "probability": 0, "reward": 0}

## Resumable death-roll job.  This is an opt-in orchestration API; the legacy
## roll_monster_drops contract below remains unchanged.  The job owns one
## RandomNumberGenerator and advances one source slot per call, so callers must
## keep a death at the head of their queue until done to preserve RNG order.
func begin_monster_drop_roll_job(monster_id: int, rng: RandomNumberGenerator, include_audit := false) -> Dictionary:
	include_audit = include_audit or _v5_trace_enabled
	return {
		"phase": "resolve",
		"monster_id": monster_id,
		"rng": rng,
		"include_audit": include_audit,
		"slot_index": 0,
		"resolved_slots": [],
		"successful_rewards": [],
		"diagnostics": {"selection_work_units": 0, "selection_candidate_count": 0},
		"result": _new_drop_roll_result(monster_id),
		"done": false,
	}

func _new_drop_roll_result(monster_id: int) -> Dictionary:
	return {
		"contract_id": DROP_CONTRACT_ID,
		"runtime_authority": {"authority_id": _sheet_authority.authority_id, "schema": "hardcore.dpv2.user_loot_sheet_authority.v1", "effective_probability_authority_id": "dpv2.user_loot_sheet.v1", "effective_probability_schema": "hardcore.dpv2.user_loot_sheet_authority.v1", "identity_key": "canonical_monster_id", "fallback_forbidden": true, "probability_formula": "sheet E column as final pre-RNG per-slot probability; sheet D column as final gold amount; no legacy stages"},
		"monster_id": monster_id,
		"canonical_monster_id": -1,
		"configured": false,
		"reason": "",
		"source_slot_gate": GameData.dpv2_source_slot_gate(),
		"source_entry_count": 0,
		"resolution_attempted_count": 0,
		"resolved_entry_count": 0,
		"resolved_gold_count": 0,
		"drop_enabled_source_slots": 0,
		"drop_disabled_source_slots": 0,
		"reward_resolved_enabled_slots": 0,
		"probability_resolved_enabled_slots": 0,
		"rng_eligible_slots": 0,
		"all_resolved_slots_rng": false,
		"all_enabled_resolved_slots_rng_before_overflow": false,
		"ground_output_plus_discarded_equals_successful": true,
		"items": [], "item_records": [], "gold_drops": [], "overflow_discarded": [],
		"attempts": [], "slot_attempts": [], "debug": [], "rejected_entries": [],
		"rng_roll_count": 0, "successful_roll_count": 0, "ground_output_count": 0,
		"overflow_discarded_count": 0, "protected_overflow_count": 0,
	}

func advance_monster_drop_roll_job(job: Dictionary, max_slots := 1) -> Dictionary:
	if bool(job.get("done", false)):
		return job
	var result: Dictionary = job.get("result", {})
	if bool(job.get("initialized", false)):
		return _advance_monster_drop_roll_job_phase(job, max_slots)
	var rng: RandomNumberGenerator = job.get("rng")
	var monster_id := int(job.get("monster_id", -1))
	if not _sheet_authority.valid:
		result["reason"] = "user_loot_sheet_authority_unavailable"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	if not GameData.is_dpv2_direct_baseline_loaded():
		result["reason"] = "dpv2_direct_baseline_unavailable"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	var resolved_id := GameData.canonical_monster_id(monster_id)
	if resolved_id <= 0:
		result["reason"] = "invalid_monster_id"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	result["canonical_monster_id"] = resolved_id
	var include_audit := bool(job.get("include_audit", false))
	var profile := _production_profile(resolved_id) if include_audit else _lean_profile(resolved_id)
	if profile.is_empty():
		result["reason"] = "dpv2_direct_profile_unresolved"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	result["direct_profile"] = {"canonical_monster_id": resolved_id, "drop_profile_id": str(profile.get("drop_profile_id", "")), "baseline_origin": str(profile.get("baseline_origin", ""))}
	var slots_value: Variant = profile.get("slots", [])
	if not slots_value is Array:
		result["reason"] = "dpv2_direct_slots_invalid"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	var slots: Array = slots_value
	result["configured"] = true
	result["source_entry_count"] = slots.size()
	result["ground_slot_group"] = {"classification": GameData.canonical_monster_classification(resolved_id), "ground_slot_limit": GameData.dpv2_ground_slot_limit_for_monster(resolved_id), "policy_authority": "monster.ground_slot_groups.runtime.v1"}
	job["initialized"] = true
	job["slots"] = slots
	job["resolved_id"] = resolved_id
	if not bool(profile.get("drop_enabled", false)):
		result["reason"] = "drop_disabled"; result["drop_disabled_source_slots"] = 0; result["all_resolved_slots_rng"] = true; result["all_enabled_resolved_slots_rng_before_overflow"] = true; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	result["drop_enabled_source_slots"] = slots.size()
	if slots.is_empty():
		result["all_resolved_slots_rng"] = true
		result["all_enabled_resolved_slots_rng_before_overflow"] = true
		job["done"] = true
		job["result"] = result
		return _finish_drop_roll_job(job)
	if rng == null:
		result["reason"] = "rng_missing"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
	return _advance_monster_drop_roll_job_phase(job, max_slots)

func _advance_monster_drop_roll_job_phase(job: Dictionary, max_slots := 1) -> Dictionary:
	var result: Dictionary = job.get("result", {})
	var rng: RandomNumberGenerator = job.get("rng")
	var resolved_id := int(job.get("resolved_id", -1))
	var slots: Array = job.get("slots", [])
	var include_audit := bool(job.get("include_audit", false))
	var cursor := int(job.get("slot_index", 0))
	var work := maxi(1, max_slots)
	if str(job.get("phase", "resolve")) == "resolve":
		while cursor < slots.size() and work > 0:
			var raw_slot: Variant = slots[cursor]
			result["resolution_attempted_count"] = int(result.get("resolution_attempted_count", 0)) + 1
			if not raw_slot is Dictionary:
				_append_rejection(result, {}, "dpv2_direct_slot_invalid"); cursor += 1; work -= 1; continue
			var slot: Dictionary = raw_slot
			var probability := _production_probability(resolved_id, str(slot.get("slot_uid", ""))) if include_audit else _lean_probability(resolved_id, str(slot.get("slot_uid", "")))
			if not bool(probability.get("ok", false)):
				_append_rejection(result, slot, str(probability.get("reason", "dpv2_direct_probability_invalid"))); cursor += 1; work -= 1; continue
			result["probability_resolved_enabled_slots"] = int(result.get("probability_resolved_enabled_slots", 0)) + 1
			var reward := _production_reward(slot) if include_audit else _lean_reward(slot)
			if not bool(reward.get("ok", false)):
				_append_rejection(result, slot, str(reward.get("reason", "dpv2_direct_reward_unresolved"))); result["probability_resolved_enabled_slots"] = int(result.get("probability_resolved_enabled_slots", 0)) - 1; cursor += 1; work -= 1; continue
			result["reward_resolved_enabled_slots"] = int(result.get("reward_resolved_enabled_slots", 0)) + 1
			var denominator := int(probability.get("final_denominator", 0))
			var numerator := int(probability.get("final_numerator", 0))
			if numerator <= 0 or denominator <= 0:
				_append_rejection(result, slot, "spb_effective_probability_invalid"); result["reward_resolved_enabled_slots"] = int(result.get("reward_resolved_enabled_slots", 0)) - 1; result["probability_resolved_enabled_slots"] = int(result.get("probability_resolved_enabled_slots", 0)) - 1; cursor += 1; work -= 1; continue
			if str(reward.get("kind", "")) == "gold":
				var final_gold_amount := int(probability.get("final_gold_amount", 0))
				if final_gold_amount <= 0:
					_append_rejection(result, slot, "spb_effective_gold_amount_invalid"); result["reward_resolved_enabled_slots"] = int(result.get("reward_resolved_enabled_slots", 0)) - 1; result["probability_resolved_enabled_slots"] = int(result.get("probability_resolved_enabled_slots", 0)) - 1; cursor += 1; work -= 1; continue
				reward = reward.duplicate(true); reward["gold_amount"] = final_gold_amount
			result["resolved_entry_count"] = int(result.get("resolved_entry_count", 0)) + 1; result["rng_eligible_slots"] = int(result.get("rng_eligible_slots", 0)) + 1
			job["resolved_slots"].append({"slot": slot, "probability": probability, "reward": reward})
			cursor += 1; work -= 1
		job["slot_index"] = cursor
		if cursor < slots.size():
			job["result"] = result; return job
		if not result["rejected_entries"].is_empty():
			result["reason"] = "spb_effective_probability_fail_closed"; job["done"] = true; job["result"] = result; return _finish_drop_roll_job(job)
		job["phase"] = "roll"; job["slot_index"] = 0; cursor = 0
		if work <= 0:
			job["result"] = result; return job
	var resolved_values: Array = job.get("resolved_slots", [])
	while str(job.get("phase", "roll")) == "roll" and cursor < resolved_values.size() and work > 0:
		var resolved: Dictionary = resolved_values[cursor]
		var slot: Dictionary = resolved.get("slot", {}); var probability: Dictionary = resolved.get("probability", {}); var reward: Dictionary = resolved.get("reward", {})
		var denominator := int(probability.get("final_denominator", 0))
		var numerator := int(probability.get("final_numerator", 0))
		result["rng_roll_count"] = int(result.get("rng_roll_count", 0)) + 1
		var draw := rng.randi_range(1, denominator)
		var success := draw <= numerator
		var attempt: Dictionary = {}
		if include_audit:
			attempt = _build_attempt(slot, probability, reward, draw, success); _record_attempt(result, attempt)
		if success:
			var candidate := {"slot_uid": str(slot.get("slot_uid", "")), "canonical_item_id": int(probability.get("canonical_item_id", -1)), "reward": reward.duplicate(true), "policy": probability.duplicate(true)}
			if include_audit: candidate["attempt"] = attempt
			job["successful_rewards"].append(candidate)
		cursor += 1; work -= 1
	if str(job.get("phase", "roll")) != "output":
		job["slot_index"] = cursor
		if cursor < resolved_values.size():
			job["result"] = result; return job
		job["phase"] = "output"
	result["all_resolved_slots_rng"] = result["rng_roll_count"] == result["resolved_entry_count"]
	result["all_enabled_resolved_slots_rng_before_overflow"] = result["all_resolved_slots_rng"] and result["resolved_entry_count"] == slots.size()
	if not job.has("selection_job"):
		job["selection_job"] = _begin_resumable_selection(job["successful_rewards"], int(result["ground_slot_group"].get("ground_slot_limit", 0)))
		job["diagnostics"]["selection_candidate_count"] = job["successful_rewards"].size()
	var selection_job: Dictionary = job["selection_job"]
	selection_job = _advance_resumable_selection(selection_job, rng, work)
	job["selection_job"] = selection_job
	job["diagnostics"]["selection_work_units"] = int(job["diagnostics"].get("selection_work_units", 0)) + work - int(selection_job.get("work_left", 0))
	work = int(selection_job.get("work_left", 0))
	if not bool(selection_job.get("done", false)):
		job["result"] = result; return job
	if work <= 0:
		job["result"] = result; return job
	var selected_values: Array = selection_job.get("result", {}).get("selected", [])
	var output_index := int(job.get("output_index", 0))
	if output_index < selected_values.size():
		var selected: Dictionary = selected_values[output_index]
		var selected_reward: Dictionary = selected.get("reward", {})
		if str(selected_reward.get("kind", "")) == "gold":
			result["resolved_gold_count"] = int(result.get("resolved_gold_count", 0)) + 1
			result["gold_drops"].append(int(selected_reward.get("gold_amount", 0)))
		else:
			var selected_item_id := int(selected.get("canonical_item_id", -1))
			var selected_item_name := str(selected_reward.get("item_name", ""))
			var record := _drop_output_item_record(selected_item_id, selected_item_name, rng)
			var display_name := str(record.get("item_name", _drop_output_item_name(selected_item_id, selected_item_name)))
			result["items"].append(display_name)
			result["item_records"].append(record)
		job["output_index"] = output_index + 1
		work -= 1
		job["result"] = result
		if work <= 0:
			return job
		if job["output_index"] < selected_values.size(): return job
	var selection_result: Dictionary = selection_job.get("result", {})
	result["successful_roll_count"] = job["successful_rewards"].size(); result["overflow_discarded"] = selection_result.get("discarded", []); result["overflow_discarded_count"] = result["overflow_discarded"].size(); result["protected_overflow_count"] = int(selection_result.get("protected_discarded_count", 0)); result["ground_output_count"] = result["items"].size() + result["gold_drops"].size(); result["ground_output_plus_discarded_equals_successful"] = result["ground_output_count"] + result["overflow_discarded_count"] == result["successful_roll_count"]; job["done"] = true; job["result"] = result
	return _finish_drop_roll_job(job)

func _finish_drop_roll_job(job: Dictionary) -> Dictionary:
	if not bool(job.get("audit_finalized", false)):
		var result: Dictionary = job.get("result", {})
		if bool(job.get("include_audit", false)):
			_sync_attempt_views(result)
		if _v5_trace_enabled:
			_v5_write_trace(result)
		job["audit_finalized"] = true
	return job


func _production_profile(monster_id: int) -> Dictionary:
	# Compiled sheet profile.  Monsters absent from the sheet (retired baseline
	# rows with zero live spawns) resolve to an empty profile, which is a valid
	# zero-drop answer and never falls back to legacy probability authorities.
	return _sheet_authority.profile(monster_id)


func _production_probability(monster_id: int, slot_uid: String) -> Dictionary:
	# The sheet value IS the final pre-RNG probability.  No SPB, no V5, no
	# monster-class denominator policy, no v80/v81, no global multiplier.
	return _sheet_authority.probability(monster_id, slot_uid)


func _lean_profile(monster_id: int) -> Dictionary:
	if not _lean_profile_by_monster_id.has(monster_id):
		_lean_cache_misses["profile"] = int(_lean_cache_misses.get("profile", 0)) + 1
		_lean_profile_by_monster_id[monster_id] = _production_profile(monster_id)
	return _lean_profile_by_monster_id.get(monster_id, {})


func _lean_probability(monster_id: int, slot_uid: String) -> Dictionary:
	var authority_digest := _sheet_authority.digest
	var cache_key := "%d|%s|%s" % [
		monster_id,
		slot_uid,
		authority_digest,
	]
	if not _lean_probability_by_key.has(cache_key):
		_lean_cache_misses["probability"] = int(_lean_cache_misses.get("probability", 0)) + 1
		_lean_probability_by_key[cache_key] = _production_probability(
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
		_lean_reward_by_slot_uid[slot_uid] = _production_reward(slot)
	return _lean_reward_by_slot_uid.get(slot_uid, {})

func _production_reward(slot: Dictionary) -> Dictionary:
	var item_id := int(slot.get("canonical_item_id", -1))
	if BossMaterialDropResolverScript.owns(item_id):
		return BossMaterialDropResolverScript.reward(item_id)
	if _user_additions.owns(76, str(slot.get("slot_uid", ""))):
		return _user_additions.reward(slot)
	return GameData.dpv2_direct_resolve_slot_reward(slot)


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
			var item_name := ""
			if bool(reward.get("ok", false)) and str(reward.get("kind", "")) != "gold":
				# Icon prewarming needs only the exact output-name mapping; do not
				# allocate full catalog records for every potential drop slot.
				item_name = _drop_output_item_name(
					int(raw_slot.get("canonical_item_id", -1)),
					str(reward.get("item_name", "")),
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
	var job := begin_monster_drop_roll_job(monster_id, rng, include_audit)
	while not bool(job.get("done", false)):
		job = advance_monster_drop_roll_job(job, 2147483647)
	var result: Dictionary = job.get("result", {})
	return result


func _drop_output_item_name(canonical_item_id: int, original_name: String) -> String:
	return str(FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID.get(
		canonical_item_id,
		original_name,
	))


func _drop_output_item_record(
	canonical_item_id: int,
	original_name: String,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	if BossMaterialDropResolverScript.owns(canonical_item_id):
		var material_record := BossMaterialDropResolverScript.output_record(
			canonical_item_id, original_name, rng
		)
		return material_record if not material_record.is_empty() else _unresolved_drop_item_record(
			canonical_item_id, original_name, original_name
		)
	# Resolve one direct-drop identity without name/fuzzy ID guessing. The stable
	# item_id is always the GameData catalog ID of the item actually picked up.
	# The direct-table source ID is retained separately because the explicit
	# female-equipment presentation map changes the display to the male record.
	var attempted_item_id := canonical_item_id
	var direct_identity := _user_additions.item_identity(canonical_item_id) if canonical_item_id == 110 else GameData.dpv2_direct_item_identity(canonical_item_id)
	var canonical_name := str(direct_identity.get("canonical_item_name", ""))
	if direct_identity.is_empty() or canonical_name.is_empty():
		return _unresolved_drop_item_record(
			attempted_item_id,
			original_name,
			_drop_output_item_name(attempted_item_id, original_name),
		)
	var source_record := GameData.get_item_record(canonical_name)
	if source_record.is_empty() or str(source_record.get("name", "")) != canonical_name:
		return _unresolved_drop_item_record(
			attempted_item_id,
			original_name,
			_drop_output_item_name(attempted_item_id, canonical_name),
		)
	# The resolver must accept aliases only through GameData's exact canonical
	# alias table. Any unregistered/fuzzy display token remains unresolved.
	if not original_name.is_empty():
		var original_record := GameData.get_item_record(original_name)
		if original_record.is_empty() or str(original_record.get("name", "")) != canonical_name:
			return _unresolved_drop_item_record(
				attempted_item_id,
				original_name,
				# Keep the old output token on an invalid name/ID pairing. The
				# record remains unresolved, so this is never an identity fallback.
				_drop_output_item_name(attempted_item_id, original_name),
			)
	var output_name := _drop_output_item_name(attempted_item_id, canonical_name)
	var output_record := GameData.get_item_record(output_name)
	if output_record.is_empty() or str(output_record.get("name", "")) != output_name:
		return _unresolved_drop_item_record(
			attempted_item_id,
			original_name,
			output_name,
		)
	var output_item_id := _stable_catalog_item_id(output_record)
	# Reserved DPV2 IDs (the 920xxx skill-book range) intentionally point to
	# legacy service records that expose only serviceIndex in the presentation
	# catalog. Once the exact direct ID/name identity above is validated, the
	# direct canonical ID is the stable item identity for those records.
	if output_item_id < 0 and output_name == canonical_name:
		output_item_id = attempted_item_id
	if output_item_id < 0:
		return _unresolved_drop_item_record(
			attempted_item_id,
			original_name,
			output_name,
		)
	return {
		"item_id": output_item_id,
		"canonical_item_id": output_item_id,
		"canonical_name": output_name,
		"source_item_id": attempted_item_id,
		"source_canonical_item_id": attempted_item_id,
		"source_canonical_name": canonical_name,
		"item_name": output_name,
		"name": output_name,
		"output_item_id": output_item_id,
		"output_record": output_record.duplicate(true),
		"identity_status": "resolved",
	}


func _unresolved_drop_item_record(
	attempted_item_id: int,
	original_name: String,
	output_name: String,
) -> Dictionary:
	return {
		"item_id": -1,
		"canonical_item_id": -1,
		"source_item_id": attempted_item_id,
		"source_canonical_item_id": attempted_item_id,
		"canonical_name": "",
		"source_canonical_name": "",
		"item_name": output_name,
		"name": output_name,
		"original_name": original_name,
		"output_item_id": -1,
		"output_record": {},
		"identity_status": "unresolved",
	}


func _stable_catalog_item_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value: Variant = record.get(key, -1)
		if value is String and not (value as String).is_valid_int():
			continue
		var item_id := int(value)
		if item_id >= 0:
			return item_id
	return -1


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
		"slot_origin": str(probability.get("slot_origin", "")),
		"drop_authority": str(probability.get("drop_authority", "")),
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
		"user_balance_reason": str(probability.get("user_balance_reason", "")),
		"user_balance_source_uid": str(probability.get("user_balance_source_uid", "")),
		"pre_user_balance_numerator": int(probability.get("pre_user_balance_numerator", 0)),
		"pre_user_balance_denominator": int(probability.get("pre_user_balance_denominator", 0)),
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


func _begin_resumable_selection(successful_rewards: Array, maximum_ground_slots: int) -> Dictionary:
	return {
		"protected_groups": {},
		"ordinary_groups": {},
		"priorities": [],
		"pending_candidates": successful_rewards.duplicate(false),
		"build_index": 0,
		"building": true,
		"priority_index": 0,
		"ordinary_start": 0,
		"group": [],
		"group_index": 0,
		"shuffle_index": -1,
		"group_shuffling": false,
		"remaining": maxi(0, maximum_ground_slots),
		"result": {"selected": [], "discarded": [], "protected_discarded_count": 0},
		"done": false,
		"work_left": 0,
	}


func _advance_resumable_selection(selection: Dictionary, rng: RandomNumberGenerator, work: int) -> Dictionary:
	var units := maxi(0, work)
	while units > 0 and bool(selection.get("building", false)):
		var build_index := int(selection.get("build_index", 0))
		var pending: Array = selection.get("pending_candidates", [])
		if build_index < pending.size():
			var raw_candidate: Variant = pending[build_index]
			if raw_candidate is Dictionary:
				var candidate: Dictionary = raw_candidate
				var policy: Dictionary = candidate.get("policy", {})
				var priority_value := int(policy.get("overflow_priority", 0))
				var target_groups: Dictionary = selection["protected_groups"] if bool(policy.get("protected_drop", false)) else selection["ordinary_groups"]
				if not target_groups.has(priority_value):
					target_groups[priority_value] = []
				(target_groups[priority_value] as Array).append(candidate)
			selection["build_index"] = build_index + 1
			units -= 1
			continue
		var built_protected_groups: Dictionary = selection.get("protected_groups", {})
		var built_ordinary_groups: Dictionary = selection.get("ordinary_groups", {})
		var built_priorities: Array = built_protected_groups.keys()
		built_priorities.sort(); built_priorities.reverse()
		var ordinary_priorities: Array = built_ordinary_groups.keys()
		ordinary_priorities.sort(); ordinary_priorities.reverse()
		for ordinary_priority: Variant in ordinary_priorities:
			built_priorities.append(ordinary_priority)
		selection["priorities"] = built_priorities
		selection["ordinary_start"] = built_protected_groups.keys().size()
		selection["building"] = false
		selection["work_left"] = units
	var priorities: Array = selection.get("priorities", [])
	var protected_groups: Dictionary = selection.get("protected_groups", {})
	var ordinary_groups: Dictionary = selection.get("ordinary_groups", {})
	var result: Dictionary = selection.get("result", {})
	while units > 0 and not bool(selection.get("done", false)):
		var group: Array = selection.get("group", [])
		var group_index := int(selection.get("group_index", 0))
		if group.is_empty() or group_index >= group.size():
			var priority_index := int(selection.get("priority_index", 0))
			if priority_index >= priorities.size():
				selection["done"] = true
				break
			var priority: Variant = priorities[priority_index]
			var protected_count := int(selection.get("ordinary_start", 0))
			var groups: Dictionary = protected_groups if priority_index < protected_count else ordinary_groups
			group = (groups.get(int(priority), []) as Array).duplicate(false)
			selection["group"] = group
			selection["group_index"] = 0
			selection["priority_index"] = priority_index + 1
			selection["group_shuffling"] = int(selection.get("remaining", 0)) > 0 and group.size() > int(selection.get("remaining", 0))
			selection["shuffle_index"] = group.size() - 1
			group_index = 0
			if group.is_empty():
				selection["group"] = []
				continue
		if bool(selection.get("group_shuffling", false)) and int(selection.get("shuffle_index", -1)) > 0:
			var shuffle_index := int(selection.get("shuffle_index", -1))
			var swap_index := rng.randi_range(0, shuffle_index)
			var temporary: Variant = group[shuffle_index]
			group[shuffle_index] = group[swap_index]
			group[swap_index] = temporary
			selection["group"] = group
			selection["shuffle_index"] = shuffle_index - 1
			units -= 1
			continue
		if bool(selection.get("group_shuffling", false)):
			selection["group_shuffling"] = false
		var candidate: Dictionary = group[group_index]
		if int(selection.get("remaining", 0)) > 0:
			result.selected.append(candidate)
			_mark_selected(candidate)
			selection["remaining"] = int(selection.get("remaining", 0)) - 1
		else:
			_append_discarded(result, candidate)
		selection["group_index"] = group_index + 1
		units -= 1
	selection["result"] = result
	selection["work_left"] = units
	return selection


func _select_ground_rewards(
	successful_rewards: Array,
	rng: RandomNumberGenerator,
	maximum_ground_slots: int,
) -> Dictionary:
	var selection := _begin_resumable_selection(successful_rewards, maximum_ground_slots)
	while not bool(selection.get("done", false)):
		selection = _advance_resumable_selection(selection, rng, 2147483647)
	return selection.get("result", {})


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

func _v5_write_trace(result: Dictionary) -> void:
	_v5_roll_sequence += 1
	var trace := {
		"event_kind": "drop_roll_not_authoritative_death",
		"roll_sequence": _v5_roll_sequence,
		"ticks_usec": Time.get_ticks_usec(),
		"canonical_monster_id": result.get("canonical_monster_id", -1),
		"drop_profile": result.get("direct_profile", {}),
		"source_bindings": GameData.dpv2_single_player_drop_boost.get("source_bindings", {}),
		"death_event_id": null,
		"map_id": null,
		"spawn_id": null,
		"context_binding": "ACTOR_CONTEXT_NOT_AVAILABLE_IN_EXISTING_SERVICE_API",
		"attempts": result.get("attempts", []),
	}
	var path := "user://dpv2_v5_trace.jsonl"
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(trace))
