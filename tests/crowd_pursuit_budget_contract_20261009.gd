extends Node

const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Enemy := preload("res://scripts/enemy.gd")
const RuntimeFixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")

class ContractOwner extends Node:
	const ContractBudget := preload("res://scripts/monster_ai_package/decision_budget.gd")
	var decision_scope: Array = []
	var runnable_kinds: Dictionary = {}
	var dispatch_calls: int = 0
	var invalidate_on_dispatch: bool = false
	var invalidate_after_consume: bool = false
	var consume_token: int = 0
	var second_consume_token: int = 0

	func _hc_pursuit_budget_scope() -> Array:
		return decision_scope.duplicate()

	func _hc_pursuit_budget_kind_runnable(kind: StringName) -> bool:
		return bool(runnable_kinds.get(kind, true))

	func _hc_dispatch_pursuit_process(kind: StringName) -> bool:
		dispatch_calls += 1
		if invalidate_on_dispatch:
			decision_scope = ["invalidated", dispatch_calls]
			return false
		consume_token = ContractBudget.consume_dispatch_pursuit_turn(self, decision_scope, kind)
		second_consume_token = ContractBudget.consume_dispatch_pursuit_turn(self, decision_scope, kind)
		if consume_token != 0:
			ContractBudget.end_pursuit_turn(consume_token)
		if invalidate_after_consume:
			decision_scope = ["invalidated_after_consume", dispatch_calls]
		return consume_token != 0

var _failures: Array[String] = []
var _clock_usec: int = 0
var _owners: Array[Node] = []

func _ready() -> void:
	set_process(true)
	await _run_contract()
	_cleanup()
	if _failures.is_empty():
		print("HC_PURSUIT_BUDGET_CONTRACT_20261009_PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("HC_TEST_FAIL ", failure)
	get_tree().quit(1)

func _run_contract() -> void:
	_configure_frame_budget(1000000)
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	Budget.bind_pursuit_dispatch_process_owner(self)
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "immediate pursuit mode is accepted")
	_check(Enemy.configure_pursuit_process_budget_mode("budgeted"), "budgeted pursuit mode is accepted")
	_check(not Enemy.configure_pursuit_process_budget_mode("unsupported"), "unknown pursuit mode is rejected")
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "contract restores immediate pursuit mode")
	await _test_process_cap_and_catchup()
	await _test_dispatch_macro_batch()
	await _test_fifo_and_stale_lifecycle()
	await _test_runnable_obsolete()
	await _test_optional_budget_preserves_age()
	await _test_frame_fairness_denial()
	await _test_nested_legacy_kinds()
	await _test_necessary_overrun_is_not_ai()
	await _test_new_step_frequency_gate()

func _configure_frame_budget(limit_usec: int) -> void:
	FrameBudget.configure_for_tests(limit_usec, Callable(self, "_engine_process_epoch"), Callable(self, "_clock"))

func _engine_process_epoch() -> int:
	return Engine.get_process_frames()

func _clock() -> int:
	return _clock_usec

func _new_owner(index: int, physics_enabled: bool = true) -> ContractOwner:
	var owner := ContractOwner.new()
	owner.name = "PursuitContractOwner_%02d" % index
	owner.decision_scope = ["body_%02d" % index, index]
	owner.set_physics_process(physics_enabled)
	add_child(owner)
	_owners.append(owner)
	return owner

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _cadence_state(actor: EnemyActor) -> String:
	return str({
		"last_reason": actor._hc_last_reason,
		"target_id": actor.target.get_instance_id() if is_instance_valid(actor.target) else 0,
		"control_time": actor.control_time,
		"stationary": actor.stationary,
		"authority_failed": actor._movement_authority_failed_closed,
		"active_leg": actor._movement_step_active,
		"visual_struck": actor.visual != null and actor.visual.is_struck_action_active(),
		"deadline": actor._new_step_decision_next_time_s,
	})

