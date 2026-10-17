extends RefCounted
## S-only lifetime continuation. The original exit callback still runs once;
## final free is delayed by already accepted obligations, with no new timer.
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _streamer: RefCounted
var _renderer: RefCounted
var _phase := "LIVE"
var _ids: Array[int] = []
var _destruction_requested: Dictionary = {}
func configure_owner(core: RefCounted, streamer: RefCounted, renderer: RefCounted) -> bool:
	if OS.get_thread_caller_id()==OS.get_main_thread_id() or _core!=null or core==null or core.owner_thread_id()!=_owner: return false
	for row: Array in [[streamer,["begin_live_close","live_close_status","finish_owner","service_live_close_at_original_process_phase","live_binding_ready_for_original_renderer_free","finish_visual_resources_at_original_free"]],[renderer,["original_renderer_retirement_ids","request_original_renderer_destruction","original_renderer_destruction_receipt"]]]:
		for method: String in row[1]:
			if row[0]==null or not row[0].has_method(method): return false
	_core=weakref(core); _streamer=streamer; _renderer=renderer
	return true
func begin_original_world_exit() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if _core==null or _phase!="LIVE": return false
	var captured: Dictionary = _renderer.original_renderer_retirement_ids()
	if captured.get("success")!=true or not captured.get("ids") is Array: return false
	for id: Variant in captured.ids:
		if not id is int or id<=0 or id in _ids: return false
		_ids.append(id)
	if not _streamer.begin_live_close(): return false
	_phase="ACCEPTED_BINDINGS"
	return true
func original_p_close_commit(frame: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	if _phase in ["LIVE","CLOSED"]: return {"status":_phase}
	var core: RefCounted = _core.get_ref()
	var budget: RefCounted = core.original_source_session().original_frame_budget()
	var budget_state: Dictionary = budget.snapshot()
	if budget_state.get("open_scopes")!=0: return {"status":"INVALID","error":"original_close_commit_inside_budget_scope"}
	if not frame.get("source_process_frame") is int or frame.source_process_frame<0: return {"status":"INVALID","error":"actual_original_process_frame_required"}
	# Native's actual original closing-P producer supplies the full frame. The
	# streamer validates its exact provenance/schema and executes only accepted
	# commit and scalar cleanup in the necessary lane. Ordinary poll/residency/AI
	# is forbidden here; resource/W wake cannot fabricate a new P frame.
	if not _streamer.service_live_close_at_original_process_phase(frame): return {"status":"INVALID","error":"actual_native_closing_P_cleanup_rejected"}
	# Root's original P resource commit entry, with budget scope stack empty.
	# These narrow ports inspect real S lease/ticket ledgers; they never reissue
	# gameplay, discard accepted transfer, or blanket-free Main Nodes.
	if _phase=="ACCEPTED_BINDINGS":
		for id: int in _ids:
			if not _streamer.live_binding_ready_for_original_renderer_free(id): return {"status":"PENDING","phase":_phase,"service_id":id}
			if not _destruction_requested.has(id):
				if not _renderer.request_original_renderer_destruction(id): return {"status":"PENDING","phase":_phase,"service_id":id}
				_destruction_requested[id]=true
		_phase="RENDERER_RETIREMENT"
	if _phase=="RENDERER_RETIREMENT":
		for id: int in _ids:
			var receipt: Dictionary = _renderer.original_renderer_destruction_receipt(id)
			if receipt.get("status")!="READY": return {"status":receipt.get("status","INVALID"),"phase":_phase,"receipt":receipt}
			if receipt.get("service_id")!=id or receipt.get("actual_node_absent")!=true: return {"status":"INVALID","phase":_phase,"receipt":receipt}
		# The original actor/visual final-free source body, once, owns the one
		# finish_visual_resources_at_original_free call. Do not duplicate it here.
		_phase="RENDERER_READY"
	if _phase in ["RENDERER_READY","READY"]:
		# Original final-free is now allowed to enqueue its one actual binding
		# retirement. Continue servicing until that new debt has really settled.
		return {"status":"RENDERER_READY","streaming_status":_streamer.live_close_status()}
	return {"status":_phase}
func finish_at_original_world_free() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if _phase=="CLOSED": return true
	if _phase not in ["RENDERER_READY","READY"] or _streamer.live_close_status().get("status")!="READY": return false
	# Root's original exit statements and final actor/service GC must have finished
	# BEFORE finishing the coordinator they still call. Core invokes this only
	# after close_at_original_world_exit returned true at the original boundary.
	if not _streamer.finish_owner(): return false
	_phase="CLOSED"
	return true
func original_world_retirement_complete() -> bool: return _phase=="CLOSED"

func original_renderer_retirement_complete() -> bool: return _phase in ["RENDERER_READY","READY","CLOSED"]
