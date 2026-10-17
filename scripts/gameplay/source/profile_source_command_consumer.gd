extends RefCounted
## Called by Root's actual native-input/original P source dispatcher. No second
## command queue, timer, HP, profile clone or writer. The exact original Model
## method is invoked once on its owner; Root UI awaits its reliable receipt.
const Model := preload("res://scripts/gameplay/profile/profile_model.gd")
var _owner:=OS.get_thread_caller_id()
var _session: WeakRef
var _allowed: Dictionary
var _receipt_outbox: RefCounted
var _accepted: Dictionary={}
var _unpublished: Dictionary={}
func configure_owner(session: RefCounted,original_commands: Dictionary,outbox: RefCounted) -> bool:
	if _session!=null or OS.get_thread_caller_id()==OS.get_main_thread_id() or session.owner_thread_id()!=_owner: return false
	if outbox==null or not outbox.has_method("emit_original_profile_command_receipt"): return false
	if original_commands.is_empty(): return false
	for key: Variant in original_commands:
		if not key is String or key.begins_with("_") or not original_commands[key] is int or original_commands[key]<0: return false
	_session=weakref(session); _allowed=original_commands; _receipt_outbox=outbox
	return true
func start_original_profile_command(packet: Dictionary) -> bool:
	assert(OS.get_thread_caller_id()==_owner and _session!=null)
	var made: Dictionary=_session.get_ref().original_profile_owner()
	if made.get("success")!=true: return false
	var profile: RefCounted=made.profile
	if profile.get_script()!=Model or profile._owner_thread_id!=_owner: return false
	if packet.get("contract_id")!="hardcore.profile.ui.command.v1" or not packet.get("command_id") is int or packet.command_id<=0 or packet.get("profile_id")!=profile.active_profile_id or not packet.get("method") is String or not packet.get("arguments") is Array: return false
	var method: String=packet.method
	if not _allowed.has(method) or packet.arguments.size()!=_allowed[method] or not profile.has_method(method): return false
	# No main Objects/Callables/opaque mutable capabilities enter command values.
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.validate(packet.arguments,false).get("success",false): return false
	var id:=int(packet.command_id)
	if _accepted.has(id): return _accepted[id]==packet
	_accepted[id]=packet.duplicate(true)
	_run_original_profile_command(profile,packet)
	return true
func _run_original_profile_command(profile: RefCounted,packet: Dictionary) -> void:
	var method: String=packet.method
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var result: Variant=await profile.callv(method,packet.arguments)
	if not graph.validate(result,false).get("success",false):
		_session.get_ref().fault("original_profile_ui_result_requires_canonical_port",{"method":method})
		return
	# Failure to enqueue keeps the real result obligation in the actual reliable
	# Root outbox; this module must not re-execute the original transaction.
	_unpublished[int(packet.command_id)]={"contract_id":"hardcore.profile.ui.command_receipt.v1","command_id":packet.command_id,"profile_id":profile.active_profile_id,"method":method,"result":result}
	flush_original_profile_receipts()
func flush_original_profile_receipts() -> bool:
	for id: int in _unpublished.keys():
		if not _receipt_outbox.emit_original_profile_command_receipt(_unpublished[id]): return false
		_unpublished.erase(id)
	return true
func acknowledge_original_profile_command_receipt(id: int) -> bool:
	if _unpublished.has(id) or not _accepted.has(id): return false
	_accepted.erase(id)
	return true