func _test_process_cap_and_catchup() -> void:
	var owners: Array[ContractOwner] = []
	for index: int in 6:
		owners.append(_new_owner(index))
	await get_tree().process_frame

	var tokens: Array[int] = []
	for owner: ContractOwner in owners:
		var token: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
		if token > 0:
			tokens.append(token)
	_check(tokens.size() == 5, "process epoch grants at most five distinct owners")
	var duplicate: int = Budget.begin_pursuit_turn(owners[0], owners[0].decision_scope, &"new_step")
	_check(duplicate == 0, "same owner and kind cannot catch up-grant twice")
	var second_kind_queued: int = Budget.begin_pursuit_turn(owners[5], owners[5].decision_scope, &"observation")
	_check(second_kind_queued == 0, "queued owner cannot mint a second process lease in the same epoch")
	var snapshot: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(snapshot.get("queue_length", -1)) == 1, "sixth owner remains queued")
	_check(int(snapshot.get("grants", -1)) == 5, "grant count records five admitted owners")
	if not snapshot.queue.is_empty():
		_check(snapshot.queue[0].pending_kinds.size() == 2, "queued observation and new-step kinds coexist")
	var borrowed: int = Budget.pursuit_turn_kind(owners[0], &"observation")
	_check(borrowed < 0, "active pursuit lease lends one legacy observation token")
	_clock_usec = 100
	var before_reset: Dictionary = Budget.pursuit_process_snapshot()
	var frame_before_reset: Dictionary = FrameBudget.snapshot()
	Budget.reset_pursuit_process_diagnostics()
	var after_reset: Dictionary = Budget.pursuit_process_snapshot()
	var frame_after_reset: Dictionary = FrameBudget.snapshot()
	_check(int(after_reset.get("queue_length", -1)) == int(before_reset.get("queue_length", -2)), "diagnostic reset preserves pending queue")
	_check(int(after_reset.get("open_turns", -1)) == int(before_reset.get("open_turns", -2)), "diagnostic reset preserves active leases")
	_check(int(after_reset.get("grants", -1)) == 0, "diagnostic reset clears grant statistics only")
	_check(int(frame_after_reset.get("spent_usec", -1)) == int(frame_before_reset.get("spent_usec", -2)), "diagnostic reset preserves spent frame capacity")
	if borrowed < 0:
		Budget.end(borrowed)
	for reverse_index: int in range(tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(tokens[reverse_index])
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "all process leases close")

	await get_tree().process_frame
	var delayed: int = Budget.begin_pursuit_turn(owners[5], owners[5].decision_scope, &"new_step")
	_check(delayed > 0, "queued owner is serviced after a real process epoch")
	_check(Budget.pursuit_turn_active(owners[5]), "serviced owner exposes active lease")
	Budget.end_pursuit_turn(delayed)

