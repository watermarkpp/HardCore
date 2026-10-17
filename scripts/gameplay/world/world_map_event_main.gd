extends RefCounted

## One actual Main map effect cursor. The shared prefix consumer first applies
## the effect and acknowledges its prefix; only then is its result published.
## This object owns no map gameplay, budget ledger, mailbox or worker.
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
var _host: Object
var _leaf: RefCounted
var _producer: RefCounted
var _descriptor: Dictionary
var _effect: Dictionary = {}
var _reply: Dictionary = {}
var _last_identity: Dictionary = {}
var _last_event: Dictionary = {}
var _last_reply: Dictionary = {}
var _fault: Dictionary = {}

func configure_main(host: Object, actual_leaf: RefCounted, actual_producer: RefCounted, descriptor: Dictionary) -> bool:
	if _host != null or OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	for method: String in ["claim_original_map_loading_event","submit_original_map_loading_reply","publish_original_map_loading_publication","sample_main_thread_cpu_usec"]:
		if host == null or not host.has_method(method): return false
	if actual_leaf == null or actual_producer == null or descriptor.get("main_executor_id") != get_instance_id(): return false
	for method: String in ["execute_original_map_command","inspect_actual_original_map_io","apply_original_map_visual_effect"]:
		if not actual_leaf.has_method(method): return false
	_host = host; _leaf = actual_leaf; _producer = actual_producer; _descriptor = descriptor.duplicate(true)
	return true

