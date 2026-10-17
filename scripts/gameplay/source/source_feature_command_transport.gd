extends RefCounted
## Source custody for Main commands/results only. Original resource requests,
## work queues, cancellation, callbacks and leases stay in the one Coordinator.
const Catalog := preload("res://scripts/gameplay/source/feature_original_command_catalog.gd")
const Digest := preload("res://scripts/gameplay/source/source_command_digest.gd")
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _session_id := 0
var _last_command := 0
var _closed := false
var _calls: Dictionary = {}
var _ack_facts: Dictionary = {}

func configure_original_owner(session: RefCounted) -> bool:
	if _owner == OS.get_main_thread_id() or OS.get_thread_caller_id() != _owner or _session != null or session == null or session.owner_thread_id() != _owner: return false
	var actual: Dictionary = session.feature_resource_session()
	if not actual.get("coordinator") is RefCounted or not actual.get("primitives") is RefCounted or not is_same(actual.coordinator.Budget,session.original_frame_budget()): return false
	_session = weakref(session); _session_id = session.original_budget_session_id()
	return _session_id > 0

func dispatch_original_packet(packet: Dictionary) -> Dictionary:
	if packet.get("contract_id") == "hardcore.feature.Main_command.v1": return {"handled":true,"accepted":_accept_original_call(packet)}
	if packet.get("contract_id") == "hardcore.feature.Main_command_ack.v1": return {"handled":true,"accepted":_accept_actual_result_ack(packet)}
	return {"handled":false}

