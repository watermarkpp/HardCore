extends RefCounted
const LIVE_OPERATIONS := [&"status", &"load_threaded_request", &"load_threaded_get", &"replace_roots", &"close_get_escrow", &"bind_profile", &"bind_or_clear", &"observe_binding", &"retire_visual_binding", &"retire_threaded_resource_claims", &"forget_invalid_claim"]

## S endpoint of the approved original-position continuation protocol.
## No pre-read status snapshot. No ResourceLoader, ObjectDB, Node or Main object.
const THREAD_LOAD_INVALID_RESOURCE := 0
const THREAD_LOAD_IN_PROGRESS := 1
const THREAD_LOAD_FAILED := 2
const THREAD_LOAD_LOADED := 3
const ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const PROTOCOL := "hardcore.streaming.primitives.v2"
var _owner: int = OS.get_thread_caller_id()
var _configured := false
var _failed := false
var _failure: Callable
var _transport: RefCounted
var _budget: RefCounted
var _clock: RefCounted
var _catalog: Dictionary
var _site: Dictionary
var _bridge_generation := 0
var _operation_sequence := 0
var _texture_sizes: Dictionary = {}
var _collection_receipts: Array[int] = []
var _collection_tokens: Dictionary = {}
var _roots: Dictionary = {}
var _binding_facts: Dictionary = {}
var deadline_fail_count := 0
var deadline_failures: Array[Dictionary] = []

func owner_thread_id() -> int: return _owner
func is_configured() -> bool: return _configured and not _failed

func _reject(reason: String) -> bool:
	_failed = true
	push_error("Streaming primitive boundary rejected: " + reason)
	if _failure.is_valid(): _failure.call(reason)
	return false

func _check(ok: bool, reason: String) -> bool:
	return true if ok and not _failed else _reject(reason)

