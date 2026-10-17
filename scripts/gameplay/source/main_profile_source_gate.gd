extends RefCounted
## Main facade gate; no profile state, gameplay queue, RNG or writer.
var _facade: WeakRef
var _router: RefCounted
var _state := "MAIN"
var _snapshot: Dictionary = {}
var _denied: Array[Dictionary] = []
func configure_main(facade: Node, router: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _facade!=null or facade.get_script()!=preload("res://scripts/player_state.gd"): return false
	for method: String in ["reject_original_main_profile_writer","submit_original_profile_command","request_original_profile_notification","verify_original_profile_ui_receiver_closure"]:
		if router==null or not router.has_method(method): return false
	_facade=weakref(facade)
	_router=router
	return true
func prepare() -> bool:
	if _state!="MAIN": return false
	_state="PREPARED"
	return true
func abort() -> bool:
	if _state!="PREPARED": return false
	_state="MAIN"
	return true
func commit(initial_view: Dictionary) -> bool:
	if _state!="PREPARED": return false
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(initial_view,true,false)
	if captured.get("success")!=true: return false
	_snapshot=captured.value
	_state="S"
	return true
func state() -> String: return _state
func original_main_call_allowed(method: String) -> bool:
	if _state=="MAIN": return true
	# Actual capture accesses the stored Model directly; callers cannot recover
	# it through an old facade method once writer admission closes.
	var fact: Dictionary={"method":method,"state":_state,"source_process_frame":Engine.get_process_frames()}
	_denied.append(fact)
	_router.reject_original_main_profile_writer(fact)
	return false
func reject_legacy_call(method: String) -> Variant:
	original_main_call_allowed(method)
	return null # Formal rejected action; no old model call follows this return.
func read_original_profile_view(field: StringName) -> Variant:
	if _state!="S" or not _snapshot.has(field):
		_router.reject_original_main_profile_writer({"method":"unpublished_view:"+str(field),"state":_state})
		assert(false,"MISSING actual original Profile UI view field")
		return null
	return _snapshot[field]
func update_original_profile_view(values: Dictionary) -> bool:
	# Root checks reliable same-session S publication provenance before entry.
	if _state!="S": return false
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(values,true,false)
	if captured.get("success")!=true: return false
	_snapshot=captured.value
	return true
func read_original_profile_query(method: StringName) -> Variant:
	var types: Dictionary = preload("res://scripts/gameplay/profile/profile_original_ui_queries.gd").TYPES
	if not types.has(method):
		return reject_legacy_call("unpublished_query:"+str(method))
	var queries: Variant = read_original_profile_view(preload("res://scripts/gameplay/profile/profile_original_ui_queries.gd").FIELD)
	if not queries is Dictionary or not queries.has(method) or typeof(queries[method]) != types[method]:
		return reject_legacy_call("invalid_query:"+str(method))
	return queries[method]
func submit_original_profile_command(method: StringName, arguments: Array) -> Dictionary:
	if _state!="S": return {"success":false,"errors":["actual_s_profile_not_committed"]}
	return await _router.submit_original_profile_command(method,arguments)
func source_notification(what: int) -> void:
	if _state=="S": _router.request_original_profile_notification(what)
	elif _state=="PREPARED": _router.reject_original_main_profile_writer({"method":"notification","what":what,"state":_state})
func denied_source_writes() -> Array[Dictionary]: return _denied.duplicate(true)

var _pending_model: RefCounted
var _return_application: WeakRef
var _return_export: Dictionary
var _return_receipt: Dictionary
func prepare_actual_terminal_return(application: RefCounted, publication: Dictionary, resource_lease: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _state!="S" or application==null or application.get_script()!=preload("res://scripts/gameplay/source/main_boot_application.gd") or not application.verify_actual_profile_return_terminal(self,publication,false): return {"success":false,"status":"BLOCKED","error":"actual_same_joined_Source_export_and_unbound_Native_required"}
	if _pending_model!=null: return {"success":true,"adoption_prepared":true} if _return_application.get_ref()==application and _return_export==publication else {"success":false,"status":"INVALID"}
	var made: Dictionary=_facade.get_ref().create_actual_terminal_return_model(self,publication.state,resource_lease)
	if made.get("success")!=true: return made
	_pending_model=made.model;_return_application=weakref(application);_return_export=publication
	return {"success":true,"adoption_prepared":true,"actual_new_Main_model_id":_pending_model.get_instance_id(),"adoption":made.adoption}

func commit_actual_terminal_return(application: RefCounted, publication: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _state!="S" or _pending_model==null or _return_application.get_ref()!=application or _return_export!=publication or not application.verify_actual_profile_return_terminal(self,publication,true): return {"success":false,"status":"BLOCKED","error":"actual_retired_source_graph_and_prepared_Main_Profile_required"}
	var facade: Node=_facade.get_ref()
	_state="RETURN_COMMITTING"
	if not facade.install_actual_terminal_return_model(self,_pending_model):
		_state="S"
		return {"success":false,"status":"INVALID","error":"actual_new_Main_Profile_installation_rejected"}
	_state="RETURNED" # This gate is retired forever; a new Session gets a new gate.
	if not facade.finish_actual_terminal_return_gate(self): return {"success":false,"status":"INVALID","error":"actual_retired_Profile_gate_detachment_failed"}
	_return_receipt={"success":true,"status":"READY","contract_id":"hardcore.profile.Main_terminal_return.v1","owner_session_id":publication.owner_session_id,"actual_new_Main_model_id":_pending_model.get_instance_id(),"actual_source_model_id":publication.source_profile_model_id,"actual_Main_process_frame":Engine.get_process_frames()}
	_snapshot={};_router=null;_return_application=null
	return _return_receipt.duplicate(true)
