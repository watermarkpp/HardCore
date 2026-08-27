extends Node

const Cadence := preload("res://scripts/monster_movement_cadence.gd")
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"

var _records_by_id: Dictionary = {}
var _checks := 0


func _ready() -> void:
	_run()
	print("MONSTER_MOVEMENT_CADENCE_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _run() -> void:
	_load_authority_records()
	_test_exact_id_and_authority_shape()
	_test_intervals_and_strict_cadence()
	_test_long_frame_and_same_timestamp()
	_test_clock_regression_fail_closed()
	_test_walk_wait_strict_unlock()
	_test_stationary_accepted_and_compatibility()
	_test_invalid_authority_fails_closed()
	_test_runtime_disabled_fails_closed()


func _load_authority_records() -> void:
	assert(FileAccess.file_exists(AUTHORITY_PATH), "M00R runtime authority must be present")
	var file := FileAccess.open(AUTHORITY_PATH, FileAccess.READ)
	assert(file != null, "M00R runtime authority must open")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "M00R runtime authority JSON must parse")
	for raw_record: Variant in parsed.get("records", []):
		assert(raw_record is Dictionary, "authority records must be dictionaries")
		var record: Dictionary = raw_record
		_records_by_id[str(record.get("monster_id", -1))] = record
	assert(_records_by_id.size() == 156, "all 156 M00R records must be available")


func _record(id: int) -> Dictionary:
	var record: Dictionary = _records_by_id.get(str(id), _records_by_id.get("%d.0" % id, {}))
	assert(not record.is_empty(), "missing M00R record %d" % id)
	return record.duplicate(true)


func _test_exact_id_and_authority_shape() -> void:
	var record := _record(64)
	var cadence := Cadence.new()
	assert(cadence.configure(record), "nested runtime authority record must bind")
	assert(cadence.monster_id == 64)
	assert(cadence.source_status == Cadence.STATUS_ACCEPTED_CANDIDATE)
	assert(cadence.state_snapshot().contract_id == Cadence.CONTRACT_ID)
	_checks += 4
	for record_key: String in _records_by_id:
		var every_record: Dictionary = _records_by_id[record_key]
		var every_cadence := Cadence.new(every_record)
		assert(every_cadence.configured, "every M00R record must satisfy M01A shape: %s" % record_key)
	_checks += _records_by_id.size()

	var wrong_name := record.duplicate(true)
	wrong_name["canonical_name"] = "intentionally wrong display name"
	var id_only_binding := Cadence.new()
	assert(id_only_binding.configure(wrong_name), "display name must not affect exact ID binding")
	assert(id_only_binding.monster_id == 64)
	_checks += 2

	var name_only := record.duplicate(true)
	name_only.erase("monster_id")
	var rejected_name_only := Cadence.new()
	assert(not rejected_name_only.configure(name_only))
	var name_only_result := rejected_name_only.evaluate(999999)
	assert(name_only_result.decision == Cadence.DECISION_IMMOBILE)
	assert(name_only_result.error_code == Cadence.AUTHORITY_VIOLATION_CODE)
	_checks += 3

	var flat_movement_master_row := {
		"monster_id": 64,
		"movement_source_status": Cadence.STATUS_ACCEPTED_CANDIDATE,
		"movement_enabled": true,
		"walk_interval_ms": 1000,
		"walk_step": 1,
		"walk_wait_ms": 0,
	}
	var rejected_flat := Cadence.new()
	assert(not rejected_flat.configure(flat_movement_master_row), "flat movement master rows are not runtime authority records")
	_checks += 1

	var missing_binding := _record(64)
	missing_binding["movement"].erase("source")
	assert(not Cadence.new().configure(missing_binding), "M00R source binding is required")
	_checks += 1


