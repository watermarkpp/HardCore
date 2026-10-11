extends Node
const B := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const D := preload("res://scripts/monster_ai_package/decision_budget.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failed := 0
var now_us := 100
var epoch := 1
class Owner extends Node:
	var generation := 1
	var runnable := true
	func _hc_pursuit_budget_scope() -> Array:
		return [get_instance_id(), generation]
	func _hc_pursuit_budget_kind_runnable(_kind: StringName) -> bool:
		return runnable
func check(ok: bool, message: String) -> void:
	proof.record(ok, message)
	if not ok:
		failed += 1
		print("CHECK_FAILED ", message)
func configure(progress := 600) -> void:
	epoch += 1
	B.configure_for_tests(100, func() -> int: return epoch, func() -> int: return now_us)
	B.configure_progress_for_tests(progress)
func close(token: int, cost: int) -> void:
	check(token > 0, "expected synchronous scope is admitted")
	if token > 0:
		now_us += cost
		B.end(token)
func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	configure()
	B.mark_pending("old_background", true)
	B.mark_progress_pending("pursuit", true)
	var p := B.begin_progress("pursuit")
	check(p > 0, "a real pending gameplay category does not yield to an older background category")
	if p > 0:
		now_us += 10
		var necessary := B.begin("damage", true)
		now_us += 40
		check(B.remaining_progress_usec() == 590, "in-flight necessary child does not double-charge its progress parent")
		B.end(necessary)
		close(B.begin("old_background"), 20)
		now_us += 10
		B.end(p)
	var snapshot := B.snapshot()
	check(snapshot.spent_usec == 80 and snapshot.progress_spent_usec == 20 and snapshot.necessary_spent_usec == 40 and snapshot.background_spent_usec == 20, "mixed nested lanes reconcile exactly with the full inclusive ledger")
	check(B.remaining_progress_usec() == 580 and B.remaining_usec() == 80, "completed mixed children retain independent correct allowances")
	configure()
	var background := B.begin("background")
	now_us += 5
	close(B.begin_progress("nested_progress"), 30)
	now_us += 5
	B.end(background)
	snapshot = B.snapshot()
	check(snapshot.spent_usec == 40 and snapshot.progress_spent_usec == 30 and snapshot.background_spent_usec == 10, "reverse cross-lane nesting charges each exclusive segment once")
	configure()
	B.mark_pending("background", true)
	B.mark_progress_pending("path", true)
	B.mark_progress_pending("pursuit", true)
	check(B.begin_progress("pursuit") == 0, "two gameplay services preserve oldest-first fairness inside their own lane")
	close(B.begin("background"), 10)
	close(B.begin_progress("path"), 10)
	close(B.begin_progress("pursuit"), 10)
	check(B.remaining_progress_usec() == 580 and B.remaining_usec() == 90, "background remains serviceable while gameplay categories arbitrate")
	D.reset_pursuit_process_state()
	configure(0)
	var owners: Array[Owner] = []
	for i: int in 9:
		var owner := Owner.new()
		add_child(owner)
		owner.set_physics_process(true)
		owners.append(owner)
		check(D.begin_pursuit_turn(owner, owner._hc_pursuit_budget_scope(), &"new_step") == 0, "zero allowance queues without granting movement")
	owners[0].free()
	owners[1].free()
	owners[2].runnable = false
	await get_tree().process_frame
	configure()
	check(D.begin_pursuit_turn(owners[8], owners[8]._hc_pursuit_budget_scope(), &"new_step") == 0, "newer owner cannot overtake the oldest five runnable reservations")
	var served := 0
	for i: int in range(7, 2, -1):
		var owner := owners[i]
		var token := D.begin_pursuit_turn(owner, owner._hc_pursuit_budget_scope(), &"new_step")
		if token != 0:
			now_us += 10
			D.end_pursuit_turn(token)
			served += 1
	check(served == 5, "dead and unrunnable heads do not waste the bounded live batch")
	check(D.begin_pursuit_turn(owners[8], owners[8]._hc_pursuit_budget_scope(), &"new_step") == 0, "five completed owners do not refund same-epoch admission")
	await get_tree().process_frame
	epoch += 1
	var tail := D.begin_pursuit_turn(owners[8], owners[8]._hc_pursuit_budget_scope(), &"new_step")
	check(tail > 0, "the next oldest owner is serviceable next epoch without a timer reset")
	if tail > 0: D.end_pursuit_turn(tail)
	for owner: Owner in owners:
		if is_instance_valid(owner):
			D.cancel(owner.get_instance_id())
			owner.free()
	D.reset_pursuit_process_state()
	check(B.snapshot().open_scopes == 0 and D.pursuit_process_snapshot().open_turns == 0, "all scopes and leases close before returning")
	B.reset_test_configuration()
	var ok := proof.write_receipt("v111_progress_edges_test", proof.records.size(), failed)
	print("V111_PROGRESS_EDGES_%s checks=%d failed=%d" % ["PASS" if ok else "FAIL", proof.records.size(), failed])
	get_tree().quit(0 if ok else 1)
