extends Node

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var compiler := Compiler.new()

func _ready() -> void:
	_run.call_deferred()

func _limits() -> Dictionary:
	return {"pending_facts":8192,"active_states":4096,"receipts":65536}

func _request(n: Variant, b: Variant, g: Variant, l: Variant, s: Variant) -> Dictionary:
	return {"maximum_receivers":n,"child_bindings":b,"maximum_generation":g,
		"binding_count":l,"persistent_bindings":s}

func _compile(request: Variant, limits: Variant) -> Dictionary:
	# Missing production protocol remains a typed RED, not a script error.
	if not compiler.has_method("compile_child_capacity"):
		return {"success":false,"reason":"child_capacity_protocol_missing"}
	return compiler.call("compile_child_capacity",request,limits)

func _check(value: bool, label: String) -> void:
	checks += 1; proof.record(value,label)
	if not value: errors.append(label)

func _run() -> void:
	var request := _request(3,1,1,2,1)
	var result := _compile(request,_limits())
	_check(bool(result.get("success",false)),"one declared child generation includes all three root and nine potential child receivers")
	if not bool(result.get("success",false)):
		print("CHILD_CAPACITY_RED_REASON="+str(result.get("reason")))
		_finish(); return
	var cost: Dictionary = result.cost
	_check(cost.facts==12 and cost.receipts==24 and cost.states==12 and cost.child_actions==3,
		"hand-derived N3 B1 G1 L2 S1 reserves 12 facts, 24 receipts, 12 states and 3 child actions")
	request.maximum_receivers=999
	_check(cost.is_read_only() and cost.facts==12,"accepted cost is immutable and independent of caller mutations")
	result=_compile(_request(3,2,2,3,1),_limits())
	_check(result.success and result.cost.facts==129 and result.cost.receipts==387
		and result.cost.states==129 and result.cost.child_actions==42,
		"two independent child sources and two generations retain full 3+18+108 facts and 42 child actions")
	result=_compile(_request(30,1,1,2,3),_limits())
	_check(not result.success and result.reason=="invalid_child_capacity_request",
		"a persistent binding count larger than the declared total cannot underwrite a valid cost")
	result=_compile(_request(30,1,1,3,3),_limits())
	_check(result.success and result.cost.facts==930 and result.cost.receipts==2790
		and result.cost.states==2790 and result.cost.child_actions==30,
		"30 is a fixture size, with all 900 potential child receivers and three sources counted")
	result=_compile(_request(30,1,2,3,3),_limits())
	_check(not result.success and result.reason=="child_fact_capacity",
		"a third layer is refused before gameplay, rather than truncating a committed chain")
	result=_compile(_request(30,1,1,5,5),_limits())
	_check(not result.success and result.reason=="child_state_capacity","global fact space does not imply enough persistent state capacity")
	result=_compile(_request(30,1,1,3,0),{"pending_facts":8192,"active_states":4096,"receipts":2000})
	_check(not result.success and result.reason=="child_receipt_capacity","immediate child actions still require every source receipt")
	result=_compile(_request(0,1,9007199254740991,2,1),_limits())
	_check(result.success and result.cost.facts==0 and result.cost.states==0
		and result.cost.receipts==0 and result.cost.child_actions==0,"empty legal world has zero work even for a large finite program")
	result=_compile(_request(1,1,1000000000,1,0),_limits())
	_check(not result.success and result.reason=="child_fact_capacity","large single-receiver lineage is rejected without a billion-step loop")
	result=_compile(_request(4096,2,9007199254740991,2,1),_limits())
	_check(not result.success and result.reason=="child_fact_capacity","exponential declared work cannot overflow into a small accepted value")
	result=_compile(_request(4,0,9007199254740991,2,1),_limits())
	_check(result.success and result.cost.facts==4 and result.cost.receipts==8
		and result.cost.states==4 and result.cost.child_actions==0,"a program with no child producer owns only its original work")
	for malformed: Variant in [null,[],_request(-1,1,1,2,1),_request(1.5,1,1,2,1),
		_request(true,1,1,2,1),_request(3,3,1,2,1),_request(3,1,-1,2,1),_request(3,1,1,0,0)]:
		result=_compile(malformed,_limits())
		_check(not result.success and result.reason=="invalid_child_capacity_request","invalid program fields fail closed: "+JSON.stringify(malformed))
	var extra:=_request(3,1,1,2,1); extra.execute="arbitrary"
	result=_compile(extra,_limits())
	_check(not result.success and result.reason=="invalid_child_capacity_request","unknown executable or future request fields are not silently ignored")
	for malformed_limits: Variant in [null,{},_limits().merged({"receipts":-1},true),
		_limits().merged({"pending_facts":1.5},true),_limits().merged({"fallback":true},true)]:
		result=_compile(_request(3,1,1,2,1),malformed_limits)
		_check(not result.success and result.reason=="invalid_child_capacity_limits","caller must supply the complete nonnegative runtime capacities")
	result=_compile(_request(3,1,1,2,1),{"pending_facts":12,"active_states":12,"receipts":24})
	_check(result.success,"an exact capacity boundary admits the complete chain")
	result=_compile(_request(3,1,1,2,1),{"pending_facts":11,"active_states":12,"receipts":24})
	_check(not result.success and result.reason=="child_fact_capacity","one missing fact slot rejects the whole promise")
	var serial:=preload("res://scripts/features/compilation/child_capacity_proof.gd")
	result=serial.compile_serial_residency(_request(85,1,2,1,0),_limits())
	_check(result.success and result.cost.total_facts==621435 and result.cost.total_receipts==621435 \
		and result.cost.facts==170 and result.cost.receipts==170 and result.cost.child_actions==7310,
		"the real 85-slot world retains all 621435 potential facts but serial storage and closed-branch retirement reserve 170 slots")
	result=serial.compile_serial_residency(_request(90,1,2,1,0),{"pending_facts":8190,"active_states":0,"receipts":180})
	_check(result.success and result.cost.child_actions==8190,"exact resident frontier boundary retains all 90+8100 child actions")
	result=serial.compile_serial_residency(_request(90,1,2,1,0),{"pending_facts":8189,"active_states":0,"receipts":180})
	_check(not result.success and result.reason=="child_fact_capacity","one missing command-frontier slot still rejects before commitment")
	result=serial.compile_serial_residency(_request(85,1,2,2,1),_limits())
	_check(not result.success and result.reason=="child_state_capacity","serial fact storage does not reduce persistent state lifetime promises")
	result=serial.compile_serial_residency(_request(1,1,1000000000,1,0),_limits())
	_check(not result.success,"large finite frontier is rejected in logarithmic work rather than a billion iterations")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_child_capacity_test",checks,errors.size()): errors.append("receipt_write")
	print(("FRAMEWORK_CHILD_CAPACITY_PASS" if errors.is_empty() else "FRAMEWORK_CHILD_CAPACITY_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
