extends RefCounted
## Attached once to the existing Source Runtime/Session; no new Profile,
## FrameBudget, timer, RNG or transaction implementation.
const CommandsScript := preload("res://scripts/gameplay/source/source_profile_command_owner.gd")
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _commands: RefCounted
var _initial_receipt: Dictionary = {}
var _commands_initialized := false
func configure_original_owner(session: RefCounted, prepared_receipt: Dictionary) -> bool:
	if _owner==OS.get_main_thread_id() or _session!=null or session==null or session.owner_thread_id()!=_owner or prepared_receipt.is_empty(): return false
	var made: Dictionary=session.original_profile_owner()
	if made.get("success")!=true or made.get("original_loaded_handoff_applied")!=true: return false
	var evidence: Dictionary=session.lifetime_evidence()
	var profile: RefCounted=made.profile
	if evidence.get("session_id",0)<=0 or evidence.get("profile_id")!=profile.get_instance_id() or profile._owner_thread_id!=_owner or profile.active_profile_id.is_empty(): return false
	_session=weakref(session);_commands=CommandsScript.new()
	if not _commands.configure_original_owner(session,evidence.session_id): return false
	_commands_initialized = true
	_initial_receipt={"contract_id":"hardcore.profile.session.adopted.v1","prepared_receipt":prepared_receipt.duplicate(true),"owner_session_id":evidence.session_id,"profile_model_id":profile.get_instance_id(),"profile_id":profile.active_profile_id,"original_loaded_handoff_applied":made.original_loaded_handoff_applied}
	# A refused reliable append remains an obligation, rather than making an
	# initialized owner eligible to be constructed a second time.
	flush_original_adoption_receipt()
	return true
func flush_original_adoption_receipt() -> bool:
	if _initial_receipt.is_empty(): return true
	if not _session.get_ref().original_event_journal().append({"kind":"original_profile_transport","operation":&"original_profile_session_adopted","arguments":[_initial_receipt]}): return false
	_initial_receipt={}
	return true
func dispatch_original_profile_packet(packet: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	match packet.get("contract_id"):
		"hardcore.profile.ui.command.v1": return {"handled":true,"accepted":_commands.start_original_profile_command(packet)}
		"hardcore.profile.ui.command_ack.v1": return {"handled":true,"accepted":_commands.accept_original_profile_receipt_ack(packet)}
		_: return {"handled":false}
func service_original_receipts_at_actual_source_boundary() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if not _commands_initialized: return _initial_receipt.is_empty()
	return flush_original_adoption_receipt() and _commands.flush_original_profile_receipts() and _commands.flush_original_acknowledgements()
func close_original_profile_command_admission() -> void:
	if _commands_initialized: _commands.close_original_command_admission()
func actual_original_profile_command_obligations() -> Dictionary:
	return _commands.actual_original_command_obligations() if _commands_initialized else {"status":"NOT_RUN","actual_command_owner_initialized":false}
func original_profile_command_retirement_complete() -> bool:
	return _initial_receipt.is_empty() and (not _commands_initialized or _commands.original_command_retirement_complete())
