extends RefCounted

## Main runs admitted original primitives. No scheduling, LRU or second budget.
const Identity := preload("res://scripts/monster_identity.gd")
const OriginalVisual := preload("res://scripts/monster_visual.gd")
const ProfilePolicy := preload("res://scripts/gameplay/enemy/enemy_streaming_profile_policy.gd")
const PROTOCOL := "hardcore.streaming.primitives.v2"
const ACTIONS := ["idle", "walk", "attack", "hit", "death"]
var _configured := false
var _validate_ticket: Callable
var _status_observer: Object
var _bridge_generation := 0
var _next_sequence := 1
var _last_request: Dictionary
var _last_reply: Dictionary
var _accepted_claims: Dictionary = {}
var _status_records: Dictionary = {}
var _texture_references: Dictionary = {}
var _texture_roots: Dictionary = {}
var _get_escrow: Dictionary = {}
var _renderers: Dictionary = {}
var _visual_profiles: Dictionary = {}
var _profile_identities: Dictionary = {}
var _binding_versions: Dictionary = {}
var _binding_mutations: Dictionary = {}
var _failed := false
var _test_synchronous := false
var _generation_closed := false
var _actor_assets: RefCounted

func configure_original_actor_asset_inputs(loading: RefCounted, prefix: RefCounted) -> bool:
	if not _main() or not _configured or _actor_assets != null: return false
	var ledger: RefCounted = load("res://scripts/gameplay/presentation/actor_asset_main_ledger.gd").new()
	if not ledger.configure_main(self,loading,prefix): return false
	_actor_assets = ledger
	return true
func prepare_original_player_renderer_inputs(profile: RefCounted, world: Dictionary, scope: Dictionary) -> Dictionary:
	return _actor_assets.prepare_original_player_inputs(profile,world,scope) if _actor_assets != null else {"success":false,"status":"MISSING","error":"actual_actor_input_owner_missing"}
func bind_original_actor_renderer_inputs(owner: Dictionary, template_key: String, scope: Dictionary) -> Dictionary:
	return _actor_assets.bind_original_actor_inputs(owner,template_key,scope) if _actor_assets != null else {"success":false,"status":"MISSING"}
func lookup_original_actor_renderer_asset(owner: Dictionary, key: String, scope: Dictionary) -> Dictionary:
	return _actor_assets.lookup_original_actor_renderer_asset(owner,key,scope) if _actor_assets != null else {"success":false,"status":"MISSING"}
func inspect_original_actor_renderer_pin(owner: Dictionary, fact: Dictionary, scope: Dictionary) -> Dictionary:
	return _actor_assets.inspect_original_actor_renderer_pin(owner,fact,scope) if _actor_assets != null else {"success":false,"status":"MISSING"}
func verify_accepted_original_actor_template_lease(owner: Dictionary, scope: Dictionary) -> bool:
	return _actor_assets != null and _actor_assets.verify_accepted_original_actor_template_lease(owner,scope)
func prepare_original_player_identity_rehome(before: Dictionary, after: Dictionary, scope: Dictionary, transaction: Dictionary) -> Dictionary:
	return _actor_assets.prepare_original_player_identity_rehome(before,after,scope,transaction) if _actor_assets != null else {"success":false,"status":"MISSING"}
func finish_original_player_identity_rehome(before: Dictionary, after: Dictionary, scope: Dictionary, view: Node2D) -> Dictionary:
	return _actor_assets.finish_original_player_identity_rehome(before,after,scope,view) if _actor_assets != null else {"success":false,"status":"MISSING"}
func audio_for_renderer(token: int) -> AudioStream:
	return _actor_assets.audio_for_renderer(token) if _actor_assets != null else null
func bind_original_actor_renderer_instance(owner: Dictionary, scope: Dictionary, view: Node2D) -> Dictionary:
	return _actor_assets.bind_original_actor_renderer_instance(owner,scope,view) if _actor_assets != null else {"success":false,"status":"MISSING"}
func begin_original_actor_renderer_retirement(owner: Dictionary, scope: Dictionary) -> Dictionary:
	return _actor_assets.begin_original_actor_renderer_retirement(owner,scope) if _actor_assets != null else {"status":"INVALID"}