func _test_dispatch_macro_batch() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	Budget.configure_pursuit_dispatch_enabled(true)
	_configure_frame_budget(1000000)
	var owners: Array[ContractOwner] = []
	for index: int in 6:
		var owner: ContractOwner = _new_owner(4000 + index)
		owners.append(owner)
		Budget.enqueue_dispatch(owner, owner.decision_scope, &"new_step")
	await get_tree().process_frame
	var first: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(str(first.get("status", "")) == "SERVICED", "macro dispatcher services a real queued batch")
	_check(int(first.get("grants", -1)) == 5, "macro dispatcher admits at most five distinct owners")
	_check(int(first.get("maintenance_used", -1)) <= 8, "macro dispatcher shares bounded maintenance validation")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_frame_budget_scopes", -1)) == 1, "macro batch opens one optional FrameBudget scope")
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "macro batch closes its outer scope")
	var repeat: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(str(repeat.get("status", "")) == "ALREADY_DISPATCHED", "repeated macro call does not mint another process batch")
	_check(int(repeat.get("grants", -1)) == 0, "repeated macro call grants no additional owner")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_frame_budget_scopes", -1)) == 1, "repeated macro call opens no second optional scope")
	Budget.reset_pursuit_process_diagnostics()
	var reset_same_epoch: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(str(reset_same_epoch.get("status", "")) == "ALREADY_DISPATCHED", "diagnostic reset cannot mint a second batch in the same process epoch")
	_check(int(reset_same_epoch.get("grants", -1)) == 0, "same-epoch diagnostic reset grants no additional owner")
	await get_tree().process_frame
	var next: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(int(next.get("grants", -1)) == 1, "remaining queued owner is served on the next process epoch")
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "next macro batch leaves no orphan scope")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(0)
	var budget_waiter: ContractOwner = _new_owner(4050)
	Budget.enqueue_dispatch(budget_waiter, budget_waiter.decision_scope, &"new_step")
	await get_tree().process_frame
	var budget_before: Dictionary = Budget.pursuit_process_snapshot()
	var budget_before_rows: Array = budget_before.get("dispatch_queue_rows", [])
	var budget_before_row: Dictionary = budget_before_rows[0] if not budget_before_rows.is_empty() else {}
	var budget_denied: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(str(budget_denied.get("status", "")) == "FRAME_DENIED", "macro optional budget denial is explicit")
	_check(FrameBudget.last_denial_reason("monster_pursuit_process") == "budget", "macro denial preserves the shared budget reason")
	var budget_after: Dictionary = Budget.pursuit_process_snapshot()
	var budget_after_rows: Array = budget_after.get("dispatch_queue_rows", [])
	var budget_after_row: Dictionary = budget_after_rows[0] if not budget_after_rows.is_empty() else {}
	_check(int(budget_after.get("dispatch_queue_length", -1)) >= 1, "macro budget denial preserves queue age")
	_check(int(budget_after_row.get("queued_process_epoch", -1)) == int(budget_before_row.get("queued_process_epoch", -2)), "budget denial preserves the original queued epoch")
	_check(int(budget_after.get("dispatch_denied_budget", -1)) >= 1, "budget denial increments the dispatch denial counter")
	_configure_frame_budget(1000000)
	FrameBudget.mark_pending("older_macro_blocker", true, true, false, null, false)
	var fairness_waiter: ContractOwner = _new_owner(4060)
	Budget.enqueue_dispatch(fairness_waiter, fairness_waiter.decision_scope, &"new_step")
	await get_tree().process_frame
	var fairness_denied: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(str(fairness_denied.get("status", "")) == "FRAME_DENIED", "macro fairness denial does not bypass an older resource category")
	_check(FrameBudget.last_denial_reason("monster_pursuit_process") == "fairness", "macro fairness reason remains observable")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_denied_fairness", -1)) >= 1, "macro fairness denial increments its dedicated counter")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var invalidated: ContractOwner = _new_owner(4100)
	invalidated.invalidate_on_dispatch = true
	Budget.enqueue_dispatch(invalidated, invalidated.decision_scope, &"new_step")
	await get_tree().process_frame
	var invalid_result: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(int(invalid_result.get("grants", -1)) == 0, "callback invalidation grants no pursuit turn")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_post_invalid", -1)) >= 1, "callback invalidation stops with post-invalid evidence")
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "callback invalidation closes the batch scope")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var consumed_then_invalid: ContractOwner = _new_owner(4101)
	consumed_then_invalid.invalidate_after_consume = true
	var after_invalid: ContractOwner = _new_owner(4102)
	Budget.enqueue_dispatch(consumed_then_invalid, consumed_then_invalid.decision_scope, &"new_step")
	Budget.enqueue_dispatch(after_invalid, after_invalid.decision_scope, &"new_step")
	await get_tree().process_frame
	var consumed_invalid_result: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(consumed_then_invalid.consume_token != 0, "callback consumes its dispatch lease before invalidation")
	_check(consumed_then_invalid.second_consume_token == 0, "a dispatch lease cannot be consumed twice")
	_check(after_invalid.dispatch_calls == 0, "post-consume scope invalidation stops the following owner")
	_check(int(consumed_invalid_result.get("grants", -1)) == 1, "post-consume invalidation does not refund the consumed lease")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_queue_length", -1)) >= 1, "post-consume invalidation preserves the following queued owner")
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "explicit callback lease close leaves no orphan scope")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var old_scope: ContractOwner = _new_owner(4103)
	var old_scope_next: ContractOwner = _new_owner(4104)
	Budget.enqueue_dispatch(old_scope, old_scope.decision_scope, &"observation")
	Budget.enqueue_dispatch(old_scope, old_scope.decision_scope, &"new_step")
	Budget.enqueue_dispatch(old_scope_next, old_scope_next.decision_scope, &"new_step")
	old_scope.decision_scope = ["retired_all_kinds", 4103]
	await get_tree().process_frame
	var old_scope_result: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(int(old_scope_result.get("grants", -1)) == 1, "scope retirement still services the next valid owner")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_queue_length", -1)) == 0, "scope retirement removes every queued kind for the old owner")
	# Lifecycle ordering is exercised through the real dispatch queue. The first
	# tail has physics processing disabled while can_process remains true; it is
	# retired and must not block the following queue work.
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var dispatch_head: ContractOwner = _new_owner(4110)
	var disabled_behind: ContractOwner = _new_owner(4111, false)
	Budget.enqueue_dispatch(dispatch_head, dispatch_head.decision_scope, &"new_step")
	Budget.enqueue_dispatch(disabled_behind, disabled_behind.decision_scope, &"new_step")
	await get_tree().process_frame
	var fifo_result: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(int(fifo_result.get("grants", -1)) == 1, "dispatch FIFO serves the valid head before a physics-disabled entry")
	_check(disabled_behind.dispatch_calls == 0, "physics-disabled entry is retired without invoking its callback")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_queue_length", -1)) == 0, "physics-disabled tail is retired in the same bounded batch")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var enabled_pending: ContractOwner = _new_owner(4112, true)
	Budget.bind_pursuit_dispatch_process_owner(self)
	Budget.enqueue_dispatch(enabled_pending, enabled_pending.decision_scope, &"new_step")
	var enabled_pending_frame: Dictionary = FrameBudget.snapshot()
	var enabled_pending_rows: Dictionary = enabled_pending_frame.get("pending", {})
	_check(enabled_pending_rows.has("monster_pursuit_process"), "nonempty dispatch queue registers its FrameBudget category")
	var enabled_pending_record: Dictionary = enabled_pending_rows.get("monster_pursuit_process", {})
	_check(enabled_pending_record.has("runnable") and bool(enabled_pending_record.get("runnable", false)), "enabled dispatch root publishes a runnable pending witness")
	var disabled_dispatch_root := Node.new()
	disabled_dispatch_root.name = "DisabledDispatchRoot"
	add_child(disabled_dispatch_root)
	disabled_dispatch_root.set_process(false)
	Budget.bind_pursuit_dispatch_process_owner(disabled_dispatch_root)
	var disabled_root_frame: Dictionary = FrameBudget.snapshot()
	var disabled_root_rows: Dictionary = disabled_root_frame.get("pending", {})
	_check(disabled_root_rows.has("monster_pursuit_process"), "binding a disabled dispatch root keeps the pending category registered")
	var disabled_root_record: Dictionary = disabled_root_rows.get("monster_pursuit_process", {})
	_check(disabled_root_record.has("runnable") and not bool(disabled_root_record.get("runnable", true)), "disabled dispatch root publishes a non-runnable witness")
	var other_category_token: int = FrameBudget.begin("another_category", false)
	_check(other_category_token > 0, "a disabled dispatch root does not fairness-block another category")
	if other_category_token > 0:
		FrameBudget.end(other_category_token)
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_queue_length", -1)) == 1, "disabled dispatch root test does not delete the pending business request")
	Budget.bind_pursuit_dispatch_process_owner(self)
	disabled_dispatch_root.queue_free()
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var scope_stale: ContractOwner = _new_owner(4120)
	var scope_valid: ContractOwner = _new_owner(4121)
	Budget.enqueue_dispatch(scope_stale, scope_stale.decision_scope, &"new_step")
	Budget.enqueue_dispatch(scope_valid, scope_valid.decision_scope, &"new_step")
	scope_stale.decision_scope = ["retired", 4120]
	await get_tree().process_frame
	var scope_result: Dictionary = Budget.dispatch_pursuit_process_batch()
	_check(int(scope_result.get("grants", -1)) == 1, "scope-invalidated dispatch entry is retired before the next valid owner")
	_check(int(Budget.pursuit_process_snapshot().get("dispatch_queue_length", -1)) == 0, "scope invalidation does not leave an orphan dispatch request")
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	Budget.configure_pursuit_dispatch_enabled(false)

