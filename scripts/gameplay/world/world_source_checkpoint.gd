extends RefCounted
## Genuine Source checkpoint evidence. Godot material idle callbacks are Main
## owned. This provider does not run them on the Source world's thread.
var _owner:=OS.get_thread_caller_id()
var _host: Object
var _dispatcher: RefCounted
var _core: WeakRef
var _world: Dictionary
var _initial_world: Dictionary
func owner_thread_id() -> int: return _owner
func configure_owner(host: Object, dispatcher: RefCounted) -> bool:
	if _host!=null or _owner==OS.get_main_thread_id() or host==null or not host.is_class("HardCoreSimulationHost") or dispatcher==null or dispatcher.owner_thread_id()!=_owner: return false
	_host=host;_dispatcher=dispatcher
	return true
func bind_original_world(core: RefCounted) -> bool:
	if _host==null or core==null or core.owner_thread_id()!=_owner: return false
	if _core!=null and _core.get_ref()!=null and not _core.get_ref().is_original_world_closed(): return is_same(_core.get_ref(),core)
	_core=weakref(core);_world=core.current_world_identity();_initial_world=_world.duplicate(true)
	return true
func original_idle_callbacks(domain: StringName, frame: Dictionary) -> Dictionary:
	var closing_service: bool = domain == &"P" and frame.get("closing_session") == true and frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("source_boundary") == "NODE_PROCESS_SERVICE" and frame.get("closing_process_publication",{}).get("phase") == "NODE_PROCESS_SERVICE"
	if not _current(frame) or domain not in [&"H",&"P"] or (frame.get("phase")!=("H_AFTER_TIMERS" if domain==&"H" else "P_AFTER_TIMERS") and not closing_service): return _missing("actual_native_after_timer_checkpoint")
	var core: RefCounted=_core.get_ref()
	if not core.has_method("original_source_delete_checkpoint_receipt"): return _missing("actual_Source_delete_FIFO_receipt")
	var actual: Dictionary=core.original_source_delete_checkpoint_receipt()
	if actual.get("success")!=true or actual.get("frame")!=frame or actual.get("domain")!=domain: return _missing("actual_Source_delete_FIFO_not_finished")
	if actual.get("remaining") != 0 and not core.verify_original_deferred_final_free(actual): return _missing("actual_Source_delete_FIFO_deferred_debt_unproved")
	return {"success":true,"actual_original_checkpoint":true,"native_frame":frame,"source_delete_receipt":actual,"source_idle_callbacks_invoked":[],"engine_material_idle_owner":&"Main"}
func original_control_boundary(phase: StringName, frame: Dictionary) -> Dictionary:
	if not _current(frame) or phase not in [&"U_BEGIN",&"U_END",&"U_WAKE"] or frame.get("phase")!=String(phase): return _missing("actual_native_control_boundary")
	# Native has already selected the real control phase. H/P deltas, timer sweeps
	# and budget epoch are neither changed nor simulated by this observer.
	return {"success":true,"actual_original_checkpoint":true,"phase":phase,"native_frame":frame,"source_world":_world}
func original_world_exit_admission(world: Dictionary) -> Dictionary: return _exit(world,false)
func original_fault_exit_admission(world: Dictionary) -> Dictionary: return _exit(world,true)
func _exit(world: Dictionary, faulted: bool) -> Dictionary:
	if not _advance_actual_arrival_route() or world!=_world or _core==null or _core.get_ref()==null: return _missing("actual_same_Source_world_exit")
	var core: RefCounted=_core.get_ref()
	var frame: Dictionary=_host.current_clock_frame()
	if not _dispatcher.original_source_callbacks_closed(core): return _missing("actual_Source_world_callbacks_stopped_and_inputs_drained")
	# Same Native closing-P publication already delivered to the sole Session's
	# MainIO owner. Retention permits exit to create cleanup work; it never says
	# those accepted operations or their physical resources have already drained.
	var io: Variant = core.original_source_session().get("_services").get("main_io")
	if not io is RefCounted or not io.has_method("actual_original_world_io_retention_state"): return _missing("actual_bound_Source_MainIO_owner_required")
	var retained: Dictionary = io.actual_original_world_io_retention_state(core)
	if retained.get("status") == "PENDING": return retained
	if retained.get("success") != true or retained.get("world") != world or retained.get("core_object_id") != core.get_instance_id() or retained.get("actual_native_receipt") != true or retained.get("actual_io_owners_retained") != true: return _missing("actual_Main_IO_owner_retention_not_proved")
	return {"success":true,"world":world,"source_callbacks_closed":true,"actual_io_owners_retained":true,"actual_checkpoint":{"native_frame":frame,"source_owner":core.get_instance_id(),"faulted":faulted,"actual_retention":retained}}
func _current(frame: Dictionary) -> bool:
	if not _advance_actual_arrival_route(): return false
	return OS.get_thread_caller_id()==_owner and _host!=null and _core!=null and _core.get_ref()!=null and frame==_host.current_clock_frame() and _core.get_ref().current_world_identity()==_world
static func _missing(code: String) -> Dictionary: return {"success":false,"status":"MISSING","error":code}

func _advance_actual_arrival_route() -> bool:
	if OS.get_thread_caller_id() != _owner or _host == null or _core == null or _core.get_ref() == null: return false
	var core: RefCounted = _core.get_ref()
	var current: Dictionary = core.current_world_identity()
	if current == _world: return true
	var transaction: Dictionary = core.get("_last_original_map_arrival")
	if not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or transaction.before_world != _world or transaction.after_world != current or transaction.owner_session_id != core.original_source_session().original_budget_session_id() or transaction.source_root_id != core.original_root_owner().get_instance_id() or not _host.verify_committed_original_map_arrival(transaction): return false
	_world = current.duplicate(true)
	return true