func poll_original_actor_renderer_retirement(owner: Dictionary, scope: Dictionary) -> Dictionary:
	return _actor_assets.poll_original_actor_renderer_retirement(owner,scope) if _actor_assets != null else {"status":"INVALID"}
func release_original_actor_input_template(template_key: String) -> Dictionary:
	return _actor_assets.release_original_template(template_key) if _actor_assets != null else {"status":"INVALID"}

func _main() -> bool:
	if OS.get_thread_caller_id() == OS.get_main_thread_id() and not _failed: return true
	_failed = true
	push_error("Main streaming primitive accessed from wrong owner or after failure")
	return false

func configure_main(validate_host_ticket: Callable, status_observer: Object, bridge_generation: int, test_synchronous := false) -> bool:
	if not _main() or _configured or not validate_host_ticket.is_valid() or bridge_generation <= 0: return false
	if status_observer == null or not status_observer.is_class("HardCoreResourceObservation") or not status_observer.has_method("threaded_status") or not status_observer.has_method("retire_generation"):
		push_error("missing registered HardCore observation_process_epoch status entry")
		return false
	_validate_ticket = validate_host_ticket
	_status_observer = status_observer
	_bridge_generation = bridge_generation
	if test_synchronous and not PlayerState.test_mode: return false
	_test_synchronous = test_synchronous
	_configured = true
	return true

func _error(reason: String) -> Dictionary:
	_failed = true
	push_error("Main resource transaction rejected: " + reason)
	return {"protocol_error": reason, "executed": false}

func capture_catalog(monster_ids: PackedInt32Array) -> Dictionary:
	if not _main(): return {}
	var result := {"protocol": PROTOCOL, "monster_data": {}, "mappings": {}, "exists": {},
		"thread_load_constants": {"invalid": ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"in_progress": ResourceLoader.THREAD_LOAD_IN_PROGRESS, "failed": ResourceLoader.THREAD_LOAD_FAILED,
			"loaded": ResourceLoader.THREAD_LOAD_LOADED}}
	for id: int in monster_ids:
		var data: Dictionary = GameData.get_monster_by_id(id)
		var mapping: Dictionary = ProfilePolicy.mapping_for_profile(Identity.appearance_profile(Identity.monster_id(data))) if not data.is_empty() else {}
		result.monster_data[str(id)] = data.duplicate(true)
		result.mappings[str(id)] = mapping.duplicate(true)
		for action: Dictionary in mapping.get("actions", {}).values():
			var path := str(action.get("path", ""))
			if not result.exists.has(path): result.exists[path] = ResourceLoader.exists(path) if not path.is_empty() else false
	return result

func register_renderer(service_id: int, renderer: Node2D) -> bool:
	if not _main() or service_id <= 0 or renderer == null or not (renderer.has_method("apply_event_checked") or renderer.has_method("apply_event")) or int(renderer.canonical_service_id) != service_id or _renderers.has(service_id): return false
	_renderers[service_id] = weakref(renderer)
	return true

func execute_original_primitive(request: Dictionary) -> Dictionary:
	if not _main() or not _configured: return {}
	if request == _last_request and not _last_reply.is_empty(): return _last_reply.duplicate(true)
	var identity: Dictionary = request.get("identity", {})
	if request.get("protocol") != PROTOCOL or int(identity.get("bridge_generation", 0)) != _bridge_generation or int(identity.get("op_sequence", 0)) != _next_sequence or int(request.get("predecessor_receipt", -1)) != _next_sequence - 1:
		return _error("bridge generation/op sequence/predecessor mismatch")
	# Host has applied the exact earlier Main journal prefix and reserved this
	# command's receipt slot. It never waits here for S to compute a next step.
	if not bool(_validate_ticket.call(request, &"original_resource_primitive")): return _error("source continuation, prefix or single-budget lease invalid")
	var started := Time.get_ticks_usec()
	var outcome := _execute_resource_operation(request, false)
	if outcome.is_empty(): return {}
	var result: Variant = outcome.result
	var native_observation: Dictionary = outcome.native_observation
	if _failed: return {}
	var finished := Time.get_ticks_usec()
	_last_request = request.duplicate(true)
	_last_reply = {"request": _last_request, "executed": true,
		"disposition": &"executed_late" if finished > int(request.site.deadline_usec) else &"executed",
		"result": result, "started_usec": started, "finished_usec": finished, "completed_prefix_ordinal": 1,
		"native_observation": native_observation}
	_next_sequence += 1
	return _last_reply.duplicate(true)