func _test_fifo_and_stale_lifecycle() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var owners: Array[ContractOwner] = []
	for index: int in 30:
		owners.append(_new_owner(100 + index))
	await get_tree().process_frame
	var first_batch: Array[int] = []
	for owner: ContractOwner in owners:
		var token: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"observation")
		if token > 0:
			first_batch.append(token)
	_check(first_batch.size() == 5, "thirty-owner process admits only first five")
	var queued: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(queued.get("queue_length", -1)) == 25, "thirty-owner backlog retains twenty-five requests")
	_check(int(queued.get("maintenance_used", -1)) <= 8, "maintenance validation shares the eight-call process cap")
	var maintenance_before_reset: int = int(queued.get("maintenance_used", -1))
	Budget.reset_pursuit_process_diagnostics()
	var maintenance_after_reset: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(maintenance_after_reset.get("maintenance_used", -1)) == maintenance_before_reset, "diagnostic reset does not replenish maintenance quota")
	var rows: Array = queued.get("queue", [])
	_check(rows.size() == 25, "FIFO snapshot has every waiting owner")
	if rows.size() == 25:
		_check(int(rows[0].owner_id) == owners[5].get_instance_id(), "FIFO starts with sixth owner")
	for reverse_index: int in range(first_batch.size() - 1, -1, -1):
		Budget.end_pursuit_turn(first_batch[reverse_index])

	# A changed scope keeps the request identity and age but must be validated
	# against the current witness before service.
	owners[5].decision_scope = ["body_changed", 105]
	await get_tree().process_frame
	var refreshed: int = Budget.begin_pursuit_turn(owners[5], owners[5].decision_scope, &"observation")
	_check(refreshed > 0, "queued owner with refreshed scope is serviceable")
	Budget.end_pursuit_turn(refreshed)

	# Isolate stale-owner checks from the thirty-owner backlog. First retain a
	# valid FIFO head as the negative control, with a disabled entry behind it.
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var valid_head: ContractOwner = _new_owner(900)
	var disabled_behind: ContractOwner = _new_owner(999, false)
	await get_tree().process_frame
	var filler: Array[int] = []
	for index: int in 5:
		var filler_owner: ContractOwner = _new_owner(910 + index)
		var token: int = Budget.begin_pursuit_turn(filler_owner, filler_owner.decision_scope, &"new_step")
		if token > 0:
			filler.append(token)
	var valid_head_request: int = Budget.begin_pursuit_turn(valid_head, valid_head.decision_scope, &"new_step")
	var disabled_behind_request: int = Budget.begin_pursuit_turn(disabled_behind, disabled_behind.decision_scope, &"new_step")
	_check(valid_head_request == 0 and disabled_behind_request == 0, "valid and disabled owners remain queued behind cap")
	for reverse_index: int in range(filler.size() - 1, -1, -1):
		Budget.end_pursuit_turn(filler[reverse_index])
	await get_tree().process_frame
	var valid_head_token: int = Budget.begin_pursuit_turn(valid_head, valid_head.decision_scope, &"new_step")
	_check(valid_head_token > 0, "valid FIFO head remains ahead of disabled entry")
	if valid_head_token > 0:
		Budget.end_pursuit_turn(valid_head_token)

	# Now make the disabled entry the actual queue head and prove it is pruned.
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var disabled: ContractOwner = _new_owner(1000, false)
	await get_tree().process_frame
	var disabled_tokens: Array[int] = []
	for index: int in 5:
		var filler_owner: ContractOwner = _new_owner(1010 + index)
		var token: int = Budget.begin_pursuit_turn(filler_owner, filler_owner.decision_scope, &"new_step")
		if token > 0:
			disabled_tokens.append(token)
	var disabled_request: int = Budget.begin_pursuit_turn(disabled, disabled.decision_scope, &"new_step")
	_check(disabled_request == 0, "disabled head waits without consuming a grant")
	for reverse_index: int in range(disabled_tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(disabled_tokens[reverse_index])
	await get_tree().process_frame
	var valid_after_disabled: ContractOwner = _new_owner(1099)
	var valid_after_disabled_token: int = Budget.begin_pursuit_turn(valid_after_disabled, valid_after_disabled.decision_scope, &"new_step")
	_check(valid_after_disabled_token > 0, "disabled queued head is pruned before valid service")
	if valid_after_disabled_token > 0:
		Budget.end_pursuit_turn(valid_after_disabled_token)

	# Cancellation and destruction remove stale queue entries without refunding
	# already admitted work.
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var cancel_owner: ContractOwner = _new_owner(1000)
	await get_tree().process_frame
	for owner: ContractOwner in owners.slice(0, 5):
		var token: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"observation")
		if token > 0:
			Budget.end_pursuit_turn(token)
	var canceled: int = Budget.begin_pursuit_turn(cancel_owner, cancel_owner.decision_scope, &"observation")
	_check(canceled == 0, "queued cancellation candidate is not admitted past cap")
	Budget.cancel(cancel_owner.get_instance_id())
	cancel_owner.queue_free()
	await get_tree().process_frame
	var after_cancel: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(after_cancel.get("open_turns", -1)) == 0, "cancel and destruction leave no open pursuit lease")

	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	var dead: ContractOwner = _new_owner(1100)
	var blockers: Array[ContractOwner] = []
	for index: int in 5:
		blockers.append(_new_owner(1110 + index))
	await get_tree().process_frame
	var blocker_tokens: Array[int] = []
	for owner: ContractOwner in blockers:
		var token: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"observation")
		if token > 0:
			blocker_tokens.append(token)
	var dead_request: int = Budget.begin_pursuit_turn(dead, dead.decision_scope, &"observation")
	_check(dead_request == 0, "destruction candidate remains a queued request")
	for reverse_index: int in range(blocker_tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(blocker_tokens[reverse_index])
	dead.queue_free()
	await get_tree().process_frame
	var survivor: ContractOwner = _new_owner(1200)
	var survivor_token: int = Budget.begin_pursuit_turn(survivor, survivor.decision_scope, &"observation")
	_check(survivor_token > 0, "destroyed queued owner does not block the next owner")
	if survivor_token > 0:
		Budget.end_pursuit_turn(survivor_token)

func _test_runnable_obsolete() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var owner: ContractOwner = _new_owner(1300)
	owner.runnable_kinds[&"new_step"] = false
	await get_tree().process_frame
	var immediate_denial: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(immediate_denial == 0, "non-runnable kind is denied before reserving a slot")
	_check(Budget.pursuit_process_last_denial() == "UNRUNNABLE", "non-runnable denial is classified explicitly")

	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	owner.runnable_kinds[&"new_step"] = true
	var blockers: Array[ContractOwner] = []
	await get_tree().process_frame
	var tokens: Array[int] = []
	for index: int in 5:
		var blocker: ContractOwner = _new_owner(1310 + index)
		blockers.append(blocker)
		var token: int = Budget.begin_pursuit_turn(blocker, blocker.decision_scope, &"observation")
		if token > 0:
			tokens.append(token)
	var queued: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(queued == 0, "runnable request waits behind the process cap")
	owner.runnable_kinds[&"new_step"] = false
	for reverse_index: int in range(tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(tokens[reverse_index])
	await get_tree().process_frame
	var survivor: ContractOwner = _new_owner(1399)
	var survivor_token: int = Budget.begin_pursuit_turn(survivor, survivor.decision_scope, &"observation")
	_check(survivor_token > 0, "obsolete non-runnable request is retired before valid service")
	if survivor_token > 0:
		Budget.end_pursuit_turn(survivor_token)
	var obsolete_snapshot: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(obsolete_snapshot.get("cancel_reasons", {}).get("not_serviceable", 0)) >= 1, "obsolete retirement records not_serviceable reason")

func _test_optional_budget_preserves_age() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(0)
	var owner: ContractOwner = _new_owner(2000)
	await get_tree().process_frame
	var denied: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(denied == 0, "optional pursuit turn is denied when frame budget is exhausted")
	_check(FrameBudget.last_denial_reason("monster_pursuit_process") == "budget", "frame denial exposes the budget reason")
	var waiting: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(waiting.get("queue_length", -1)) == 1, "optional denial keeps FIFO request queued")
	var frame_waiting: Dictionary = FrameBudget.snapshot()
	_check(frame_waiting.pending.has("monster_pursuit_process"), "optional denial marks the real pursuit category pending")
	var before_age: int = int(waiting.queue[0].wait_processes) if not waiting.queue.is_empty() else -1
	await get_tree().process_frame
	_configure_frame_budget(1000000)
	var granted: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(granted > 0, "queued optional pursuit turn retries after budget recovery")
	var after: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(after.get("max_wait_processes", -1)) >= before_age, "budget denial preserves request age")
	if granted > 0:
		Budget.end_pursuit_turn(granted)
	var spent_before_cancel: int = int(FrameBudget.snapshot().get("spent_usec", -1))
	Budget.cancel(owner.get_instance_id())
	_check(int(FrameBudget.snapshot().get("spent_usec", -2)) == spent_before_cancel, "cancel does not refund spent optional capacity")