func _test_intervals_and_strict_cadence() -> void:
	# These are real M00R bindings at the released 800/1000/1500 intervals.
	for interval_case: Array in [[70, 800], [64, 1000], [19, 1500]]:
		var id: int = interval_case[0]
		var expected_interval: int = interval_case[1]
		var cadence := Cadence.new(_record(id))
		assert(cadence.walk_interval_ms == expected_interval)
		assert(cadence.evaluate(expected_interval).decision == Cadence.DECISION_WAIT, "strict cadence boundary must wait")
		var first := cadence.evaluate(expected_interval + 1)
		assert(first.decision == Cadence.DECISION_GRANT and first.granted)
		_checks += 4

	# No released row is exactly 1800ms; this complete authority-shaped
	# synthetic row exercises the explicit cadence without a default or
	# move-speed derivation.
	var interval_1800 := _record(64)
	interval_1800["movement"]["walk_interval_ms"] = 1800
	var cadence_1800 := Cadence.new(interval_1800)
	assert(cadence_1800.configure(interval_1800))
	assert(cadence_1800.evaluate(1800).decision == Cadence.DECISION_WAIT)
	assert(cadence_1800.evaluate(1801).decision == Cadence.DECISION_GRANT)
	_checks += 3

	# No released row is exactly 200ms, so this is a complete synthetic
	# authority-shaped row derived only to exercise the locked minimum boundary.
	var minimum_200 := _record(64)
	minimum_200["movement"]["walk_interval_ms"] = 200
	var cadence_200 := Cadence.new(minimum_200)
	assert(cadence_200.evaluate(200).decision == Cadence.DECISION_WAIT)
	assert(cadence_200.evaluate(201).decision == Cadence.DECISION_GRANT)
	var below_200 := _record(64)
	below_200["movement"]["walk_interval_ms"] = 199
	assert(not Cadence.new().configure(below_200))
	_checks += 3

	var boundary := Cadence.new(_record(64))
	assert(boundary.evaluate(1000).decision == Cadence.DECISION_WAIT)
	assert(boundary.evaluate(1001).decision == Cadence.DECISION_GRANT)
	assert(boundary.evaluate(2001).decision == Cadence.DECISION_WAIT)
	assert(boundary.evaluate(2002).decision == Cadence.DECISION_GRANT)
	_checks += 3

	var initial_tick := Cadence.new()
	assert(initial_tick.configure(_record(64), 1000))
	assert(initial_tick.evaluate(2000).decision == Cadence.DECISION_WAIT)
	assert(initial_tick.evaluate(2001).decision == Cadence.DECISION_GRANT)
	_checks += 3

	var resettable := Cadence.new(_record(64))
	assert(resettable.evaluate(1001).granted)
	assert(resettable.reset(5000))
	assert(resettable.walk_count == 0 and not resettable.walk_wait_locked)
	assert(resettable.source_status == Cadence.STATUS_ACCEPTED_CANDIDATE)
	assert(resettable.evaluate(6000).decision == Cadence.DECISION_WAIT)
	assert(resettable.evaluate(6001).granted)
	var reset_regression := resettable.reset(6000)
	assert(not reset_regression and resettable.authority_violation)
	_checks += 7


func _test_long_frame_and_same_timestamp() -> void:
	var cadence := Cadence.new(_record(64))
	assert(cadence.evaluate(1001).granted, "first event must grant")
	var long_frame := cadence.evaluate(10001)
	assert(long_frame.granted, "long frame may grant one event")
	assert(long_frame.walk_tick_ms == 10001, "long frame resets cadence at current timestamp")
	var same_timestamp := cadence.evaluate(10001)
	assert(not same_timestamp.granted and same_timestamp.reason == "same_timestamp")
	var not_catch_up := cadence.evaluate(11000)
	assert(not not_catch_up.granted, "one interval after the reset is still strict >")
	var next_event := cadence.evaluate(11002)
	assert(next_event.granted, "next event occurs only after the new strict boundary")
	_checks += 6


func _test_clock_regression_fail_closed() -> void:
	var cadence := Cadence.new(_record(64))
	assert(cadence.evaluate(1001).granted)
	var regression := cadence.evaluate(1000)
	assert(regression.decision == Cadence.DECISION_IMMOBILE)
	assert(regression.error_code == Cadence.AUTHORITY_VIOLATION_CODE)
	assert(regression.reason == "time_regression")
	assert(cadence.failed_closed and cadence.authority_violation)
	var after_failure := cadence.evaluate(999999)
	assert(after_failure.decision == Cadence.DECISION_IMMOBILE)
	assert(after_failure.source_status == Cadence.STATUS_ACCEPTED_CANDIDATE)
	_checks += 6


func _test_walk_wait_strict_unlock() -> void:
	var cadence := Cadence.new(_record(162))
	# ID162's move interval is now the user-authoritative 21CQ value; the
	# strict cadence algorithm and the audited step/wait semantics are unchanged.
	assert(cadence.walk_interval_ms == 1000 and cadence.walk_step == 5 and cadence.walk_wait_ms == 1200)
	var event_delta := cadence.walk_interval_ms + 1
	for event_index: int in range(1, 6):
		var now := event_index * event_delta
		assert(cadence.evaluate(now).granted, "WalkStep event %d must grant" % event_index)
	var sixth_tick := 6 * event_delta
	var sixth := cadence.evaluate(sixth_tick)
	assert(sixth.granted, "WalkStep threshold event still grants")
	assert(sixth.walk_count == 0 and sixth.walk_wait_locked)
	var exact_wait := cadence.evaluate(sixth_tick + cadence.walk_wait_ms)
	assert(not exact_wait.granted and exact_wait.reason == "walk_wait_locked", "wait unlock is strict >")
	var unlocked := cadence.evaluate(sixth_tick + cadence.walk_wait_ms + 1)
	assert(unlocked.granted, "wait must unlock after strict boundary")
	_checks += 10

	var zero_wait := Cadence.new(_record(64))
	assert(zero_wait.evaluate(1001).granted)
	var second := zero_wait.evaluate(2002)
	assert(second.granted and second.walk_wait_locked, "strict > WalkStep must lock after the threshold")
	var same_tick := zero_wait.evaluate(2002)
	assert(not same_tick.granted)
	var zero_wait_unlock := zero_wait.evaluate(2003)
	assert(not zero_wait_unlock.granted, "zero wait still uses strict > and cadence remains pending")
	_checks += 4