func _renderer(id: int) -> Object:
	var holder: WeakRef = _renderers.get(id)
	var value: Object = holder.get_ref() if holder != null else null
	return value if value != null and is_instance_valid(value) else null

func _binding_fact(id: int) -> Dictionary:
	var renderer: Object = _renderer(id)
	if renderer == null: return _error("binding observation requires actual renderer")
	var sprite: Sprite2D = renderer.sprite
	return {"service_id": id, "binding_version": int(_binding_versions.get(id, 0)),
		"profile_identity": (_profile_identities.get(id, {"service_id": id, "resource_key": "", "world_generation": -1}) as Dictionary).duplicate(true),
		"actual_visible": bool(renderer.visible), "sprite_exists": is_instance_valid(sprite),
		"texture_nonnull": is_instance_valid(sprite) and sprite.texture != null,
		"actual_texture_token": sprite.texture.get_instance_id() if is_instance_valid(sprite) and sprite.texture != null else 0,
		"active_resources": (_visual_profiles.get(id, {}) as Dictionary).duplicate(true),
		"covered_main_mutation_sequence": int(_binding_mutations.get(id, 0))}

func _replace_roots(scope: String, tokens: Array) -> bool:
	for token: int in tokens:
		if not _texture_references.has(token): return false
	if tokens.is_empty(): _texture_roots.erase(scope)
	else: _texture_roots[scope] = tokens.duplicate()
	_release_unrooted()
	return true

func _release_unrooted() -> void:
	var held := {}
	for tokens: Array in _texture_roots.values():
		for token: int in tokens: held[token] = true
	for token: int in _get_escrow.values(): held[token] = true
	for token: int in _texture_references.keys():
		if not held.has(token): _texture_references.erase(token)

func texture_for_renderer(token: int) -> Texture2D:
	if not _main() or not _texture_references.has(token):
		_error("renderer requested texture after physical profile lifetime")
		return null
	return _texture_references[token] as Texture2D

func ownership_receipt() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"protocol_error": "wrong owner"}
	return {"accepted_claims": _accepted_claims.duplicate(), "texture_count": _texture_references.size(),
		"root_count": _texture_roots.size(), "escrow_count": _get_escrow.size(), "failed": _failed,
		"bridge_generation": _bridge_generation, "next_primitive_sequence": _next_sequence}

func close_generation(host_ticket: Dictionary) -> Dictionary:
	# Normal and fault paths share this final close. Fault status does not bar
	# factual cleanup; it must remain visible in the final ownership receipt.
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"ok": false, "error": "close_requires_main"}
	if _generation_closed: return {"ok": true, "bridge_generation": _bridge_generation, "already_closed": true}
	if not _configured or not bool(_validate_ticket.call(host_ticket, &"close_resource_generation")): return {"ok": false, "error": "accepted_prefix_or_global_obligations_unsettled"}
	if _actor_assets != null and not _actor_assets.terminal(): return {"ok":false,"error":"actual_actor_assets_still_owned"}
	# A successful handoff to ContentLayers empties our accepted count, but is
	# not proof that the transferred obligation finished. Host's close ticket
	# must also cover that original service, all consumers and prefix receipts.
	if not _accepted_claims.is_empty() or not _texture_roots.is_empty() or not _get_escrow.is_empty() or not _texture_references.is_empty() or not _renderers.is_empty(): return {"ok": false, "error": "physical_ownership_unsettled"}
	var result: Dictionary = _status_observer.retire_generation(_bridge_generation)
	if result.get("ok") != true: return {"ok": false, "error": "native_observation_retirement_failed", "native": result}
	_generation_closed = true
	_configured = false
	return {"ok": true, "bridge_generation": _bridge_generation, "completed_op_prefix": _next_sequence - 1, "ownership": ownership_receipt()}

