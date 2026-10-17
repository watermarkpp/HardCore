extends RefCounted

## The actual existing Main WorldBackground remains the only map display/cache.
## The coordinator here owns only the original physical resource cache/claims.
## The S coordinator owns stages, collision/actor queues and readiness counts.
const Coordinator := preload("res://scripts/world_bootstrap_coordinator.gd")
const Publication := preload("res://scripts/gameplay/world/world_environment_publication.gd")
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
var _background: Node2D
var _producer_ref: WeakRef
var _producer: RefCounted:
	get: return _producer_ref.get_ref() if _producer_ref != null else null
	set(value): _producer_ref = weakref(value) if value != null else null
var _coordinator: RefCounted
var _descriptor: Dictionary
var _scope: Dictionary
var _last_request: Dictionary = {}
var _last_result: Dictionary = {}
var _next_sequence := 1
var _loading_receipt: Dictionary = {}
var _descriptors: Array = []
var _actual_retiring_claims: Dictionary = {}
var _actual_claim_history: Array = []
var _actual_retirement_started := false
var _actual_terminal_started := false
var _actual_terminal_visuals: Array[WeakRef] = []

static func capture_main(background: Node2D, source_root_id: int, owner_session_id: int, world_context: Dictionary, executor_id: int, loading_producer: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or background == null or source_root_id == 0 or owner_session_id == 0 or executor_id == 0: return {"success":false,"status":"MISSING"}
	for method: String in ["prepare_original_visual_map_build","build_original_visual_map_item","finish_original_visual_map_build","original_visual_environment_is_physics_free","actual_original_visual_build_state"]:
		if not background.has_method(method): return {"success":false,"status":"MISSING","method":method}
	if not background.original_visual_environment_is_physics_free(): return {"success":false,"status":"MISSING","error":"old_Main_physics_handoff_not_complete"}
	for method: String in ["verify_original_map_loading_command","capture_original_map_loading_publication_receipt","bind_original_map_io_observer","inspect_original_map_claim_transfer"]:
		if loading_producer == null or not loading_producer.has_method(method): return {"success":false,"status":"MISSING","method":method}
	var descriptor := {"contract_id":"source.map.loading.owner.v1","source_root_id":source_root_id,
		"owner_session_id":owner_session_id,"world_context":world_context,"main_executor_id":executor_id}
	return {"success":true,"publication":{"contract_id":"source.map.loading.publication.v1","world_context":world_context,
		"owner_descriptor":descriptor,"max_items_per_frame":int(ProjectSettings.get_setting("world/loading/max_items_per_frame",Coordinator.DEFAULT_MAX_ITEMS_PER_FRAME)),
		"slice_budget_ms":float(ProjectSettings.get_setting("world/loading/slice_budget_ms",Coordinator.DEFAULT_SLICE_BUDGET_MS))}}

func configure_main(background: Node2D, actual_loading_producer: RefCounted, descriptor: Dictionary) -> bool:
	if _background != null or OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	var checked := capture_main(background,int(descriptor.source_root_id),int(descriptor.owner_session_id),descriptor.world_context,int(descriptor.main_executor_id),actual_loading_producer)
	if checked.get("success") != true or checked.publication.owner_descriptor != descriptor: return false
	_background = background; _producer = actual_loading_producer; _descriptor = descriptor.duplicate(true)
	_coordinator = Coordinator.new()
	var observed: Dictionary = _producer.bind_original_map_io_observer(self,descriptor)
	return observed.get("success") == true and observed.get("actual_owner_descriptor") == _descriptor

func _visual_facts() -> Dictionary:
	return {"environment_node_count":_background.environment_node_count(),"chunk_texture_count":_background.editor_runtime_chunk_texture_count(),
		"gothic_collision_entries":_background.get("_gothic_camp_built").get("collisions",[])}
func _resource_facts() -> Dictionary:
	return {"ok":true,"resource_manifest":_coordinator.resource_manifest.duplicate(true),"diagnostic":_coordinator.diagnostic.duplicate(true),"failed_required":_coordinator.has_failed_required_resource(),
		"unexpected_sync_load_count":_coordinator.unexpected_sync_load_count,"unexpected_sync_load_count_build_map":_coordinator.unexpected_sync_load_count_build_map,
		"unexpected_sync_load_count_build_collision":_coordinator.unexpected_sync_load_count_build_collision,"unexpected_sync_load_count_spawn_actors":_coordinator.unexpected_sync_load_count_spawn_actors}

func execute_original_map_command(request: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if request == _last_request: return _last_result # Reply backpressure never replays Nodes/load_get.
	if request.get("contract_id") != "source.map.loading.request.v1" or request.get("owner_descriptor") != _descriptor or request.get("request_sequence") != _next_sequence or not request.get("arguments") is Array: return {"ok":false,"error":"map_command_identity_or_order"}
	var permitted: Dictionary = _producer.verify_original_map_loading_command(request,_descriptor)
	if permitted.get("status") != "READY" or permitted.get("scope") != request.get("scope"): return {"ok":false,"error":"actual_Main_Loading_permission"}
	_scope = request.scope
	var args: Array = request.arguments
	var result: Dictionary
	match request.operation:
		"prepare":
			if args.size() != 3 or not args[0] is int or not args[1] is int or not args[2] is Dictionary: return {"ok":false,"error":"prepare_schema"}
			if has_pending_actual_original_map_claims() or _actual_terminal_started: return {"ok":false,"error":"previous_actual_Map_claims_or_terminal_owner"}
			_actual_retirement_started = false; _actual_claim_history = []
			# Original Main resources from any older build are retained/transferred.
			_coordinator.begin_map_transition(int(args[0]))
			_coordinator.generation = int(args[1])
			result = _background.prepare_original_visual_map_build(int(args[0]),_coordinator,args[2])
			result.resource_manifest = _coordinator.resource_manifest.duplicate(true)
		"request_resources":
			if args.size() != 1 or args[0] != _coordinator.resource_manifest: return {"ok":false,"error":"same_original_manifest_required"}
			var requested: int = _coordinator.request_threaded_prefetch()
			result = _resource_facts(); result.requested = requested
		"poll_resources":
			if not args.is_empty(): return {"ok":false}
			var complete: bool = _coordinator.poll_threaded_prefetch()
			result = _resource_facts(); result.complete = complete
		"select_descriptors":
			if not args.is_empty() or _coordinator.has_failed_required_resource(): return {"ok":false}
			_background._select_wall_render_mode()
			_descriptors = _background.get("_pending_map_descriptors").duplicate(true)
			result = {"ok":true,"descriptors":_descriptors,"wall_render_mode":_background.get("_wall_render_mode")}
		"capture_environment":
			if not args.is_empty(): return {"ok":false}
			var captured := Publication.capture(_background,[int(_scope.map_id)])
			if captured.get("ok") != true: return captured
			var publication: Dictionary = captured.publication.duplicate(true)
			for id: int in publication.runtime_maps:
				publication.runtime_maps[id].game_content = Bridge.game_content_for_map(id)
			# This actual producer must inspect MapService identity, acquired resources,
			# pin closure/bindings, immutable bytes and the live covered Loading scope.
			_loading_receipt = _producer.capture_original_map_loading_publication_receipt(_scope,publication,_coordinator,self)
			if _loading_receipt.get("status") != "READY": return {"ok":false,"error":"actual_map_Loading_pin_or_MapService_receipt"}
			result = {"ok":true,"publication":publication,"actual_loading_receipt":_loading_receipt}
		"build_item":
			if args.size() != 1 or not args[0] is Dictionary or _descriptors.is_empty() or args[0] != _descriptors.front(): return {"ok":false,"error":"original_descriptor_order"}
			var node: Node = _background.build_original_visual_map_item(args[0])
			var actual_state: Dictionary = _background.actual_original_visual_build_state()
			if actual_state.get("ok") != true: return {"ok":false,"error":"actual_Main_visual_build_failed","details":actual_state}
			# Original map queue counts every descriptor, including a legitimate null
			# visual. S still receives the exact result/facts before advancing.
			_descriptors.pop_front()
			result = {"ok":true,"created":node != null,"visual_facts":_visual_facts()}
		"finish_visual":
			if not args.is_empty() or not _descriptors.is_empty(): return {"ok":false}
			if not _background.finish_original_visual_map_build(): return {"ok":false,"error":"actual_Main_visual_finish_failed","details":_background.actual_original_visual_build_state()}
			result = {"ok":true,"visual_facts":_visual_facts()}
		"retire_claims":
			if not args.is_empty(): return {"ok":false}
			var retired: Dictionary = service_actual_original_map_claim_retirement()
			# Legacy field means original responsibility is cleared. This branch
			# actually consumes terminal tokens; it never invents a FIFO transfer.
			result = {"ok":retired.get("success") == true,"transferred":retired.get("status") == "READY","actual_io":inspect_actual_original_map_io()}
		"zone":
			if args.size() != 2 or not args[0] is String or not args[1] is Dictionary: return {"ok":false}
			_background.zone_name = args[0]; _background.zone_data = args[1].duplicate(true)
			result = {"ok":true}
		"focus":
			if args.size() != 1 or not args[0] is Vector2: return {"ok":false}
			# M focus is display-only. The original physics focus update runs on S.
			_background.set("_focus_position",args[0]); _background.queue_redraw()
			result = {"ok":true}
		_: return {"ok":false,"error":"unsupported_map_opcode"}
	var copied := Graph.copy_and_seal(result)
	if not copied.ok: return {"ok":false,"error":"map_result_live_value","errors":copied.errors}
	_last_request = request.duplicate(true); _last_result = copied.value; _next_sequence += 1
	return _last_result

func inspect_actual_original_map_io() -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var transferred: Dictionary = _producer.inspect_original_map_claim_transfer(self,_descriptor,_coordinator)
	return {"owner_descriptor":_descriptor,"generation":_coordinator.generation,"resource_manifest":_coordinator.resource_manifest.duplicate(true),
		"retired_threaded_requests":_coordinator.get("_retired_threaded_requests").duplicate(true),
		"actual_prefetched_paths":_coordinator.get("_prefetched_resources").keys(),"actual_transfer":transferred,"actual_loading_receipt":_loading_receipt,
		"actual_retiring_claims":_actual_retiring_claims.duplicate(true),"actual_claim_history":_actual_claim_history.duplicate(true),"actual_live_visual_ids":_actual_live_visual_ids(),"terminal":_actual_terminal_started and _actual_retiring_claims.is_empty() and _actual_live_visual_ids().is_empty() and _coordinator.get("_prefetched_resources").is_empty()}

func has_pending_actual_original_map_claims() -> bool:
	if not _actual_retiring_claims.is_empty() or not _coordinator.get("_retired_threaded_requests").is_empty(): return true
	for entry: Dictionary in _coordinator.resource_manifest.values():
		if entry.get("status") == "requested": return true
	return false

func service_actual_original_map_claim_retirement() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _coordinator == null: return {"success":false,"status":"INVALID"}
	_actual_retirement_started = true
	# Move the exact accepted responsibilities once. Calling the old transfer
	# method here would call a MainFacade method which cannot synchronously S-await.
	for path: String in _coordinator.resource_manifest.keys():
		var entry: Dictionary = _coordinator.resource_manifest[path]
		if entry.get("status") != "requested": continue
		if not entry.get("claim_count") is int or entry.claim_count <= 0: return {"success":false,"status":"INVALID","error":"actual_Map_requested_claim_count_retained"}
		_actual_retiring_claims[path] = {"remaining":entry.claim_count,"origin":entry.duplicate(true)}
		_coordinator.resource_manifest.erase(path)
	var retired: Dictionary = _coordinator.get("_retired_threaded_requests")
	for path: String in retired.keys():
		if not retired[path].get("claim_count") is int or retired[path].claim_count <= 0: return {"success":false,"status":"INVALID","error":"actual_Map_retired_claim_count_retained"}
		var count: int = retired[path].claim_count
		if not _actual_retiring_claims.has(path): _actual_retiring_claims[path] = {"remaining":0,"origin":retired[path].duplicate(true)}
		_actual_retiring_claims[path].remaining += count
		retired.erase(path)
	var maximum := int(ProjectSettings.get_setting("world/loading/max_items_per_frame",Coordinator.DEFAULT_MAX_ITEMS_PER_FRAME))
	var budget_usec := int(float(ProjectSettings.get_setting("world/loading/slice_budget_ms",Coordinator.DEFAULT_SLICE_BUDGET_MS))*1000.0)
	var started := Time.get_ticks_usec()
	var completed := 0
	var visited := 0
	for path: String in _actual_retiring_claims.keys():
		if visited > 0 and (visited >= maxi(1,maximum) or Time.get_ticks_usec()-started >= budget_usec): break
		var row: Dictionary = _actual_retiring_claims[path]
		while row.remaining > 0:
			if visited > 0 and (visited >= maxi(1,maximum) or Time.get_ticks_usec()-started >= budget_usec): break
			visited += 1
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: break
			if status not in [ResourceLoader.THREAD_LOAD_LOADED,ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]: return {"success":false,"status":"INVALID","error":"actual_Map_loader_status"}
			if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_actual_claim_history.append({"path":path,"status":status,"get_performed":false,"released_count":row.remaining,"actual_Main_process_frame":Engine.get_process_frames()})
				row.remaining = 0
			else:
				var resource: Resource = ResourceLoader.load_threaded_get(path)
				row.remaining -= 1; completed += 1
				_actual_claim_history.append({"path":path,"status":status,"get_performed":true,"released_count":1,"actual_resource_id":resource.get_instance_id() if resource != null else 0,"actual_Main_process_frame":Engine.get_process_frames()})
				resource = null
		if row.remaining == 0: _actual_retiring_claims.erase(path)
	return {"success":true,"status":"READY" if _actual_retiring_claims.is_empty() else "PENDING","actual_Main_get_count":completed,"actual_remaining_paths":_actual_retiring_claims.size(),"actual_transfer_performed":false}

func _actual_live_visual_ids() -> Array:
	var ids: Array = []
	for reference: WeakRef in _actual_terminal_visuals:
		var node: Node = reference.get_ref()
		if is_instance_valid(node): ids.append(node.get_instance_id())
	return ids

func service_actual_original_map_terminal() -> Dictionary:
	var retired: Dictionary = service_actual_original_map_claim_retirement()
	if retired.get("status") != "READY": return retired
	if not _actual_terminal_started:
		for node: Node in _background.get("_environment_nodes"):
			if is_instance_valid(node): _actual_terminal_visuals.append(weakref(node))
		_actual_terminal_started = true
		_background.clear_environment() # Original release, including actor-sort siblings.
		_descriptors.clear(); _coordinator.get("_prefetched_resources").clear()
		_coordinator.resource_manifest.clear()
	return {"success":true,"status":"READY" if _actual_live_visual_ids().is_empty() else "PENDING","actual_live_visual_ids":_actual_live_visual_ids()}

func can_commit_actual_original_map_route(before: Dictionary, after: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or has_pending_actual_original_map_claims(): return false
	if _descriptor == after: return true
	var expected: Dictionary = before.duplicate(true); expected.world_context = after.get("world_context",{})
	return _descriptor == before and after == expected and after.world_context.get("world_runtime_id") == before.world_context.get("world_runtime_id")
func commit_actual_original_map_route(before: Dictionary, after: Dictionary) -> bool:
	if not can_commit_actual_original_map_route(before,after): return false
	_descriptor = after.duplicate(true)
	return true

func apply_original_map_visual_effect(event: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var args: Variant = event.get("arguments")
	if not args is Array: return {"success":false,"error":"actual_map_visual_arguments"}
	match str(event.get("operation","")):
		"source_map_visual_zone":
			if args.size() != 3 or not args[0] is String or not args[1] is Dictionary or args[2] != _coordinator.generation: return {"success":false,"error":"actual_map_visual_generation"}
			_background.zone_name = args[0]; _background.zone_data = args[1].duplicate(true)
		"source_map_visual_focus":
			if args.size() != 2 or not args[0] is Vector2 or not args[0].is_finite(): return {"success":false,"error":"actual_map_visual_generation"}
			# The actual initial background accepts its original focus before the
			# first map has been prepared. This changes no terrain or map identity.
			var initial_focus: bool = args[1] == -1 and _scope.is_empty() and _last_request.is_empty() and _descriptor.world_context.runtime_map_id == -1 and _descriptor.world_context.world_epoch == 0
			if not initial_focus and args[1] != _coordinator.generation: return {"success":false,"error":"actual_map_visual_generation"}
			_background.set("_focus_position",args[0]); _background.queue_redraw()
		_: return {"success":false,"error":"actual_map_visual_selector"}
	return {"success":true,"actual_map_generation":_coordinator.generation}
