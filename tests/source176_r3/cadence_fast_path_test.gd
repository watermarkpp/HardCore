extends Node
const Current := preload("res://scripts/monster_movement_cadence.gd")
const Reference := preload("res://tests/source176_r3/helpers/cadence_reference_r2.gd")
const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value and errors.size() < 20:
		errors.append(label)

func _run() -> void:
	var file := FileAccess.open("res://assets/data/monster_runtime_authority_v1.json", FileAccess.READ)
	var authority: Dictionary = JSON.parse_string(file.get_as_text())
	var records: Array = authority.records
	check(records.size() == 156, "complete exact authority set")
	var probe := Current.new(records[0])
	if not probe.has_method("evaluate_grant"):
		errors.append("allocation-free evaluate_grant entry is missing")
		_finish({})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	for record: Dictionary in records:
		var old := Reference.new(record)
		var verbose := Current.new(record)
		var fast := Current.new(record)
		var now := 0
		for step in range(300):
			now += rng.randi_range(0, 1800)
			if step % 71 == 0:
				check(old.reset(now) == fast.reset(now), "explicit reset parity")
				verbose.reset(now)
			var expected: Dictionary = old.evaluate(now)
			check(expected == verbose.evaluate(now), "verbose decision and reason parity")
			check(bool(expected.granted) == bool(fast.call("evaluate_grant", now)), "fast grant parity")
			check(old.state_snapshot() == fast.state_snapshot(), "all cadence state fields match")
			check(not bool(fast.call("evaluate_grant", now)), "same timestamp cannot grant twice")
			old.evaluate(now)
			verbose.evaluate(now)
		var malformed_times: Array = [null, true, "100", -1, 1.5, NAN, INF]
		for value: Variant in malformed_times:
			var old_invalid := Reference.new(record)
			var fast_invalid := Current.new(record)
			check(bool(old_invalid.evaluate(value).granted) == bool(fast_invalid.call("evaluate_grant", value)), "invalid input cannot grant")
			check(old_invalid.state_snapshot() == fast_invalid.state_snapshot(), "invalid input fails closed identically")
		var old_backwards := Reference.new(record)
		var fast_backwards := Current.new(record)
		old_backwards.evaluate(5000)
		fast_backwards.call("evaluate_grant", 5000)
		old_backwards.evaluate(4999)
		fast_backwards.call("evaluate_grant", 4999)
		check(old_backwards.state_snapshot() == fast_backwards.state_snapshot(), "regressed clock fails closed identically")
	# A mechanical cost measurement of the same state transition, separate
	# from the required repeated native-scene P95/P99 comparison.
	var sample_record: Dictionary = {}
	for record: Dictionary in records:
		if int(record.monster_id) == 64:
			sample_record = record
	var cost_rows: Array = []
	for repeat in range(5):
		var old_cost := Reference.new(sample_record)
		var fast_cost := Current.new(sample_record)
		var old_started := Time.get_ticks_usec()
		for n in range(20000):
			old_cost.evaluate(n * 17)
		var old_us := Time.get_ticks_usec() - old_started
		var fast_started := Time.get_ticks_usec()
		for n in range(20000):
			fast_cost.call("evaluate_grant", n * 17)
		var fast_us := Time.get_ticks_usec() - fast_started
		check(old_cost.state_snapshot() == fast_cost.state_snapshot(), "cost run remains state equivalent")
		cost_rows.append({"calls": 20000, "verbose_usec": old_us, "fast_usec": fast_us})
	_finish({"authority_count": records.size(), "cost_rows": cost_rows})

func _finish(extra: Dictionary) -> void:
	extra["checks"] = checks
	extra["errors"] = errors
	F.write_evidence("cadence_fast_path", extra)
	print(("R3_CADENCE_FAST_PASS" if errors.is_empty() else "R3_CADENCE_FAST_FAIL")
		+ " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