func _test_stationary_accepted_and_compatibility() -> void:
	var stationary := Cadence.new(_record(30))
	assert(stationary.source_status == Cadence.STATUS_LOCKED)
	var immobile := stationary.evaluate(999999)
	assert(immobile.decision == Cadence.DECISION_IMMOBILE and not immobile.granted)
	assert(immobile.source_status == Cadence.STATUS_LOCKED)
	_checks += 3

	var accepted := Cadence.new(_record(64))
	assert(accepted.source_status == Cadence.STATUS_ACCEPTED_CANDIDATE)
	assert(accepted.evaluate(1001).decision == Cadence.DECISION_GRANT)
	_checks += 2

	var compatibility := Cadence.new(_record(41))
	assert(compatibility.source_status == Cadence.STATUS_COMPATIBILITY_HOLD)
	assert(compatibility.evaluate(1500).decision == Cadence.DECISION_WAIT)
	var hold_grant := compatibility.evaluate(1501)
	assert(hold_grant.granted and hold_grant.decision == Cadence.DECISION_GRANT)
	assert(hold_grant.public_decision == Cadence.DECISION_COMPATIBILITY)
	assert(hold_grant.authority_decision == Cadence.DECISION_COMPATIBILITY)
	assert(hold_grant.cadence_decision == Cadence.DECISION_GRANT)
	assert(compatibility.evaluate_decision(3002) == Cadence.DECISION_GRANT)
	assert(hold_grant.source_status == Cadence.STATUS_COMPATIBILITY_HOLD)
	_checks += 7


func _test_invalid_authority_fails_closed() -> void:
	var missing_interval := _record(64)
	missing_interval["movement"].erase("walk_interval_ms")
	assert(not Cadence.new().configure(missing_interval))
	assert(Cadence.new().configure(_record(64)))
	_checks += 2

	var bad_status := _record(64)
	bad_status["movement"]["movement_source_status"] = "DATA_HOLD"
	var bad_status_cadence := Cadence.new()
	assert(not bad_status_cadence.configure(bad_status))
	assert(bad_status_cadence.evaluate(999).decision == Cadence.DECISION_IMMOBILE)
	_checks += 2

	var below_minimum := _record(64)
	below_minimum["movement"]["walk_interval_ms"] = 199
	var below_minimum_cadence := Cadence.new()
	assert(not below_minimum_cadence.configure(below_minimum))
	assert(below_minimum_cadence.last_error_code == Cadence.AUTHORITY_VIOLATION_CODE)
	_checks += 2

	var negative_wait := _record(64)
	negative_wait["movement"]["walk_wait_ms"] = -1
	negative_wait["movement"]["walk_wait_explicit_zero"] = false
	assert(not Cadence.new().configure(negative_wait))
	_checks += 1

	var boolean_step := _record(64)
	boolean_step["movement"]["walk_step"] = true
	assert(not Cadence.new().configure(boolean_step))
	_checks += 1

	var no_config := Cadence.new()
	var no_config_result := no_config.evaluate(100000)
	assert(no_config_result.decision == Cadence.DECISION_IMMOBILE)
	assert(no_config_result.error_code == Cadence.AUTHORITY_VIOLATION_CODE)
	_checks += 2

	var invalid_time := Cadence.new(_record(64))
	var fractional_time := invalid_time.evaluate(1000.5)
	assert(fractional_time.decision == Cadence.DECISION_IMMOBILE)
	assert(fractional_time.error_code == Cadence.AUTHORITY_VIOLATION_CODE)
	var negative_time := Cadence.new(_record(64)).evaluate(-1)
	assert(negative_time.decision == Cadence.DECISION_IMMOBILE)
	_checks += 4


func _test_runtime_disabled_fails_closed() -> void:
	var disabled := _record(33)
	assert(not bool(disabled.get("runtime_allowed", true)))
	var cadence := Cadence.new(disabled)
	var result := cadence.evaluate(999999)
	assert(result.decision == Cadence.DECISION_IMMOBILE)
	assert(not result.granted and result.reason == "stationary_or_runtime_disabled")
	assert(result.source_status == Cadence.STATUS_ACCEPTED_CANDIDATE)
	_checks += 4
