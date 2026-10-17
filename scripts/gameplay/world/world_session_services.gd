extends RefCounted
## Session runtime provider wrapper. The original callback/birth dispatcher and
## IO owner remain actual dependencies. MonsterSourceFrames is only one service.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _frames: RefCounted
var _monster_frames: RefCounted
var _feature: RefCounted
var _io: RefCounted
var _prepared := false
var _final := false
static func create_original_bound_session_services(session: RefCounted, publication: Dictionary, actual_frame_dispatcher: RefCounted, feature_retirement: RefCounted, main_io: RefCounted) -> Dictionary:
	if session==null or not session.has_method("original_source_frames_owner"): return {"success":false,"status":"MISSING","error":"actual_original_Session"}
	var raw: RefCounted=session.original_source_frames_owner(publication)
	if raw==null: return {"success":false,"status":"MISSING","error":"actual_original_overlay_handoff"}
	var owner:=new()
	if not owner.configure_owner(session,actual_frame_dispatcher,raw,feature_retirement,main_io): return {"success":false,"status":"MISSING","error":"actual_original_callback_Feature_IO_providers"}
	return {"success":true,"owner":owner,"raw_monster_source_frames":raw}
func owner_thread_id() -> int: return _owner
func configure_owner(session: RefCounted, actual_frame_dispatcher: RefCounted, monster_frames: RefCounted, actual_feature_owner: RefCounted, actual_io_receipts: RefCounted) -> bool:
	if _session!=null or _owner==OS.get_main_thread_id() or session.owner_thread_id()!=_owner: return false
	for spec: Array in [[actual_frame_dispatcher,["dispatch_original_session_inputs","dispatch_original_session_phase","dispatch_original_close_process_boundary","prepare_original_source_session_close","close_original_source_session"]],[monster_frames,["prepare_original_source_session_close","close_original_source_session","service_original_close_session_resource_obligations"]],[actual_feature_owner,["original_session_retirement_state"]],[actual_io_receipts,["service_original_source_main_io_cleanup","actual_original_session_io_retirement_state"]]]:
		var port: RefCounted=spec[0]
		if port==null or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id()!=_owner: return false
		for method: String in spec[1]:
			if not port.has_method(method): return false
	_session=weakref(session);_frames=actual_frame_dispatcher;_monster_frames=monster_frames;_feature=actual_feature_owner;_io=actual_io_receipts
	return true
func dispatch_original_session_inputs(domain: String, packets: Array, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	return not _final and is_same(_session.get_ref(),session) and _frames.dispatch_original_session_inputs(domain,packets,runtime,session,core)
func dispatch_original_session_phase(name: String, frame: Dictionary, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	return not _final and is_same(_session.get_ref(),session) and _frames.dispatch_original_session_phase(name,frame,runtime,session,core)
func dispatch_original_close_process_boundary(boundary: String, frame: Dictionary, runtime: RefCounted, session: RefCounted, core: RefCounted) -> bool:
	return not _final and is_same(_session.get_ref(),session) and _frames.dispatch_original_close_process_boundary(boundary,frame,runtime,session,core)
func service_original_close_session_resource_obligations(session: RefCounted, core: RefCounted, frame: Dictionary) -> bool:
	if _final or not is_same(_session.get_ref(),session): return false
	# Existing held-Core entry, same budget. Neither method begins another scope.
	return _monster_frames.service_original_close_session_resource_obligations(session,core,frame) and _io.service_original_source_main_io_cleanup(session,core,frame)
func prepare_original_source_session_close(session: RefCounted) -> bool:
	if _final: return is_same(_session.get_ref(),session)
	if not is_same(_session.get_ref(),session) or not _frames.prepare_original_source_session_close(session) or not _monster_frames.prepare_original_source_session_close(session): return false
	var feature: Dictionary=_feature.original_session_retirement_state()
	var io: Dictionary=_io.actual_original_session_io_retirement_state(session)
	# Status is produced by the actual owner ledgers/accepted Main replies. Empty
	# arrays, an S token and a quiet Native packet slot cannot substitute for it.
	if feature.get("status")!="READY" or feature.get("accepted_claims_terminal")!=true or feature.get("code_leases_retired")!=true: return false
	if io.get("status")!="READY" or io.get("actual_native_receipt")!=true or io.get("loaders_terminal")!=true or io.get("accepted_callbacks_terminal")!=true or io.get("renderer_consumers_retired")!=true: return false
	_prepared=true
	return true
func close_original_source_session(session: RefCounted) -> bool:
	if _final: return is_same(_session.get_ref(),session)
	if not _prepared or not session.actual_original_close_process_producer_drained() or not _monster_frames.close_original_source_session(session): return false
	if not _frames.close_original_source_session(session): return false
	_final=true;_feature=null;_io=null;_frames=null;_monster_frames=null
	return true
