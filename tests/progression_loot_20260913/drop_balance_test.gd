extends Node

const Service := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const LegacyProbability := preload("res://tests/helpers/legacy_drop_probability_policy.gd")
const COMPILED_PATH := "res://assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"


func _ready() -> void:
	assert(GameData.ensure_loaded())
	var legacy := LegacyProbability.new()
	assert(legacy.valid, "sealed v80 ledger and exact historical catalog must validate")
	_test_sealed_v80_rows_and_copies(legacy)
	var service := Service.new()
	_test_current_compiled_rolls(service)
	service.free()
	print("DROP_BALANCE_V80_PASS: archive=782 exact rows/17 copies; production=compiled probabilities/RNG/output parity")
	get_tree().quit(0)


func _test_sealed_v80_rows_and_copies(legacy: RefCounted) -> void:
	var count := 0
	for uid: String in legacy.records:
		var row: Dictionary = legacy.records[uid]
		var actual: Dictionary = legacy.probability_v80(int(row.monster_id), uid)
		assert(actual.ok, "%s %s" % [uid, actual])
		assert(actual.final_numerator == int(row.after[0]) and actual.final_denominator == int(row.after[1]), uid)
		count += 1
	assert(count == 782)
	var direct: Dictionary = GameData.dpv2_direct_profile(159)
	var extended: Dictionary = legacy.profile_v80(159)
	assert(legacy.copied_slots.size() == 17)
	assert(extended.slots.size() == direct.slots.size() + 17)
	assert(extended.slots.slice(0, direct.slots.size()) == direct.slots)
	var source_by_uid := {}
	for source: Dictionary in GameData.dpv2_direct_profile(158).slots:
		source_by_uid[str(source.slot_uid)] = source
	for copied: Dictionary in legacy.copied_slots:
		var source_uid := str(copied.user_balance_source_uid)
		assert(source_by_uid.has(source_uid), source_uid)
		var expected: Dictionary = source_by_uid[source_uid].duplicate(true)
		expected.slot_uid = "dpv2.user.v80.m159.from." + source_uid
		expected.user_balance_source_uid = source_uid
		assert(copied == expected, str(copied))
	# This is the archived ordinary policy, never a current production rule.
	for slot: Dictionary in GameData.dpv2_direct_profile(18).slots:
		var uid := str(slot.slot_uid)
		assert(not legacy.records.has(uid))
		var source := GameData.dpv2_effective_slot_probability(18, uid)
		var actual: Dictionary = legacy.probability_v80(18, uid)
		var expected: Dictionary = legacy._apply_drop_probability_policy(source, "ordinary")
		assert(actual == expected, uid)


func _test_current_compiled_rolls(service: Node) -> void:
	# Read expected values directly from the compiled authority, independently
	# of the service/provider probability accessor under test.
	var compiled: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COMPILED_PATH))
	var slots_by_monster := {}
	for monster: Dictionary in compiled.monsters:
		slots_by_monster[int(monster.monster_id)] = monster.slots
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	for mid: int in [79, 81, 83, 85, 87, 158, 159, 76, 198, 225, 18]:
		assert(slots_by_monster.has(mid), "compiled fixture has no monster %d" % mid)
		var expected_slots: Array = slots_by_monster[mid]
		var expected_by_uid := {}
		for slot: Dictionary in expected_slots:
			expected_by_uid[str(slot.slot_uid)] = slot
			var probability: Dictionary = service._production_probability(mid, str(slot.slot_uid))
			assert(probability.ok)
			assert(int(probability.final_numerator) == int(slot.final_numerator), str(slot.slot_uid))
			assert(int(probability.final_denominator) == int(slot.final_denominator), str(slot.slot_uid))
		var before := rng.state
		var audited: Dictionary = service.roll_monster_drops(mid, rng, true)
		var audited_rng_state := rng.state
		rng.state = before
		var lean: Dictionary = service.roll_monster_drops(mid, rng, false)
		assert(audited.reason.is_empty() and lean.reason.is_empty(), "%d %s %s" % [mid, audited.reason, lean.reason])
		assert(audited.all_resolved_slots_rng and lean.all_resolved_slots_rng)
		assert(audited.ground_output_count <= 15 and lean.ground_output_count <= 15)
		assert(int(audited.source_entry_count) == expected_slots.size())
		assert(int(audited.rng_roll_count) == expected_slots.size())
		assert(audited.attempts.size() == expected_slots.size())
		for attempt: Dictionary in audited.attempts:
			var expected: Dictionary = expected_by_uid[str(attempt.slot_uid)]
			assert(int(attempt.final_numerator) == int(expected.final_numerator), str(attempt.slot_uid))
			assert(int(attempt.final_denominator) == int(expected.final_denominator), str(attempt.slot_uid))
		assert(rng.state == audited_rng_state, "audit/lean RNG consumption diverged: %d" % mid)
		assert(lean.items == audited.items and lean.gold_drops == audited.gold_drops)
		assert(lean.item_records == audited.item_records)
		assert(lean.successful_roll_count == audited.successful_roll_count)
		assert(lean.ground_output_count == audited.ground_output_count)
		assert(lean.overflow_discarded_count == audited.overflow_discarded_count)
	# The sheet explicitly retires this ordinary profile; legacy /3 must not
	# manufacture a draw or consume RNG for its empty production table.
	assert((slots_by_monster[18] as Array).is_empty())
	var empty_before := rng.state
	var empty: Dictionary = service.roll_monster_drops(18, rng, true)
	assert(empty.configured and empty.source_entry_count == 0 and empty.rng_roll_count == 0)
	assert(empty.items.is_empty() and empty.gold_drops.is_empty() and rng.state == empty_before)
	# ID199 has a historical profile but no compiled table. It must fail
	# closed without falling back to that archived profile or advancing RNG.
	assert(not slots_by_monster.has(199))
	var retired_before := rng.state
	var retired: Dictionary = service.roll_monster_drops(199, rng, true)
	assert(not retired.configured and retired.reason == "dpv2_direct_profile_unresolved")
	assert(retired.rng_roll_count == 0 and retired.items.is_empty() and retired.gold_drops.is_empty())
	assert(rng.state == retired_before)