func execute_original_journal_event(event: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if not _fault.is_empty(): return {"status":"INVALID","error":_fault}
	if _host == null or event.get("operation") != &"map_loading" or not event.get("reply_identity") is Dictionary or not event.get("arguments") is Array or event.arguments.size() != 1 or not event.arguments[0] is Dictionary: return _fail("map_event_schema")
	if event == _last_event: return {"status":"APPLIED","success":true}
	if not _effect.is_empty():
		return {"status":"APPLIED","success":true} if event == _effect.event else {"status":"PENDING"}
	var request: Dictionary = event.arguments[0]
	if request.get("owner_descriptor") != _descriptor: return _fail("map_actual_owner")
	# Sample before claim so an unavailable real CPU counter performs no effect.
	var cpu_start: int = _host.sample_main_thread_cpu_usec()
	if cpu_start < 0: return _fail("MISSING:actual_Main_CPU_sampler")
	var claimed: Dictionary = _host.claim_original_map_loading_event(event.reply_identity,event)
	if claimed.get("status") == "PENDING": return {"status":"PENDING"}
	if claimed.get("status") != "READY": return _fail("actual_map_claim",claimed)
	if not claimed.get("main_prefix") is Dictionary: return _fail("actual_accepted_map_prefix_missing")
	var started: int = Time.get_ticks_usec()
	# The actual unchanged Main visual/resource leaf executes once here.
	var result: Dictionary = _leaf.execute_original_map_command(request)
	var finished: int = Time.get_ticks_usec()
	var cpu_finished: int = _host.sample_main_thread_cpu_usec()
	if cpu_finished < cpu_start: return _fail("actual_Main_CPU_counter_invalid")
	var copied: Dictionary = Graph.copy_and_seal(result)
	if not copied.ok: return _fail("map_result_not_plain",copied)
	_effect = {"event":event.duplicate(true),"source_request":request.duplicate(true),"identity":event.reply_identity.duplicate(true),"accepted_prefix":claimed.main_prefix,
		"result":copied.value,"started_usec":started,"finished_usec":finished,"actual_Main_CPU_usec":cpu_finished-cpu_start}
	# APPLIED acknowledges only the completed display/resource effect. Its accepted
	# result slot and real map owner debt remain until S settlement and IO proof.
	return {"status":"APPLIED","success":true}

func confirm_original_map_prefix_acknowledged(prefix: Dictionary, receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	if _effect.is_empty(): return true # Prefix may contain only other services.
	if prefix.size() != 4 or receipt.size() != 4 or receipt.get("applied") != true or receipt.get("bridge_generation") != prefix.get("bridge_generation") or receipt.get("journal_generation") != prefix.get("journal_generation") or receipt.get("through_ordinal") != prefix.get("through_ordinal") or not prefix.get("events") is Array: return false
	var found := false
	for item: Dictionary in prefix.events:
		if item == _effect.event: found = true
	if not found: return false
	var accepted: Dictionary = _effect.accepted_prefix
	if accepted.bridge_generation != prefix.bridge_generation or accepted.journal_generation != prefix.journal_generation or int(accepted.through_ordinal) > int(prefix.through_ordinal): return false
	# Project the actual acknowledged superset to the immutable accepted prefix.
	# Native independently verifies this through ordinal is in its actual Main ACK
	# ledger. No ACK is inferred from execute/emit/callback success.
	var covered_receipt := {"bridge_generation":accepted.bridge_generation,"journal_generation":accepted.journal_generation,"through_ordinal":accepted.through_ordinal,"applied":true}
	var candidate := {"contract_id":"source.map.loading.reply.v1","source_request":_effect.source_request,
		"identity":_effect.identity,"executed":true,"result":_effect.result,"started_usec":_effect.started_usec,
		"finished_usec":_effect.finished_usec,"actual_Main_CPU_usec":_effect.actual_Main_CPU_usec,
		"native_main_prefix_receipt":covered_receipt}
	if not _reply.is_empty(): return _reply == candidate
	_reply = candidate
	return true

func flush_original_map_replies() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if not _fault.is_empty(): return {"status":"INVALID","error":_fault}
	if _effect.is_empty(): return {"status":"READY"}
	if _reply.is_empty(): return {"status":"PENDING"} # No inferred prefix ACK.
	if _reply.result.get("ok") == true and _reply.source_request.operation == "capture_environment":
		var published: Dictionary = _host.publish_original_map_loading_publication(_reply.source_request.scope,_reply.result.publication,_reply.result.actual_loading_receipt)
		if published.get("status") == "PENDING": return published
		if published.get("status") != "READY": return _fail("actual_map_publication",published)
	var sent: Dictionary = _host.submit_original_map_loading_reply(_effect.identity,_reply)
	if sent.get("status") == "PENDING": return sent
	if sent.get("status") != "READY": return _fail("actual_map_reply_submission",sent)
	_last_identity = _effect.identity; _last_event = _effect.event; _last_reply = _reply
	_effect = {}; _reply = {}
	return {"status":"READY"}

func verify_actual_original_map_reply(identity: Dictionary, reply: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	return (not _reply.is_empty() and identity == _effect.identity and reply == _reply) or (identity == _last_identity and reply == _last_reply)

func actual_owner_descriptor() -> Dictionary: return _descriptor.duplicate(true)
func actual_map_leaf() -> RefCounted: return _leaf
func can_commit_actual_original_map_route(before: Dictionary, after: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or has_pending_original_map_reply(): return false
	if _descriptor == after: return true
	var expected: Dictionary = before.duplicate(true); expected.world_context = after.get("world_context",{})
	return _descriptor == before and expected == after
func commit_actual_original_map_route(before: Dictionary, after: Dictionary) -> bool:
	if not can_commit_actual_original_map_route(before,after): return false
	_descriptor = after.duplicate(true)
	return true
func inspect_actual_original_map_io() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	return _leaf.inspect_actual_original_map_io()
func has_pending_original_map_reply() -> bool: return not _effect.is_empty()
func apply_original_map_visual_effect(event: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	return _leaf.apply_original_map_visual_effect(event)
func _fail(error: String, details: Dictionary = {}) -> Dictionary:
	_fault = {"kind":error,"details":details.duplicate(true)}
	return {"status":"INVALID","error":_fault}
