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
	_verify_once_per_epoch_callback_does_not_strand_budget()
	_verify_new_and_delayed_callbacks()
	_verify_sustained_service_pressure()
	_verify_callback_order_permutations()
	_verify_opportunity_is_not_equal_share()
	_verify_detached_and_retired_owners()
	_verify_empty_category_identity()
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
	check(served == owners + owners, "fixture-requested callback rounds each receive service when allowance remains")
	check(B.snapshot().spent_usec == 80 and B.remaining_usec() == 20,
		"fair rounds share the same allowance rather than resetting it per service")

func _verify_once_per_epoch_callback_does_not_strand_budget() -> void:
	outer_iteration = 80
	now_us = 3500
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	for owner: String in ["resource_completion", "feature_effects", "persistence_main"]:
		B.mark_pending(owner,true)
	# Resource polling returns only once in this actual process epoch. Its
	# ongoing subscription stays pending, but another callback is unavailable.
	var resource := B.begin("resource_completion")
	check(resource>0,"once-per-epoch resource callback receives its initial fair turn")
	if resource>0: now_us += 10; B.end(resource)
	var effects := B.begin("feature_effects")
	check(effects>0,"effect queue receives its initial fair turn")
	if effects>0: now_us += 10; B.end(effects)
	check(B.begin("feature_effects") == 0,"remaining work still yields to a not-yet-served runnable owner")
	var persistence := B.begin("persistence_main")
	check(persistence>0,"not-yet-served persistence callback retains its initial fair turn")
	if persistence>0: now_us += 10; B.end(persistence)
	var completed := 0
	for quantum in 6:
		var token := B.begin("feature_effects")
		if token == 0: break
		now_us += 10; B.end(token); completed += 1
	check(completed == 6,"after all owners get one epoch turn, queued effects consume the still-unused same budget")
	check(B.snapshot().spent_usec == 90 and B.remaining_usec() == 10,
		"repeated quanta neither reset nor enlarge the shared epoch budget")
	var overrun := B.begin("feature_effects")
	if overrun>0: now_us += 20; B.end(overrun)
	check(B.remaining_usec() == 0 and B.begin("feature_effects") == 0,
		"existing atomic overrun exhausts the same budget and blocks further optional work")
	outer_iteration = 81
	check(B.begin("feature_effects") == 0,"next epoch restores oldest-first admission ahead of the prolific owner")
	resource = B.begin("resource_completion")
	check(resource>0,"once-per-epoch resource owner is not starved in the next epoch")
	if resource>0: B.end(resource)
	check(B.snapshot().pending.feature_effects.pending_epoch == 80 and B.snapshot().open_scopes == 0,
		"work-conserving admission preserves backlog identity and closed scopes")

func _verify_new_and_delayed_callbacks() -> void:
	outer_iteration = 82
	now_us = 3800
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	B.mark_pending("feature_effects", true)
	var token := B.begin("feature_effects")
	now_us += 10; B.end(token)
	B.mark_pending("new_resource", true)
	check(B.begin("feature_effects") == 0, "new same-epoch pending resource keeps priority over already-served effects")
	var denied: Dictionary = B.snapshot().categories.feature_effects.last_denial
	check(denied.reason == "fairness" and denied.blocking_category == "new_resource" and int(denied.remaining_usec) == 90,
		"denial evidence identifies an actual blocker and remaining allowance")
	var age: int = B.snapshot().pending.new_resource.pending_epoch
	B.mark_pending("new_resource", true)
	token = B.begin("new_resource")
	check(token > 0 and B.snapshot().pending.new_resource.pending_epoch == age,
		"repeated real demand preserves age and the resource gets its next actual callback")
	if token > 0: now_us += 10; B.end(token)
	token = B.begin("new_resource")
	check(token > 0, "a new same-epoch explicit resource callback remains admissible after its earlier service")
	if token > 0: now_us += 10; B.end(token)
	outer_iteration = 83
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	B.mark_pending("persistence_main", true)
	B.mark_pending("resource_completion", true)
	check(B.begin("resource_completion") == 0, "resource callback initially yields to older not-yet-served persistence")
	check(B.snapshot().categories.resource_completion.denied_fairness == 1,
		"resource admission failure is distinguished from budget exhaustion")
	token = B.begin("persistence_main")
	if token > 0: now_us += 10; B.end(token)
	token = B.begin("resource_completion")
	check(token > 0, "initially rejected resource receives its real turn after the older callback completes")
	if token > 0: now_us += 100; B.end(token)
	check(B.begin("feature_effects") == 0 and B.snapshot().categories.feature_effects.denied_budget == 1,
		"budget exhaustion cannot be mistaken for a fairness refusal or grant extra work")

