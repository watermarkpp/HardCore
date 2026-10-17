extends RefCounted
## Original MonsterSourceFrames policy. Only actual Main replies reveal status,
## dimensions and textures. One Session instance survives map/world changes.
const CACHE_BUDGET := 48 * 1024 * 1024
const MAX_IN_FLIGHT := 2
var _owner := OS.get_thread_caller_id()
var _data: Dictionary
var _exact_sources: Dictionary
var _session: WeakRef
var _core: WeakRef
var _endpoint: RefCounted
var _requested: Dictionary = {}
var _textures: Dictionary = {}
var _queue: Array[String] = []
var _last_use: Dictionary = {}
var _resident_bytes := 0
var _last_poll_frame := -1
var _loads := 0
var _evictions := 0
var _handoff: Dictionary
var _loading_scope: Dictionary
var _root_op := 0
var _escrow_op := 0
var _escrows: Array = []
var _retiring := false
var _last_demand := 0

func owner_thread_id() -> int: return _owner
func configure_session(session: RefCounted, publication: Dictionary) -> bool:
	if _session != null or _owner == OS.get_main_thread_id() or session.owner_thread_id() != _owner: return false
	if publication.get("contract_id") != "world.source_frames.original_handoff.v1" or not publication.get("data") is Dictionary or not publication.get("projectile_sources") is Dictionary: return false
	# The original static cache may have been used by preview/old Main. Such
	# claims require an actual transfer; zero cannot be guessed by bootstrap.
	if publication.get("original_requested_count") != 0 or publication.get("original_texture_count") != 0 or publication.get("original_queued_count") != 0 or publication.get("original_last_poll_frame") != -1: return false
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = graph.capture(publication, true, false)
	if copied.get("success") != true: return false
	_handoff = copied.value
	_data = _handoff.data
	_exact_sources = _handoff.projectile_sources
	_session = weakref(session)
	return true

func bind_current_world(core: RefCounted, endpoint: RefCounted, publication: Dictionary) -> bool:
	if _session == null or core.owner_thread_id() != _owner or endpoint.owner_thread_id() != _owner: return false
	if _core != null and _core.get_ref() != null: return false
	if publication.get("session_cache_id") != _handoff.session_cache_id or publication.get("data_sha256") != _handoff.data_sha256 or publication.get("projectile_sha256") != _handoff.projectile_sha256: return false
	var scope: String="source_overlay_frames:%d" % _handoff.session_cache_id
	var records: Array=[]
	for record: Dictionary in _textures.values(): records.append({"token":record.token,"size":record.size})
	if not endpoint.has_method("adopt_original_source_texture_metadata") or not endpoint.adopt_original_source_texture_metadata(scope,records,publication.get("actual_texture_roots",{})): return false
	_core = weakref(core); _endpoint = endpoint; _retiring = false; _loading_scope=publication.loading_scope
	return true

func profile_for_id(monster_id: int) -> Dictionary:
	var key := str(_data.get("profile_by_monster_id", {}).get(str(monster_id), ""))
	if monster_id == 224: key = "cow_king"
	return _data.get("profiles", {}).get(key, {})

func request_profile(profile: Dictionary, direction := 0) -> void:
	var count := int(profile.get("frame_count", profile.get("frames_per_direction", 0)))
	var records: Array = profile.get("frames", [])
	for index in range(direction * count, mini((direction + 1) * count, records.size())):
		request(str(records[index].path))

func request(path: String) -> void:
	if _retiring or _textures.has(path) or _requested.has(path) or _queue.has(path): return
	_queue.append(path)

func _profile_has_id(profile: Dictionary, monster_id: int) -> bool:
	for value: Variant in profile.get("monster_ids", []):
		if int(value) == monster_id: return true
	return false

func prewarm_for_monster_id(monster_id: int) -> void:
	for profile: Dictionary in _exact_sources.get("profiles", {}).values():
		if _profile_has_id(profile, monster_id): request_profile(profile)

func accept_original_texture_demand(demand: Dictionary) -> bool:
	if demand.get("contract_id") != "world.source_frames.original_demand.v1" or demand.get("session_cache_id") != _handoff.session_cache_id or not demand.get("sequence") is int or demand.sequence != _last_demand + 1 or not demand.get("path") is String: return false
	_last_demand = demand.sequence
	var path: String = demand.path
	if _textures.has(path):
		_last_use[path] = int(_core.get_ref().clock_ports.get_process_frames())
	elif not _retiring and not _requested.has(path):
		_queue.erase(path)
		_queue.push_front(path)
	return true

func _intent(op: StringName, args: Array, path: String, cleanup := false) -> int:
	var admitted: int=_endpoint.enqueue_live_operation(op,args,"source_frames:%d:%s" % [_handoff.session_cache_id,path],[],cleanup)
	if admitted<=0: _fault("source_frames_LIVE_intent_admission_failed")
	return admitted

