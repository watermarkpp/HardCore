extends RefCounted

## The original Root queue is a pure fact ledger of its actual Main claims.
## Main physical IO remains a separately inspected obligation after Node0 reply.
var _owner := OS.get_thread_caller_id()
var _root: RefCounted
var _world: RefCounted
var _caster: RefCounted
var _budget: RefCounted
var _host: Object
var _owner_descriptor: Dictionary
var _reserve_usec := 0
var _request_sequence := 0
var _job: Dictionary = {}
var _last_completed: Dictionary = {}
var _last_source_process_frame := -1
var _frame_texture_threaded: Dictionary = {}
var _loading_texture_threaded: Array = []
var _last_io: Dictionary
var _loading_state: Variant
var _commit_open := false
var _commit_source_p := -1

func configure_owner(root: RefCounted, world: RefCounted, session: RefCounted,
	caster: RefCounted, actual_owner_descriptor: Dictionary, original_reservation_usec: int) -> bool:
	if _root != null or OS.get_thread_caller_id() == OS.get_main_thread_id() or root == null or world == null or session == null or caster == null or original_reservation_usec < 0: return false
	if actual_owner_descriptor.get("contract_id") != "source.caster.warm.owner.v1" or actual_owner_descriptor.get("source_root_id") != root.get_instance_id() or actual_owner_descriptor.get("world_context") != world.current_world_identity(): return false
	var proof: Dictionary = caster.original_loading_publication()
	if proof.get("main_executor_id") != actual_owner_descriptor.get("main_executor_id") or proof.get("world_context") != actual_owner_descriptor.get("world_context"): return false
	_root = root; _world = world; _caster = caster; _budget = session.original_frame_budget()
	_host = world.original_caster_reply_host(); _owner_descriptor = actual_owner_descriptor.duplicate(true)
	_reserve_usec = original_reservation_usec
	return _budget.owner_thread_id() == _owner and caster.register_original_warm_owner(self)

func owner_thread_id() -> int: return _owner
func _check() -> void: assert(OS.get_thread_caller_id() == _owner and _root != null)
func _fault(code: String) -> bool:
	_world.fault(code,{"owner_descriptor":_owner_descriptor})
	return false
func _current_owner_descriptor() -> Dictionary:
	var current: Dictionary = _owner_descriptor.duplicate(true)
	current.world_context = _world.current_world_identity()
	return current
func original_frame_texture_claim_facts() -> Dictionary:
	_check()
	return _frame_texture_threaded.duplicate(true)
func _complete_transport() -> bool:
	if _job.is_empty() or not _job.get("applied",false): return _job.is_empty()
	if _caster.has_pending_original_caster_event(int(_job.command.command_id)): return false
	if not _budget.retire_settlement(int(_job.reservation.reservation_id)): return _fault("actual_warm_budget_settlement_retire_failed")
	_last_completed = _job; _job = {}
	return true

func _submit(operation: String, arguments: Array, category: String, necessary: bool) -> bool:
	_check()
	if not _complete_transport() or not _job.is_empty(): return false
	var frame: Dictionary = _world.current_clock_frame()
	if not frame.get("source_process_frame") is int: return _fault("actual_warm_source_process_frame_missing")
	if int(frame.source_process_frame) == _last_source_process_frame: return false
	if int(_budget.snapshot().open_scopes) != 0: return false
	var lane: int = _budget.LANE_NECESSARY if necessary else _budget.LANE_BACKGROUND
	if not necessary and _budget.remaining_usec() <= 0: return false
	var reservation: Dictionary = _budget.reserve_live(category,lane,_reserve_usec)
	if reservation.is_empty(): return false
	if reservation.owner_session_id != _owner_descriptor.owner_session_id:
		_budget.release_unaccepted(reservation)
		return _fault("actual_warm_single_session_budget_owner_mismatch")
	var payload := {"contract_id":"source.caster.warm.request.v1","source_root_id":_root.get_instance_id(),
		"world_context":_world.current_world_identity(),"arguments":arguments,"reservation":reservation,
		"request_sequence":_request_sequence+1,"source_process_frame":int(frame.source_process_frame)}
	var accepted: Dictionary = _caster.emit_original_source_warm_event(operation,payload)
	if accepted.get("status") != "ACCEPTED":
		if not _budget.release_unaccepted(reservation):
			_job = {"unaccepted_reservation":reservation,"operation":operation,"admission_failure":accepted}
			return _fault("actual_warm_unaccepted_reservation_release_failed")
		if accepted.get("status") == "INVALID": return _fault("actual_warm_event_rejected")
		return false
	_request_sequence += 1; _last_source_process_frame = int(frame.source_process_frame)
	_job = {"operation":operation,"arguments":arguments.duplicate(true),"command":accepted.command,
		"ticket":accepted.reply_identity,"reservation":reservation,"owner_descriptor":_current_owner_descriptor(),"applied":false,"settled":false}
	return false # Accepted original work is pending until actual Main receipt.

