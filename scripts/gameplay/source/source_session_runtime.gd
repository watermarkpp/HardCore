extends RefCounted
const CloseProcess := preload("res://scripts/gameplay/source/source_close_process_dispatcher.gd")
## The Script passed to actual Host.start. Root installs the concrete original
## source services at this FIXED path; no Script/Object is accepted in boot.
const Installation := preload("res://scripts/gameplay/source/source_session_runtime_installation.gd")
const Factory := preload("res://scripts/gameplay/source/source_session_factory.gd")
const WorldCore := preload("res://scripts/gameplay/world/world_simulation_core.gd")
const CatalogGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
var _owner := OS.get_thread_caller_id()
var _host: Object
var _session: RefCounted
var _services: Dictionary
var _world: RefCounted
var _failed := false
var _original_frame_dispatcher: RefCounted
var _expected_boot_session_id := 0
var _failed_before_session_main_io: Dictionary
var _construction_stage := "FACTORY_ENTRY"
var _construction_failure: Dictionary
var _boot_trace := false
var _catalog_reader: Dictionary = {}
func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_boot_trace = bool(boot.get("project_settings",{}).get("hardcore/diagnostics/main_boot_trace",false))
	_trace_boot("SOURCE_FACTORY_ENTRY")
	_expected_boot_session_id = int(boot.get("session_id",0))
	# The Main publisher retains the immutable catalog publication. This actual
	# Source thread must register its reader before Feature/Profile factories
	# consult those shared catalogs, and retain it through their final cleanup.
	var catalog: Variant = boot.get("content_snapshot",{}).get("catalog_lease")
	if not catalog is Dictionary or catalog != boot.get("profile_publication",{}).get("catalog_lease") or not CatalogGate.enter_reader(catalog):
		_failed = true
		_construction_failure = {"success":false,"errors":["actual_Source_catalog_reader_required"]}
		return
	_catalog_reader = catalog
	_trace_boot("SOURCE_CATALOG_READER_ACQUIRED")
	var installed: Dictionary = Installation.create_original_session_services(host, boot)
	if installed.get("success") != true:
		_construction_failure = installed
		_services = installed.get("constructed_source_services",{})
		_failed = true
		push_error("MISSING actual original SourceSession installation")
		return
	_services = installed.services
	_original_frame_dispatcher=installed.original_frame_dispatcher
	_construction_stage = "SOURCE_SERVICES_INSTALLED"
	_trace_boot(_construction_stage)
	var created: Dictionary = Factory.create(host, boot, _services)
	if not created.get("success", false):
		_construction_failure = created
		var partial: Variant = created.get("faulted_session")
		if partial is RefCounted: _session = partial
		_failed = true
		if _boot_trace and _session != null:
			for fact: Dictionary in _session.get("_faults"):
				var original: Dictionary = fact.get("details",{}).get("original_failure",{})
				print("HC_SOURCE_BOOT_FAILURE ",JSON.stringify({"code":fact.code,"errors":fact.get("details",{}).get("errors",[]),"original_errors":original.get("errors",[]),"original_error":original.get("error",""),"nested_error":original.get("details",{}).get("error","")}))
		return
	_session = created.session
	_construction_stage = "SESSION_INITIALIZED"
	_trace_boot(_construction_stage)
	var wrapped: Dictionary=preload("res://scripts/gameplay/world/world_session_services.gd").create_original_bound_session_services(_session,boot.get("source_frames_publication",{}),_services.source_frames,_services.get("feature_retirement"),_services.get("main_io"))
	if wrapped.get("success")!=true:
		_session.fault("MISSING_actual_original_Session_services",wrapped)
		_failed=true
		return
	_services.source_frames=wrapped.owner
	_construction_stage = "SESSION_WORLD_SERVICES_BOUND"
	_trace_boot(_construction_stage)
	for method: String in ["dispatch_original_session_inputs","dispatch_original_session_phase","prepare_original_source_session_close","close_original_source_session"]:
		if not _services.source_frames.has_method(method):
			_session.fault("original_source_frame_service_missing", {"method":method})
			_failed = true
	if _failed: return
	_trace_boot("BEFORE_ORIGINAL_SELECTED_WORLD_INITIALIZE")
	var first: Dictionary=_original_frame_dispatcher.initialize_original_selected_world(self,_session)
	if first.get("success")!=true:
		_session.fault("actual_epoch0_original_Core_birth_failed",first)
		_failed=true
		_construction_failure = first
	else: _construction_stage = "ORIGINAL_SELECTED_WORLD_INITIALIZED"
	_trace_boot(_construction_stage)
func _trace_boot(stage: String) -> void:
	# Use the captured setting, not a Main singleton read from Source. Only
	# bounded actual stage/thread/time facts are printed; never the save graph.
	if _boot_trace: print("HC_SOURCE_BOOT_TRACE ",JSON.stringify({"stage":stage,"thread":OS.get_thread_caller_id(),"usec":Time.get_ticks_usec()}))
func owner_thread_id() -> int: return _owner
func current_original_world_core() -> RefCounted: return _world
func source_prepare_before_sync() -> bool:
	if _failed or _session==null or _world==null: return false
	return _original_frame_dispatcher.prepare_original_physics_before_sync(self,_session,_world,_host.current_clock_frame())
func source_session() -> RefCounted: return _session
func birth_original_world(world_boot: Dictionary) -> bool:
	if _failed or _world != null or _session.is_faulted() or not _session.original_profile_owner().get("success",false): return false
	_world = WorldCore.new(_host, world_boot, _session)
	if not _original_frame_dispatcher.bind_original_replacement_world(_world): return false
	return not _world.is_faulted() and _world.get("_ready") == true