func poll() -> void:
	assert(OS.get_thread_caller_id() == _owner and _core != null and _core.get_ref() != null)
	var frame := int(_core.get_ref().clock_ports.get_process_frames())
	if frame == _last_poll_frame: return
	_last_poll_frame = frame
	# The original empty poll performs no loader call and needs no Loading
	# permission. Preserve that case before checking any real pending claim.
	if _requested.is_empty() and _queue.is_empty() and _root_op == 0 and _escrow_op == 0 and _escrows.is_empty(): return
	if not _endpoint.live_resource_phase():
		_poll_original_loading(frame)
		return
	service_accepted_results(frame)
	if _root_op != 0 or _escrow_op != 0: return
	for path: String in _requested.keys():
		var job: Dictionary = _requested[path]
		if job.op != 0: continue
		job.phase = "status"
		job.op = _intent(&"status",[path],path,_retiring)
	while not _retiring and _requested.size() < MAX_IN_FLIGHT and not _queue.is_empty():
		var path: String = _queue.pop_front()
		_requested[path] = {"phase":"request","op":_intent(&"load_threaded_request",[path,"Texture2D",false],path),"claim":false}

func service_accepted_results(frame: int) -> void:
	# A reply wake may advance accepted state without inventing a new P frame.
	# Admission and LRU frame numbers always come from the actual Source P.
	if _root_op != 0:
		var root: Dictionary = _endpoint.take_live_operation(_root_op)
		if root.status == "COMMITTED":
			_root_op = 0
			if not _escrows.is_empty(): _escrow_op = _intent(&"close_get_escrow",[_escrows.duplicate()],"escrow",true)
		elif root.status != "PENDING": _fault("source_frames_actual_roots_failed"); return
		if _root_op != 0: return
	if _escrow_op != 0:
		var escrow: Dictionary = _endpoint.take_live_operation(_escrow_op)
		if escrow.status == "COMMITTED": _escrow_op = 0; _escrows.clear()
		elif escrow.status != "PENDING": _fault("source_frames_actual_escrow_failed"); return
		if _escrow_op != 0: return
	for path: String in _requested.keys():
		var job: Dictionary = _requested[path]
		if job.op == 0: continue
		var result: Dictionary = _endpoint.take_live_operation(job.op)
		if result.status == "PENDING": continue
		if result.status == "ABANDONED_UNACCEPTED": _requested.erase(path); continue
		if result.status != "COMMITTED": _fault("source_frames_actual_result_invalid"); return
		job.op = 0
		match job.phase:
			"request":
				if result.result == OK: job.claim = true
				else: _requested.erase(path)
			"status":
				match int(result.result):
					3, 2:
						job.phase = "get"; job.op = _intent(&"load_threaded_get",[path],path,_retiring)
					0:
						job.phase = "forget"; job.op = _intent(&"forget_invalid_claim",[path,1],path,true)
					1: pass
					_: _fault("source_frames_actual_status_invalid")
			"get":
				_requested.erase(path)
				var loaded: Variant = result.get("texture")
				if loaded == null: continue
				if not _install_actual_texture(path,int(loaded),_endpoint.texture_size(loaded),frame): return
				# Exact get receipt; never close another consumer's/newer escrow.
				_escrows.append(int(result.identity.op_sequence))
			"forget": _requested.erase(path)
	if not _escrows.is_empty() and _root_op == 0 and _escrow_op == 0:
		var tokens: Array[int] = []
		for entry: Dictionary in _textures.values(): tokens.append(entry.token)
		_root_op = _intent(&"replace_roots",["source_overlay_frames:%d" % _handoff.session_cache_id,tokens],"roots",_retiring)

func retire_pending_threaded_claims() -> bool:
	_retiring = true
	_queue.clear() # Source has stopped; these requests were never accepted.
	poll()
	return _requested.is_empty() and _root_op == 0 and _escrow_op == 0

func release_current_world() -> bool:
	if not _retiring or not _requested.is_empty() or _root_op != 0 or _escrow_op != 0: return false
	if _core.get_ref().original_session_close_resource_owner_held(): return false
	var tokens: Array=[]
	for record: Dictionary in _textures.values(): tokens.append(record.token)
	if not _endpoint.release_original_source_texture_metadata("source_overlay_frames:%d" % _handoff.session_cache_id,tokens,self): return false
	_core = null; _endpoint = null
	return true # Cached textures remain Session-owned, as the original static cache.

func diagnostics() -> Dictionary:
	return {"entries":_textures.size(),"resident_bytes":_resident_bytes,"requested":_requested.size(),"queued":_queue.size(),"loads":_loads,"evictions":_evictions}
func _fault(code: String) -> void: _core.get_ref().fault(code,{})