func consume_original_warm_receipt(receipt: Dictionary, observation: Dictionary) -> Dictionary:
	_check()
	if _job.is_empty() or receipt.get("source_command") != _job.command or not receipt.get("warm_result") is Dictionary: return {"status":"INVALID"}
	if _job.applied: return {"status":"READY"}
	if not _commit_open or _commit_source_p != int(_host.current_clock_frame().source_process_frame): return {"status":"PENDING"}
	var result: Dictionary = receipt.warm_result
	if result.get("contract_id") != "source.caster.warm.result.v1" or result.get("owner_descriptor") != _job.owner_descriptor or result.get("request_sequence") != _request_sequence or not result.get("frame_texture_threaded") is Dictionary or not result.get("loading_texture_threaded") is Array or not result.get("actual_io") is Dictionary: return {"status":"INVALID"}
	if int(_budget.snapshot().open_scopes) != 0: return {"status":"PENDING"}
	if not _job.settled:
		if not observation.get("native_received_usec") is int or not observation.get("native_s_poll_epoch") is int: return {"status":"INVALID"}
		var reply := {"executed":true,"request":{"reservation":_job.reservation,"identity":_job.ticket,
			"submitted_usec":int(_job.command.source_clock.presentation_submitted_usec)},
			"started_usec":int(receipt.actual_started_usec),"finished_usec":int(receipt.actual_finished_usec),
			"native_s_poll_epoch":int(observation.native_s_poll_epoch)}
		var settled: Dictionary = _budget.settle_live(_job.reservation,_job.ticket,reply,
			int(observation.native_received_usec),int(_host.current_clock_frame().epoch))
		if settled.is_empty(): return {"status":"INVALID"}
		_job.settled = true; _job.settlement = settled
	# Full source queue replacement is the actual once-applied Main result.
	_frame_texture_threaded = result.frame_texture_threaded.duplicate(true)
	_loading_texture_threaded = result.loading_texture_threaded.duplicate()
	_last_io = result.actual_io.duplicate(true); _loading_state = result.actual_loading_window_active
	_job.result = result; _job.applied = true
	return {"status":"READY"}

func pump_pending_warm_textures() -> void:
	_check()
	_submit("source_caster_warm::collect_admit",[],"caster_texture_warm",false)
func _retired(operation: String, loading: bool) -> bool:
	_check()
	_complete_transport()
	if not _last_completed.is_empty() and _last_completed.operation == operation:
		var actual: Dictionary = _last_completed.result.actual_io
		if actual.get("owner_descriptor") != _last_completed.owner_descriptor: return _fault("actual_warm_IO_identity_changed")
		if loading:
			if actual.loading_texture_threaded.is_empty() and actual.persistent_transfers.is_empty(): return true
		elif actual.retirement_requested == true and actual.frame_texture_threaded.is_empty(): return true
	return _submit(operation,[],"caster_texture_retirement",true)
