extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

const B := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Diagnostics := preload("res://scripts/runtime_diagnostics.gd")
var now_us := 100
var outer_iteration := 7
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	_proof.record(value, message)
	checks += 1
	if not value:
		errors.append(message)

func _run() -> void:
	PlayerState.test_mode = true
	Diagnostics.set_device_lab_performance_enabled(false)
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	var path := B.begin("path")
	check(path > 0, "first path work is admitted")
	now_us = 130
	var resource := B.begin("resource_completion")
	check(resource > 0, "nested optional work can use remaining time")
	now_us = 170
	B.end(resource)
	now_us = 200
	B.end(path)
	var result := B.snapshot()
	check(result.spent_usec == 100, "nested wall time is charged once to the shared total")
	check(result.categories.path.inclusive_usec == 100 and result.categories.path.self_usec == 60,
		"parent inclusive and self costs remain distinguishable")
	check(result.categories.resource_completion.inclusive_usec == 40,
		"nested category keeps its own inclusive cost")
	check(B.begin("death_work") == 0, "third optional owner cannot reset an exhausted iteration")
	check(B.begin("persistence_main") == 0, "fourth optional owner shares the same exhaustion")
	outer_iteration = 8
	check(B.remaining_usec() == 100, "one new outer iteration restores one shared budget")
	var death := B.begin("death_work")
	now_us = 310
	check(B.remaining_usec() == 0, "in-flight root work counts before its token closes")
	check(B.begin("path") == 0, "nested entry cannot hide an already over-budget root")
	B.end(death)
	check(B.snapshot().spent_usec == 110, "non-preemptible quantum overrun is measured exactly")
	outer_iteration = 9
	now_us = 400
	var persistence := B.begin("persistence_main")
	now_us = 450
	B.end(persistence)
	check(B.remaining_usec() == 50, "diagnostics disabled cannot disable budget accounting")
	# Necessary callbacks never disappear when optional maintenance is exhausted.
	var optional := B.begin("path")
	now_us += 70
	B.end(optional)
	check(B.remaining_usec() == 0, "optional overrun exhausts all remaining allowance")
	var receipt := B.begin("durable_receipt", true)
	check(receipt > 0, "already durable receipt remains admissible after exhaustion")
	now_us += 25
	B.end(receipt)
	check(B.snapshot().spent_usec == 145 and B.snapshot().overrun_usec == 45,
		"necessary over-budget work remains visible in the same ledger")
	check(B.snapshot().categories.durable_receipt.necessary_scopes == 1,
		"necessary work has its own measured receipt count")
	check(B.begin("resource_completion") == 0, "necessary work does not grant a second optional budget")
	_verify_continuous_queue_fairness()
	_verify_multiple_rounds_in_one_epoch()
	_verify_suspended_owners()
	_verify_disabled_hierarchy()
	B.reset_test_configuration()
	if not _proof.write_receipt("frame_budget_test", checks, errors.size()):
		errors.append("framework assertion receipt failed")
	print(("FRAMEWORK_FRAME_BUDGET_PASS" if errors.is_empty() else "FRAMEWORK_FRAME_BUDGET_FAIL")
		+ " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _verify_continuous_queue_fairness() -> void:
	now_us = 1000
	outer_iteration = 50
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	var owners := ["path", "death_work", "resource_completion", "persistence_main"]
	var served: Array[String] = []
	for owner: String in owners:
		B.mark_pending(owner, true)
	for frame in range(4):
		outer_iteration = 50 + frame
		# A frequently replaced path target must retain its continuous queue age.
		B.mark_pending("path", true)
		for owner: String in owners:
			var token := B.begin(owner)
			if token == 0:
				continue
			served.append(owner)
			now_us += 110 # One legal atomic quantum can overrun; it cannot be preempted.
			B.end(token)
	check(served == owners, "four continuously runnable owners each receive service despite fixed callback order")
	var pending: Dictionary = B.snapshot().pending
	check(pending.path.pending_epoch == 50 and pending.path.oldest_age_frames == 3,
		"target replacements preserve original backlog age")
	check(B.snapshot().open_scopes == 0, "all owner callbacks close synchronous scopes")
	B.mark_pending("death_work", false)
	check(not B.snapshot().pending.has("death_work"), "drained owner leaves fairness arbitration")
	outer_iteration = 54
	check(B.remaining_usec() == 100, "next frame receives exactly one allowance without accumulated credit")

func _verify_multiple_rounds_in_one_epoch() -> void:
	outer_iteration = 70
	now_us = 3000
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	var owners := ["path", "death_work", "resource_completion", "persistence_main"]
	for owner: String in owners:
		B.mark_pending(owner, true)
	var served: Array[String] = []
	for round_index in range(2):
		for owner: String in owners:
			var token := B.begin(owner)
			if token > 0:
				served.append(owner)
				now_us += 10
				B.end(token)
	check(served == owners + owners, "same-epoch callbacks receive multiple fair rounds when allowance remains")
	check(B.snapshot().spent_usec == 80 and B.remaining_usec() == 20,
		"fair rounds share the same allowance rather than resetting it per service")

func _verify_suspended_owners() -> void:
	outer_iteration = 90
	now_us = 4000
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	B.mark_pending("path", true)
	B.mark_pending("persistence_main", true)
	# Model the owner metadata without relying on a new API being present.
	# A queued worker can be pending while not runnable; it cannot own a turn.
	B._pending.path["runnable"] = false
	var token := B.begin("persistence_main")
	check(token > 0, "waiting worker does not block another runnable owner")
	if token > 0:
		B.end(token)
	outer_iteration = 91
	B._pending.path["runnable"] = true
	B._pending.persistence_main["runs_when_paused"] = true
	get_tree().paused = true
	token = B.begin("persistence_main")
	check(token > 0, "paused simulation owner cannot starve an always-running receipt owner")
	if token > 0:
		B.end(token)
	get_tree().paused = false
	check(B.snapshot().pending.path.pending_epoch == 90,
		"suspending a pending owner preserves its continuous backlog age")

func _verify_disabled_hierarchy() -> void:
	var parent := Node.new()
	var child := Node.new()
	add_child(parent)
	parent.add_child(child)
	child.set_process(true)
	child.set_physics_process(true)
	for physics_owner: bool in [false, true]:
		outer_iteration += 1
		now_us = 5000
		B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
		parent.process_mode = Node.PROCESS_MODE_DISABLED
		B.mark_pending("disabled_child", true, true, false, child, physics_owner)
		B.mark_pending("persistence_main", true, true, true, self)
		check(child.is_processing() and child.is_physics_processing() and not child.can_process(),
			"inherited disabled hierarchy retains callback flags but cannot actually run")
		var token := B.begin("persistence_main")
		check(token > 0, "disabled child cannot reserve a turn ahead of a runnable receipt owner: " + str(physics_owner))
		if token > 0:
			B.end(token)
		check(not B.snapshot().pending.disabled_child.runnable,
			"disabled hierarchy is exposed as nonrunnable in the shared ledger")
		var pending_epoch: int = B.snapshot().pending.disabled_child.pending_epoch
		parent.process_mode = Node.PROCESS_MODE_INHERIT
		check(B.snapshot().pending.disabled_child.runnable
			and B.snapshot().pending.disabled_child.pending_epoch == pending_epoch,
			"reenabling the actual owner restores eligibility without losing backlog age")
		check(B.begin("persistence_main") == 0, "restored oldest owner receives its preserved fair turn")
		token = B.begin("disabled_child")
		check(token > 0, "restored owner is admitted for its real callback")
		if token > 0:
			B.end(token)
		parent.process_mode = Node.PROCESS_MODE_DISABLED
		token = B.begin("disabled_child")
		check(token > 0, "explicit synchronous drive can still service a deliberately disabled owner")
		if token > 0:
			B.end(token)
	parent.free()