func retire_after_owner_fault(host_ticket: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not _configured: return {"complete": false}
	if not bool(_validate_ticket.call(host_ticket, &"fault_resource_retirement")): return {"complete": false}
	if _actor_assets != null and not _actor_assets.terminal(): return {"complete":false,"error":"actual_actor_assets_still_owned"}
	_failed = true
	var complete := true
	for path: String in _accepted_claims.keys():
		if bool(ContentLayers.retire_threaded_resource_claims(path, int(_accepted_claims[path]))): _accepted_claims.erase(path)
		else: complete = false
	_texture_roots.clear()
	_get_escrow.clear()
	_texture_references.clear()
	_visual_profiles.clear()
	_profile_identities.clear()
	_renderers.clear()
	return {"complete": complete, "receipt": ownership_receipt()}

func _execute_resource_operation(request: Dictionary, live: bool) -> Dictionary:
	var result: Variant
	var native_observation: Dictionary = {}
	var args: Array = request.args if live else request.arguments
	var process_epoch := Engine.get_process_frames() if live else int(request.site.observation_process_epoch)
	var operation := StringName(request.op if live else request.operation)
	var actual_sequence := int(request.identity.op_sequence)
	match operation:
		&"status":
			if args.size() != 1: return _error("status ABI invalid")
			var path := str(args[0])
			# REQUIRED narrow engine entry: exact original status algorithm,
			# _ensure_load_progress, RenderingServer sync and original sample.
			# Only the registered call's process epoch is supplied explicitly.
			native_observation = _status_observer.threaded_status(path, process_epoch, _bridge_generation)
			for field in ["ok", "status", "progress", "progress_ensured", "observation_process_epoch", "bridge_generation", "actual_start_usec", "actual_end_usec"]:
				if not native_observation.has(field): return _error("incomplete native status receipt: " + field)
			if native_observation.ok != true or int(native_observation.observation_process_epoch) != process_epoch or int(native_observation.bridge_generation) != _bridge_generation:
				return _error("native status rejected owner/epoch/incarnation")
			result = int(native_observation.status)
			if result not in [0, 1, 2, 3]: return _error("native returned invalid status value")
			_status_records[path] = {"status": result, "process_epoch": process_epoch, "sequence": actual_sequence}
		&"load_threaded_request":
			if args.size() != 3 or str(args[1]) != "Texture2D": return _error("request ABI differs from original")
			result = ResourceLoader.load_threaded_request(str(args[0]), str(args[1]), bool(args[2]))
			if int(result) == OK: _accepted_claims[str(args[0])] = int(_accepted_claims.get(str(args[0]), 0)) + 1
		&"load_threaded_get":
			if args.size() != 1: return _error("get ABI invalid")
			var path := str(args[0])
			if int(_accepted_claims.get(path, 0)) <= 0: return _error("get has no accepted native claim")
			var observed: Dictionary = _status_records.get(path, {})
			if int(observed.get("status", -1)) not in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED] or (not live and int(observed.get("process_epoch", -1)) != process_epoch):
				return _error("get lacks original same-P LOADED observation")
			# Do NOT perform an extra status read here. That would change original
			# progress/RenderingServer sync and possibly the returned observation.
			_accepted_claims[path] = int(_accepted_claims[path]) - 1
			if int(_accepted_claims[path]) == 0: _accepted_claims.erase(path)
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			result = {"is_texture": texture != null, "token": 0, "size": Vector2.ZERO}
			if texture != null:
				var token := texture.get_instance_id()
				_texture_references[token] = texture
				_get_escrow[actual_sequence] = token
				result = {"is_texture": true, "token": token, "size": texture.get_size(), "receipt": actual_sequence}
		&"retire_threaded_resource_claims":
			if args.size() != 2 or int(args[1]) <= 0: return _error("retirement ABI invalid")
			var path := str(args[0])
			var count := int(args[1])
			if int(_accepted_claims.get(path, 0)) < count: return _error("retirement duplicates native ownership")
			result = bool(ContentLayers.retire_threaded_resource_claims(path, count))
			if result:
				_accepted_claims[path] = int(_accepted_claims[path]) - count
				if int(_accepted_claims[path]) == 0: _accepted_claims.erase(path)
		&"forget_invalid_claim":
			if args.size() != 2 or int(args[1]) <= 0: return _error("invalid-claim retirement ABI invalid")
			var path := str(args[0])
			if int(_status_records.get(path, {}).get("status", -1)) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: return _error("claim retirement lacks actual INVALID observation")
			var remaining := int(_accepted_claims.get(path, 0))
			if remaining > 0 and remaining < int(args[1]): return _error("invalid count exceeds original ownership")
			if remaining > int(args[1]): _accepted_claims[path] = remaining - int(args[1])
			else: _accepted_claims.erase(path)
			result = true
		&"replace_roots":
			if args.size() != 2 or not _replace_roots(str(args[0]), args[1]): return _error("invalid physical reference replacement")
			result = true
		&"close_get_escrow":
			for receipt: int in args[0]:
				if not _get_escrow.has(receipt): return _error("get escrow closed twice")
				_get_escrow.erase(receipt)
			_release_unrooted()
			result = true
		&"bind_profile":
			if args.size() != 3 or not args[1] is Dictionary or not args[2] is Dictionary or _renderer(int(args[0])) == null: return _error("profile binding ABI/renderer invalid")
			var id := int(args[0])
			var profile: Dictionary = args[1]
			if int(args[2].get("service_id", 0)) != id or not args[2].has("resource_key") or not args[2].has("world_generation"): return _error("profile identity incomplete")
			var tokens: Array[int] = []
			for action: String in ACTIONS:
				if profile.has(action) and profile[action] != null: tokens.append(int(profile[action]))
			if not _replace_roots("visual_profile:%d" % id, tokens): return _error("profile contains a physically retired texture")
			_visual_profiles[id] = profile.duplicate(true)
			_profile_identities[id] = args[2].duplicate(true)
			_binding_versions[id] = int(_binding_versions.get(id, 0)) + 1
			_binding_mutations[id] = actual_sequence
			result = _binding_fact(id)
		&"bind_or_clear":
			if args.size() != 3 or not args[2] is Array: return _error("binding mutation ABI invalid")
			var id := int(args[0])
			var renderer: Object = _renderer(id)
			if renderer == null: return _error("canonical Main renderer missing")
			var binding_operation := StringName(args[1])
			if binding_operation not in [&"visual_visible", &"visual_create_body_sprite", &"sprite_texture"]: return _error("not an admitted binding mutation")
			if binding_operation == &"visual_create_body_sprite" and (not args[2].is_empty() or is_instance_valid(renderer.sprite)): return _error("Sprite already exists")
			if binding_operation == &"visual_visible" and (args[2].size() != 1 or not args[2][0] is bool): return _error("visible ABI invalid")
			if binding_operation == &"sprite_texture":
				if args[2].size() != 1 or not is_instance_valid(renderer.sprite): return _error("texture binding without actual Sprite")
				if args[2][0] != null and not _texture_references.has(int(args[2][0])): return _error("texture binding without physical ownership")
			var actual_event: Dictionary={"service_id":id,"operation":binding_operation,"arguments":args[2]}
			if renderer.has_method("apply_event_checked"):
				if renderer.apply_event_checked(actual_event)!=true: return _error("actual Main binding mutation rejected")
			else: renderer.apply_event(actual_event)
			# A returned callback is not a physical binding result. Check the
			# actual unchanged Main property before advancing the binding ledger.
			if binding_operation==&"visual_create_body_sprite" and not is_instance_valid(renderer.sprite): return _error("actual Sprite creation missing")
			if binding_operation==&"visual_visible" and renderer.visible!=args[2][0]: return _error("actual visibility mutation missing")
			if binding_operation==&"sprite_texture":
				if args[2][0]==null:
					if renderer.sprite.texture!=null: return _error("actual texture clear missing")
				elif renderer.sprite.texture==null or renderer.sprite.texture.get_instance_id()!=int(args[2][0]): return _error("actual retained texture binding missing")
			_binding_mutations[id] = actual_sequence
			_binding_versions[id] = int(_binding_versions.get(id, 0)) + 1
			result = _binding_fact(id)
		&"observe_binding": result = _binding_fact(int(args[0]))
		&"retire_visual_binding":
			var id := int(args[0])
			if _renderer(id) != null: return _error("profile retirement precedes actual original renderer destruction")
			if not _renderers.has(id): return _error("unknown/already retired renderer")
			if not _replace_roots("visual_profile:%d" % id, []): return _error("visual physical roots did not retire")
			_visual_profiles.erase(id)
			_profile_identities.erase(id)
			_binding_versions.erase(id)
			_binding_mutations.erase(id)
			_renderers.erase(id)
			result = true
		&"test_sync_load_count":
			if not _test_synchronous or not args.is_empty(): return _error("test-only synchronous counter unavailable")
			OriginalVisual._client_texture_load_request_count += 1
			result = true
		&"test_sync_load_texture":
			if not _test_synchronous or args.size() != 2 or not args[1] is Vector2i: return _error("test-only synchronous texture load unavailable")
			# Exact original imported Texture2D/size test then source-image fallback.
			var path := str(args[0])
			var expected_size: Vector2i = args[1]
			var texture: Texture2D
			if ResourceLoader.exists(path):
				var imported := load(path) as Texture2D
				if imported != null and Vector2i(imported.get_size()) == expected_size: texture = imported
			if texture == null:
				var image := Image.load_from_file(ProjectSettings.globalize_path(path))
				texture = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
			result = {"is_texture": texture != null, "token": 0, "size": Vector2.ZERO}
			if texture != null:
				var token := texture.get_instance_id()
				_texture_references[token] = texture
				_get_escrow[actual_sequence] = token
				result = {"is_texture": true, "token": token, "size": texture.get_size(), "receipt": actual_sequence}
		_: return _error("operation is not an original resource primitive")
	return {} if _failed else {"result":result,"native_observation":native_observation}

