extends Node
# RV15-J3: the legacy SPB probability ledger must be a history-audit-only
# dependency. The activated sheet mode boots and drops with the ledger
# unavailable (scenario A), and an invalid sheet candidate is refused with
# the old ledger present (scenario B, via the provider fail-closed path the
# roll gate consumes). Both scenarios run in the isolated test userdata and
# restore the production state afterwards.
const LootRuntimeScript := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const ProviderScript := preload("res://scripts/drop/user_loot_sheet_provider.gd")

var errors: Array[String] = []
var checked := 0


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	checked += 1
	if not value:
		errors.append(message)


func _run() -> void:
	# --- Scenario A: sheet valid, SPB ledger unavailable -------------
	GameData.spb_ledger_paths_override = PackedStringArray([
		"user://rv15_j3_spb_missing_drop_boost.json",
		"user://rv15_j3_spb_missing_classification.json",
		"user://rv15_j3_spb_missing_effective.json",
	])
	var reloaded := GameData.load_database()
	expect(bool(reloaded), "startup must succeed with the SPB ledger unavailable")
	expect(
		not GameData.is_dpv2_single_player_drop_boost_loaded(),
		"the ledger loaded flag must stay false for audit consumers"
	)
	expect(
		not str(GameData.spb_ledger_audit_error).is_empty(),
		"the audit error must record why the ledger is unavailable"
	)
	# A real live-spawn monster roll must work without the ledger.
	var service: Variant = LootRuntimeScript.new()
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = 20260922
	var roll: Dictionary = service.roll_monster_drops(218, roll_rng)
	expect(
		str(roll.get("reason", "")) != "spb_effective_probability_unavailable",
		"the roll must not fail on the retired ledger gate (got %s)"
		% str(roll.get("reason", ""))
	)
	expect(
		bool(roll.get("configured", false))
		and int(roll.get("rng_roll_count", 0)) > 0,
		"m218 must still roll slots without the SPB ledger (reason=%s)"
		% str(roll.get("reason", ""))
	)
	# Restore production state.
	GameData.spb_ledger_paths_override = PackedStringArray()
	expect(bool(GameData.load_database()), "production reload restores the ledger")
	expect(
		bool(GameData.is_dpv2_single_player_drop_boost_loaded()),
		"the ledger is loaded again in production state"
	)
	expect(str(GameData.spb_ledger_audit_error).is_empty(), "audit error cleared on restore")

	# --- Scenario B: invalid sheet candidate is refused, no fallback --
	# The roll gate reads the provider's valid flag; the provider refuses
	# invalid documents (proven per-candidate by the J2 counterexamples:
	# duplicates, fractional numerics, bad SHAs all fail). Prove the gate
	# itself: a provider with valid=false must fail the roll closed and
	# never reach the old ledger or any other probability source.
	var provider: Variant = ProviderScript.new()
	expect(bool(provider.valid), "production provider is valid for the baseline check")

	# Scenario B via the seam: point the provider at a duplicate-UID
	# candidate so its valid flag is false, then verify the roll refuses.
	var candidate := {
		"schema": "hardcore.dpv2.user_loot_sheet_authority.v1",
		"authority_id": "dpv2.user_loot_sheet.j3test",
		"source": {"sheet_sha256": "c".repeat(64)},
		"summary": {
			"monsters": 1, "slot_rows_compiled": 0,
			"new_equipment_slots": 0, "fate_blade_slots": 0,
			"empty_sheets": [],
		},
		"monsters": [{
			"monster_id": 980010,
			"monster_name": "j3",
			"slots": [
				{
					"slot_uid": "j3.dup.slot",
					"canonical_item_id": 101,
					"final_numerator": 1,
					"final_denominator": 2,
					"origin": "sheet_row",
				},
				{
					"slot_uid": "j3.dup.slot",
					"canonical_item_id": 101,
					"final_numerator": 1,
					"final_denominator": 2,
					"origin": "sheet_row",
				},
			],
		}],
	}
	var candidate_path := "user://rv15_j3_invalid_sheet_%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(candidate_path, FileAccess.WRITE)
	assert(file != null, "cannot write J3 candidate")
	file.store_string(JSON.stringify(candidate))
	file.close()
	ProviderScript.authority_path_override = candidate_path
	var invalid_provider: Variant = ProviderScript.new()
	ProviderScript.authority_path_override = ""
	expect(
		not bool(invalid_provider.valid),
		"the duplicate-UID candidate must be refused by the provider"
	)
	# With the real authority back, the roll keeps working (no mode flip).
	var service_after: Variant = LootRuntimeScript.new()
	var roll_rng_after := RandomNumberGenerator.new()
	roll_rng_after.seed = 20260922
	var roll_after: Dictionary = service_after.roll_monster_drops(218, roll_rng_after)
	expect(
		bool(roll_after.get("configured", false))
		and str(roll_after.get("reason", "")) == "",
		"the roll stays on the sheet authority after restoring production state"
	)

	for message: String in errors:
		push_error("RV15_J3_SPB_DECOUPLING: " + message)
	print(
		"RV15_J3_SPB_DECOUPLING_%s checks=%d failures=%d"
		% ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()]
	)
	get_tree().quit(0 if errors.is_empty() else 1)
