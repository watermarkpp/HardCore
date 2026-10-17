extends Node

const Budget := preload("res://scripts/gameplay/enemy/enemy_owner_frame_budget.gd")
const SessionBudget := preload("res://scripts/gameplay/source/source_session_budget.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

# Deterministic inputs only. Every admission, scope, reservation, accounting and
# fairness decision below runs the actual production ledger, on a real owner thread.
class Inputs extends RefCounted:
	var owner := OS.get_thread_caller_id()
	var epoch := 70
	var usec := 1000
	var paused := false
	var resource_failures: Array[String] = []
	func record_resource_failure(reason: String) -> void: resource_failures.append(reason)
	func owner_thread_id() -> int: return owner
	func get_process_frames() -> int: return epoch
	func get_ticks_usec() -> int: return usec
	func tree_is_paused() -> bool: return paused
	func get_setting(_key: String, fallback: Variant) -> Variant: return fallback
	func cold_gate() -> bool: return true

func _make_budget(clock: Inputs, session := false) -> RefCounted:
	var budget: RefCounted = SessionBudget.new() if session else Budget.new()
	var bindings := {"Engine":clock,"Time":clock,"ProjectSettings":clock,"phase":clock}
	if not budget.configure_owner(bindings, clock): return null
	budget.configure_for_tests(100, clock.get_process_frames, clock.get_ticks_usec)
	return budget

func _add(rows: Array[Dictionary], ok: bool, label: String) -> void:
	rows.append({"passed":ok,"label":label})

func _decision(budget: RefCounted, identity: Dictionary) -> Dictionary:
	return budget.call("continuation_scope_decision", identity)

static func _foreign_scope_probe(budget: RefCounted, identity: Dictionary) -> Dictionary:
	return {"capture":budget.call("capture_continuation_scope"),
		"decision":budget.call("continuation_scope_decision", identity)}

func _owner_checks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var clock := Inputs.new()
	var budget: RefCounted = _make_budget(clock)
	_add(rows, budget != null, "actual owner-local ledger configured on its owning thread")
	if budget == null: return rows
	var abi := budget.has_method("capture_continuation_scope") and budget.has_method("continuation_scope_decision")
	_add(rows, abi, "actual ledger exposes read-only current-scope continuation ABI")
	if not abi: return rows

	# No token is invented outside an admitted root scope.
	_add(rows, budget.call("capture_continuation_scope").is_empty(), "no admission means no continuation identity")
	budget.mark_pending("binding", true)
	var token: int = budget.begin("binding")
	var identity: Dictionary = budget.call("capture_continuation_scope")
	_add(rows, token > 0 and identity.get("token") == token and identity.get("depth") == 1,
		"capture identifies the actual admitted root token and depth")
	var before: Dictionary = budget.snapshot()
	var service_sequence: int = budget._service_sequence
	var next_token: int = budget._next_token
	_add(rows, _decision(budget, identity).get("allowed") == true, "same root with available allowance may continue")
	_add(rows, budget.snapshot() == before and budget._service_sequence == service_sequence and budget._next_token == next_token,
		"read-only capture/check does not debit time twice, record a service or create a scope")
	clock.usec += 10
	var child: int = budget.begin("nested_completion")
	_add(rows, child > 0 and _decision(budget, identity).get("allowed") == false,
		"open child cannot impersonate the captured root continuation")
	clock.usec += 7
	budget.end(child)
	_add(rows, _decision(budget, identity).get("allowed") == true,
		"completed child and natural elapsed preserve root identity")
	clock.usec += 83
	var exhausted := _decision(budget, identity)
	_add(rows, exhausted.get("allowed") == false and exhausted.get("reason") == "budget",
		"real in-flight wall time exhausts the original scope without waiting for end")
	budget.end(token)
	_add(rows, budget.snapshot().spent_usec == 100 and budget.snapshot().categories.binding.scopes == 1,
		"one original root closes once and nested time is not duplicated")
	_add(rows, _decision(budget, identity).get("allowed") == false, "closed root identity cannot authorize another operation")

	# Read-only fairness projects service of the current completed quantum;
	# it must not exploit _fair_blocker's intentional nested-scope bypass.
	clock.epoch += 1
	budget.configure_for_tests(100, clock.get_process_frames, clock.get_ticks_usec)
	budget.mark_pending("binding", true)
	budget.mark_pending("other", true)
	token = budget.begin("binding")
	identity = budget.call("capture_continuation_scope")
	_add(rows, token > 0 and budget._fair_blocker("binding") == null,
		"fixture reaches the real existing active-scope fairness bypass")
	before = budget.snapshot()
	var fairness := _decision(budget, identity)
	_add(rows, fairness.get("allowed") == false and fairness.get("reason") == "fairness" and fairness.get("blocking_category") == "other",
		"unserved runnable peer retains its turn before a second binding quantum")
	_add(rows, budget.snapshot() == before and budget._service_sequence == 0,
		"fairness refusal is read-only and does not fake service history")
	budget.end(token)
	var other: int = budget.begin("other")
	_add(rows, other > 0, "original FIFO fairness admits the peer after the real root closes")
	budget.end(other)
	token = budget.begin("binding")
	identity = budget.call("capture_continuation_scope")
	_add(rows, token > 0 and _decision(budget, identity).get("allowed") == true,
		"all peers actually served allows unused same-epoch allowance")

	# Eligibility remains live. Checking does not silently repair an epoch.
	budget.mark_pending("binding", true, false)
	_add(rows, _decision(budget, identity).get("reason") == "unrunnable", "calling category becoming unrunnable stops continuation")
	budget.mark_pending("binding", true, true)
	clock.paused = true
	_add(rows, _decision(budget, identity).get("reason") == "unrunnable", "pause eligibility is read at the continuation point")
	budget.mark_pending("binding", true, true, true)
	_add(rows, _decision(budget, identity).get("allowed") == true, "existing runs-when-paused permission is retained")
	clock.paused = false
	var stored_epoch: int = budget._epoch
	clock.epoch += 1
	_add(rows, _decision(budget, identity).get("allowed") == false and budget._epoch == stored_epoch,
		"changed source epoch refuses without synchronizing or resetting an open ledger")
	clock.epoch -= 1
	var foreign: RefCounted = _make_budget(clock)
	_add(rows, _decision(foreign, identity).get("allowed") == false, "identity from another ledger cannot grant work")
	var changed := identity.duplicate(true)
	changed["lane"] = 1
	_add(rows, _decision(budget, changed).get("allowed") == false, "forged scope lane cannot gain different allowance")
	var wrong_thread := Thread.new()
	var foreign_started := wrong_thread.start(_foreign_scope_probe.bind(budget, identity))
	_add(rows, foreign_started == OK, "foreign-owner refusal tested on a second actual thread")
	if foreign_started == OK:
		var foreign_result: Dictionary = wrong_thread.wait_to_finish()
		_add(rows, foreign_result.capture.is_empty() and foreign_result.decision.get("allowed") == false,
			"foreign caller is rejected before reading Source clock or changing ledger")
	budget.end(token)
	var next_root: int = budget.begin("binding")
	_add(rows, next_root != token and _decision(budget, identity).get("allowed") == false,
		"same epoch and category with a new token is not the old admitted scope")
	budget.end(next_root)

	# The inherited lane policy is shared, not copied into a second ledger.
	clock.epoch += 1
	budget.configure_for_tests(100, clock.get_process_frames, clock.get_ticks_usec)
	budget.configure_progress_for_tests(200)
	budget.mark_progress_pending("progress_other", true)
	budget.mark_pending("binding", true)
	token = budget.begin("binding")
	identity = budget.call("capture_continuation_scope")
	_add(rows, token > 0 and _decision(budget, identity).get("allowed") == true,
		"progress-only peer does not acquire a new background-lane veto")
	budget.end(token)
	token = budget.begin("accepted_cleanup", true)
	identity = budget.call("capture_continuation_scope")
	clock.usec += 1000
	_add(rows, _decision(budget, identity).get("allowed") == true,
		"original necessary scope retains its own permission without creating a new necessary admission")
	budget.end(token)

	# SourceSessionBudget's true outstanding reservations reduce availability.
	clock.epoch += 1
	var session_budget: RefCounted = _make_budget(clock, true)
	var session_owner := Object.new()
	_add(rows, session_budget.configure_session(session_owner.get_instance_id(), clock.cold_gate),
		"actual reservation subclass configures without a companion budget")
	var reservation: Dictionary = session_budget.reserve_live("reserved_source", 0, 60)
	_add(rows, not reservation.is_empty() and session_budget.remaining_usec() == 40,
		"real unaccepted reservation occupies existing background allowance")
	session_budget.mark_pending("binding", true)
	token = session_budget.begin("binding")
	identity = session_budget.call("capture_continuation_scope")
	clock.usec += 40
	_add(rows, _decision(session_budget, identity).get("reason") == "budget",
		"continuation uses subclass reservations plus current scope wall time")
	session_budget.end(token)
	_add(rows, session_budget.release_unaccepted(reservation) and session_budget.live_obligations() == 0,
		"reservation completes its original unaccepted release path")
	# External continuation test uses controlled protocol input only. It proves
	# the ledger guard; it is NOT a Native resource execution/BindingFact receipt.
	_add(rows, session_budget.configure_resource_continuations(clock.record_resource_failure),
		"actual inherited resource continuation guard is configured")
	clock.epoch += 1
	token = session_budget.begin("cold_scope")
	identity = session_budget.call("capture_continuation_scope")
	var call_identity := {"component_call":1}
	var segment: Dictionary = session_budget.begin_resource_external_segment(call_identity, {"component_site":1})
	_add(rows, not segment.is_empty() and _decision(session_budget, identity).get("allowed") == false and clock.resource_failures.is_empty(),
		"active external segment refuses read-only continuation without introducing a source fault")
	var resumed: bool = session_budget.resume_resource_external_segment(segment, {"executed":true,"request":{"identity":call_identity}})
	_add(rows, resumed and _decision(session_budget, identity).get("allowed") == true,
		"same actual scope is valid again after its original external continuation resumes")
	session_budget.end(token)
	session_owner.free()
	return rows

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var thread := Thread.new()
	var started := thread.start(_owner_checks)
	proof.record(started == OK, "ledger test runs on a genuine non-Main owner thread")
	if started != OK:
		failures += 1
	else:
		while thread.is_alive():
			await get_tree().process_frame
		for row: Dictionary in thread.wait_to_finish():
			proof.record(row.passed, row.label)
			if not row.passed: failures += 1
	var valid := proof.write_receipt("multicore_budget_continuation_20261015", proof.records.size(), failures)
	print("MULTICORE_BUDGET_CONTINUATION_20261015_", "PASS" if valid and failures == 0 else "FAIL")
	get_tree().quit(0 if valid and failures == 0 else 1)