func _plain(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Dictionary:
		for key in value:
			if not _plain(key) or not _plain(value[key]): return false
	elif value is Array:
		for item in value:
			if not _plain(item): return false
	return true

func _seal(value: Variant) -> Variant:
	if value is Dictionary:
		for key in value: _seal(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value: _seal(item)
		value.make_read_only()
	return value

func configure_owner(catalog: Dictionary, transport: RefCounted, shared_budget: RefCounted, clock: RefCounted, fail_owner: Callable) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner or not fail_owner.is_valid(): return false
	_failure = fail_owner
	for provider in [transport, shared_budget, clock]:
		if not _check(provider != null and provider.has_method("owner_thread_id") and provider.owner_thread_id() == _owner, "cross-owner dependency"): return false
	for method in ["capabilities", "exchange_original_primitive", "ordered_main_prefix", "next_original_operation_sequence", "completed_original_operation_sequence", "next_original_call_ordinal", "is_original_operation_completed"]:
		if not _check(transport.has_method(method), "transport lacks " + method): return false
	for method in ["begin_resource_external_segment", "resume_resource_external_segment", "resource_continuations_configured", "resource_external_segment_active"]:
		if not _check(shared_budget.has_method(method), "single ledger lacks external segment " + method): return false
	if not _check(shared_budget.resource_continuations_configured(), "budget continuation guard not installed"): return false
	var caps: Dictionary = transport.capabilities()
	for key in ["original_point_continuation", "explicit_observation_process_epoch", "exclusive_same_epoch_budget", "ordered_main_prefix", "deadline_preserves_continuation", "abort_owner_on_failure"]:
		if not _check(caps.get(key) == true, "missing transport guarantee " + key): return false
	_bridge_generation = int(caps.get("bridge_generation", 0))
	if not _check(_bridge_generation > 0, "missing bridge incarnation"): return false
	if not _check(_plain(catalog) and catalog.get("protocol") == PROTOCOL, "unsealed/mismatched catalog"): return false
	for key in ["monster_data", "mappings", "exists", "thread_load_constants"]:
		if not _check(catalog.get(key) is Dictionary, "catalog lacks " + key): return false
	if not _check(catalog.thread_load_constants == {"invalid": 0, "in_progress": 1, "failed": 2, "loaded": 3}, "native status constants differ"): return false
	_catalog = _seal(catalog.duplicate(true))
	_transport = transport
	_budget = shared_budget
	_clock = clock
	_configured = true
	return true

func begin_original_phase(call_site: Dictionary) -> bool:
	if not _check(is_configured() and OS.get_thread_caller_id() == _owner and _site.is_empty(), "phase owner invalid or original continuation still open"): return false
	for key in ["clock_epoch", "domain", "entry_id", "entry_ordinal", "bootstrap", "observation_process_epoch", "world_context", "deadline_usec"]:
		if not _check(call_site.has(key), "source call site lacks " + key): return false
	if not _check(_plain(call_site) and call_site.domain in [&"H", &"P"] and int(call_site.deadline_usec) > 0, "invalid call site/deadline"): return false
	_site = _seal(call_site.duplicate(true))
	return true

func finish_original_phase() -> bool:
	if not _check(is_configured() and OS.get_thread_caller_id() == _owner and not _site.is_empty() and not _budget.resource_external_segment_active(), "unsettled/missing resource continuation"): return false
	_site = {}
	return true

func monster_data(id: int) -> Dictionary:
	if not _check(is_configured() and _catalog.monster_data.has(str(id)), "unknown monster catalog ID"): return {}
	return _catalog.monster_data[str(id)]

func mapping_for_monster(id: int) -> Dictionary:
	if not _check(is_configured() and _catalog.mappings.has(str(id)), "unknown mapping catalog ID"): return {}
	return _catalog.mappings[str(id)]

func exists(path: String) -> bool:
	if not _check(is_configured() and _catalog.exists.has(path), "unpublished immutable ResourceLoader.exists fact"): return false
	return bool(_catalog.exists[path])

func _exchange(operation: StringName, arguments: Array) -> Dictionary:
	if live_resource_phase():
		_reject("LIVE caller attempted synchronous resource exchange: " + str(operation))
		return {}
	if not _check(is_configured() and OS.get_thread_caller_id() == _owner and not _site.is_empty() and _plain(arguments), "primitive outside mapped source continuation or nonnumeric arguments"): return {}
	_operation_sequence = int(_transport.next_original_operation_sequence())
	if not _check(_operation_sequence > 0, "unified native operation prefix mismatch"): return {}
	var call_ordinal := int(_transport.next_original_call_ordinal(_site))
	if not _check(call_ordinal > 0, "native shared original call ordinal missing"): return {}
	var site := _site.duplicate(true)
	site["call_ordinal"] = call_ordinal
	var identity := {"bridge_generation": _bridge_generation, "op_sequence": _operation_sequence}
	var external: Dictionary = _budget.begin_resource_external_segment(identity, site)
	if not _check(not external.is_empty(), "single budget could not seal current continuation"): return {}
	var request := {"protocol": PROTOCOL, "identity": identity, "site": site,
		"operation": operation, "arguments": arguments.duplicate(true), "budget": external,
		"predecessor_receipt": _operation_sequence - 1, "output_slot": 0,
		"main_prefix": _transport.ordered_main_prefix(), "submitted_usec": int(_clock.get_ticks_usec())}
	# This native call preserves the actual GDScript stack and local variables.
	# It parks S without spinning. M never waits for S. Deadline records FAIL
	# but MUST NOT return an invented result/unwind this source continuation.
	var reply: Variant = _transport.exchange_original_primitive(request)
	var received_usec := int(_clock.get_ticks_usec())
	if not _check(reply is Dictionary and _plain(reply) and reply.get("request") == request and reply.get("executed") == true and reply.has("result") and reply.has("started_usec") and reply.has("finished_usec"), "non-result cannot resume an original resource call"): return {}
	if not _check(reply.get("disposition") in [&"executed", &"executed_late"] and int(reply.get("completed_prefix_ordinal", -1)) == 1, "missing exact executed prefix"): return {}
	if not _check(int(reply.started_usec) >= int(request.submitted_usec) and int(reply.finished_usec) >= int(reply.started_usec) and received_usec >= int(reply.finished_usec), "resource wall clock/provenance mismatch"): return {}
	if not _budget.resume_resource_external_segment(external, reply): return {}
	if not _check(_transport.is_original_operation_completed(identity), "unified native operation was not consumed"): return {}
	if reply.disposition == &"executed_late" or received_usec > int(site.deadline_usec):
		deadline_fail_count += 1
		deadline_failures.append(_seal({"status": &"FAIL", "identity": identity.duplicate(true), "site": site.duplicate(true), "started_usec": reply.started_usec, "finished_usec": reply.finished_usec, "received_usec": received_usec}))
	return reply

func load_threaded_get_status(path: String) -> int:
	var reply := _exchange(&"status", [path])
	if not _check(not reply.is_empty() and reply.result is int and int(reply.result) in [0, 1, 2, 3], "actual source status missing"): return -1
	return int(reply.result)

func load_threaded_request(path: String, type_hint: String, use_sub_threads: bool) -> int:
	var reply := _exchange(&"load_threaded_request", [path, type_hint, use_sub_threads])
	if not _check(not reply.is_empty() and reply.result is int, "request acceptance missing"): return ERR_UNAVAILABLE
	return int(reply.result)

func load_threaded_get(path: String) -> Variant:
	var reply := _exchange(&"load_threaded_get", [path])
	return _accept_texture_descriptor(reply)

func increment_test_sync_load_count() -> bool:
	var reply := _exchange(&"test_sync_load_count", [])
	return _check(not reply.is_empty() and reply.result == true, "original synchronous test counter failed")

func load_client_texture_for_tests(path: String, expected_size: Vector2i) -> Variant:
	return _accept_texture_descriptor(_exchange(&"test_sync_load_texture", [path, expected_size]))

func _accept_texture_descriptor(reply: Dictionary) -> Variant:
	if not _check(not reply.is_empty() and reply.result is Dictionary, "get descriptor missing"): return null
	var value: Dictionary = reply.result
	if not _check(value.has("is_texture") and value.has("token") and value.has("size"), "get descriptor incomplete"): return null
	if not bool(value.is_texture): return null # Actual native cast returned null.
	var token := int(value.token)
	if not _check(token != 0 and value.size is Vector2 and int(value.get("receipt", 0)) == _operation_sequence, "invalid native texture provenance"): return null
	if _texture_sizes.has(token) and not _check(_texture_sizes[token] == value.size, "texture mutated under a live profile"): return null
	_texture_sizes[token] = value.size
	_collection_receipts.append(int(value.receipt))
	_collection_tokens[int(value.receipt)] = token
	return token

func texture_size(token: Variant) -> Vector2:
	if not _check(is_configured() and token is int and _texture_sizes.has(token), "texture without real get provenance"): return Vector2.ZERO
	return _texture_sizes[token]

func retire_threaded_resource_claims(path: String, count: int) -> bool:
	var reply := _exchange(&"retire_threaded_resource_claims", [path, count])
	if not _check(not reply.is_empty() and reply.result is bool, "retirement receipt absent"): return false
	return bool(reply.result)

func forget_invalid_claim(path: String, count: int) -> bool:
	var reply := _exchange(&"forget_invalid_claim", [path, count])
	return _check(not reply.is_empty() and reply.result == true, "INVALID retirement unconfirmed")

func _profile_tokens(profiles: Array) -> Array[int]:
	var tokens: Array[int] = []
	for profile: Dictionary in profiles:
		for action: String in ACTIONS:
			var token: Variant = profile.get(action)
			if token == null: continue
			if not _check(token is int and _texture_sizes.has(token), "profile holds unknown texture"): return []
			if not tokens.has(token): tokens.append(token)
	return tokens

func replace_profile_roots(scope: String, profiles: Array) -> void:
	if not _check(is_configured(), "lifetime operation after failure"): return
	var tokens := _profile_tokens(profiles)
	if not is_configured() or _roots.get(scope, []) == tokens: return
	var reply := _exchange(&"replace_roots", [scope, tokens])
	if not _check(not reply.is_empty() and reply.result == true, "physical eviction/retention not completed"): return
	if tokens.is_empty(): _roots.erase(scope)
	else: _roots[scope] = tokens
	_prune_texture_metadata()

func bind_visual_profile(service_id: int, profile: Dictionary, profile_identity: Dictionary) -> void:
	var tokens := _profile_tokens([profile])
	if not is_configured(): return
	var reply := _exchange(&"bind_profile", [service_id, profile, profile_identity])
	if not _accept_fact(service_id, reply): return
	var scope := "visual_profile:%d" % service_id
	if tokens.is_empty(): _roots.erase(scope)
	else: _roots[scope] = tokens
	_prune_texture_metadata()

func apply_binding_event(service_id: int, operation: StringName, arguments: Array) -> bool:
	var reply := _exchange(&"bind_or_clear", [service_id, operation, arguments])
	return _accept_fact(service_id, reply)

func retire_visual_binding(service_id: int) -> bool:
	var reply := _exchange(&"retire_visual_binding", [service_id])
	if not _check(not reply.is_empty() and reply.result == true, "original renderer destruction unconfirmed"): return false
	_roots.erase("visual_profile:%d" % service_id)
	_binding_facts.erase(service_id)
	_prune_texture_metadata()
	return true

func observe_binding(service_id: int) -> bool:
	return _accept_fact(service_id, _exchange(&"observe_binding", [service_id]))

func _accept_fact(service_id: int, reply: Dictionary) -> bool:
	if not _check(not reply.is_empty() and reply.result is Dictionary, "actual binding fact absent"): return false
	var fact: Dictionary = reply.result
	for key in ["service_id", "binding_version", "profile_identity", "actual_visible", "sprite_exists", "texture_nonnull", "actual_texture_token", "active_resources", "covered_main_mutation_sequence"]:
		if not _check(fact.has(key), "binding fact incomplete: " + key): return false
	if not _check(int(fact.service_id) == service_id and _plain(fact), "binding identity mismatch"): return false
	_binding_facts[service_id] = _seal(fact.duplicate(true))
	return true

func binding_fact(service_id: int) -> Dictionary:
	if not _check(is_configured() and _binding_facts.has(service_id), "binding never actually observed"): return {}
	return _binding_facts[service_id]

func has_binding_fact(service_id: int) -> bool: return _binding_facts.has(service_id)

func close_collection_escrow() -> void:
	if _collection_receipts.is_empty(): return
	var reply := _exchange(&"close_get_escrow", [_collection_receipts.duplicate()])
	if not _check(not reply.is_empty() and reply.result == true, "temporary physical get ownership not released"): return
	_collection_receipts.clear()
	_collection_tokens.clear()
	_prune_texture_metadata()

func _prune_texture_metadata() -> void:
	var held := {}
	for tokens: Array in _roots.values():
		for token: int in tokens: held[token] = true
	for token: int in _collection_tokens.values(): held[token] = true
	for token: int in _texture_sizes.keys():
		if not held.has(token): _texture_sizes.erase(token)

## Explicit LIVE API: these functions never impersonate the synchronous int/bool
## return values above. Intents retain full work until actual Native acceptance.
var _live_session: WeakRef
var _live_category := ""
var _live_policy: Dictionary = {}
var _live_consumer_key := ""
var _live_intent_sequence := 0
var _live_intents: Dictionary = {}
var _live_queue: Array[int] = []
var _live_retirement: Array[Dictionary] = []
var _live_ticket_services: Dictionary = {}

func configure_live_session(session: RefCounted, category: String, reservation_policy: Dictionary) -> bool:
	if not _check(is_configured() and _live_session == null and session != null and session.owner_thread_id() == _owner and not category.is_empty(), "LIVE session configuration order"): return false
	for name in ["live_resource_phase", "register_live_resource_consumer", "submit_live_resource", "commit_live_resource", "retire_live_resource", "begin_resource_commit_phase", "finish_resource_commit_phase", "original_transport_obligations_released", "freeze_original_main_prefix", "capture_live_resource_continuation_context"]:
		if not _check(session.has_method(name), "LIVE session lacks " + name): return false
	for op in LIVE_OPERATIONS:
		if not _check(reservation_policy.get(op) is int and int(reservation_policy[op]) >= 0, "actual reservation policy absent: " + str(op)): return false
	_live_session = weakref(session)
	_live_category = category
	_live_policy = _seal(reservation_policy.duplicate(true))
	_live_consumer_key = "enemy_streaming:%d" % get_instance_id()
	return session.register_live_resource_consumer(_live_consumer_key, self)

func live_resource_phase() -> bool:
	if _live_session == null or _live_session.get_ref() == null: return false
	var session: RefCounted = _live_session.get_ref()
	return session.live_resource_phase() or (session.get("_phase") == "LIVE" and session.actual_original_closing_resource_service())

# A comparison token, never a resource receipt or permission to change time.
func capture_live_poll_context() -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not is_configured() or _site.is_empty(): return {}
	if not live_resource_phase() or _budget.resource_external_segment_active() or _site.domain != &"P": return {}
	var session: RefCounted = _live_session.get_ref()
	var context: Dictionary = session.capture_live_resource_continuation_context()
	if context.is_empty() or int(context.budget_id) != _budget.get_instance_id(): return {}
	if int(context.clock_epoch) != int(_site.clock_epoch) or int(context.source_process_frame) != int(_site.observation_process_epoch): return {}
	var caps: Dictionary = _transport.capabilities()
	if int(caps.get("bridge_generation",0)) != _bridge_generation or int(context.bridge_generation) != _bridge_generation: return {}
	return _seal({"contract_id":"hardcore.streaming.poll_continuation.v1",
		"primitive_id":get_instance_id(),"transport_id":_transport.get_instance_id(),
		"consumer_key":_live_consumer_key,"category":_live_category,
		"session":context.duplicate(true),"site":_site.duplicate(true)})

func enqueue_live_operation(op: StringName, args: Array, order_key: String, dependencies: Array = [], cleanup := false) -> int:
	if _live_session != null and _live_session.get_ref() != null and _live_session.get_ref().actual_original_clock_frame().get("closing_session") == true and not cleanup: return 0
	if not _check(live_resource_phase() and _plain(args) and _plain(dependencies) and not order_key.is_empty() and _live_policy.has(op), "invalid LIVE operation intent"): return 0
	if op == &"close_get_escrow":
		if not _check(args.size() == 1 and args[0] is Array, "GET escrow close arguments"): return 0
		for receipt: int in args[0]:
			if not _check(not _live_get_receipt_awaits_source_take(receipt), "GET escrow cannot close before original Source result consumption"): return 0
	_live_intent_sequence += 1
	var id := _live_intent_sequence
	_live_intents[id] = {"op":op,"args":args.duplicate(true),"order_key":order_key,"dependencies":dependencies.duplicate(true),"cleanup":cleanup,"accepted":false,"committed":false,"consumed":false}
	_live_queue.append(id)
	return id

func flush_live_submissions() -> bool:
	if not live_resource_phase(): return true
	if not _check(not _site.is_empty() and OS.get_thread_caller_id() == _owner, "LIVE submit needs current original source site"): return false
	var session: RefCounted = _live_session.get_ref()
	# Reservations require the SAME budget stack to be empty. Caller closes its
	# scalar segment before this function; Native acceptance does no Main wait.
	for id: int in _live_queue.duplicate():
		var item: Dictionary = _live_intents[id]
		if item.accepted: continue
		var request := {"protocol":"hardcore.streaming.live_primitives.v1", "site":_site.duplicate(true),
			"op":item.op,"args":item.args.duplicate(true), "main_prefix":session.freeze_original_main_prefix(),
			"deadline_usec":int(_site.deadline_usec),"order_key":item.order_key,
			"dependencies":item.dependencies.duplicate(true),"priority":2 if item.cleanup else 0,"cleanup":item.cleanup}
		var accepted: Dictionary = session.submit_live_resource(request, _live_category, 2 if item.cleanup else 0, int(_live_policy[item.op]), _live_consumer_key)
		if accepted.get("status") in ["BUSY", "BACKPRESSURE"]: break
		if accepted.get("status") != "PENDING" or not accepted.get("request") is Dictionary:
			var actual: Dictionary = _transport.status()
			var prefix: Dictionary = request.main_prefix
			var facts := {"operation":str(item.op),"status":accepted.get("status"),"error":accepted.get("error",""),"through":prefix.get("through_ordinal"),"first":-1 if prefix.get("events",[]).is_empty() else prefix.events[0].ordinal,"native":actual.get("original_main_applied_prefix"),"packets":actual.get("unsettled_original_published_prefixes")}
			return _check(false, "LIVE Native admission invalid: "+JSON.stringify(facts))
		item.accepted = true
		item.request = _seal(accepted.request.duplicate(true))
		item.identity = item.request.identity
		if item.op in [&"bind_profile", &"bind_or_clear", &"observe_binding", &"retire_visual_binding"]:
			_live_ticket_services[JSON.stringify([item.identity.bridge_generation,item.identity.op_sequence])] = {"identity":item.identity,"service_id":int(item.args[0])}
		_live_queue.erase(id)
	return true

func commit_live_results() -> bool:
	if not live_resource_phase(): return true
	var session: RefCounted = _live_session.get_ref()
	for item: Dictionary in _live_intents.values():
		if not item.accepted or item.committed: continue
		var result: Dictionary = session.commit_live_resource(item.identity)
		if result.get("status") in ["PENDING", "BUSY"]: continue
		if not _check(result.get("status") == "SETTLED", "LIVE result commit rejected"): return false
		item.budget_receipt = _seal(result.budget_receipt.duplicate(true))
	for identity: Dictionary in _live_retirement.duplicate():
		if session.retire_live_resource(identity):
			_live_retirement.erase(identity)
			_live_ticket_services.erase(JSON.stringify([identity.bridge_generation,identity.op_sequence]))
	return true

func commit_original_live_feature_reply(identity: Dictionary, reply: Dictionary) -> Dictionary:
	# Session calls this after its once-only budget debit AND Native settlement.
	for item: Dictionary in _live_intents.values():
		if not item.accepted or item.identity != identity: continue
		if item.committed: return {"success":item.reply == reply}
		if not _check(reply.get("request") == item.request and reply.get("executed") == true and _plain(reply), "LIVE reply identity/provenance mismatch"): return {"success":false}
		if item.op == &"status":
			if not _check(reply.result is int and int(reply.result) in [0,1,2,3] and reply.get("native_observation") is Dictionary and reply.native_observation.get("status") == reply.result, "actual LIVE status observation missing"): return {"success":false}
		elif item.op == &"load_threaded_request":
			if not _check(reply.result is int, "actual request acceptance is not int"): return {"success":false}
		elif item.op == &"load_threaded_get":
			_operation_sequence = int(identity.op_sequence)
			item.texture = _accept_texture_descriptor(reply)
			if not is_configured(): return {"success":false}
		elif item.op in [&"bind_profile", &"bind_or_clear", &"observe_binding"]:
			if not _accept_fact(int(item.args[0]), reply): return {"success":false}
			if item.op == &"bind_profile":
				var scope := "visual_profile:%d" % int(item.args[0])
				var tokens := _profile_tokens([item.args[1]])
				if tokens.is_empty(): _roots.erase(scope)
				else: _roots[scope] = tokens
		elif item.op == &"replace_roots":
			if not _check(reply.result == true, "actual root replacement failed"): return {"success":false}
			if item.args[1].is_empty(): _roots.erase(item.args[0])
			else: _roots[item.args[0]] = item.args[1].duplicate()
		elif item.op == &"close_get_escrow":
			if not _check(reply.result == true, "actual escrow close failed"): return {"success":false}
			for receipt: int in item.args[0]:
				_collection_receipts.erase(receipt)
				_collection_tokens.erase(receipt)
		elif item.op == &"retire_visual_binding":
			if not _check(reply.result == true, "actual renderer retirement failed"): return {"success":false}
			_binding_facts.erase(int(item.args[0]))
			_roots.erase("visual_profile:%d" % int(item.args[0]))
		else:
			if not _check(reply.result is bool, "actual claim retirement result missing"): return {"success":false}
		item.reply = _seal(reply.duplicate(true))
		if reply.get("native_deadline_status") == "FAIL":
			deadline_fail_count += 1
			deadline_failures.append(_seal({"status":&"FAIL","identity":identity.duplicate(true),"site":reply.request.site.duplicate(true),"started_usec":reply.started_usec,"finished_usec":reply.finished_usec,"received_usec":reply.native_received_usec,"main_cpu_usec":reply.main_cpu_usec}))
		item.committed = true
		_live_retirement.append(identity.duplicate(true))
		_prune_texture_metadata()
		return {"success":true}
	return {"success":false,"error":"unknown_actual_enemy_ticket"}

func original_ticket_lease_obligations_retired(identity: Dictionary) -> bool:
	# True means real Main acknowledgement or transfer to the pinned sole vault.
	# It is never inferred from an S token, a completed result, or an empty queue.
	return _live_session.get_ref().original_transport_obligations_released(identity)

func take_live_operation(id: int) -> Dictionary:
	if not _live_intents.has(id): return {"status":"INVALID"}
	var item: Dictionary = _live_intents[id]
	if not item.committed: return {"status":"PENDING"}
	if item.get("abandoned", false):
		_live_intents.erase(id)
		return {"status":"ABANDONED_UNACCEPTED"}
	if item.consumed: return {"status":"INVALID","error":"source_result_consumed_twice"}
	item.consumed = true
	var value := {"status":"COMMITTED","result":item.reply.result,"reply":item.reply,"identity":item.identity,"budget_receipt":item.budget_receipt}
	if item.op == &"load_threaded_get": value.texture = item.texture
	_live_intents.erase(id)
	return value

func live_operation_identity(id: int) -> Dictionary:
	return _live_intents[id].identity if _live_intents.has(id) and _live_intents[id].accepted else {}

func live_operations_drained() -> bool:
	return _live_intents.is_empty() and _live_queue.is_empty() and _live_retirement.is_empty()

func live_profile_tokens(profiles: Array) -> Array[int]: return _profile_tokens(profiles)
func live_root_tokens(scope: String) -> Array: return _roots.get(scope, []).duplicate()
func live_collection_receipts() -> Array: return _collection_receipts.duplicate()

func _live_get_receipt_awaits_source_take(receipt: int) -> bool:
	# Main completion/settlement is not the original job's take. Until that
	# exact consumer advances, its real Main get escrow must remain physical.
	for item: Dictionary in _live_intents.values():
		if item.op == &"load_threaded_get" and item.accepted and not item.consumed and int(item.identity.op_sequence) == receipt: return true
	return false

func live_closeable_collection_receipts() -> Array:
	var receipts: Array = []
	for receipt: int in _collection_receipts:
		if not _live_get_receipt_awaits_source_take(receipt): receipts.append(receipt)
	return receipts


func live_collection_receipts_still_open(receipts: Array) -> Array:
	var result: Array = []
	for receipt: int in receipts:
		if _collection_receipts.has(receipt): result.append(receipt)
	return result

func live_binding_transport_drained(service_id: int) -> bool:
	for item: Dictionary in _live_intents.values():
		if item.op in [&"bind_profile", &"bind_or_clear", &"observe_binding", &"retire_visual_binding"] and int(item.args[0]) == service_id: return false
	for held: Dictionary in _live_ticket_services.values():
		if int(held.service_id) == service_id: return false
	return true

func abandon_unaccepted_at_original_exit() -> void:
	# Source has actually stopped. Only work with no Native acceptance may be
	# abandoned; accepted ticket identities and their real results stay owned.
	for id: int in _live_queue.duplicate():
		var item: Dictionary = _live_intents[id]
		if item.accepted: continue
		item.abandoned = true
		item.committed = true
		item.reply = {"result":null}
		_live_queue.erase(id)

func live_source_session() -> RefCounted: return _live_session.get_ref()
func live_escrow_empty() -> bool: return _collection_receipts.is_empty()
func live_roots_empty() -> bool: return _roots.is_empty() and _binding_facts.is_empty()
func release_live_consumer() -> bool:
	return live_operations_drained() and _live_session.get_ref().unregister_live_resource_consumer(_live_consumer_key, self)

func original_source_texture_get_receipt(token: int) -> int:
	return _operation_sequence if _collection_tokens.get(_operation_sequence)!=null and _collection_tokens[_operation_sequence]==token else 0
func replace_original_source_texture_roots(scope: String, tokens: Array) -> bool:
	for token: Variant in tokens:
		if not token is int or not _texture_sizes.has(token): return _reject("source cache root has no actual get provenance")
	var reply: Dictionary=_exchange(&"replace_roots",[scope,tokens])
	if reply.get("result")!=true: return false
	if tokens.is_empty(): _roots.erase(scope)
	else: _roots[scope]=tokens.duplicate()
	_prune_texture_metadata()
	return true
func close_original_source_texture_escrows(receipts: Array) -> bool:
	for receipt: int in receipts:
		if receipt not in _collection_receipts: return _reject("source cache escrow provenance")
	var reply: Dictionary=_exchange(&"close_get_escrow",[receipts])
	if reply.get("result")!=true: return false
	for receipt: int in receipts: _collection_receipts.erase(receipt);_collection_tokens.erase(receipt)
	_prune_texture_metadata()
	return true
func adopt_original_source_texture_metadata(scope: String, records: Array, actual: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=_owner or not is_configured() or actual.get("scope")!=scope or actual.get("records")!=records or actual.get("bridge_generation")!=_bridge_generation or actual.get("actual_Main_vault")!=true: return false
	var tokens: Array=[]
	for record: Dictionary in records:
		if not record.get("token") is int or record.token==0 or not record.get("size") is Vector2 or not record.size.is_finite() or record.size.x<=0 or record.size.y<=0: return false
		if _texture_sizes.has(record.token) and _texture_sizes[record.token]!=record.size: return false
		_texture_sizes[record.token]=record.size;tokens.append(record.token)
	if tokens.is_empty(): _roots.erase(scope)
	else: _roots[scope]=tokens
	return true

func release_original_source_texture_metadata(scope: String, tokens: Array, actual_owner: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_owner or not live_operations_drained() or _roots.get(scope,[])!=tokens or actual_owner==null or actual_owner.owner_thread_id()!=_owner or not actual_owner.has_method("owns_original_source_texture_root") or not actual_owner.owns_original_source_texture_root(scope,tokens): return false
	# Only local endpoint observation metadata transfers to the actual persistent
	# Session cache. No Main root/Texture or Native transferred obligation retires.
	_roots.erase(scope);_prune_texture_metadata()
	return true