func _verify_sustained_service_pressure() -> void:
	outer_iteration = 84
	now_us = 3900
	B.configure_for_tests(100, func() -> int: return outer_iteration, func() -> int: return now_us)
	var owners := ["resource_completion", "feature_effects", "death_work", "persistence_main"]
	var completed := {}
	for owner: String in owners:
		B.mark_pending(owner, true); completed[owner] = 0
	for frame in 6:
		outer_iteration = 84 + frame
		for owner: String in owners + ["feature_effects"]:
			var attempts := 1 if owner != "feature_effects" else 10
			for quantum in attempts:
				var token := B.begin(owner)
				if token == 0: break
				now_us += 10; B.end(token); completed[owner] += 1
		check(B.snapshot().spent_usec <= 100 and B.snapshot().open_scopes == 0,
			"sustained effects share one closed allowance: frame " + str(frame))
	for owner: String in ["resource_completion", "death_work", "persistence_main"]:
		check(int(completed[owner]) == 6, "continuous effect pressure cannot starve the actual callback: " + owner)
	check(int(completed.feature_effects) > 6, "unused allowance serves more than one effect quantum per frame")

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

func _callback_orders(prefix: Array,remaining: Array,result: Array) -> void:
	if remaining.is_empty(): result.append(prefix); return
	for index in remaining.size():
		var rest := remaining.duplicate()
		var owner: String = str(rest.pop_at(index))
		_callback_orders(prefix+[owner],rest,result)

func _verify_callback_order_permutations() -> void:
	var owners := ["resource_completion", "feature_effects", "death_work", "persistence_main"]
	var orders: Array = []
	_callback_orders([],owners,orders)
	check(orders.size() == 24, "all four-owner callback order permutations are covered")
	for order: Array in orders:
		outer_iteration = 200
		now_us = 10000
		B.configure_for_tests(100,func() -> int: return outer_iteration,func() -> int: return now_us)
		for owner: String in owners: B.mark_pending(owner,true)
		var served: Array[String] = []
		for frame in 4:
			outer_iteration = 200+frame
			for owner: String in order:
				B.mark_pending(owner,true)
				var token := B.begin(owner)
				if token == 0: continue
				served.append(owner); now_us += 110; B.end(token)
		check(served == owners, "one atomic overrun per epoch still serves all four oldest owners within four epochs: "+str(order))
		check(B.snapshot().pending.resource_completion.pending_epoch == 200 and B.snapshot().open_scopes == 0,
			"callback order and repeated submissions preserve age without open scopes: "+str(order))

func _verify_opportunity_is_not_equal_share() -> void:
	outer_iteration = 210
	now_us = 12000
	B.configure_for_tests(100,func() -> int: return outer_iteration,func() -> int: return now_us)
	B.mark_pending("A",true); B.mark_pending("B",true)
	var completed := {"A":0,"B":0}
	for frame in 2:
		outer_iteration = 210+frame
		for owner: String in ["A","B"]:
			for quantum in 10:
				var token := B.begin(owner)
				if token == 0: break
				now_us += 10; B.end(token); completed[owner] += 1
	check(completed.A == 2 and completed.B == 18,
		"first-service fairness plus unused allowance is explicitly not equal share or strict round-robin")
	check(B.snapshot().spent_usec == 100 and B.snapshot().open_scopes == 0,
		"opportunity-based unequal throughput still shares exactly one allowance")