var _live_host_ref: WeakRef
var _live_host: Object:
	get: return _live_host_ref.get_ref() if _live_host_ref != null else null
var _live_transfer_receipt: Dictionary = {}
var _live_transfer_completed := true

func configure_live_main(host: Object, actual_script_sha: String) -> bool:
	if not _main() or not _configured or _live_host != null or host == null: return false
	for method in ["bind_live_original_resource_vault", "sample_main_thread_cpu_usec", "transfer_live_original_resource_obligations", "ack_live_original_resource_retirement", "certify_live_original_resource_vault_closed"]:
		if not host.has_method(method): return false
	if not host.bind_live_original_resource_vault(self, actual_script_sha): return false
	_live_host_ref = weakref(host)
	return true

func execute_live_original_primitive(request: Dictionary) -> Dictionary:
	if not _main() or not _configured or _live_host == null or not _live_transfer_completed: return {}
	if request == _last_request and not _last_reply.is_empty(): return _last_reply.duplicate(true)
	if request.get("protocol") != "hardcore.streaming.live_primitives.v1" or int(request.get("identity", {}).get("bridge_generation", 0)) != _bridge_generation:
		return _error("LIVE resource vault incarnation mismatch")
	if not bool(_validate_ticket.call(request, &"original_live_resource_primitive")): return _error("actual LIVE execution ticket not claimed")
	var started := Time.get_ticks_usec()
	var cpu_started := int(_live_host.sample_main_thread_cpu_usec())
	if cpu_started < 0: return _error("actual Main CPU sample missing")
	var outcome := _execute_resource_operation(request, true)
	if outcome.is_empty(): return {}
	var cpu_finished := int(_live_host.sample_main_thread_cpu_usec())
	var finished := Time.get_ticks_usec()
	if cpu_finished < cpu_started: return _error("actual Main CPU sample regressed")
	_last_request = request.duplicate(true)
	_last_reply = {"request":_last_request,"executed":true,
		"disposition":&"executed_late" if finished > int(request.deadline_usec) else &"executed",
		"result":outcome.result,"started_usec":started,"finished_usec":finished,
		"main_cpu_usec":cpu_finished-cpu_started,"completed_prefix_ordinal":1,
		"actual_lease_obligations":_actual_live_obligations(StringName(request.op), request.args, outcome.result, int(request.identity.op_sequence))}
	if request.op == &"status": _last_reply.native_observation = outcome.native_observation
	_live_transfer_receipt = {"contract_id":"hardcore.resource.actual_vault_transfer.v1",
		"bridge_generation":_bridge_generation,"owner_incarnation":get_instance_id(),
		"identity":request.identity.duplicate(true),"lease_ids":_last_reply.actual_lease_obligations.duplicate(true),
		"actual_main_op_sequence":int(request.identity.op_sequence),"actual_operation":request.op}
	_live_transfer_completed = false
	return _last_reply.duplicate(true)

