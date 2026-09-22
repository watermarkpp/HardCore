extends Node
# RV15-J2 validation counterexamples for the compiled user loot sheet
# authority. Every case writes an isolated candidate document into the
# official sandbox user:// space, points the provider's narrow path seam at
# it, and asserts the load is refused BEFORE any RNG or drop node could
# exist. The seam is reset after every case so production always reads the
# real authority.
const ProviderScript := preload("res://scripts/drop/user_loot_sheet_provider.gd")

var errors: Array[String] = []
var checked := 0
var _last_candidate_path := ""


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	checked += 1
	if not value:
		errors.append(message)


func write_candidate(name: String, document: Dictionary) -> String:
	var path := "user://rv15_j2_%s_%d.json" % [name, Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write candidate %s" % name)
	file.store_string(JSON.stringify(document))
	file.close()
	_last_candidate_path = path
	return path


func load_with_error(path: String) -> Dictionary:
	ProviderScript.authority_path_override = path
	var provider: Variant = ProviderScript.new()
	ProviderScript.authority_path_override = ""
	return {
		"valid": bool(provider.valid),
		"error": str(provider.load_error),
		"slot_count": int(provider.slot_count),
	}


func base_monster(monster_id: int, slots: Array) -> Dictionary:
	return {
		"monster_id": monster_id,
		"monster_name": "j2-%d" % monster_id,
		"slots": slots,
	}


func base_slot(uid: String, item_id: int) -> Dictionary:
	return {
		"slot_uid": uid,
		"canonical_item_id": item_id,
		"final_numerator": 1,
		"final_denominator": 60,
		"origin": "sheet_row",
	}


func gold_slot(uid: String, amount: int) -> Dictionary:
	return {
		"slot_uid": uid,
		"gold_amount": amount,
		"final_numerator": 1,
		"final_denominator": 4,
		"origin": "sheet_row",
	}


func base_document(monsters: Array, slot_rows_compiled: int = 0) -> Dictionary:
	return {
		"schema": "hardcore.dpv2.user_loot_sheet_authority.v1",
		"authority_id": "dpv2.user_loot_sheet.j2test",
		"source": {
			"sheet_sha256": "a".repeat(64),
		},
		"summary": {
			"monsters": monsters.size(),
			"slot_rows_compiled": slot_rows_compiled,
			"new_equipment_slots": 0,
			"fate_blade_slots": 0,
			"user_directive_overlay_slots": 0,
			"empty_sheets": [],
		},
		"monsters": monsters,
	}


func refuse(name: String, document: Dictionary, expected_fragment: String) -> void:
	var result := load_with_error(write_candidate(name, document))
	expect(not bool(result.valid), "%s must be refused" % name)
	expect(
		result.error.find(expected_fragment) != -1,
		"%s error must mention %s (got %s)" % [name, expected_fragment, result.error]
	)


func _run() -> void:
	# 0. The real production authority still validates (baseline sanity).
	var real: Variant = ProviderScript.new()
	expect(
		bool(real.valid), "real authority must stay valid"
	)
	expect(int(real.slot_count) == 6120, "real authority keeps 6120 slots after the overlay")
	expect(int(real.overlay_slot_count) == 144, "real authority keeps 144 overlay slots")
	real = null

	# 1. Same-monster duplicate UID: refused, not merged, not re-indexed.
	refuse(
		"same_monster_duplicate",
		base_document([
			base_monster(980001, [
				base_slot("dup.slot", 101),
				{
					"slot_uid": "dup.slot",
					"canonical_item_id": 101,
					"final_numerator": 1,
					"final_denominator": 2,
					"origin": "sheet_row",
				},
			])
		]),
		"slot_uid_duplicate"
	)

	# 2. Cross-monster duplicate UID: refused.
	refuse(
		"cross_monster_duplicate",
		base_document([
			base_monster(980001, [base_slot("xdup.slot", 101)]),
			base_monster(980002, [base_slot("xdup.slot", 101)]),
		]),
		"slot_uid_duplicate"
	)

	# 3. Fractional numerator (1.9) is rejected, never truncated to 1.
	refuse(
		"fractional_numerator",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "frac.slot",
					"canonical_item_id": 101,
					"final_numerator": 1.9,
					"final_denominator": 60,
					"origin": "sheet_row",
				},
			])
		]),
		"probability_invalid"
	)

	# 4. Bool and string numerics are rejected.
	refuse(
		"bool_numerator",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "bool.slot",
					"canonical_item_id": 101,
					"final_numerator": true,
					"final_denominator": 60,
					"origin": "sheet_row",
				},
			])
		]),
		"probability_invalid"
	)
	refuse(
		"string_denominator",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "str.slot",
					"canonical_item_id": 101,
					"final_numerator": 1,
					"final_denominator": "60",
					"origin": "sheet_row",
				},
			])
		]),
		"probability_invalid"
	)

	# 5. Denominator above the project RNG rational bound is refused.
	refuse(
		"denominator_overflow",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "big.slot",
					"canonical_item_id": 101,
					"final_numerator": 1,
					"final_denominator": 2147483648,
					"origin": "sheet_row",
				},
			])
		]),
		"probability_invalid"
	)

	# 6. Probability greater than 1 is refused.
	refuse(
		"probability_above_one",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "over.slot",
					"canonical_item_id": 101,
					"final_numerator": 2,
					"final_denominator": 1,
					"origin": "sheet_row",
				},
			])
		]),
		"probability_invalid"
	)

	# 7. Item and gold identities are mutually exclusive.
	refuse(
		"dual_identity",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "dual.slot",
					"canonical_item_id": 101,
					"gold_amount": 5000,
					"final_numerator": 1,
					"final_denominator": 4,
					"origin": "sheet_row",
				},
			])
		]),
		"identity_invalid"
	)

	# 8. Missing identity on a probability slot is refused.
	refuse(
		"missing_identity",
		base_document([
			base_monster(980001, [
				{
					"slot_uid": "noid.slot",
					"final_numerator": 1,
					"final_denominator": 4,
					"origin": "sheet_row",
				},
			])
		]),
		"identity_invalid"
	)

	# 9. A malformed source SHA is refused.
	refuse(
		"bad_source_sha",
		{
			"schema": "hardcore.dpv2.user_loot_sheet_authority.v1",
			"authority_id": "dpv2.user_loot_sheet.j2test",
			"source": {"sheet_sha256": "not-a-sha"},
			"summary": {
				"monsters": 1, "slot_rows_compiled": 0,
				"new_equipment_slots": 0, "fate_blade_slots": 0,
				"empty_sheets": [],
			},
			"monsters": [base_monster(980001, [base_slot("sha.slot", 101)])],
		},
		"sheet_sha_missing"
	)

	# 10. A summary that disagrees with the per-slot tally is refused.
	refuse(
		"summary_mismatch",
		{
			"schema": "hardcore.dpv2.user_loot_sheet_authority.v1",
			"authority_id": "dpv2.user_loot_sheet.j2test",
			"source": {"sheet_sha256": "b".repeat(64)},
			"summary": {
				"monsters": 5,
				"slot_rows_compiled": 0,
				"new_equipment_slots": 0,
				"fate_blade_slots": 0,
				"empty_sheets": [],
			},
			"monsters": [base_monster(980001, [base_slot("tally.slot", 101)])],
		},
		"summary_monster_mismatch"
	)

	# 11. The legal complete document still loads and the queried
	# probabilities and gold are exactly the compiled values.
	var ok_document := base_document([
		base_monster(980003, [
			base_slot("ok.item.slot", 105),
			gold_slot("ok.gold.slot", 150),
		])
	], 2)
	var ok_result := load_with_error(write_candidate("legal_complete", ok_document))
	expect(bool(ok_result.valid), "legal complete document must load: " + ok_result.error)
	# The candidate file is deterministic, so a second provider built under
	# the seam reads back the exact same document for the value probes.
	ProviderScript.authority_path_override = _last_candidate_path
	var ok_provider: Variant = ProviderScript.new()
	ProviderScript.authority_path_override = ""
	expect(int(ok_provider.slot_count) == 2, "legal document slot tally")
	var item_result: Dictionary = ok_provider.probability(980003, "ok.item.slot")
	expect(
		int(item_result.get("final_numerator", 0)) == 1
		and int(item_result.get("final_denominator", 0)) == 60
		and int(item_result.get("canonical_item_id", 0)) == 105,
		"legal item slot reads its exact values"
	)
	var gold_result: Dictionary = ok_provider.probability(980003, "ok.gold.slot")
	expect(
		int(gold_result.get("final_gold_amount", 0)) == 150
		and int(gold_result.get("final_denominator", 0)) == 4,
		"legal gold slot reads its exact values"
	)

	for message: String in errors:
		push_error("RV15_J2_PROVIDER_VALIDATION: " + message)
	print(
		"RV15_J2_PROVIDER_VALIDATION_%s checks=%d failures=%d"
		% ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()]
	)
	get_tree().quit(0 if errors.is_empty() else 1)