func leave_original_world() -> bool:
	if _world == null or not _original_frame_dispatcher.begin_original_world_exit(_world) or not _world.close_session(): return false
	_world = null
	return true
func on_inputs(domain: String, packets: Array) -> bool:
	if _failed: return false
	return _services.source_frames.dispatch_original_session_inputs(domain, packets, self, _session, _world)
func on_phase(name: String, frame: Dictionary) -> bool:
	if _failed or _session.is_faulted(): return false
	# Active Core's P_GROUP already emits the original process_frame signal.
	if name == "P_GROUP" and _world == null:
		if not _session.service_original_process_frame_without_world(int(frame.source_process_frame)): return false
	# The actual source callback manifest decides exact hall/loading/world
	# callback priority/tree order and calls Core.on_phase exactly once.
	return _services.source_frames.dispatch_original_session_phase(name, frame, self, _session, _world)
var _actual_close_trace_seen: Dictionary = {}
func _actual_close_trace(stage: String) -> void:
	if not _boot_trace or _actual_close_trace_seen.has(stage): return
	_actual_close_trace_seen[stage] = true
	print("HC_SOURCE_RUNTIME_CLOSE ",JSON.stringify({"stage":stage,"thread":OS.get_thread_caller_id(),"runtime_id":get_instance_id(),"usec":Time.get_ticks_usec()}))
func close_session() -> bool:
	_actual_close_trace("enter")
	if _original_close_session_freed: return true
	if _session == null: return _close_actual_failure_before_session()
	_actual_close_trace("before_dispatcher_admission")
	if not _original_frame_dispatcher.begin_original_session_close(self,_session,_world): return false
	_actual_close_trace("after_dispatcher_admission")
	if _world!=null:
		if not _world.hold_original_session_close_resource_owner(): return false
		# Advance original Root exit/GC while retaining actual Native resource
		# endpoint and current World Context until persistent cache cleanup READY.
		_actual_close_trace("before_World_close")
		_world.close_session()
		_actual_close_trace("after_World_close")
	_actual_close_trace("before_resource_waiters")
	if _session.original_resource_service_waiter_count()>0: return false
	# Advance/inspect genuine accepted service/IO/lease retirement without final
	# freeing the Session. Its actual source implementation is strictly required.
	_actual_close_trace("before_persistent_frames_prepare")
	if not _services.source_frames.prepare_original_source_session_close(_session): return false
	_actual_close_trace("after_persistent_frames_prepare")
	if _world!=null:
		if not _world.release_original_session_close_resource_owner() or not leave_original_world(): return false
	if not _host.has_method("original_close_process_producer_drained") or not _host.has_method("request_original_close_process_producer_stop"):
		_session.fault("MISSING_actual_close_producer_STOP_drain",{})
		return false
	if not _session.publish_actual_terminal_profile_return(self): return false
	if not _host.request_original_close_process_producer_stop(): return false
	# Not Host.quiescent: Native confirms actual producer STOP and drains accepted
	# phases/Main ACKs while this live Session/dispatcher still owns obligations.
	if not _host.original_close_process_producer_drained(): return false
	if not _services.source_frames.close_original_source_session(_session): return false
	if not _release_actual_catalog_reader(): return false
	_original_close_session_freed=true
	return true

var _original_close_session_freed := false
func on_original_close_process_phase(frame: Dictionary) -> bool:
	if _original_close_session_freed or _host == null or frame != _host.current_clock_frame() or frame.get("closing_session") != true: return false
	if _session == null:
		var publication: Dictionary = frame.get("closing_process_publication",{})
		if publication.get("phase") == "NODE_PROCESS_SERVICE":
			var io: Variant = publication.get("main_io")
			if not io is Dictionary or io.get("contract_id") != "hardcore.source.main_io_observation.v1" or io.get("owner_session_id") != _expected_boot_session_id or io.get("physical_owners_retained") != true or io.get("status") not in ["OWNERS_RETAINED","BUSINESS_DRAINED"]: return false
			_failed_before_session_main_io = io
		return _failed
	# Deliver the authenticated fact before a partial Core cleanup attempts its
	# retention checkpoint. The later same-frame service is exactly idempotent.
	if frame.get("source_boundary") == "NODE_PROCESS_SERVICE":
		var io: Variant = _services.get("main_io")
		if not io is RefCounted or not io.service_original_source_main_io_cleanup(_session,_world,frame): return false
	return CloseProcess.dispatch_original_close_process_frame(frame,self,_session,_world,_services.source_frames,_host)

func _close_actual_failure_before_session() -> bool:
	if not _failed or _world != null or _failed_before_session_main_io.get("status") != "BUSINESS_DRAINED": return false
	var state: Dictionary = _host.status()
	for key: String in ["accepted_live_resource_obligations","accepted_worker_group_obligations","unsettled_original_published_prefixes","input_queue_size"]:
		if not state.get(key) is int or state[key] != 0: return false
	if state.get("original_primitive_in_flight") != false or state.get("source_admission_scopes_quiescent") != true or state.get("caster_reply_obligations_quiescent") != true: return false
	if not _host.original_close_process_producer_drained():
		_host.request_original_close_process_producer_stop()
		return false
	# No Session/Core was ever constructed on this branch. The actual Native
	# ledgers and consumed Main business proof precede destruction of these
	# Source-only installation objects; no live gameplay owner is discarded.
	_services = {}; _original_frame_dispatcher = null
	if not _release_actual_catalog_reader(): return false
	_original_close_session_freed = true
	return true

func _release_actual_catalog_reader() -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	if _catalog_reader.is_empty(): return true
	if not CatalogGate.leave_reader(_catalog_reader): return false
	_catalog_reader = {}
	return true