func _actual_live_obligations(op: StringName, args: Array, result: Variant, sequence: int) -> Array:
	# Witnesses are derived from the original vault AFTER the actual mutation.
	# Only entries created/held by this operation are transferred, not a snapshot
	# of unrelated obligations or stale claims that a get already consumed.
	var leases: Array = []
	if op == &"load_threaded_request" and int(result) == OK:
		leases.append({"kind":"loader_claim","path":str(args[0]),"count":1})
	elif op == &"load_threaded_get" and bool(result.is_texture):
		leases.append({"kind":"get_escrow","receipt":sequence,"token":int(_get_escrow[sequence])})
	elif op == &"replace_roots" and not args[1].is_empty():
		leases.append({"kind":"texture_roots","scope":str(args[0]),"tokens":(_texture_roots[str(args[0])] as Array).duplicate()})
	elif op in [&"bind_profile", &"bind_or_clear"]:
		var id := int(args[0])
		leases.append({"kind":"renderer_binding","service_id":id,"binding_version":int(_binding_versions[id]),
			"tokens":(_texture_roots.get("visual_profile:%d" % id, []) as Array).duplicate()})
	return leases

func transfer_current_live_obligations() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _live_host == null or _last_reply.is_empty(): return {"status":"INVALID"}
	if _live_transfer_completed: return {"status":"TRANSFERRED"}
	var leases: Array = _last_reply.actual_lease_obligations
	if leases.is_empty():
		if not _live_host.ack_live_original_resource_retirement(_last_request.identity, leases): return {"status":"PENDING"}
		_live_transfer_completed = true
		return {"status":"TRANSFERRED","physical_obligations_empty":true}
	var transferred: Dictionary = _live_host.transfer_live_original_resource_obligations(_last_request.identity, leases, _live_transfer_receipt)
	if transferred.get("status") == "TRANSFERRED": _live_transfer_completed = true
	return transferred