func _test_frame_fairness_denial() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	FrameBudget.mark_pending("older_contract_category", true, true, false, null, false)
	var owner: ContractOwner = _new_owner(2500)
	await get_tree().process_frame
	var token: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(token == 0, "older pending FrameBudget category blocks optional pursuit fairly")
	_check(FrameBudget.last_denial_reason("monster_pursuit_process") == "fairness", "FrameBudget distinguishes fairness from budget exhaustion")
	if token > 0:
		Budget.end_pursuit_turn(token)

func _test_nested_legacy_kinds() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var owner: ContractOwner = _new_owner(3000)
	var blockers: Array[ContractOwner] = []
	await get_tree().process_frame
	var blocker_tokens: Array[int] = []
	for index: int in 5:
		var blocker: ContractOwner = _new_owner(3010 + index)
		blockers.append(blocker)
		var blocker_token: int = Budget.begin_pursuit_turn(blocker, blocker.decision_scope, &"observation")
		if blocker_token > 0:
			blocker_tokens.append(blocker_token)
	var queued_new_step: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(queued_new_step == 0, "nested-process owner starts with a queued new-step request")
	for reverse_index: int in range(blocker_tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(blocker_tokens[reverse_index])
	await get_tree().process_frame
	var outer: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"observation")
	_check(outer > 0, "observation creates one outer pursuit lease")
	if outer <= 0:
		return
	var second_outer: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(second_outer == 0, "active owner cannot open a second process lease in one epoch")
	if second_outer > 0:
		Budget.end_pursuit_turn(second_outer)
	var mismatched_nested: int = Budget.borrow_pursuit_turn(owner, ["wrong_scope"], &"nested_process_kind")
	_check(mismatched_nested == 0, "nested borrow rejects a mismatched scope")
	var nested: int = Budget.borrow_pursuit_turn(owner, owner.decision_scope, &"nested_process_new_step")
	var nested_again: int = Budget.borrow_pursuit_turn(owner, owner.decision_scope, &"nested_process_new_step")
	_check(nested < 0 and nested_again == 0, "nested process kind is borrowed once")
	var observation: int = Budget.begin(owner, owner.decision_scope, &"observation")
	var observation_again: int = Budget.begin(owner, owner.decision_scope, &"observation")
	var neighbor: int = Budget.begin(owner, owner.decision_scope, &"neighbor")
	var neighbor_again: int = Budget.begin(owner, owner.decision_scope, &"neighbor")
	_check(observation < 0 and neighbor < 0, "legacy kinds borrow the active pursuit lease")
	_check(observation_again == 0 and neighbor_again == 0, "each legacy kind is admitted once")
	Budget.end_pursuit_turn(neighbor)
	Budget.end_pursuit_turn(observation)
	if nested < 0:
		Budget.end_pursuit_turn(nested)
	Budget.end_pursuit_turn(outer)
	_check(int(Budget.pursuit_process_snapshot().get("nested_served", -1)) == 1, "nested process borrow retires its matching pending kind on close")
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "nested borrowed kinds close with outer lease")
	_check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "nested borrowed kinds do not open a second frame scope")

