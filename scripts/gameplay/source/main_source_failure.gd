extends RefCounted
## Main's one failure reporter. A refusal never calls the old Profile, unfreezes
## PREPARED or drops accepted Source/IO owners. Native latches the first fault.
var _host: WeakRef
var _records: Array[Dictionary] = []
func owner_thread_id() -> int: return OS.get_main_thread_id()
func configure_main(host: Object) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host != null or host == null or not host.is_class("HardCoreSimulationHost"): return false
	if not host.has_method("bind_original_main_source_fault_owner") or not host.has_method("report_original_main_source_fault"): return false
	if not host.bind_original_main_source_fault_owner(self,get_script().get_source_code().sha256_text()): return false
	_host = weakref(host)
	return true
func reject_original_main_profile_writer(fact: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id() and _host != null and _host.get_ref() != null)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var observed: Dictionary = fact.duplicate(true)
	observed["actual_main_process_frame"] = Engine.get_process_frames()
	observed["actual_main_physics_frame"] = Engine.get_physics_frames()
	var captured: Dictionary = graph.capture(observed,true,false)
	if captured.get("success") != true or not observed.get("method") is String or observed.method.is_empty():
		captured = graph.capture({"method":"invalid_original_Main_fault_fact","actual_main_process_frame":Engine.get_process_frames(),"actual_main_physics_frame":Engine.get_physics_frames()},true,false)
	_records.append(captured.value)
	var accepted: bool = _host.get_ref().report_original_main_source_fault(self,captured.value)
	if not accepted:
		push_error("actual Native Main fault owner/provenance changed")
		assert(false,"actual Native Main fault owner/provenance changed")
func actual_original_main_source_faults() -> Array[Dictionary]: return _records.duplicate(true)