func _verify_detached_and_retired_owners() -> void:
	outer_iteration = 220
	now_us = 14000
	B.configure_for_tests(100,func() -> int: return outer_iteration,func() -> int: return now_us)
	var owner := Node.new()
	add_child(owner); owner.set_process(true)
	B.mark_pending("lifecycle_owner",true,true,false,owner)
	B.mark_pending("persistence_main",true,true,true,self)
	remove_child(owner)
	var token := B.begin("persistence_main")
	check(token>0 and not B.snapshot().pending.lifecycle_owner.runnable,
		"a detached live owner cannot withhold another callback's fair turn")
	if token>0: B.end(token)
	add_child(owner)
	check(B.begin("persistence_main") == 0,"reattached owner recovers its preserved unserved turn")
	token = B.begin("lifecycle_owner")
	check(token>0,"reattached owner can consume its actual callback")
	if token>0: B.end(token)
	outer_iteration = 221
	owner.queue_free()
	token = B.begin("persistence_main")
	check(token>0 and not B.snapshot().pending.lifecycle_owner.runnable,
		"queued-free owner immediately stops blocking without waiting for a destruction callback")
	if token>0: B.end(token)
	B.mark_pending("lifecycle_owner",false)
	check(not B.snapshot().pending.has("lifecycle_owner"),"drained identity retires its pending registration")
	outer_iteration = 222
	B.mark_pending("lifecycle_owner",true)
	check(B.snapshot().pending.lifecycle_owner.pending_epoch == 222,
		"a later new pending registration cannot inherit a drained identity's old queue age")

func _verify_empty_category_identity() -> void:
	outer_iteration = 240
	now_us = 16000
	B.configure_for_tests(100,func() -> int: return outer_iteration,func() -> int: return now_us)
	B.mark_pending("",true,false)
	var token := B.begin("")
	check(token == 0,"empty category cannot bypass its explicit unrunnable state")
	if token > 0: B.end(token)
	check(B.snapshot().categories[""].denied_unrunnable == 1,
		"empty unrunnable identity records the actual denial reason")
	check(B.snapshot().spent_usec == 0 and B.snapshot().open_scopes == 0,
		"empty unrunnable rejection leaves no scope or charged work")
	B.mark_pending("",true,true)
	B.mark_pending("named_peer",true)
	token = B.begin("named_peer")
	check(token == 0,"older unserved empty identity keeps its turn ahead of a named peer")
	if token > 0: now_us += 10; B.end(token)
	check(B.snapshot().categories.named_peer.denied_fairness == 1,
		"named peer records fairness denial caused by the empty category")
	token = B.begin("")
	check(token > 0,"eligible empty category remains a valid ordinary owner")
	if token > 0: now_us += 10; B.end(token)
	token = B.begin("named_peer")
	check(token > 0,"served empty owner does not keep unused allowance from its peer")
	if token > 0: now_us += 10; B.end(token)
	check(B.snapshot().spent_usec == 20 and B.snapshot().open_scopes == 0,
		"both admitted owners retain exact shared accounting and closed scopes")
	outer_iteration = 241
	B.mark_pending("",true,false)
	token = B.begin("named_peer")
	check(token > 0,"unrunnable empty peer cannot block another owner's next epoch")
	if token > 0: now_us += 10; B.end(token)
	token = B.begin("",true)
	check(token > 0,"necessary empty-category work retains the existing mandatory exception")
	if token > 0: now_us += 110; B.end(token)
	check(B.snapshot().spent_usec == 120 and B.snapshot().overrun_usec == 20,
		"necessary empty-category work is fully charged without a second budget")
	check(B.begin("") == 0,"empty category cannot bypass exhausted optional allowance")
	B.mark_pending("",false)
	check(not B.snapshot().pending.has(""),"empty identity drains through the same registration owner")
