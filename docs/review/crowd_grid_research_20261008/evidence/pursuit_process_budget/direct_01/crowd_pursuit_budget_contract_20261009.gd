extends Node

const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Enemy := preload("res://scripts/enemy.gd")

class ContractOwner extends Node:
	var decision_scope: Array = []

	func _hc_pursuit_budget_scope() -> Array:
		return decision_scope.duplicate()

var _failures: Array[String] = []
var _clock_usec: int = 0
var _owners: Array[Node] = []

func _ready() -> void:
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
	Budget.reset_pursuit_process_diagnostics()
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "immediate pursuit mode is accepted")
	_check(Enemy.configure_pursuit_process_budget_mode("budgeted"), "budgeted pursuit mode is accepted")
	_check(not Enemy.configure_pursuit_process_budget_mode("unsupported"), "unknown pursuit mode is rejected")
	_check(Enemy.configure_pursuit_process_budget_mode("immediate"), "contract restores immediate pursuit mode")
	await _test_process_cap_and_catchup()
	await _test_fifo_and_stale_lifecycle()
	await _test_optional_budget_preserves_age()
	await _test_nested_legacy_kinds()
	await _test_necessary_overrun_is_not_ai()

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

func _test_process_cap_and_catchup() -> void:
	Budget.reset_pursuit_process_diagnostics()
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
	var snapshot: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(snapshot.get("queue_length", -1)) == 1, "sixth owner remains queued")
	_check(int(snapshot.get("grants", -1)) == 5, "grant count records five admitted owners")
	for reverse_index: int in range(tokens.size() - 1, -1, -1):
		Budget.end_pursuit_turn(tokens[reverse_index])
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "all process leases close")

	await get_tree().process_frame
	var delayed: int = Budget.begin_pursuit_turn(owners[5], owners[5].decision_scope, &"new_step")
	_check(delayed > 0, "queued owner is serviced after a real process epoch")
	_check(Budget.pursuit_turn_active(owners[5]), "serviced owner exposes active lease")
	Budget.end_pursuit_turn(delayed)

func _test_fifo_and_stale_lifecycle() -> void:
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

	# A disabled queued owner is pruned and cannot block the next valid owner.
	var disabled: ContractOwner = _new_owner(999, false)
	await get_tree().process_frame
	var filler: Array[int] = []
	for index: int in 5:
		var token: int = Budget.begin_pursuit_turn(owners[index], owners[index].decision_scope, &"new_step")
		if token > 0:
			filler.append(token)
	var disabled_request: int = Budget.begin_pursuit_turn(disabled, disabled.decision_scope, &"new_step")
	_check(disabled_request == 0, "disabled owner waits without consuming a grant")
	for reverse_index: int in range(filler.size() - 1, -1, -1):
		Budget.end_pursuit_turn(filler[reverse_index])
	await get_tree().process_frame
	var valid_after_disabled: int = Budget.begin_pursuit_turn(owners[0], owners[0].decision_scope, &"new_step")
	_check(valid_after_disabled > 0, "disabled queued owner does not block valid FIFO service")
	Budget.end_pursuit_turn(valid_after_disabled)

	# Cancellation and destruction remove stale queue entries without refunding
	# already admitted work.
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

func _test_optional_budget_preserves_age() -> void:
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(0)
	var owner: ContractOwner = _new_owner(2000)
	await get_tree().process_frame
	var denied: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(denied == 0, "optional pursuit turn is denied when frame budget is exhausted")
	var waiting: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(waiting.get("queue_length", -1)) == 1, "optional denial keeps FIFO request queued")
	var before_age: int = int(waiting.queue[0].wait_processes) if not waiting.queue.is_empty() else -1
	await get_tree().process_frame
	_configure_frame_budget(1000000)
	var granted: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(granted > 0, "queued optional pursuit turn retries after budget recovery")
	var after: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(after.get("max_wait_processes", -1)) >= before_age, "budget denial preserves request age")
	if granted > 0:
		Budget.end_pursuit_turn(granted)

func _test_nested_legacy_kinds() -> void:
	Budget.reset_pursuit_process_diagnostics()
	_configure_frame_budget(1000000)
	var owner: ContractOwner = _new_owner(3000)
	await get_tree().process_frame
	var outer: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"observation")
	_check(outer > 0, "observation creates one outer pursuit lease")
	if outer <= 0:
		return
	var second_outer: int = Budget.begin_pursuit_turn(owner, owner.decision_scope, &"new_step")
	_check(second_outer == 0, "active owner cannot open a second process lease in one epoch")
	if second_outer > 0:
		Budget.end_pursuit_turn(second_outer)
	var observation: int = Budget.begin(owner, owner.decision_scope, &"observation")
	var observation_again: int = Budget.begin(owner, owner.decision_scope, &"observation")
	var neighbor: int = Budget.begin(owner, owner.decision_scope, &"neighbor")
	var neighbor_again: int = Budget.begin(owner, owner.decision_scope, &"neighbor")
	_check(observation < 0 and neighbor < 0, "legacy kinds borrow the active pursuit lease")
	_check(observation_again == 0 and neighbor_again == 0, "each legacy kind is admitted once")
	Budget.end(neighbor)
	Budget.end(observation)
	Budget.end_pursuit_turn(outer)
	_check(int(Budget.pursuit_process_snapshot().get("open_turns", -1)) == 0, "nested borrowed kinds close with outer lease")
	_check(int(FrameBudget.snapshot().get("open_scopes", -1)) == 0, "nested borrowed kinds do not open a second frame scope")

func _test_necessary_overrun_is_not_ai() -> void:
	Budget.reset_pursuit_process_diagnostics()
	_clock_usec = 0
	_configure_frame_budget(1)
	var necessary: int = FrameBudget.begin("contract_necessary", true)
	_check(necessary > 0, "necessary scope remains admissible after optional budget exhaustion")
	_clock_usec = 100
	FrameBudget.end(necessary)
	var frame_snapshot: Dictionary = FrameBudget.snapshot()
	_check(int(frame_snapshot.get("overrun_usec", 0)) > 0, "necessary overrun is retained by frame budget")
	var pursuit_snapshot: Dictionary = Budget.pursuit_process_snapshot()
	_check(int(pursuit_snapshot.get("grants", -1)) == 0, "necessary overrun does not manufacture an AI grant")

func _cleanup() -> void:
	if int(Budget.pursuit_process_snapshot().get("open_turns", 0)) != 0:
		Budget.reset_pursuit_process_diagnostics()
	if int(FrameBudget.snapshot().get("open_scopes", 0)) != 0:
		FrameBudget.reset_test_configuration()
	FrameBudget.reset_test_configuration()
	for owner: Node in _owners:
		if is_instance_valid(owner):
			owner.queue_free()
	_clock_usec = 0
