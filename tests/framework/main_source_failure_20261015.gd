extends Node
## Actual Main fault latch, without Source creation or any persistence writes.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func _ready() -> void:
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	var available: bool = host.has_method("bind_original_main_source_fault_owner") and host.has_method("report_original_main_source_fault")
	check(available,"actual Native Main failure admission and irreversible fault latch exist")
	if available: _verify(host)
	var written: bool = _proof.write_receipt("main_source_failure_20261015",_proof.records.size(),_failed)
	print("MAIN_SOURCE_FAILURE_20261015_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
func _verify(host: Object) -> void:
	var owner: RefCounted = load("res://scripts/gameplay/source/main_source_failure.gd").new()
	check(not host.bind_original_main_source_fault_owner(owner,"0".repeat(64)),"unreviewed fault producer source is rejected before binding")
	check(owner.configure_main(host),"real Main failure provider binds to its exact loaded Script and Host")
	check(not owner.configure_main(host),"failure owner cannot be reconfigured")
	var foreign: RefCounted = load("res://scripts/gameplay/source/main_source_failure.gd").new()
	check(not host.bind_original_main_source_fault_owner(foreign,foreign.get_script().get_source_code().sha256_text()),"a second concrete failure owner cannot replace the first")
	check(not host.report_original_main_source_fault(foreign,{"method":"foreign"}),"unregistered reporter cannot fault this Host")
	var facade: Node = get_tree().root.get_node("PlayerState")
	var model: RefCounted = facade.get("_model")
	var before: PackedByteArray = var_to_bytes([model.active_profile_id,model.gold,model.inventory,model.warehouse_inventory])
	owner.reject_original_main_profile_writer({"method":"isolated.refused_legacy_profile_mutation","state":"PREPARED"})
	var status: Dictionary = host.status()
	var receipt: Dictionary = status.get("original_main_source_fault",{})
	check(receipt.get("contract_id") == "hardcore.main.source_fault.v1" and receipt.get("owner_runtime_id") == owner.get_instance_id(),"Native retains the actual Main fault owner identity")
	check(status.get("fault") == "original_main_source_fault:isolated.refused_legacy_profile_mutation" and status.get("close_requested") == true,"actual Native latch requests original closing without clearing the fault")
	check(receipt.get("fact",{}).get("actual_main_process_frame") == Engine.get_process_frames() and receipt.fact.actual_main_physics_frame == Engine.get_physics_frames(),"recorded timing comes from actual Main Engine counters")
	check(receipt.is_read_only() and receipt.fact.is_read_only(),"accepted fault receipt is immutable across consumers")
	owner.reject_original_main_profile_writer({"method":"isolated.second_refusal","state":"PREPARED"})
	check(host.status().original_main_source_fault == receipt and owner.actual_original_main_source_faults().size() == 2,"later refusal does not overwrite first Native failure or discard local evidence")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":32,"bridge_generation":115155,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var factory: Script = load("res://scripts/gameplay/source/source_session_runtime.gd")
	check(not host.start(factory,{},config),"latched Main writer refusal prevents actual Source factory/physics startup")
	check(host.status().get("running") == false and host.status().get("owner_thread") == 0,"failed admission does not construct or claim a Source thread")
	check(host.close_and_join(),"never-started Host closes without a fabricated Source drain")
	check(facade.get("_model") == model and before == var_to_bytes([model.active_profile_id,model.gold,model.inventory,model.warehouse_inventory]),"refusal never writes or replaces the actual Profile or warehouse")
