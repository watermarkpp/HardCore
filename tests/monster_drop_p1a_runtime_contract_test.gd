extends Node

const EXPECTED_PROFILE_ID := "drop.168"
const EXPECTED_MONSTER_ID := 168
const EXPECTED_LINE_NUMBER := 20
const EXPECTED_SLOT_INDEX := "slot_020"
const EXPECTED_CHANCE := "1/00"
const EXPECTED_RAW_TEXT := "1/00 灵魂战衣(男)"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(
		GameData.ensure_loaded(),
		"GameData failed to load for P1A runtime contract test"
	)
	assert(
		LootRuntime.has_method("_chance_denominator"),
		"LootRuntime._chance_denominator missing"
	)

	# These assertions exercise the real runtime parser rather than a P1A copy.
	assert(
		int(LootRuntime.call("_chance_denominator", "1/3")) == 3
	)
	assert(
		int(LootRuntime.call("_chance_denominator", "1/0")) < 0,
		"1/0 must fail closed"
	)
	assert(
		int(LootRuntime.call("_chance_denominator", "1/00")) < 0,
		"1/00 must fail closed"
	)
	# Current LootRuntime accepts digit-only leading-zero denominators and then
	# converts them numerically. Freeze the behavior we actually scanned.
	assert(
		int(LootRuntime.call("_chance_denominator", "1/010")) == 10,
		"current runtime contract changed for 1/010"
	)

	var profile: Dictionary = (
		GameData.get_canonical_monster_drop_profile(EXPECTED_MONSTER_ID)
	)
	assert(not profile.is_empty(), "drop.168 profile missing")
	assert(
		str(profile.get("drop_profile_id", "")) == EXPECTED_PROFILE_ID
	)

	var entries_value: Variant = profile.get("entries", [])
	assert(entries_value is Array, "drop.168 entries must be Array")
	var entries: Array = entries_value

	var anomaly: Dictionary = {}
	var valid_audit_only_entry: Dictionary = {}
	var metadata_unresolved_but_runtime_resolved: Dictionary = {}

	for row_value: Variant in entries:
		assert(row_value is Dictionary)
		var row: Dictionary = row_value
		if (
			int(row.get("line_number", -1)) == EXPECTED_LINE_NUMBER
			and str(row.get("chance", "")) == EXPECTED_CHANCE
		):
			anomaly = row

		var denominator := int(
			LootRuntime.call(
				"_chance_denominator",
				str(row.get("chance", ""))
			)
		)
		var reward := GameData.resolve_canonical_drop_reward(row)
		if (
			valid_audit_only_entry.is_empty()
			and str(row.get("rate_policy", "")) == "AUDIT_ONLY"
			and denominator > 0
			and bool(reward.get("ok", false))
		):
			valid_audit_only_entry = row
		if (
			metadata_unresolved_but_runtime_resolved.is_empty()
			and str(row.get("item_resolution_status", ""))
				== "unresolved_token"
			and denominator > 0
			and bool(reward.get("ok", false))
		):
			metadata_unresolved_but_runtime_resolved = row

	assert(not anomaly.is_empty(), "unique 1/00 anomaly not found")
	assert(
		str(anomaly.get("slot_index", "")) == EXPECTED_SLOT_INDEX
	)
	assert(
		str(anomaly.get("raw_text", "")) == EXPECTED_RAW_TEXT
	)
	assert(
		str(anomaly.get("rate_policy", "")) == "AUDIT_ONLY"
	)
	assert(
		str(anomaly.get("slot_status", ""))
			== "CONFIRMED_SOURCE_SLOT"
	)
	assert(
		int(LootRuntime.call(
			"_chance_denominator",
			str(anomaly.get("chance", ""))
		)) < 0
	)

	# Prove provenance is independent of the real parser and reward resolver.
	assert(
		not valid_audit_only_entry.is_empty(),
		"no valid AUDIT_ONLY runtime-resolvable row found in drop.168"
	)
	var synthetic := valid_audit_only_entry.duplicate(true)
	synthetic["rate_policy"] = "SYNTHETIC_PROVENANCE_ONLY"
	var original_denominator := int(
		LootRuntime.call(
			"_chance_denominator",
			str(valid_audit_only_entry.get("chance", ""))
		)
	)
	var synthetic_denominator := int(
		LootRuntime.call(
			"_chance_denominator",
			str(synthetic.get("chance", ""))
		)
	)
	assert(original_denominator == synthetic_denominator)
	var original_reward := (
		GameData.resolve_canonical_drop_reward(
			valid_audit_only_entry
		)
	)
	var synthetic_reward := (
		GameData.resolve_canonical_drop_reward(synthetic)
	)
	assert(
		bool(original_reward.get("ok", false))
		== bool(synthetic_reward.get("ok", false))
	)

	# This is the exact semantic split that P1A-R1 previously got wrong:
	# source metadata may say unresolved_token while the actual runtime resolver
	# succeeds through canonical item authority.
	assert(
		not metadata_unresolved_but_runtime_resolved.is_empty(),
		"expected at least one unresolved_token metadata row "
		+ "that resolves at runtime"
	)

	var closure: Dictionary = (
		GameData.canonical_monster_runtime_drop_closure(
			EXPECTED_MONSTER_ID
		)
	)
	assert(
		bool(closure.get("allowed", false)),
		"monster 168 must currently pass the monster-level runtime gate: %s"
		% closure
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 16820260825
	var rolled: Dictionary = (
		LootRuntime.roll_monster_drops(
			EXPECTED_MONSTER_ID,
			rng
		)
	)
	assert(
		bool(rolled.get("configured", false)),
		"LootRuntime did not enter drop.168 profile: %s" % rolled
	)

	var found_obsolete_runtime_rejection := false
	var rejected_value: Variant = rolled.get("rejected_entries", [])
	assert(rejected_value is Array)
	for rejection_value: Variant in rejected_value:
		if not rejection_value is Dictionary:
			continue
		var rejection: Dictionary = rejection_value
		if (
			int(rejection.get("line_number", -1))
				== EXPECTED_LINE_NUMBER
			and str(rejection.get("reason", ""))
				== "chance_token_invalid"
		):
			found_obsolete_runtime_rejection = true
			break
	assert(
		not found_obsolete_runtime_rejection,
		"source chance provenance must not reject a DPV2 runtime slot: %s"
		% rolled
	)
	assert(
		int(rolled.get("rng_roll_count", -1))
		== int(rolled.get("resolved_entry_count", -2)),
		"every DPV2-resolved row must reach RNG: %s" % rolled
	)
	assert(
		bool(rolled.get("all_resolved_slots_rng", false)),
		"full-slot RNG contract was not reported: %s" % rolled
	)

	print(
		"MONSTER_DROP_P1A_RUNTIME_CONTRACT_PASS: "
		+ "1/00 retained as provenance and does not gate RNG; "
		+ "AUDIT_ONLY proven provenance-only; "
		+ "all resolved slots reached DPV2 RNG"
	)
	get_tree().quit(0)
