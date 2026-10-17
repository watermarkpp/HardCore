extends RefCounted

## Main-only leaf. Registry remains the sole mutable cache and pending path queue.
const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const PER_FRAME := 2 # Source GameRoot.FRAME_TEXTURE_WARM_PER_FRAME.
const MAX_IN_FLIGHT := 4 # Source GameRoot.FRAME_TEXTURE_WARM_MAX_IN_FLIGHT.
const OPERATIONS := ["source_caster_warm::collect_admit", "source_caster_warm::retire",
	"source_caster_warm::loading_state", "source_caster_warm::loading_claim_retire"]
var _caster: RefCounted
var _root: Node
var _content: Node
var _closing_producer: RefCounted
var _owner_descriptor: Dictionary
var _claims: Dictionary = {}
var _loading_claims: Dictionary = {}
var _transfers: Dictionary = {}
var _claim_sequence := 0
var _main_frame := -1
var _attempts_in_frame := 0
var _retiring := false
var _history: Array[Dictionary] = []
var _active_ticket: Dictionary
var _loading_adopted := false
var _original_main_root_id := 0
var _registration_descriptor: Dictionary

func configure_main(caster: RefCounted, root: Node, content: Node,
	closing_producer: RefCounted, owner_descriptor: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _caster != null or root == null or not root.is_inside_tree(): return _fail("actual_Main_root_once_required")
	if caster == null or content == null or closing_producer == null: return _fail("MISSING:actual_warm_Main_closing_IO_producer")
	for method: String in ["bind_original_caster_warm_io_observer", "release_original_caster_warm_io_observer", "inspect_actual_original_threaded_claim_transfer"]:
		if not closing_producer.has_method(method): return _fail("MISSING:actual_Main_closing_producer:" + method)
	if not content.has_method("retire_threaded_resource_claims") or not content.has_method("threaded_resource_claim_diagnostics"): return _fail("MISSING:actual_Main_ContentLayers_claim_owner")
	if owner_descriptor.get("contract_id") != "source.caster.warm.owner.v1" or owner_descriptor.get("main_executor_id") != caster.get_instance_id() or int(owner_descriptor.get("source_root_id",0)) == 0 or int(owner_descriptor.get("owner_session_id",0)) <= 0 or not owner_descriptor.get("world_context") is Dictionary: return _fail("actual_warm_owner_descriptor_required")
	_caster = caster; _root = root; _content = content; _closing_producer = closing_producer
	_original_main_root_id = root.get_instance_id()
	_owner_descriptor = owner_descriptor.duplicate(true)
	_registration_descriptor = _owner_descriptor.duplicate(true)
	var registered: Dictionary = closing_producer.bind_original_caster_warm_io_observer(self, get_script().get_source_code().sha256_text(), _owner_descriptor)
	if registered.get("success") != true or registered.get("actual_owner_descriptor") != _owner_descriptor:
		return _fail("actual_closing_IO_observer_registration_unproved")
	return {"success":true,"actual_owner_descriptor":_owner_descriptor}

func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not _main() or _owner_descriptor.get("world_context") != transaction.get("before_world") or _owner_descriptor.get("owner_session_id") != transaction.get("owner_session_id") or _owner_descriptor.get("source_root_id") != transaction.get("source_root_id") or not _caster.get("_host").verify_committed_original_map_arrival(transaction): return false
	var next: Dictionary = _owner_descriptor.duplicate(true)
	next.world_context = transaction.after_world.duplicate(true)
	_owner_descriptor = next
	# Issued offers/transfers and the actual observer registration are frozen
	# original records. New calls capture this current owner into their reply.
	return true

func adopt_actual_original_loading_claims(origin: Node) -> Dictionary:
	if not _main() or origin != _root or _loading_adopted: return _fail("actual_original_loading_owner_required")
	var claims: Variant = origin.get("_loading_texture_threaded")
	if not claims is Dictionary: return _fail("MISSING:actual_original_Main_loading_claim_dictionary")
	for raw_path: Variant in claims:
		if not raw_path is String or str(raw_path).is_empty() or claims[raw_path] != true: return _fail("original_loading_claim_source_schema")
	# Reuse the actual owner dictionary; do not copy a second writable claim owner.
	_loading_claims = claims
	_loading_adopted = true
	return {"success":true,"original_owner_node_id":origin.get_instance_id(),"actual_paths":claims.keys()}

func execute_original_warm(operation: String, payload: Dictionary, actual_ticket: Dictionary) -> Dictionary:
	if not _main() or operation not in OPERATIONS: return _fail("actual_Main_warm_opcode")
	if not _loading_adopted or actual_ticket.size() != 3: return _fail("actual_loading_claim_adoption_and_journal_ticket_required")
	if payload.size() != 7 or payload.get("contract_id") != "source.caster.warm.request.v1" or payload.get("source_root_id") != _owner_descriptor.source_root_id or payload.get("world_context") != _owner_descriptor.world_context or not payload.get("arguments") is Array or not payload.get("reservation") is Dictionary or payload.reservation.get("owner_session_id") != _owner_descriptor.owner_session_id or int(payload.get("request_sequence",0)) <= 0 or not payload.get("source_process_frame") is int: return _fail("actual_source_warm_request_identity")
	var result: Dictionary
	_active_ticket = actual_ticket.duplicate(true)
	_issued_source_process_frame=int(payload.source_process_frame)
	match operation:
		"source_caster_warm::collect_admit":
			if not payload.arguments.is_empty(): return _fail("warm_collect_arity")
			result = _collect_admit()
		"source_caster_warm::retire":
			if not payload.arguments.is_empty(): return _fail("warm_retire_arity")
			result = _retire()
		"source_caster_warm::loading_state":
			if payload.arguments.size() != 1 or not payload.arguments[0] is bool: return _fail("warm_loading_state_arity")
			Registry.set_loading_window_active(payload.arguments[0])
			result = {"success":true}
		"source_caster_warm::loading_claim_retire":
			if not payload.arguments.is_empty(): return _fail("warm_loading_claim_retire_arity")
			result = _retire_loading_claims()
	if result.get("success") != true: return result
	result.warm_result = {"contract_id":"source.caster.warm.result.v1", "owner_descriptor":_owner_descriptor,
		"request_sequence":payload.request_sequence,"source_process_frame":payload.source_process_frame,
		"actual_Main_process_frame":Engine.get_process_frames(),"attempts_in_Main_frame":_attempts_in_frame,
		"frame_texture_threaded":_claims.duplicate(true),"loading_texture_threaded":_loading_claims.keys(),
		"actual_loading_window_active":Registry.is_loading_window_active(),"actual_io":inspect_actual_original_caster_warm_io(),
		"events":_history.duplicate(true)}
	_history.clear()
	return result

func _collect_admit() -> Dictionary:
	if Registry.is_loading_window_active(): return {"success":true}
	for path: String in _claims.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			_claims.erase(path) # The accepted native request token was actually retrieved once.
			if texture != null: Registry.retain_loaded_texture(path,texture)
			else: Registry.mark_frame_texture_terminal_failure(path,"wrong_resource_type")
			_history.append({"path":path,"kind":"collected","status":status,"actual_texture_id":texture.get_instance_id() if texture != null else 0})
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path) # Original terminal FAILED token release.
			_claims.erase(path); Registry.mark_frame_texture_terminal_failure(path,"failed")
			_history.append({"path":path,"kind":"collected","status":status,"actual_texture_id":0})
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_claims.erase(path); Registry.mark_frame_texture_terminal_failure(path,"invalid")
			_history.append({"path":path,"kind":"invalid","status":status})
	# Exact source ordering: collect first, then retiring owner check, then admit.
	if _retiring or not is_instance_valid(_root) or _root.is_queued_for_deletion(): return {"success":true}
	var actual_frame := Engine.get_process_frames()
	if actual_frame != _main_frame:
		_main_frame = actual_frame; _attempts_in_frame = 0
	if _claims.size() >= MAX_IN_FLIGHT or _attempts_in_frame >= PER_FRAME: return {"success":true}
	for path: String in Registry.take_pending_warm_paths(mini(PER_FRAME-_attempts_in_frame, MAX_IN_FLIGHT-_claims.size())):
		if _claims.has(path): continue
		_attempts_in_frame += 1
		var error := ResourceLoader.load_threaded_request(path,"Texture2D",false)
		if error == OK:
			_claim_sequence += 1
			_claims[path] = {"path":path,"claim_sequence":_claim_sequence,"claim_count":1,
				"actual_Main_owner_id":get_instance_id(),"actual_Main_process_frame":actual_frame,"request_error":error,
				"originating_event_identity":_active_ticket.duplicate(true)}
		elif error == ERR_BUSY: Registry.queue_sequence_warm([path],false) # No accepted claim.
		else: Registry.mark_frame_texture_terminal_failure(path,"request_rejected_%d" % error)
		_history.append({"path":path,"kind":"requested","request_error":error,"accepted":error == OK})
	return {"success":true}

