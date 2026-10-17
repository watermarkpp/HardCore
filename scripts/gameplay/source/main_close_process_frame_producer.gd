extends RefCounted
const Listener := preload("res://scripts/gameplay/source/main_close_process_frame_listener.gd")
const CONTRACT := "hardcore.source.closing_process_frame.v1"
var _host: Object
var _tree: SceneTree
var _listener: WeakRef
var _fatal: RefCounted
var _bridge_generation := 0
var _generation := 0
var _last_published_sequence := 0
var _last_main_signal := -1
var _capacity := 0
var _captured: Dictionary = {}
var _accepted: Array[Dictionary] = []
var _pending_service: Dictionary = {}
var _accepted_signal: Dictionary = {}
var _armed := false
var _capture_stopped := false
var _finished := false
var _stop_request: Dictionary = {}
var _stop_receipt: Dictionary = {}
var _missed_opportunities := 0
var _fault: Dictionary = {}
var _session_io: RefCounted

func bind_actual_original_session_io(producer: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _session_io != null or _armed or not _captured.is_empty() or not _pending_service.is_empty() or producer == null: return false
	if producer.get_script() != preload("res://scripts/gameplay/source/main_source_closing_io_producer.gd") or producer.get("_host") != _host or not producer.get("_session_id") is int or producer.get("_session_id") <= 0: return false
	_session_io = producer
	return true

func configure_main(host: Object, tree: SceneTree, actual_bridge_generation: int, actual_generation: int, measured_pending_pair_capacity: int, fatal: RefCounted, actual_session_io: RefCounted = null) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null or host==null or tree==null or actual_bridge_generation<=0 or actual_generation<=0 or measured_pending_pair_capacity<=0: return _fail("actual_Main_once_and_measured_pair_capacity_required")
	if fatal==null or not fatal.has_method("reject_original_main_profile_writer"): return _fail("actual_synchronous_source_fault_required")
	for method: String in ["bind_original_close_process_producer","enqueue_original_close_process_frame","acquire_original_close_process_frame_receipt","ack_original_close_process_frame_receipt","verify_original_close_process_producer_terminal_receipt","acquire_original_close_process_producer_stop_request","confirm_original_close_process_producer_stopped"]:
		if not host.has_method(method): return _fail("MISSING:actual_Native_closing_P_mailbox:"+method)
	if tree.root.get_node_or_null("HardCoreOriginalCloseProcessFrame")!=null: return _fail("actual_single_closing_frame_listener_required")
	_host=host; _tree=tree; _fatal=fatal; _bridge_generation=actual_bridge_generation; _generation=actual_generation; _capacity=measured_pending_pair_capacity
	if actual_session_io != null and not bind_actual_original_session_io(actual_session_io): return _fail("actual_same_Session_IO_binding_required")
	var listener: Node = Listener.new()
	if not listener.configure_main(self):
		listener.free()
		return _fail("actual_Main_listener_configuration_failed")
	listener.name="HardCoreOriginalCloseProcessFrame"
	_listener=weakref(listener)
	tree.root.add_child(listener)
	if not host.bind_original_close_process_producer(self,get_script().get_source_code().sha256_text()):
		_finished = true
		listener.free()
		_listener = null
		return _fail("actual_Native_close_producer_binding_failed")
	_tree.process_frame.connect(_on_actual_process_frame_signal)
	if host.status().get("close_requested") == true: _armed = true
	return {"success":true,"producer_runtime_id":get_instance_id(),"listener_runtime_id":listener.get_instance_id(),"generation":_generation,"pending_pair_capacity":_capacity}
func arm_at_original_close_request() -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host==null or _finished or _capture_stopped or not _fault.is_empty(): return false
	_armed=true
	return true
func _actual_listener() -> Node:
	if _listener==null: return null
	var listener: Node = _listener.get_ref()
	if not is_instance_valid(listener) or listener.get_script()!=Listener or listener.get_tree()!=_tree or not listener.is_inside_tree() or listener.is_queued_for_deletion() or listener.process_mode!=Node.PROCESS_MODE_ALWAYS or not listener.is_processing(): return null
	return listener
func _publication(listener: Node, phase: String, delta: float) -> Dictionary:
	var original := {"contract_id":CONTRACT,"phase":phase,"bridge_generation":_bridge_generation,"producer_runtime_id":get_instance_id(),"listener_runtime_id":listener.get_instance_id(),"listener_script_sha256":listener.get_script().get_source_code().sha256_text(),"generation":_generation,"sequence":_last_published_sequence+1,"main_process_frame":Engine.get_process_frames(),"main_physics_frame":Engine.get_physics_frames(),"wall_usec":Time.get_ticks_usec(),"delta":delta,"tree_paused":_tree.paused,"time_scale":Engine.time_scale}
	if phase == "NODE_PROCESS_SERVICE" and _session_io != null:
		var io: Dictionary = _session_io.capture_actual_original_session_io()
		if io.get("contract_id") != "hardcore.source.main_io_observation.v1":
			_reject("actual_Main_IO_capture_failed",io); return {}
		original["main_io"] = io
		# Stamp after the actual observation, not before its recorded wall time.
		original.wall_usec = Time.get_ticks_usec()
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(original,true,false)
	if captured.get("success")!=true:
		_reject("original_close_runtime_capture_failed",captured)
		return {}
	return captured.value
func _on_actual_process_frame_signal() -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	if _host==null or _finished or not _fault.is_empty(): return
	var actual_state: Dictionary = _host.status()
	if actual_state.get("started") != true: return
	if actual_state.get("close_requested") == true and not _capture_stopped: _armed = true
	_service_actual_receipts_and_stop()
	if not _armed or _capture_stopped: return
	var listener: Node = _actual_listener()
	if listener==null:
		_reject("CLOSE_SERVICE_UNAVAILABLE",{})
		return
	var main_frame := Engine.get_process_frames()
	if main_frame<=_last_main_signal: return
	_last_main_signal=main_frame
	if not _pending_service.is_empty(): _submit_pending_service()
	if not _pending_service.is_empty() or not _accepted_signal.is_empty() or _accepted.size()+2>_capacity*2:
		_missed_opportunities+=1
		return
	var delta := listener.get_process_delta_time()
	if not is_finite(delta) or delta<0.0:
		_reject("actual_SIGNAL_delta_invalid",{})
		return
	var original: Dictionary = _publication(listener,"PROCESS_SIGNAL",delta)
	if original.is_empty(): return
	_captured=original
	var reply: Dictionary = _host.enqueue_original_close_process_frame(original)
	if str(reply.get("status","")) in ["BUSY","BACKPRESSURE"]:
		# Unadmitted opportunity is explicitly missed; never replay this old
		# SIGNAL to fulfill an await registered after its actual Main occurrence.
		_missed_opportunities+=1
		_captured={}
		return
	if not _accept_actual_reply(original,reply): return
	_accepted_signal=original
	_captured={}
func record_actual_original_process_frame(listener: Node, delta: float) -> void:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	if _host==null or _finished or not _fault.is_empty(): return
	_service_actual_receipts_and_stop()
	if not _pending_service.is_empty(): _submit_pending_service()
	if _accepted_signal.is_empty(): return
	# Complete an accepted half-pair even if STOP arrived between the phases.
	if listener!=_actual_listener() or Engine.get_process_frames()!=_accepted_signal.main_process_frame or not is_finite(delta) or delta<0.0 or listener.get_process_delta_time()!=delta:
		_reject("accepted_SIGNAL_lost_actual_NODE_PROCESS_SERVICE",{})
		return
	_pending_service=_publication(listener,"NODE_PROCESS_SERVICE",delta)
	_submit_pending_service()
	_service_actual_receipts_and_stop()
func _submit_pending_service() -> bool:
	if _pending_service.is_empty(): return true
	var reply: Dictionary = _host.enqueue_original_close_process_frame(_pending_service)
	if str(reply.get("status","")) in ["BUSY","BACKPRESSURE"]: return false
	if not _accept_actual_reply(_pending_service,reply): return false
	_pending_service={}
	_accepted_signal={}
	return true
func _accept_actual_reply(original: Dictionary, reply: Dictionary) -> bool:
	if str(reply.get("status","")) not in ["ACCEPTED","DUPLICATE"] or reply.get("publication")!=original:
		_reject("actual_Native_closing_phase_admission_rejected",reply)
		return false
	if int(original.sequence)!=_last_published_sequence+1:
		_reject("original_phase_sequence_not_contiguous",{})
		return false
	_last_published_sequence=int(original.sequence)
	_accepted.append(reply)
	return true
func verify_original_close_process_frame_publication(publication: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _finished or not _fault.is_empty() or _actual_listener()==null: return _fail("actual_live_Main_close_producer_required")
	if publication==_captured or publication==_pending_service:
		return {"success":true,"publication":publication,"producer_runtime_id":get_instance_id(),"listener_runtime_id":_actual_listener().get_instance_id(),"producer_script_sha256":get_script().get_source_code().sha256_text()}
	for recorded: Dictionary in _accepted:
		if recorded.get("publication")==publication:
			return {"success":true,"publication":publication,"producer_runtime_id":get_instance_id(),"listener_runtime_id":_actual_listener().get_instance_id(),"producer_script_sha256":get_script().get_source_code().sha256_text()}
	return _fail("uncaptured_original_Main_process_phase")
func _service_actual_receipts_and_stop() -> void:
	while true:
		var receipt: Dictionary = _host.acquire_original_close_process_frame_receipt()
		if receipt.get("status") in ["PENDING","BUSY"]: break
		if receipt.get("status")!="CONSUMED" or receipt.get("source_hook_completed")!=true:
			_reject("actual_consumed_phase_receipt_invalid",receipt)
			return
		var found := -1
		for index: int in range(_accepted.size()):
			if _accepted[index].get("publication")==receipt.get("publication"):
				found=index
				break
		if found<0:
			_reject("foreign_closing_phase_consumption_receipt",receipt)
			return
		if not _host.ack_original_close_process_frame_receipt(receipt): return
		_accepted.remove_at(found)
	if _stop_request.is_empty():
		var request: Dictionary = _host.acquire_original_close_process_producer_stop_request()
		if request.get("status")=="STOP_REQUESTED":
			if request.get("generation")!=_generation or request.get("bridge_generation")!=_bridge_generation:
				_reject("foreign_producer_STOP_request",request)
				return
			_stop_request=request
			_armed=false
		elif request.get("status") not in ["PENDING","BUSY"]:
			_reject("actual_STOP_request_status_invalid",request)
			return
	if not _stop_request.is_empty() and _accepted_signal.is_empty() and _pending_service.is_empty():
		_capture_stopped=true
		if _stop_receipt.is_empty():
			_stop_receipt={"contract_id":"hardcore.source.closing_process_stop.v1","bridge_generation":_bridge_generation,"generation":_generation,"producer_runtime_id":get_instance_id(),"last_published_sequence":_last_published_sequence}
		_host.confirm_original_close_process_producer_stopped(_stop_receipt)
func verify_original_close_process_producer_stopped(receipt: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _capture_stopped or _armed or not _pending_service.is_empty() or not _accepted_signal.is_empty() or receipt!=_stop_receipt: return _fail("actual_producer_NOT_STOPPED")
	return {"success":true,"receipt":_stop_receipt,"producer_runtime_id":get_instance_id(),"listener_runtime_id":_actual_listener().get_instance_id() if _actual_listener()!=null else 0}
func finish_after_actual_prestart_abort() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _finished: return false
	var state: Dictionary = _host.status()
	if state.get("main_channels_aborted") != true or state.get("started") != false or state.get("physics_handoff_prepared") != false: return false
	if not _accepted.is_empty() or not _pending_service.is_empty() or not _accepted_signal.is_empty() or not _captured.is_empty() or _last_published_sequence != 0: return false
	_finished = true
	if _tree.process_frame.is_connected(_on_actual_process_frame_signal): _tree.process_frame.disconnect(_on_actual_process_frame_signal)
	var listener: Node = _actual_listener()
	if listener != null: listener.free()
	_listener = null
	_session_io = null
	_host = null
	return true

func finish_at_actual_Host_close(receipt: Dictionary) -> bool:
	if not _capture_stopped or not _pending_service.is_empty() or not _accepted_signal.is_empty() or not _accepted.is_empty() or not _host.verify_original_close_process_producer_terminal_receipt(receipt): return false
	_finished=true
	if _tree.process_frame.is_connected(_on_actual_process_frame_signal): _tree.process_frame.disconnect(_on_actual_process_frame_signal)
	var listener: Node = _listener.get_ref()
	if is_instance_valid(listener): listener.free()
	return true
func original_listener_exit(listener: Node) -> void:
	if not _finished and _listener!=null and _listener.get_ref()==listener: _reject("CLOSE_SERVICE_UNAVAILABLE",{})
func capture_actual_closing_process_obligations() -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	return {"accepted":_accepted.duplicate(true),"pending_service":_pending_service.duplicate(true),"accepted_signal":_accepted_signal.duplicate(true),"stop_receipt":_stop_receipt.duplicate(true),"capture_stopped":_capture_stopped,"missed_unadmitted_opportunities":_missed_opportunities,"fault":_fault.duplicate(true)}
func _reject(code: String, details: Dictionary) -> void:
	if not _fault.is_empty(): return
	_fault={"code":code,"details":details}
	_fatal.reject_original_main_profile_writer(_fault)
func _fail(code: String) -> Dictionary: return {"success":false,"errors":[code]}
