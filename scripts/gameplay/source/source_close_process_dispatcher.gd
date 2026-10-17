extends RefCounted
## Native alone advances Source P for SIGNAL; SERVICE has the same real pair.
static func dispatch_original_close_process_frame(frame: Dictionary, runtime: RefCounted, session: RefCounted, world: RefCounted, source_frames: RefCounted, host: Object) -> bool:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or runtime==null or session==null or host==null or runtime.owner_thread_id()!=OS.get_thread_caller_id() or session.owner_thread_id()!=OS.get_thread_caller_id(): return false
	if frame!=host.current_clock_frame() or frame.get("closing_session")!=true or not frame.get("source_process_frame") is int or not frame.get("actual_main_process_frame") is int or not frame.get("closing_process_publication") is Dictionary: return false
	if world!=null:
		if world.owner_thread_id()!=runtime.owner_thread_id() or not world.has_method("on_original_close_process_phase"): return false
		return world.on_original_close_process_phase(frame)
	# No-world Source phase still needs its original persistent tree/callback/
	# deferred scopes. Root implements that actual source service, not a flag.
	if source_frames==null or not source_frames.has_method("service_original_close_session_obligations"):
		session.fault("MISSING_original_close_session_source_scopes",{})
		return false
	return source_frames.service_original_close_session_obligations(session,frame)