func _retire() -> Dictionary:
	_retiring = true
	# Original final-owner branch may join on Main; S keeps running and polls.
	for path: String in _claims.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			if texture != null: Registry.retain_loaded_texture(path,texture)
			else: Registry.mark_frame_texture_terminal_failure(path,"failed" if status == ResourceLoader.THREAD_LOAD_FAILED else "wrong_resource_type")
		else: Registry.mark_frame_texture_terminal_failure(path,"invalid")
		_history.append({"path":path,"kind":"original_final_get","status":status,"claim":_claims[path]})
		_claims.erase(path)
	return {"success":true}

func _retire_loading_claims() -> Dictionary:
	if _issued_feature_main==null: return _fail("MISSING:actual_Main_Feature_issued_claim_bridge")
	var pending_accept := false
	for path: String in _loading_claims.keys():
		if not _issued_loading_offers.has(path):
			_issued_transfer_sequence+=1
			var identity: Dictionary=_active_ticket.duplicate(true)
			identity.transfer_sequence=_issued_transfer_sequence
			var evidence: Dictionary=_closing_producer.capture_original_issued_claim_evidence(self,identity,path,1,_issued_source_process_frame)
			if evidence.get("success")==false: return evidence
			_issued_loading_offers[path]={"identity":identity,"evidence":evidence}
		var offer: Dictionary=_issued_loading_offers[path]
		var accepted: Dictionary=_issued_feature_main.offer_original_warm_issued_claim(offer.identity,offer.evidence,self)
		if accepted.get("status") in ["BUSY","BACKPRESSURE"] or accepted.get("state")=="OFFERED": pending_accept=true;continue
		if accepted.get("state") not in ["ACCEPTED","ORIGIN_RELEASED","TERMINAL"]: return _fail("actual_Source_FIFO_acceptance_unproved")
		_transfers[path]={"path":path,"claim_count":1,"actual_content_node_id":_content.get_instance_id(),"actual_original_owner_id":_original_main_root_id,"issued_claim_identity":offer.identity,"issued_claim_evidence":offer.evidence,"actual_adoption_receipt":accepted.acceptance_receipt}
		_loading_claims.erase(path) # Source FIFO owns this exact responsibility.
		var released: Dictionary=_issued_feature_main.confirm_original_warm_claim_origin_released(offer.identity)
		if released.get("state") not in ["ORIGIN_RELEASED","TERMINAL"]: return {"success":false,"status":"PENDING"}
		_issued_loading_offers.erase(path)
	# Retry a refused origin seal without repeating original claim removal.
	for path: String in _transfers.keys():
		var transfer: Dictionary=_transfers[path]
		var state: Dictionary=_issued_feature_main.original_issued_claim_transfer_state(transfer.issued_claim_identity)
		if state.get("state")=="ACCEPTED":
			state=_issued_feature_main.confirm_original_warm_claim_origin_released(transfer.issued_claim_identity)
		if state.get("state") not in ["ORIGIN_RELEASED","TERMINAL"]: return {"success":false,"status":"PENDING"}
		_issued_loading_offers.erase(path)
		if state.get("state")=="TERMINAL":
			var actual: Dictionary=_closing_producer.inspect_actual_original_threaded_claim_transfer(transfer)
			if actual.get("status")!="READY": return _fail("actual_physical_terminal_range_unproved")
			_history.append({"path":path,"kind":"actual_transfer_terminal","actual_receipt":actual})
			_transfers.erase(path)
	if pending_accept or not _loading_claims.is_empty(): return {"success":false,"status":"PENDING"}
	# Crucial: transferred responsibilities remain in _transfers / Native's
	# attached lifetime records. The full Warm reply releases execution capacity
	# now; it never waits for those original Feature status/get leaves to clear.
	return {"success":true}