func retire_pending_warm_textures() -> bool:
	return _retired("source_caster_warm::retire",false)
func retire_loading_texture_claims() -> bool:
	return _retired("source_caster_warm::loading_claim_retire",true)
func set_loading_window_active(active: bool) -> bool:
	_check()
	_complete_transport()
	if not _last_completed.is_empty() and _last_completed.operation == "source_caster_warm::loading_state" and _last_completed.arguments == [active] and _loading_state == active: return true
	return _submit("source_caster_warm::loading_state",[active],"caster_texture_loading_state",true)

func actual_original_warm_owner_quiescent() -> bool:
	_check()
	_complete_transport()
	return _job.is_empty() and _frame_texture_threaded.is_empty() and _loading_texture_threaded.is_empty() and not _last_io.is_empty() and _last_io.persistent_transfers.is_empty() and _last_io.retirement_requested == true
func finish_original_warm_owner() -> bool:
	if not actual_original_warm_owner_quiescent(): return false
	_root = null; _world = null; _caster = null; _budget = null; _host = null
	return true
func begin_original_warm_commit_phase(frame: Dictionary) -> bool:
	_check()
	if _commit_open or not frame.get("source_process_frame") is int or not frame.get("epoch") is int or int(_budget.snapshot().open_scopes) != 0: return false
	var current: Dictionary = _host.current_clock_frame()
	if frame.source_process_frame != current.get("source_process_frame") or frame.epoch != current.get("epoch") or frame.get("phase") != current.get("phase"): return false
	var permitted: bool = frame.get("phase") == "P_GROUP"
	if frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("closing_session") == true:
		var publication: Variant = frame.get("closing_process_publication")
		permitted = publication is Dictionary and publication == current.get("closing_process_publication") and publication.get("phase") == "NODE_PROCESS_SERVICE"
	if not permitted: return false
	_commit_open = true; _commit_source_p = int(frame.source_process_frame)
	if not _accept_original_partial_warm_claims():
		_commit_open=false;_commit_source_p=-1
		return false
	return true
func end_original_warm_commit_phase() -> bool:
	_check()
	if not _commit_open: return false
	_commit_open = false; _commit_source_p = -1
	return true

var _issued_feature_owner: RefCounted
func configure_original_issued_claim_bridge(feature_owner: RefCounted) -> bool:
	if feature_owner==null or _issued_feature_owner!=null or feature_owner.owner_thread_id()!=_owner or not feature_owner.has_method("accept_original_issued_claim_offer"): return false
	_issued_feature_owner=feature_owner;return true
func _accept_original_partial_warm_claims() -> bool:
	if _issued_feature_owner==null: return _fault("MISSING:actual_S_Feature_issued_claim_bridge")
	if _job.is_empty(): return true
	if _job.get("applied",false): return true # Actual full Source receipt already consumed.
	# Uses existing caster reply record, even before full Main reply exists.
	# No status/get, additional scheduler, clock phase or reservation is created.
	var actual: Dictionary=_host.poll_original_caster_event_reply(_job.ticket)
	if actual.get("status") in ["BUSY","PENDING","READY"]:
		var offers: Variant=actual.get("claim_transfers")
		if not offers is Array: return _fault("actual_partial_caster_claim_schema")
		for evidence: Dictionary in offers:
			if evidence.get("owner_descriptor")!=_job.owner_descriptor or evidence.get("identity",{}).get("bridge_generation")!=_job.ticket.bridge_generation or evidence.identity.journal_generation!=_job.ticket.journal_generation or evidence.identity.event_ordinal!=_job.ticket.event_ordinal: return _fault("actual_partial_caster_claim_identity")
			var accepted: Dictionary=_issued_feature_owner.accept_original_issued_claim_offer(evidence.identity)
			if accepted.get("status")=="INVALID": return _fault("actual_partial_caster_claim_acceptance_failed")
		return true
	return _fault("actual_partial_caster_poll_failed")