func _test_necessary_overrun_is_not_ai() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_clock_usec = 0
	_configure_frame_budget(1)
	var grants_before: int = int(Budget.pursuit_process_snapshot().get("grants", -1))
	var necessary: int = FrameBudget.begin("contract_necessary", true)
	_check(necessary > 0, "necessary scope remains admissible after optional budget exhaustion")
	_clock_usec = 100
	FrameBudget.end(necessary)
	var frame_snapshot: Dictionary = FrameBudget.snapshot()
	_check(int(frame_snapshot.get("overrun_usec", 0)) > 0, "necessary overrun is retained by frame budget")
	var pursuit_snapshot: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(pursuit_snapshot.get("grants", -1)) == grants_before, "necessary overrun does not manufacture an AI grant")

func _test_new_step_frequency_gate() -> void:
	Budget.reset_pursuit_process_state()
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "cadence contract uses immediate process budget")
	_check(Enemy.configure_new_step_decision_interval_for_test(200), "200 ms new-step interval is accepted")
	var victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(20.0, 0.0))
	var blocked_context: Dictionary = RuntimeFixture.polygon_context([[[0, 0], [16, 0], [16, 16], [0, 16]]], 0.5)
	_check(not blocked_context.is_empty(), "blocked terrain fixture is valid and cannot silently fall back to open context")
	var actor: EnemyActor = RuntimeFixture.enemy(self, 64, Vector2(8.0, 8.0), victim, blocked_context)
	if actor.visual != null:
		actor.visual.advance_struck_action(5.0)
	actor._hc_owned_movement_call = true
	actor._combat_action_time_s = 0.0
	var attempts_before: int = int(Enemy.pursuit_process_budget_diagnostics().get("new_step_attempts", 0))
	var fails_before: int = int(Enemy.pursuit_process_budget_diagnostics().get("new_step_fail", 0))
	var first: bool = actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim)
	var first_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(not first, "blocked terrain makes the first due pursuit attempt fail at the actual entry")
	_check(int(first_diagnostics.get("new_step_attempts", 0)) == attempts_before + 1, "failed first attempt still consumes one due attempt")
	_check(int(first_diagnostics.get("new_step_fail", 0)) == fails_before + 1, "failed first attempt records the production failure")
	var first_deadline: float = actor._new_step_decision_next_time_s
	_check(first_deadline >= 0.199 and first_deadline <= 0.201, "first attempt consumes a 200 ms owner-clock deadline")
	actor._clear_autonomous_step_state()
	actor._combat_action_time_s = 0.199
	var early: bool = actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim)
	var early_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(not early, "199 ms pursuit attempt is held by the owner-clock gate")
	_check(int(early_diagnostics.get("new_step_due_wait", 0)) >= 1, "not-due attempt records due wait")
	_check(int(early_diagnostics.get("new_step_attempts", 0)) == int(first_diagnostics.get("new_step_attempts", 0)), "not-due attempt does not enter terrain or planning")
	_check(is_equal_approx(actor._new_step_decision_next_time_s, first_deadline), "not-due attempt does not move the deadline")
	actor._combat_action_time_s = 0.2
	var exact: bool = actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim)
	var exact_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(not exact, "exact due blocked attempt reaches the real planning failure")
	_check(int(exact_diagnostics.get("new_step_attempts", 0)) == int(first_diagnostics.get("new_step_attempts", 0)) + 1, "exact due time resumes one attempt")
	actor._clear_autonomous_step_state()
	actor._combat_action_time_s = 0.75
	var late: bool = actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", victim)
	var late_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(not late, "late blocked attempt fails once without catch-up")
	_check(int(late_diagnostics.get("new_step_attempts", 0)) == int(exact_diagnostics.get("new_step_attempts", 0)) + 1, "late attempt resumes once without catch-up minting")
	_check(actor._new_step_decision_next_time_s >= 0.949 and actor._new_step_decision_next_time_s <= 0.951, "late attempt schedules one next owner-clock deadline")
	RuntimeFixture.dispose(actor, victim)

	var open_victim: PlayerCharacter = RuntimeFixture.player(self, Vector2(14.0, 8.0))
	var open_actor: EnemyActor = RuntimeFixture.enemy(self, 64, Vector2(8.0, 8.0), open_victim)
	if open_actor.visual != null:
		open_actor.visual.advance_struck_action(5.0)
	await get_tree().process_frame
	open_actor._hc_owned_movement_call = true
	open_actor._combat_action_time_s = 0.0
	var open_started: bool = open_actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", open_victim)
	_check(open_started and open_actor._movement_step_active, "open fixture creates an actual active movement leg state=" + _cadence_state(open_actor))
	var position_before_active: Vector2 = open_actor.global_position
	var active_deadline: float = open_actor._new_step_decision_next_time_s
	open_actor._physics_process_internal(0.05)
	_check(open_actor.global_position.distance_to(position_before_active) > 0.000001, "active leg advances through the real physics entry state=" + _cadence_state(open_actor))
	_check(is_equal_approx(open_actor._new_step_decision_next_time_s, active_deadline), "active leg physics does not reset the source cooldown deadline")
	open_actor._combat_action_time_s = 0.05
	var active_leg: bool = open_actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", open_victim)
	_check(not active_leg and is_equal_approx(open_actor._new_step_decision_next_time_s, active_deadline), "active leg bypasses cadence without freezing or resetting it state=" + _cadence_state(open_actor))
	open_actor._clear_autonomous_step_state()
	open_actor._combat_action_time_s = 0.05
	var non_pursuit_before: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	var non_pursuit: bool = open_actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"direction_probe", open_victim)
	var non_pursuit_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(int(non_pursuit_diagnostics.get("new_step_due_wait", 0)) == int(late_diagnostics.get("new_step_due_wait", 0)), "non-pursuit path bypasses the new-step cadence")
	_check(int(non_pursuit_diagnostics.get("new_step_attempts", 0)) == int(non_pursuit_before.get("new_step_attempts", 0)) and (non_pursuit or open_actor._movement_step_active), "non-pursuit exception reaches its actual entry without minting a cadence attempt state=" + _cadence_state(open_actor))
	open_actor._clear_autonomous_step_state()
	open_actor.is_boss = true
	open_actor._combat_action_time_s = 0.05
	var boss_before: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	var boss: bool = open_actor._begin_autonomous_step_without_cadence(Vector2.RIGHT, 1.0, false, &"pursuit", open_victim)
	var boss_diagnostics: Dictionary = Enemy.pursuit_process_budget_diagnostics()
	_check(int(boss_diagnostics.get("new_step_due_wait", 0)) == int(late_diagnostics.get("new_step_due_wait", 0)), "boss pursuit bypasses the ordinary new-step cadence")
	_check(int(boss_diagnostics.get("new_step_attempts", 0)) == int(boss_before.get("new_step_attempts", 0)) and (boss or open_actor._movement_step_active), "boss exception reaches its actual entry without minting a cadence attempt state=" + _cadence_state(open_actor))
	open_actor.is_boss = false
	RuntimeFixture.dispose(open_actor, open_victim)
	_check(Enemy.configure_new_step_decision_interval_for_test(0), "cadence contract restores uncapped interval")

func _cleanup() -> void:
	if int(FrameBudget.snapshot().get("open_scopes", 0)) != 0:
		FrameBudget.reset_test_configuration()
	FrameBudget.reset_test_configuration()
	for owner: Node in _owners:
		if is_instance_valid(owner):
			owner.queue_free()
	_clock_usec = 0