func certify_actual_live_vault_closed(host_ticket: Dictionary) -> Dictionary:
	if _live_host == null or not _live_transfer_completed: return {"ok":false,"error":"actual_transfer_still_pending"}
	var closed: Dictionary = close_generation(host_ticket)
	if closed.get("ok") != true: return closed
	if not _live_host.certify_live_original_resource_vault_closed(closed): return {"ok":false,"error":"actual_native_vault_close_certificate_rejected"}
	return closed

func texture_from_token(token: int) -> Texture2D: return texture_for_renderer(token)

func capture_original_source_texture_roots(scope: String) -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	if not _configured or _generation_closed or _failed: return {}
	var records: Array=[]
	for token: int in _texture_roots.get(scope,[]):
		var texture: Texture2D=texture_for_renderer(token)
		if texture==null: return {}
		records.append({"token":token,"size":texture.get_size()})
	return {"scope":scope,"records":records,"bridge_generation":_bridge_generation,"actual_Main_vault":true}

func execute_claimed_original_cold_primitive(request: Dictionary) -> Dictionary:
	if not _main() or not _configured: return {}
	if request==_last_request and not _last_reply.is_empty(): return _last_reply.duplicate(true)
	var identity: Dictionary=request.get("identity",{})
	if request.get("protocol")!=PROTOCOL or identity.get("bridge_generation")!=_bridge_generation or not identity.get("op_sequence") is int or identity.op_sequence<=0 or request.get("predecessor_receipt")!=identity.op_sequence-1: return _error("actual shared cold identity")
	if not bool(_validate_ticket.call(request,&"original_resource_primitive")): return _error("actual Native cold execute claim")
	var started:=Time.get_ticks_usec()
	var outcome: Dictionary=_execute_resource_operation(request,false)
	if outcome.is_empty() or _failed: return {}
	_last_request=request.duplicate(true)
	_last_reply={"request":_last_request,"executed":true,"disposition":&"executed_late" if Time.get_ticks_usec()>int(request.site.deadline_usec) else &"executed","result":outcome.result,"started_usec":started,"finished_usec":Time.get_ticks_usec(),"completed_prefix_ordinal":1,"native_observation":outcome.native_observation}
	return _last_reply.duplicate(true)
