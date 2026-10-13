extends Node

const Probe := preload("res://research/coverage_v113/coverage_probe.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "native_coverage_timer_contract_20261013"
var proof := Proof.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Probe.reset()
	proof.record(Probe.begin(&"outside", &"outside", true) == 0, "outside_root_is_ignored")
	var root := Probe.begin_root(&"root")
	var outer := Probe.begin(&"candidate", &"outer", true)
	var value := 0.0
	for index in range(1500): value += sqrt(float(index + 1))
	var child := Probe.begin(&"candidate", &"child", true)
	for index in range(1500): value += sqrt(float(index + 1))
	Probe.end(child)
	Probe.end(outer)
	var sibling := Probe.begin(&"world", &"sibling", false)
	for index in range(1500): value += sqrt(float(index + 1))
	Probe.end(sibling)
	Probe.end(root)
	var snapshot: Dictionary = Probe.snapshot()
	var rows: Dictionary = snapshot.get("rows", {})
	var self_sum := 0
	for row: Dictionary in rows.values(): self_sum += int(row.get("self_usec", 0))
	proof.record(value > 0.0, "real_timer_fixture_work")
	proof.record(int(snapshot.get("stack_errors", -1)) == 0, "stack_has_no_errors")
	proof.record(int(snapshot.get("physical_root_calls", 0)) == 1, "one_root_context")
	proof.record(int(snapshot.get("stack_depth", -1)) == 0, "all_frames_closed")
	proof.record(self_sum == int(snapshot.get("physical_root_total_usec", -1)), "exclusive_self_sum_matches_root")
	proof.record(int(snapshot.get("outer_envelope_usec", -1)) == int(rows.get("outer", {}).get("inclusive_usec", -2)), "nested_envelope_counted_once")
	proof.record(int(snapshot.get("outer_envelope_usec", 0)) <= int(snapshot.get("physical_root_total_usec", -1)), "envelope_is_contained_in_root")
	proof.record(int(snapshot.get("observer_overhead_usec", 0)) > 0, "observer_overhead_is_measured")
	var file := FileAccess.open("res://outputs/native_batch_ab_v113_20261012/%s_timer.json" % OS.get_environment("HARDCORE_NATIVE_AB_LABEL"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(snapshot, "\t")); file.close()
	var failed := 0
	for record: Dictionary in proof.records:
		if not bool(record.get("passed", false)): failed += 1
	var ok := proof.write_receipt(SCENE_ID, proof.records.size(), failed)
	print("NATIVE_COVERAGE_TIMER_CONTRACT_", "PASS" if failed == 0 and ok else "FAIL")
	get_tree().quit(0 if failed == 0 and ok else 1)
