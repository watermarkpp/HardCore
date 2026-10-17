extends "res://scripts/gameplay/source/profile_source_command_consumer.gd"
## Same original consumer/Model execution; additions are admission identity,
## Native journal receipts and detached Main read projections only.
const Catalog := preload("res://scripts/gameplay/source/profile_original_command_catalog.gd")
const MAIN_CHARACTER_LIFECYCLE := ["create_character","delete_character_profile","select_character","ensure_chiyue_test_roster"]
var _session_id := 0
var _last_command := 0
var _retired_through := 0
var _retired_pending: Dictionary = {}
var _published_results: Dictionary = {}
var _pending_ack_facts: Dictionary = {}
var _view_sequence := 0
var _input_closed := false
func owner_thread_id() -> int: return _owner
func configure_original_owner(session: RefCounted, actual_session_id: int) -> bool:
	if _session!=null or _owner==OS.get_main_thread_id() or session==null or session.owner_thread_id()!=_owner or actual_session_id<=0: return false
	if Catalog.ARITIES.is_empty() or Catalog.READ_FIELDS.is_empty(): return false
	_session=weakref(session);_session_id=actual_session_id;_allowed=Catalog.ARITIES
	_receipt_outbox=self
	return true
func start_original_profile_command(packet: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if _input_closed or _session==null or packet.size()!=5 or packet.get("contract_id")!="hardcore.profile.ui.command.v1" or not packet.get("command_id") is int or not packet.get("arguments") is Array or not packet.get("method") is String: return false
	if packet.method in MAIN_CHARACTER_LIFECYCLE:
		_session.get_ref().fault("character_switch_requires_original_terminal_then_Main_load",{"method":packet.method})
		return false
	var made: Dictionary=_session.get_ref().original_profile_owner()
	if made.get("success")!=true: return false
	var profile: RefCounted=made.profile
	if profile.get_script()!=Model or profile._owner_thread_id!=_owner or packet.profile_id!=profile.active_profile_id or not Catalog.accepts(packet.method,packet.arguments.size()) or not profile.has_method(packet.method): return false
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(packet,true,false)
	if captured.get("success")!=true: return false
	var id: int=packet.command_id
	if _accepted.has(id): return _accepted[id]==packet
	if id<=_retired_through or _retired_pending.has(id) or id!=_last_command+1:
		_session.get_ref().fault("original_UI_command_replay_or_gap",{"command_id":id,"last":_last_command})
		return false
	_last_command=id;_accepted[id]=captured.value
	# Inherited sole original algorithm: await actual profile.callv, validate the
	# real return and retain it until this same outbox accepts its journal event.
	_run_original_profile_command(profile,captured.value)
	return true
func emit_original_profile_command_receipt(receipt: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	var id: int=int(receipt.command_id)
	if not _accepted.has(id): return false
	if _published_results.has(id): return true
	var made: Dictionary=_session.get_ref().original_profile_owner()
	if made.get("success")!=true: return false
	var profile: RefCounted=made.profile
	var fields: Dictionary={}
	for field: String in Catalog.READ_FIELDS: fields[field]=profile.get(field)
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var snapshot: Dictionary=graph.capture(fields,true,false)
	if snapshot.get("success")!=true:
		_session.get_ref().fault("original_UI_projection_opaque",snapshot)
		return false
	_view_sequence+=1
	var actual: Dictionary=receipt.duplicate(true)
	actual.profile_id=_accepted[id].profile_id # Command identity before a real select.
	actual.post_profile_id=profile.active_profile_id
	actual.owner_session_id=_session_id
	actual.profile_model_id=profile.get_instance_id()
	actual.command_sha256=preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(_accepted[id])
	actual.profile_view={"sequence":_view_sequence,"fields":snapshot.value}
	var immutable: Dictionary=graph.capture(actual,true,false)
	if immutable.get("success")!=true: return false
	if not _session.get_ref().original_event_journal().append({"operation":&"original_profile_command_receipt","arguments":[immutable.value]}): return false
	_published_results[id]=immutable.value
	return true
func accept_original_profile_receipt_ack(packet: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if packet.size()!=4 or packet.get("contract_id")!="hardcore.profile.ui.command_ack.v1" or packet.get("owner_session_id")!=_session_id or not packet.get("command_id") is int: return false
	var id: int=packet.command_id
	if not _published_results.has(id) or packet.get("receipt_sha256")!=preload("res://scripts/gameplay/source/source_command_digest.gd").sha256(_published_results[id]): return false
	if not acknowledge_original_profile_command_receipt(id): return false
	_published_results.erase(id);_retired_pending[id]=true
	while _retired_pending.has(_retired_through+1):
		_retired_through+=1;_retired_pending.erase(_retired_through)
	_pending_ack_facts[id]={"contract_id":"hardcore.profile.ui.acknowledged.v1","owner_session_id":_session_id,"command_id":id,"receipt_sha256":packet.receipt_sha256}
	return flush_original_acknowledgements()
func flush_original_acknowledgements() -> bool:
	for id: int in _pending_ack_facts.keys():
		if not _session.get_ref().original_event_journal().append({"operation":&"original_profile_command_acknowledged","arguments":[_pending_ack_facts[id]]}): return false
		_pending_ack_facts.erase(id)
	return true
func close_original_command_admission() -> void:
	assert(OS.get_thread_caller_id()==_owner)
	_input_closed=true
func actual_original_command_obligations() -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	return {"owner_session_id":_session_id,"accepted":_accepted.size(),"unpublished":_unpublished.size(),"published_unacknowledged":_published_results.size(),"ack_facts_unpublished":_pending_ack_facts.size(),"retired_through":_retired_through}
func original_command_retirement_complete() -> bool:
	return _accepted.is_empty() and _unpublished.is_empty() and _published_results.is_empty() and _pending_ack_facts.is_empty()
