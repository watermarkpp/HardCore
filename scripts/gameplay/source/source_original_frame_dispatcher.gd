extends RefCounted
## This is Source execution, not a Main SceneTree gameplay pump. Native remains
## the sole frame/timer owner. Every active Core phase is delivered once.
const ProfileHooks := preload("res://scripts/gameplay/source/source_profile_session_hooks.gd")
const FeatureCommands := preload("res://scripts/gameplay/source/source_feature_command_transport.gd")
var _owner:=OS.get_thread_caller_id()
var _host: Object
var _runtime: WeakRef
var _session: WeakRef
var _core: WeakRef
var _profile_hooks: RefCounted
var _feature_commands: RefCounted
var _boot: Dictionary
var _world_inputs: Array[Dictionary]=[]
var _last_phases: Dictionary={}
var _normal_closed:=false
var _world_callbacks_closed:=false
var _prepared:=false
var _final:=false
func owner_thread_id() -> int: return _owner
func configure_owner(host: Object, boot: Dictionary) -> bool:
	if _host!=null or _owner==OS.get_main_thread_id() or host==null or not host.is_class("HardCoreSimulationHost"): return false
	_host=host;_boot=boot
	return true
func initialize_original_selected_world(runtime: RefCounted, session: RefCounted) -> Dictionary:
	if _runtime!=null or runtime.owner_thread_id()!=_owner or session.owner_thread_id()!=_owner: return _missing("actual_once_S_Runtime_Session")
	var frame: Dictionary=_host.current_clock_frame()
	if frame.get("epoch")!=0 or frame.get("source_boundary")!="bootstrap_ready_query": return _missing("actual_native_epoch0_factory_PROCESS_query_bracket")
	if not _boot.get("profile_state_handoff") is Dictionary or not _boot.get("first_world_boot") is Dictionary: return _missing("actual_selected_Profile_and_prepared_World_boot")
	var selected: Dictionary=session.original_profile_owner()
	if selected.get("success")!=true or selected.get("original_loaded_handoff_applied")!=true or selected.profile.active_profile_id.is_empty(): return _missing("actual_original_selected_Profile_adopted_once")
	var world_boot: Dictionary=_boot.first_world_boot
	if world_boot.get("world_identity",{}).get("profile_id")!=selected.profile.active_profile_id or world_boot.get("assembly",{}).get("bootstrap_source_site",{}).get("clock_epoch")!=0: return _missing("actual_same_selected_epoch0_World")
	_runtime=weakref(runtime);_session=weakref(session)
	_profile_hooks=ProfileHooks.new()
	# The actual Core constructor runs here, while the Native factory has not
	# returned and external_begin_process still owns the bootstrap query bracket.
	var born: bool=runtime.birth_original_world(world_boot)
	var core: RefCounted=runtime.current_original_world_core()
	if core==null or core.owner_thread_id()!=_owner or core.current_world_identity()!=world_boot.world_identity: return _missing("actual_same_Core_born")
	_core=weakref(core)
	if not born: return _missing("actual_original_Core_constructor_failed_and_retained")
	# Publish adoption only after the complete Core constructor succeeded. A
	# Header primitive's applied prefix cannot expose a premature world-ready fact.
	if not _profile_hooks.configure_original_owner(session,_boot.source_commit_receipt): return _missing("actual_original_Profile_command_owner")
	_feature_commands = FeatureCommands.new()
	if not _feature_commands.configure_original_owner(session): return _missing("actual_original_Feature_command_transport")
	return {"success":true,"actual_epoch0_Core_born":true,"core_object_id":core.get_instance_id(),"native_frame":frame,"world":core.current_world_identity()}
