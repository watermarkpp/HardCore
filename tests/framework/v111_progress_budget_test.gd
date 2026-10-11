extends Node
const B := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const D := preload("res://scripts/monster_ai_package/decision_budget.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var budget_api: RefCounted = B.new()
var failures := 0
var now_us := 100
var epoch := 1
class Owner extends Node:
	func _hc_pursuit_budget_scope() -> Array:
		return ["v111_ready_batch", get_instance_id()]
	func _hc_pursuit_budget_kind_runnable(_kind: StringName) -> bool:
		return true
func check(ok: bool, message: String) -> void:
	proof.record(ok, message)
	if not ok:
		failures += 1
		print("CHECK_FAILED ", message)
func configure(bg: int, progress: int) -> void:
	B.configure_for_tests(bg, func() -> int: return epoch, func() -> int: return now_us)
	if budget_api.has_method("configure_progress_for_tests"):
		budget_api.call("configure_progress_for_tests", progress)
func begin_progress(name: String) -> int:
	if budget_api.has_method("begin_progress"):
		return int(budget_api.call("begin_progress", name))
	return B.begin(name)
func remaining_progress() -> int:
	return int(budget_api.call("remaining_progress_usec")) if budget_api.has_method("remaining_progress_usec") else B.remaining_usec()
func finish(token: int, cost: int) -> void:
	if token > 0:
		now_us += cost
		B.end(token)
func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	configure(100,600)
	B.mark_pending("resource",true)
	var necessary := B.begin("wake",true)
	finish(necessary,140)
	var p := begin_progress("pursuit")
	check(p>0,"ready pursuit is not starved by necessary wake or older background category")
	finish(p,70)
	check(int(B.snapshot().spent_usec)==210,"all necessary and progress time remains in the full ledger")
	check(remaining_progress()==530,"progress quota charges only actual progress work")
	var r := B.begin("resource")
	check(r>0,"background retains its own opportunity after gameplay service")
	finish(r,90)
	check(B.remaining_usec()==10,"background allowance is independent rather than erased by necessary work")
	check(remaining_progress()==530,"background cannot drain progress opportunity")
	p=begin_progress("pursuit")
	check(p>0,"same category may use remaining progress allowance")
	if p>0:
		now_us += 10
		var inner:=begin_progress("nested_path")
		check(inner>0,"nested progress remains in the same synchronous allowance")
		finish(inner,20)
		now_us += 10
		B.end(p)
	check(remaining_progress()==490,"nested progress wall time is charged exactly once")
	check(int(B.snapshot().spent_usec)==340,"inclusive total preserves nested accounting")
	p=begin_progress("pursuit");finish(p,510)
	check(remaining_progress()==0 and begin_progress("pursuit")==0,"atomic progress overrun is measured and subsequent new work waits")
	check(int(B.snapshot().get("progress_overrun_usec",-1))==20,"progress overrun is explicit rather than hidden")
	check(B.remaining_usec()==10,"exhausted progress does not starve independent background")
	epoch+=1
	check(remaining_progress()==600 and B.remaining_usec()==100,"new epoch restores one allowance per lane without debt accumulation")
	check(int(B.snapshot().open_scopes)==0,"all lanes closed")
	# Reverse callbacks of the oldest reserved batch, not a new caller overtaking it.
	D.reset_pursuit_process_state()
	var owners: Array[Owner]=[]
	configure(0,0)
	for i: int in 5:
		var owner:=Owner.new();add_child(owner);owner.set_physics_process(true);owners.append(owner)
		var denied:=D.begin_pursuit_turn(owner,owner._hc_pursuit_budget_scope(),&"new_step")
		check(denied==0,"oldest ready requests remain queued under zero test allowance")
		if denied>0:D.end_pursuit_turn(denied)
	await get_tree().process_frame
	epoch+=1
	configure(100,600)
	var served:=0
	for i: int in range(4,-1,-1):
		var owner:=owners[i]
		var token:=D.begin_pursuit_turn(owner,owner._hc_pursuit_budget_scope(),&"new_step")
		if token>0:
			now_us+=10;D.end_pursuit_turn(token);served+=1
	check(served==5,"all five oldest-ready reservations run in reverse node callback order without waiting for a head callback")
	check(int(D.pursuit_process_snapshot().open_turns)==0,"reverse batch closes every owner lease")
	for owner: Owner in owners:D.cancel(owner.get_instance_id());owner.free()
	D.reset_pursuit_process_state()
	B.reset_test_configuration()
	var ok:=proof.write_receipt("v111_progress_budget_test",proof.records.size(),failures)
	print("V111_PROGRESS_BUDGET_%s checks=%d failed=%d" % ["PASS" if ok else "FAIL",proof.records.size(),failures])
	get_tree().quit(0 if ok else 1)