func _accept_original_call(packet: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _session == null or _closed or packet.size() != 8 or packet.get("owner_session_id") != _session_id or not packet.get("command_id") is int or not packet.get("method") is String or not Catalog.accepts(packet.method,packet.get("arguments")) or not packet.get("actual_main_process_frame") is int or packet.actual_main_process_frame < 0 or packet.get("loan_id") != packet.command_id: return false
	var id: int = packet.command_id
	if _calls.has(id): return _calls[id].packet == packet
	if id != _last_command+1: return false
	var session: RefCounted = _session.get_ref()
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var frozen: Dictionary = graph.capture(packet,true,false)
	if frozen.get("success") != true: return false
	var feature: Dictionary = session.feature_resource_session()
	var arguments: Variant = feature.primitives.decode_actual_original_feature_command_value(packet.arguments)
	var scene: Variant = feature.primitives.decode_actual_original_feature_command_value(packet.scene)
	if feature.primitives.failed() or not arguments is Array: return false
	var context: Dictionary = {"contract_id":"hardcore.feature.actual_Main_call.v1","owner_session_id":_session_id,"command_id":id,"actual_main_process_frame":packet.actual_main_process_frame,"scene":scene,"loan_id":packet.loan_id}
	var imported: Dictionary = {"contract_id":"hardcore.feature.Main_call_imported.v1","owner_session_id":_session_id,"command_id":id,"command_sha256":Digest.sha256(packet),"loans_imported":true}
	_calls[id] = {"packet":frozen.value,"context":context,"import_receipt":imported,"import_published":false,"result":{},"result_published":false,"raw_result":null,"request":null}
	_last_command = id
	# This is a synchronous original Request admission prefix. A suspended
	# coroutine never leaves a mutable Session-global caller context installed.
	var admitted: Dictionary = feature.coordinator.admit_actual_original_main_command(packet.method,arguments,context)
	if admitted.get("status") == "ACCEPTED" and admitted.get("request") is RefCounted and admitted.request.has_signal("completed"):
		_calls[id].request = admitted.request
		admitted.request.completed.connect(_complete_actual_original_call.bind(id),CONNECT_ONE_SHOT)
	elif admitted.get("status") == "VALUE": _complete_actual_original_call(admitted.get("result"),id)
	else:
		if packet.method in Catalog.VOID_CALLS:
			session.fault("actual_Feature_void_cleanup_admission_failed",{"command_id":id,"method":packet.method,"details":admitted})
		_complete_actual_original_call({"success":false,"errors":admitted.get("errors",[str(admitted.get("error","actual_Feature_command_admission_failed"))]),"lease":null},id)
	flush_actual_original_receipts()
	return true

func _complete_actual_original_call(result: Variant, id: int) -> void:
	if OS.get_thread_caller_id() != _owner or not _calls.has(id) or not _calls[id].result.is_empty():
		if _session != null: _session.get_ref().fault("actual_Feature_command_completion_identity",{"command_id":id})
		return
	var session: RefCounted = _session.get_ref()
	var encoded: Dictionary = session.feature_resource_session().primitives.encode_actual_original_feature_command_result(result)
	if encoded.get("success") != true:
		session.fault("actual_Feature_command_result_opaque_retained",{"command_id":id,"details":encoded})
		_calls[id].raw_result = result
		return
	var record: Dictionary = _calls[id]
	record.raw_result = result # Original return lifetime lasts until real Main consumption.
	record.result = {"contract_id":"hardcore.feature.Main_call_result.v1","owner_session_id":_session_id,"command_id":id,"command_sha256":Digest.sha256(record.packet),"loans_imported":true,"result":encoded.value}
	flush_actual_original_receipts()

func flush_actual_original_receipts() -> bool:
	if OS.get_thread_caller_id() != _owner or _session == null or _session.get_ref() == null: return false
	var journal: RefCounted = _session.get_ref().original_event_journal()
	for id: int in _calls:
		var record: Dictionary = _calls[id]
		if not record.import_published:
			if not journal.append({"kind":"original_world_presentation","operation":&"original_feature_call_admitted","arguments":[record.import_receipt]}): return false
			record.import_published = true
		if not record.result.is_empty() and not record.result_published:
			if not journal.append({"kind":"original_world_presentation","operation":&"original_feature_call_result","arguments":[record.result]}): return false
			record.result_published = true
	for id: int in _ack_facts.keys():
		if not journal.append({"kind":"original_world_presentation","operation":&"original_feature_call_acknowledged","arguments":[_ack_facts[id]]}): return false
		_ack_facts.erase(id)
	return true

func _accept_actual_result_ack(packet: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or packet.size() != 4 or packet.get("owner_session_id") != _session_id or not packet.get("command_id") is int: return false
	var id: int = packet.command_id
	if _ack_facts.has(id): return _ack_facts[id].result_sha256 == packet.get("result_sha256")
	if not _calls.has(id) or not _calls[id].result_published or packet.get("result_sha256") != Digest.sha256(_calls[id].result): return false
	_ack_facts[id] = {"contract_id":"hardcore.feature.Main_call_acknowledged.v1","owner_session_id":_session_id,"command_id":id,"result_sha256":packet.result_sha256}
	_calls.erase(id) # Releases only this command's real args/result/Request refs.
	return flush_actual_original_receipts()

func service_actual_closing_acknowledgements(frame: Dictionary) -> bool:
	if _session == null: return false
	var actual: Dictionary = _session.get_ref().actual_original_clock_frame()
	if frame != actual or actual.get("closing_session") != true or actual.get("source_boundary") != "NODE_PROCESS_SERVICE": return false
	var io: Variant = actual.get("closing_process_publication",{}).get("main_io")
	if not io is Dictionary or io.get("contract_id") != "hardcore.source.main_io_observation.v1" or io.get("owner_session_id") != _session_id or io.get("actual_main_process_frame") != actual.get("closing_process_publication",{}).get("main_process_frame"): return false
	var acknowledgements: Variant = io.get("feature_command_acknowledgements",[])
	if not acknowledgements is Array: return false
	for packet: Variant in acknowledgements:
		if not packet is Dictionary or packet.get("contract_id") != "hardcore.feature.Main_command_ack.v1": return false
		# A repeated Main frame may carry an ACK whose fact has already left the
		# local outbox. It has no remaining Source record, so never reapplies it.
		if not packet.get("command_id") is int or packet.command_id <= 0 or packet.command_id > _last_command: return false
		if not _calls.has(packet.command_id) and not _ack_facts.has(packet.command_id): continue
		if not _accept_actual_result_ack(packet): return false
	return flush_actual_original_receipts()

func close_original_admission() -> void: _closed = true
func actual_original_command_retirement_complete() -> bool: return _calls.is_empty() and _ack_facts.is_empty()