func dispatch_original_session_inputs(domain: String, packets: Array, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	if not _same(runtime,session,core) or _final or domain not in ["H_INPUT","P_INPUT","U_WAKE"]: return false
	for packet: Variant in packets:
		if not packet is Dictionary: return false
		if _normal_closed: return false
		_world_inputs.append(packet)
	# U_WAKE never impersonates H/P. A target/attack input waits for the next
	# actual Native logical input phase. Profile transactions execute inside that
	# same Core input entry, with its genuine resource phase already open.
	if domain in ["H_INPUT","P_INPUT"] and not _world_inputs.is_empty():
		if core==null or not core.on_inputs(domain,_world_inputs,Callable(self,"_accept_profile_packet")): return false
		_world_inputs=[]
	return true
func _accept_profile_packet(packet: Dictionary) -> Dictionary:
	if _feature_commands != null:
		var feature: Dictionary = _feature_commands.dispatch_original_packet(packet)
		if feature.get("handled") == true: return feature
	var profile: Dictionary=_profile_hooks.dispatch_original_profile_packet(packet)
	if profile.get("handled")==true: return profile
	if packet.get("contract_id")!="hardcore.profile.notification.v1": return {"handled":false}
	var session: RefCounted=_session.get_ref()
	if packet.get("owner_session_id")!=session.original_budget_session_id() or not packet.get("what") is int: return {"handled":true,"accepted":false}
	var model: RefCounted=session.original_profile_owner().profile
	if packet.what not in [Node.NOTIFICATION_APPLICATION_PAUSED,Node.NOTIFICATION_APPLICATION_FOCUS_OUT,Node.NOTIFICATION_WM_CLOSE_REQUEST]: return {"handled":true,"accepted":false}
	model.suspend_profile()
	return {"handled":true,"accepted":true}
func dispatch_original_session_phase(name: String, frame: Dictionary, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	if not _same(runtime,session,core) or _final: return false
	var actual: Dictionary=_host.current_clock_frame()
	if actual.get("phase")!=name or not _matches_native_callback_frame(frame,actual): return false
	if _normal_closed: return name in ["U_BEGIN","U_END","U_WAKE","PUBLISH"]
	# Repeated U_WAKE callbacks are genuine Native wakes, not a second H/P.
	if core!=null and _world_callbacks_closed: return false
	var key: String="%d:%d:%d:%s" % [actual.epoch,actual.source_process_frame,actual.source_physics_frame,name]
	if name!="U_WAKE" and _last_phases.has(key): return false
	if name!="U_WAKE": _last_phases[key]=true
	if name=="U_BEGIN":
		for old: String in _last_phases.keys():
			if not old.begins_with(str(actual.epoch)+":"): _last_phases.erase(old)
	# Session-root scheduling continues between Worlds. It uses the same
	# Native duplicate guard above, not a second frame or an immediate timer.
	if core==null:
		return session.dispatch_original_persistent_without_world(name,actual)
	# Getter adds actual Native phase/boundary/paused fields. Every callback field
	# was checked against that getter; no frame number, delta or epoch is derived.
	if not core.on_phase(name,actual): return false
	return name!="P_GROUP" or (_profile_hooks.service_original_receipts_at_actual_source_boundary() and _feature_commands.flush_actual_original_receipts())
func prepare_original_physics_before_sync(runtime: RefCounted, session: RefCounted, core: RefCounted, frame: Dictionary) -> bool:
	if not _same(runtime,session,core) or _normal_closed or frame!=_host.current_clock_frame() or frame.get("source_boundary")!="H_PREPARE:before_sync": return false
	return core.source_prepare_before_sync()
func begin_original_session_close(runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	if not _same(runtime,session,core): return false
	var frame: Dictionary=_host.current_clock_frame()
	if frame.get("closing_session")!=true: return false
	# Actual Native closing loop has stopped regular H/P. Source storage remains
	# held by Runtime/Core; this flag describes this dispatcher, not IO retirement.
	_normal_closed=true
	_world_callbacks_closed=true
	_profile_hooks.close_original_profile_command_admission()
	if _feature_commands != null: _feature_commands.close_original_admission()
	return _world_inputs.is_empty()
func dispatch_original_close_process_boundary(boundary: String, frame: Dictionary, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	if not _same(runtime,session,core) or not _normal_closed or frame!=_host.current_clock_frame() or frame.get("closing_session")!=true or boundary not in ["PROCESS_SIGNAL","NODE_PROCESS_SERVICE"]: return false
	return boundary!="NODE_PROCESS_SERVICE" or (_profile_hooks.service_original_receipts_at_actual_source_boundary() and (_feature_commands == null or _feature_commands.service_actual_closing_acknowledgements(frame)))
func original_source_callbacks_closed(core: RefCounted) -> bool:
	return _world_callbacks_closed and _core!=null and is_same(_core.get_ref(),core) and _world_inputs.is_empty()
func service_original_close_session_obligations(session: RefCounted, frame: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=_owner or _final or not _normal_closed or _session==null or not is_same(_session.get_ref(),session) or _runtime==null or _runtime.get_ref()==null or _runtime.get_ref().current_original_world_core()!=null or not _world_inputs.is_empty() or frame!=_host.current_clock_frame(): return false
	if _core!=null and _core.get_ref()!=null and not _core.get_ref().is_original_world_closed(): return false
	return session.service_original_close_session_obligations(frame,_service_original_persistent_close_receipts)
func _service_original_persistent_close_receipts() -> bool:
	var session: RefCounted=_session.get_ref()
	var profile: Dictionary=session.original_profile_owner()
	if profile.get("success")==true: profile.profile.service_receipts()
	return _profile_hooks!=null and _profile_hooks.service_original_receipts_at_actual_source_boundary() and (_feature_commands==null or _feature_commands.service_actual_closing_acknowledgements(_host.current_clock_frame()))
func begin_original_world_exit(core: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or _core==null or not is_same(_core.get_ref(),core) or not _world_inputs.is_empty(): return false
	_world_callbacks_closed=true
	return true
func bind_original_replacement_world(core: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or _normal_closed or core==null or core.owner_thread_id()!=_owner: return false
	if _core!=null and _core.get_ref()!=null and not _core.get_ref().is_original_world_closed(): return false
	_core=weakref(core);_world_callbacks_closed=false
	return true
func prepare_original_source_session_close(session: RefCounted) -> bool:
	if _session==null or not is_same(_session.get_ref(),session) or not _normal_closed or not _world_inputs.is_empty(): return false
	_prepared=_profile_hooks.original_profile_command_retirement_complete() and (_feature_commands == null or _feature_commands.actual_original_command_retirement_complete())
	return _prepared
func close_original_source_session(session: RefCounted) -> bool:
	if _final: return _session!=null and is_same(_session.get_ref(),session)
	if not _prepared or not session.actual_original_close_process_producer_drained(): return false
	_profile_hooks=null;_feature_commands=null;_core=null;_runtime=null;_final=true
	return true
func _same(runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	return OS.get_thread_caller_id()==_owner and _runtime!=null and is_same(_runtime.get_ref(),runtime) and _session!=null and is_same(_session.get_ref(),session) and (core==null or _core!=null and is_same(_core.get_ref(),core))
static func _matches_native_callback_frame(callback: Dictionary, actual: Dictionary) -> bool:
	for key: String in ["epoch","h_ordinal","source_process_frame","source_physics_frame","next_release_usec","release_usec","observed_usec","lateness_usec","time_scale","simulation_elapsed","raw_delta","clipped_delta","scaled_delta","unscaled_timer_delta"]:
		if not callback.has(key) or callback[key]!=actual.get(key): return false
	for key: Variant in callback:
		if not actual.has(key) or callback[key]!=actual[key]: return false
	return true
static func _missing(code: String) -> Dictionary: return {"success":false,"status":"MISSING","error":code}