var _session_cleanup_started := false
var _session_cache_released := false
var _session_root_release := 0
var _session_close_final := false
func service_original_close_session_resource_obligations(session: RefCounted, core: RefCounted, frame: Dictionary) -> bool:
	if not is_same(_session.get_ref(),session) or core.owner_thread_id()!=_owner or not is_same(_core.get_ref(),core) or frame!=core.current_clock_frame() or frame.get("closing_session")!=true: return false
	if frame.get("phase")!="P_CLOSE_SERVICE" or frame.get("source_boundary")!="NODE_PROCESS_SERVICE" or frame.get("closing_process_publication",{}).get("phase")!="NODE_PROCESS_SERVICE": return false
	# Runtime's existing entry has opened this exact endpoint already. There is
	# no second begin/end, world clock or budget stack here.
	_session_cleanup_started=true;_retiring=true;_queue.clear()
	poll()
	if not _requested.is_empty() or _root_op!=0 or _escrow_op!=0: return true
	if not _session_cache_released and _session_root_release==0:
		for path: String in _textures:
			if not core.emit_original_main_event(&"source_overlay_evict",[_handoff.session_cache_id,path]): return false
		_session_root_release=_intent(&"replace_roots",["source_overlay_frames:%d" % _handoff.session_cache_id,[]],"session_close_roots",true)
	if _session_root_release!=0:
		var actual: Dictionary=_endpoint.take_live_operation(_session_root_release)
		if actual.status=="COMMITTED":
			_session_root_release=0;_session_cache_released=true
			if not core.emit_original_main_event(&"source_overlay_close",[_handoff.session_cache_id]): return false
			_textures.clear();_last_use.clear();_resident_bytes=0
		elif actual.status!="PENDING": return false
	return true
func prepare_original_source_session_close(session: RefCounted) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if not is_same(_session.get_ref(),session) or not _session_cleanup_started: return false
	# Accepted Native retirement/transfer remains visible after result commit.
	return _session_cache_released and _requested.is_empty() and _queue.is_empty() and _root_op==0 and _escrow_op==0 and _escrows.is_empty() and _session_root_release==0 and _endpoint.live_operations_drained()
func close_original_source_session(session: RefCounted) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if _session_close_final: return is_same(_session.get_ref(),session)
	if not prepare_original_source_session_close(session) or not session.actual_original_close_process_producer_drained(): return false
	_core=null;_endpoint=null;_session_close_final=true
	return true

func _install_actual_texture(path: String, token: int, size: Vector2, frame: int) -> bool:
	if token==0 or not size.is_finite() or size.x<=0 or size.y<=0: _fault("source_frames_actual_dimensions_invalid"); return false
	_loads+=1
	var bytes:=int(size.x)*int(size.y)*4
	while _resident_bytes+bytes>CACHE_BUDGET and not _textures.is_empty():
		var oldest:=str(_textures.keys()[0])
		for key: String in _textures:
			if int(_last_use[key])<int(_last_use[oldest]): oldest=key
		_resident_bytes-=int(_textures[oldest].bytes)
		_textures.erase(oldest);_last_use.erase(oldest);_evictions+=1
		if not _core.get_ref().emit_original_main_event(&"source_overlay_evict",[_handoff.session_cache_id,oldest]): return false
	_textures[path]={"token":token,"bytes":bytes,"size":size}
	_last_use[path]=frame;_resident_bytes+=bytes
	return _core.get_ref().emit_original_main_event(&"source_overlay_install",[_handoff.session_cache_id,path,token])
func _poll_original_loading(frame: int) -> void:
	# The original bootstrap entry has an actual cold continuation, guarded by
	# Main/Native Loading permission and the same external budget ledger. LIVE
	# never enters this method. Readiness still comes from real loader status.
	var session: RefCounted=_session.get_ref()
	if not session.actual_original_loading_scope_is_current(_loading_scope):
		_fault("source_frames_actual_Loading_scope_missing"); return
	for path: String in _requested.keys():
		var status: int=_endpoint.load_threaded_get_status(path)
		if status in [3,2]:
			var texture: Variant=_endpoint.load_threaded_get(path)
			_requested.erase(path)
			if texture==null: continue
			var receipt: int=_endpoint.original_source_texture_get_receipt(int(texture))
			if receipt<=0 or not _install_actual_texture(path,int(texture),_endpoint.texture_size(texture),frame): return
			var tokens: Array=[]
			for value: Dictionary in _textures.values(): tokens.append(value.token)
			if not _endpoint.replace_original_source_texture_roots("source_overlay_frames:%d" % _handoff.session_cache_id,tokens) or not _endpoint.close_original_source_texture_escrows([receipt]): _fault("source_frames_actual_Loading_texture_retention"); return
		elif status==0:
			if not _endpoint.forget_invalid_claim(path,1): _fault("source_frames_actual_invalid_claim"); return
			_requested.erase(path)
		elif status!=1: _fault("source_frames_actual_Loading_status"); return
	while not _retiring and _requested.size()<MAX_IN_FLIGHT and not _queue.is_empty():
		var path: String=_queue.pop_front()
		if _endpoint.load_threaded_request(path,"Texture2D",false)==OK: _requested[path]={"phase":"cold","op":0,"claim":true}

func owns_original_source_texture_root(scope: String, tokens: Array) -> bool:
	if OS.get_thread_caller_id()!=_owner or _session==null or not _session.get_ref().is_original_source_frames_owner(self) or scope!="source_overlay_frames:%d" % _handoff.session_cache_id or _root_op!=0 or _escrow_op!=0 or not _escrows.is_empty(): return false
	var actual: Array=[]
	for record: Dictionary in _textures.values(): actual.append(record.token)
	return actual==tokens
