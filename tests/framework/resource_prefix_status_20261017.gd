extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Port := preload("res://scripts/gameplay/world/world_resource_prefix_transport.gd")
var proof := Proof.new()
var failed := 0
func check(ok: bool, label: String) -> void:
	proof.record(ok,label)
	if not ok: failed += 1
func _ready() -> void: _run.call_deferred()
func _source() -> Array:
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	var world := RefCounted.new()
	var port := Port.new(world,host)
	var rows: Array = [[port.owner_thread_id() == OS.get_thread_caller_id() and OS.get_thread_caller_id() != OS.get_main_thread_id(),"actual separate owner thread constructs the production facade"]]
	var exists: bool = port.has_method("status")
	rows.append([exists,"production prefix facade supplies the consumed Native diagnostic API"])
	if exists:
		var before: Dictionary = host.status()
		var actual: Dictionary = port.call("status")
		rows.append([actual == before and actual == host.status(),"facade returns the exact real quiescent Native Host state, not invented fields"])
		rows.append([actual.get("started") == false and actual.get("running") == false,"diagnostic read never starts a Source or claims a running session"])
		actual["test_only_mutation"] = true
		rows.append([not port.call("status").has("test_only_mutation"),"subsequent facade read is a fresh actual Native snapshot, not a shared cached mutable dictionary"])
	else:
		rows.append([false,"actual Host diagnostic state must be readable through its production facade"])
	port = null; host = null
	return rows
func _run() -> void:
	var thread := Thread.new()
	check(thread.start(Callable(self,"_source")) == OK,"real separate Thread starts; no fake World or Native execution is claimed")
	while thread.is_alive(): await get_tree().process_frame
	for row: Array in thread.wait_to_finish(): check(row[0],row[1])
	var written: bool = proof.write_receipt("resource_prefix_status_20261017",proof.records.size(),failed)
	print("RESOURCE_PREFIX_STATUS_", "PASS" if written and failed == 0 else "FAIL")
	get_tree().quit(0 if written and failed == 0 else 1)
