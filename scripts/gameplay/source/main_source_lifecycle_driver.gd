extends Node
## Actual Main lifecycle runner. Await suspends this UI continuation; Main never
## waits for S. Closing uses accepted caster transport independently of input.
var _router: RefCounted
var _admission: RefCounted
var _transport: RefCounted
var _host: Object
var _prefix: RefCounted
var _caster: RefCounted
var _prepared: Dictionary = {}
var _closing := false
var _held_caster_prefix: Dictionary = {}
var _resource_pump: RefCounted
func bind_actual_original_resource_pump(pump: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _resource_pump != null or not _held_caster_prefix.is_empty(): return false
	if pump == null or pump.get_script() != preload("res://scripts/gameplay/source/main_original_resource_pump.gd") or pump.get("_host") != _host or not is_same(pump.get("_prefix"),_prefix) or not is_same(_transport.get("_main_pump"),pump): return false
	_resource_pump = pump
	return true
func configure_main(router: RefCounted, admission: RefCounted, transport: RefCounted, host: Object, prefix_consumer: RefCounted, caster_executor: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _router!=null: return _fail("actual_Main_once_required")
	for row: Array in [[router,["begin_original_character_launch","abort_original_checkpoint"]],[admission,["prepare_actual_loaded_source","abort_original_profile_source_handoff"]],[transport,["actual_original_character_world","request_original_source_session_adoption","actual_original_main_closing_receipt","request_original_application_close"]],[host,["publish_original_source_admission_scope","inspect_next_original_published_prefix","ack_published_original_main_prefix"]],[prefix_consumer,["apply_prefix","confirm_prefix_acknowledged","has_pending","flush_original_main_replies"]],[caster_executor,["flush_original_notifications"]]]:
		for method: String in row[1]:
			if row[0]==null or not row[0].has_method(method): return _fail("MISSING:actual_Main_lifecycle:"+method)
	_router=router; _admission=admission; _transport=transport; _host=host; _prefix=prefix_consumer; _caster=caster_executor
	process_mode=Node.PROCESS_MODE_ALWAYS
	return {"success":true}
func prepare_original_character_launch(receiver: Node) -> Dictionary:
	if _router==null or not _prepared.is_empty() or _closing: return _fail("actual_launch_not_available")
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_BLUEPRINT")
	var world: Dictionary = _transport.actual_original_character_world(receiver)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ORIGINAL_UI_CHECKPOINT")
	var begun: Dictionary = _router.begin_original_character_launch(receiver,world)
	if begun.get("success")!=true: return begun
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_LOADED_PROFILE_ADMISSION")
	var prepared: Dictionary = _admission.prepare_actual_loaded_source(begun.checkpoint)
	if prepared.get("success")!=true:
		_router.abort_original_checkpoint(begun.checkpoint)
		return prepared
	_prepared=prepared
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_PREPARED_NATIVE_SCOPE")
	var scoped: Dictionary = _admission.publish_actual_original_prepared_scope(world)
	if scoped.get("success") != true:
		var aborted: Dictionary = _admission.abort_original_profile_source_handoff(prepared.receipt)
		if aborted.get("success") != true: return aborted
		_router.abort_original_checkpoint(begun.checkpoint)
		_prepared = {}
		return scoped
	# Native binds the provider and derives actual PREPARED proof. The transport
	# must preserve full original receipt/publication and actual S loaded adoption.
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_SOURCE_SESSION_ADOPTION")
	var result: Dictionary = await _transport.request_original_source_session_adoption(_admission,prepared,world)
	if result.get("success")!=true:
		if not _admission.get("_committed"):
			var aborted: Dictionary = _admission.abort_original_profile_source_handoff(prepared.receipt)
			if aborted.get("success")!=true: return aborted
			_router.abort_original_checkpoint(begun.checkpoint)
			_prepared={}
		return result
	if _admission.get("_committed")!=true or _admission.get("_gate").state()!="S" or result.get("prepared_receipt")!=prepared.receipt: return _fail("actual_committed_same_profile_source_required")
	return result
func begin_original_source_close() -> void: _closing=true
func _process(_delta: float) -> void:
	if _host==null: return
	# The actual Session transport listener owns the sole Main resource/prefix
	# service once composed. Do not race it with this older closing-only reader.
	if _resource_pump != null: return
	# Do not call unbound Main leaves before actual Host startup.
	if not _closing and _host.status().get("running") != true: return
	var applied: Dictionary = pump_original_accepted_caster_prefix()
	if applied.get("status")=="INVALID":
		_router.reject_original_main_profile_writer({"method":"accepted_caster_close_prefix_failed","receipt":applied})
func pump_original_accepted_caster_prefix() -> Dictionary:
	if _host==null: return _fail("actual_closing_transport_unconfigured")
	if _resource_pump != null: return _resource_pump.service_original_main_resources()
	if _held_caster_prefix.is_empty():
		# Ordinary Root publications and accepted caster prefixes already share
		# the same Native published FIFO. Peek it; retain the original consumer.
		var held: Dictionary = _host.inspect_next_original_published_prefix()
		if held.get("status") in ["PENDING","BUSY"]:
			_caster.flush_original_notifications()
			var replies: Dictionary=_prefix.flush_original_main_replies()
			return replies if replies.get("status")=="INVALID" else held
		if held.get("status")!="READY" or not held.get("prefix") is Dictionary: return _fail("actual_caster_prefix_acquire_failed",held)
		_held_caster_prefix=held.prefix
	var applied: Dictionary = _prefix.apply_prefix(_held_caster_prefix)
	if applied.get("status")!="APPLIED": return applied
	var ack := {"bridge_generation":_held_caster_prefix.bridge_generation,"journal_generation":_held_caster_prefix.journal_generation,"through_ordinal":_held_caster_prefix.through_ordinal,"applied":true}
	if not _host.ack_published_original_main_prefix(_held_caster_prefix,ack) or not _prefix.confirm_prefix_acknowledged(_held_caster_prefix,ack): return _fail("actual_caster_prefix_ACK_required")
	_held_caster_prefix={}
	_caster.flush_original_notifications()
	var replies: Dictionary=_prefix.flush_original_main_replies()
	return replies if replies.get("status")=="INVALID" else {"status":"APPLIED"}
func original_close_receipt() -> Dictionary:
	if not _closing or _prefix.has_pending() or not _held_caster_prefix.is_empty(): return _fail("accepted_prefix_still_held")
	# Actual producer must inspect Host tickets, Node retirement, reliable UI
	# commands and resource lease obligations. Queue empty alone is insufficient.
	return _transport.actual_original_main_closing_receipt()
func route_original_notification(_receiver: Node, what: int) -> bool:
	if _admission==null or _admission.get("_gate")==null or _admission.get("_gate").state()=="MAIN": return false
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not _closing: _request_original_application_close(what)
		return true
	return false
func _request_original_application_close(what: int) -> void:
	_closing=true
	var receipt: Dictionary = await _transport.request_original_application_close(what)
	if receipt.get("success")!=true: return
	var terminal: Dictionary = original_close_receipt()
	if terminal.get("success")!=true or terminal.get("receipt")!=receipt.get("receipt"): return
	# Same Native terminal was observed. MainApplication owns the remaining
	# physical Root/retained CharacterSelect/producer final-free and sole quit.
	# It runs at the existing process-frame boundary after this stack returns.
	return
func _fail(code: String, details: Dictionary={}) -> Dictionary: return {"success":false,"status":"INVALID","errors":[code],"details":details}