func inspect_actual_original_caster_warm_io() -> Dictionary:
	if not _main(): return _fail("actual_Main_warm_IO_observer")
	return {"contract_id":"source.caster.warm.io.v1","owner_descriptor":_owner_descriptor,
		"actual_claim_owner_id":get_instance_id(),"frame_texture_threaded":_claims.duplicate(true),
		"loading_texture_threaded":_loading_claims.keys(),"persistent_transfers":_transfers.duplicate(true),
		"actual_ContentLayers_claim_diagnostics":_content.threaded_resource_claim_diagnostics(),
		"retirement_requested":_retiring,"actual_Main_process_frame":Engine.get_process_frames()}
func release_original_warm_owner() -> bool:
	if not _main() or not _retiring or not _claims.is_empty() or not _loading_claims.is_empty() or not _transfers.is_empty(): return false
	var actual: Dictionary = _closing_producer.release_original_caster_warm_io_observer(self,_registration_descriptor)
	if actual.get("success") != true or actual.get("actual_owner_descriptor") != _registration_descriptor: return false
	_caster = null; _root = null; _content = null; _closing_producer = null
	return true
func _main() -> bool: return OS.get_thread_caller_id() == OS.get_main_thread_id() and _caster != null
func _fail(code: String) -> Dictionary: return {"success":false,"status":"INVALID","error":code}

var _issued_loading_offers: Dictionary={}
var _issued_transfer_sequence := 0
var _issued_source_process_frame := -1
var _issued_feature_main: RefCounted
func configure_original_issued_claim_bridge(feature_main: RefCounted) -> bool:
	if not _main() or _issued_feature_main!=null or feature_main==null: return false
	for method: String in ["offer_original_warm_issued_claim","original_issued_claim_transfer_state","confirm_original_warm_claim_origin_released"]:
		if not feature_main.has_method(method): return false
	_issued_feature_main=feature_main;return true
