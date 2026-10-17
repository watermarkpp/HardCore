extends RefCounted

const Registry := preload("res://scripts/caster_skill_visual_registry.gd")
const Factory := preload("res://scripts/caster_skill_visual_factory.gd")
const Batch := preload("res://scripts/caster_skill_animation_batch.gd")
const Projectile := preload("res://scripts/gameplay/world/world_caster_projectile_display.gd")
const Ground := preload("res://scripts/gameplay/world/world_caster_ground_display.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Structure := preload("res://scripts/gameplay/world/world_caster_visual_structure.gd")
const AnimationScript := preload("res://scripts/caster_skill_animation_player.gd")
const CodeLease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const OPERATIONS := ["create_visual_model", "bind_projectile", "bind_ground", "redraw_cast", "projectile_audio_phase",
	"prepare_projectile_visual", "set_cast_y_sort", "create_fire_wall_cell", "fire_wall_animation_diagnostics",
	"activate_fire_wall_cells", "synchronize_fire_wall_cells", "cast_has_visual", "prepare_ground_visual",
	"sync_cast", "retire_cast", "discard_visual", "refresh_cell_lifetime", "source_caster_warm::collect_admit", "source_caster_warm::retire", "source_caster_warm::loading_state", "source_caster_warm::loading_claim_retire", "monster_audio", "player_physical_contact_audio", "source_interactable::spawn_npc", "source_interactable::spawn_portal", "source_interactable::face_npc", "source_interactable::retire", "source_interactable::session_diagnostics"]
var _root: Node2D
var _world: Dictionary
var _metadata: Dictionary
var _graph: RefCounted
var _resolve_actor: Callable
var _host: Object
var _claimed_event: Dictionary
var _claimed_ticket: Dictionary
var _live_reply_nodes: Dictionary
var _created_nodes: Dictionary
var _main_cpu_sampler: Callable
var _command_capacity := 0
var _proof: Dictionary
var _paths: Array[String] = []
var _textures: Dictionary = {}
var _loading_sequence_lease_held := false # Only the separate legacy probe acquires this lease.
var _code_result: Dictionary = {}
var _code_content: WeakRef
var _code_objects: Dictionary = {}
var _code_object_sources: Dictionary = {}
var _casts: Dictionary = {}
var _visuals: Dictionary = {}
var _cells: Dictionary = {}
var _batches: Dictionary = {}
var _cell_controller: Dictionary = {}
var _last_command: Dictionary
var _last_reply: Dictionary
var _awaiting_reply := false
var _execution_failure: Dictionary
var _warm_main: RefCounted
var _actual_event_claimed_usec := 0
var _closed := false

func can_commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _root != null and not _closed and _world == transaction.get("before_world") and _claimed_event.is_empty() and _claimed_ticket.is_empty() and not _awaiting_reply and _host.verify_committed_original_map_arrival(transaction) and (_original_audio_service == null or _original_audio_service.can_commit_actual_original_map_arrival(transaction,_original_audio_projection))
func commit_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_commit_actual_original_map_arrival(transaction): return false
	if _warm_main != null and not _warm_main.commit_actual_original_map_arrival(transaction): return false
	if _original_audio_service != null and not _original_audio_service.commit_actual_original_map_arrival(transaction,_original_audio_projection): return false
	_world = transaction.after_world.duplicate(true)
	# Keep the initial loading proof and all already-generated replies exactly
	# as issued. Only a new command uses the current routing identity.
	return true

func configure_main(root: Node2D, world: Dictionary, metadata: Dictionary, resolver: Callable,
	host: Object, main_cpu_sampler: Callable, actual_command_capacity: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root != null or root == null or not root.is_inside_tree(): return false
	if not Gate.is_active(metadata.get("catalog_lease", {})) or host == null or not resolver.is_valid() or not main_cpu_sampler.is_valid() or actual_command_capacity <= 0: return false
	if metadata.get("contract_id") != "world.skill.visual_metadata.v1" or Graph.fingerprint(metadata.get("metadata")) != metadata.get("metadata_sha256"): return false
	if metadata.metadata.get("structure_contract_id") != Structure.CONTRACT or not metadata.metadata.get("profiles") is Dictionary or not metadata.metadata.get("visual_profiles") is Dictionary: return false
	_graph = ClassDB.instantiate("HardCoreContentValueGraph")
	if _graph == null: return false
	var captured: Dictionary = _graph.capture(metadata,true,false)
	if captured.get("success") != true: return false
	_root = root; _world = world.duplicate(true); _metadata = captured.value
	_resolve_actor = resolver; _host = host; _main_cpu_sampler = main_cpu_sampler; _command_capacity = actual_command_capacity
	return true

func _main() -> void: assert(OS.get_thread_caller_id() == OS.get_main_thread_id() and _root != null)
func _failure(code: String) -> Dictionary: return {"success":false, "status":"INVALID", "error":code}

func prepare_actual_original_owner_closure(closure_id: int, checkpoint: Dictionary,
	deferred: Object, facade: Node, content: Node, legacy_resources: Node, actual_code_inputs: Dictionary) -> Dictionary:
	_main()
	if not _proof.is_empty() or closure_id <= 0 or _closed or not Gate.is_active(_metadata.catalog_lease): return _failure("actual_caster_owner_closure_state_required")
	if deferred == null or not deferred.is_class("HardCoreMainSourceDeferred"): return _failure("actual_native_Main_checkpoint_provider_required")
	var terminal: Dictionary = deferred.observe_original_main_source_receivers(checkpoint,facade,content,legacy_resources)
	if terminal.get("success") != true:
		var refused: Dictionary = _failure("actual_original_Main_receiver_checkpoint_required")
		refused["details"] = terminal
		return refused
	if actual_code_inputs.size() != 2 or not actual_code_inputs.get("result") is Dictionary or not actual_code_inputs.get("consumer") is Node: return _failure("actual_original_code_result_and_consumer_required")
	var result: Dictionary = actual_code_inputs.result
	var consumer: Node = actual_code_inputs.consumer
	var lease: Variant = result.get("lease")
	var code: Variant = result.get("resource")
	if not is_instance_valid(content) or content != _root.get_tree().root.get_node_or_null("ContentLayers") or not content.has_method("is_internal_code_retention_current") or not is_instance_valid(consumer): return _failure("actual_original_code_retention_owner_required")
	if result.get("success") != true or not lease is RefCounted or lease.get_script() != CodeLease or lease.is_domain() or not code is Script or not is_same(code,AnimationScript) or not is_same(lease.get("_retained_code_resource"),code): return _failure("actual_CasterAnimation_Script_and_physical_lease_required")
	var plan: RefCounted = lease.get("_code_plan")
	if plan == null or not lease.valid_for_code(plan) or not content.is_internal_code_retention_current(result,consumer): return _failure("actual_verified_code_plan_and_current_retention_required")
	var objects: Dictionary = {}
	# Actual already-loaded Script objects are retained, not filename promises.
	for source: Script in [get_script(),AnimationScript,Registry,Factory,Projectile,Ground,Batch,Structure]:
		if source == null or not source.can_instantiate() or not is_same(ResourceLoader.get_cached_ref(source.resource_path),source): return _failure("actual_live_Caster_executor_Script_required")
		objects[source.resource_path] = source
	for path: String in plan.paths():
		var shader: Resource = lease.resource_at(path)
		if not shader is Shader or not is_same(ResourceLoader.get_cached_ref(path),shader): return _failure("actual_code_lease_Shader_resource_required")
		objects[path] = shader
	# Verify the shaders actually referenced by the retained original Script.
	# A caller's list of paths or numeric IDs cannot substitute for these objects.
	for value: Variant in (AnimationScript as Script).get_script_constant_map().values():
		if value is Shader and not is_same(lease.resource_at(value.resource_path),value): return _failure("actual_CasterAnimation_Shader_input_not_held_by_lease")
	var sources: Dictionary = {}
	var facts: Array[Dictionary] = []
	for path: String in objects:
		var resource: Resource = objects[path]
		var source: String = (resource as Script).get_source_code() if resource is Script else (resource as Shader).code
		sources[path] = source
		facts.append({"resource_path":path,"resource_runtime_id":resource.get_instance_id(),"resource_class":resource.get_class(),"source_sha256":source.sha256_text()})
	var code_receipt := {"contract_id":"world.caster.actual_code_inputs.v1","actual_code_lease_verified":true,
		"code_lease_id":lease.get_instance_id(),"code_plan_signature":plan.signature(),"retained_script_runtime_id":code.get_instance_id(),
		"original_consumer_id":consumer.get_instance_id(),"content_runtime_id":content.get_instance_id(),"actual_resource_facts":facts}
	var proof := {"contract_id":"world.caster.presentation.owner.v2","world_context":_world,
		"catalog_lease":_metadata.catalog_lease,"metadata_sha256":_metadata.metadata_sha256,
		"timing_profiles_sha256":_metadata.timing_profiles_sha256,"closure_id":closure_id,
		"main_executor_id":get_instance_id(),"command_capacity":_command_capacity,
		"loading_checkpoint_receipt":terminal,"code_input_receipt":code_receipt}
	var copied: Dictionary = _graph.capture(proof,true,false)
	if copied.get("success") != true: return _failure("actual_Caster_owner_publication_not_plain")
	# No texture request, all-direction probe or sequence acquisition occurs.
	# On failure above, the original external code owner/lease are unchanged.
	_code_result = result.duplicate(false); _code_content = weakref(content)
	_code_objects = objects; _code_object_sources = sources
	_proof = copied.value
	return {"success":true,"publication":_proof}

func _actual_code_consumer() -> Node:
	if _code_result.is_empty(): return null
	# Follow the SAME physical lease's current formal retention owner. A real
	# CharacterSelect -> Root transfer does not rewrite the immutable boot proof.
	var retained: Variant = _code_result.lease.get("_retained_code_consumer")
	return retained.get_ref() if retained is WeakRef else null

func _actual_code_inputs_current() -> bool:
	if _code_result.is_empty() or _code_content == null or not is_instance_valid(_code_content.get_ref()): return false
	var consumer: Node = _actual_code_consumer()
	if not is_instance_valid(consumer) or not _code_content.get_ref().is_internal_code_retention_current(_code_result,consumer): return false
	for path: String in _code_objects:
		var resource: Resource = _code_objects[path]
		if not is_same(ResourceLoader.get_cached_ref(path),resource): return false
		var source: String = (resource as Script).get_source_code() if resource is Script else (resource as Shader).code
		if source != _code_object_sources[path]: return false
	return true

func prepare_loading_closure(closure_id: int, skills: Array[String], checkpoint: Dictionary,
	deferred: Object, facade: Node, content: Node, legacy_resources: Node) -> Dictionary:
	_main()
	if not _proof.is_empty() or closure_id <= 0 or skills.is_empty() or not Registry.is_loading_window_active(): return _failure("actual_loading_closure_state_required")
	if deferred == null or not deferred.is_class("HardCoreMainSourceDeferred"): return _failure("MISSING:actual_native_Main_checkpoint_provider")
	var terminal: Dictionary = deferred.observe_original_main_source_receivers(checkpoint, facade, content, legacy_resources)
	if terminal.get("success") != true: return _failure("MISSING:actual_Root_Loading_IO_UI_source_checkpoint")
	var started := Time.get_ticks_usec()
	var paths: Array[String] = []
	var selected: Array[String] = skills.duplicate()
	if not selected.has(""): selected.append("") # Actual unbound projectile fallback, not a fake skill.
	for skill: String in selected:
		if not skill.is_empty() and not _metadata.metadata.profiles.has(skill): return _failure("unknown_original_skill_identity")
		for path: String in Registry.animation_frame_paths(skill):
			if not paths.has(path): paths.append(path)
	var bytes := 0
	var textures: Dictionary = {}
	var texture_facts: Array[Dictionary] = []
	for path: String in paths:
		if not Registry.frame_texture_is_resident(path): return _failure("MISSING:actual_preloaded_caster_frame:" + path)
		var texture: Texture2D = Registry.request_animation_frame_texture(path)
		if texture == null: return _failure("actual_resident_texture_unavailable:" + path)
		var size_bytes: int = texture.get_width() * texture.get_height() * 4
		bytes += size_bytes
		textures[path] = texture
		texture_facts.append({"path":path, "runtime_id":texture.get_instance_id(), "width":texture.get_width(), "height":texture.get_height(), "bytes":size_bytes})
	if bytes > Registry.WORKSET_PIN_BUDGET_BYTES: return _failure("actual_original_caster_pin_capacity_exceeded")
	if not paths.is_empty():
		if not Registry.acquire_sequence_lease(paths): return _failure("actual_sequence_lease_not_acquired")
		_loading_sequence_lease_held = true
	_paths = paths; _textures = textures
	var bindings: Dictionary = {}
	for skill: String in selected:
		var profile := Registry.profile(skill)
		var merged := profile.duplicate(true)
		for key: String in Registry.visual_profile(skill):
			if not merged.has(key) and key != "animation": merged[key] = Registry.visual_profile(skill)[key]
		var cases: Dictionary = {}
		for direction: int in range(16): cases[direction] = _probe_projectile(skill, direction)
		var ground := Ground.new()
		ground.skill_id = skill
		ground.hide()
		_root.add_child(ground) # True original installer and actual Texture binding.
		var ground_case := {"has_visual":ground._sprite != null, "rejection_reason":ground.visual_rejection_reason}
		ground.free() # Real _exit_tree releases the temporary player's lease.
		bindings[skill] = {"factory_profile":merged, "role":str(profile.get("role", "")),
			"projectile_cases":cases, "ground_case":ground_case}
	var proof := {"contract_id":"world.caster.presentation.loading.v1", "world_context":_world,
		"catalog_lease":_metadata.catalog_lease, "metadata_sha256":_metadata.metadata_sha256,
		"timing_profiles_sha256":_metadata.timing_profiles_sha256, "closure_id":closure_id,
		"main_executor_id":get_instance_id(), "command_capacity":_command_capacity,
		"loading_checkpoint_receipt":terminal, "bindings":bindings, "texture_facts":texture_facts,
		"resident_bytes":bytes, "source_pin_capacity_bytes":Registry.WORKSET_PIN_BUDGET_BYTES,
		"actual_started_usec":started, "actual_finished_usec":Time.get_ticks_usec()}
	var copied: Dictionary = _graph.capture(proof, true, false)
	if copied.get("success") != true:
		if _loading_sequence_lease_held: Registry.release_sequence_lease(_paths); _loading_sequence_lease_held = false
		_paths.clear(); _textures.clear()
		return _failure("actual_caster_loading_publication_not_plain")
	_proof = copied.value
	return {"success":true, "publication":_proof}

func _probe_projectile(skill: String, direction_index: int) -> Dictionary:
	var directions := [Vector2(0,-1),Vector2(1,-2),Vector2(1,-1),Vector2(2,-1),Vector2(1,0),Vector2(2,1),Vector2(1,1),Vector2(1,2),
		Vector2(0,1),Vector2(-1,2),Vector2(-1,1),Vector2(-2,1),Vector2(-1,0),Vector2(-2,-1),Vector2(-1,-1),Vector2(-1,-2)]
	var probe := Projectile.new()
	probe.skill_id = skill; probe.direction_screen_px = directions[direction_index]
	probe.hide(); _root.add_child(probe)
	var result := {"role_valid":probe._projectile_role_valid, "rejection_reason":probe.visual_rejection_reason, "has_visual":probe._sprite != null}
	probe.free()
	return result

func execute(command: Dictionary) -> Dictionary:
	_main()
	if _claimed_event.is_empty() or _closed or _proof.is_empty() or command.size() != 8 or command.get("contract_id") != "world.caster.presentation.command.v1" or command.get("world_context") != _world or command.get("closure_id") != _proof.closure_id or command.get("main_executor_id") != get_instance_id() or not command.get("operation") in OPERATIONS or not command.get("payload") is Dictionary or not command.get("source_clock") is Dictionary: return _failure("actual_caster_command_identity_schema")
	var copied: Dictionary = _graph.capture(command, true, false)
	if copied.get("success") != true: return _failure("caster_command_not_pure_values")
	var id: int = command.get("command_id", 0)
	if not _last_command.is_empty() and id == _last_command.command_id:
		if _last_command != command: return _failure("changed_caster_command_preimage")
		if _awaiting_reply:
			var resubmitted := _submit_current_reply()
			if resubmitted.get("status") != "READY": return resubmitted
		_awaiting_reply = false
		return {"status":"APPLIED", "success":true, "receipt":_last_reply}
	if _awaiting_reply: return {"status":"PENDING"}
	if id != (int(_last_command.get("command_id", 0)) + 1): return _failure("caster_source_command_order")
	var cleanup_warm: bool = str(command.operation) == "source_interactable::retire" or str(command.operation) in ["source_caster_warm::retire","source_caster_warm::loading_claim_retire"] or (str(command.operation) == "source_caster_warm::loading_state" and command.payload.get("arguments") == [false])
	if not cleanup_warm and not _pins_intact(): return _failure("actual_caster_pin_lease_broken")
	var started := Time.get_ticks_usec()
	var cpu_start: int = _main_cpu_sampler.call()
	if cpu_start < 0: return _failure("MISSING:actual_Main_thread_CPU_sampler")
	var applied: Dictionary
	if String(command.operation).begins_with("source_interactable::"):
		if _interactable == null: return _failure("MISSING_actual_interactable_Main_leaf")
		applied = _interactable.execute_leaf(StringName(command.operation), command.payload)
		if applied.get("success") == true and int(applied.get("actual_node_id",0)) != 0:
			var node: Node2D = _interactable.actual_node(applied.actual_node_id)
			if node == null: return _failure("actual_interactable_Node_missing")
			_remember_node(node)
	elif str(command.operation).begins_with("source_caster_warm::"):
		if _warm_main == null: return _failure("MISSING:actual_original_warm_Main_leaf")
		applied = _warm_main.execute_original_warm(str(command.operation),command.payload,_claimed_ticket)
	else: applied = call(StringName(command.operation), command.payload)
	var cpu_finish: int = _main_cpu_sampler.call()
	var finished := Time.get_ticks_usec()
	if cpu_finish < cpu_start: return _failure("actual_Main_CPU_counter_invalid")
	if applied.get("success") != true: return applied
	var receipt := {"contract_id":"world.caster.presentation.receipt.v1", "world_context":_world,
		"closure_id":_proof.closure_id, "main_executor_id":get_instance_id(), "command_id":id,
		"source_command":copied.value, "actual_applied_usec":finished, "actual_started_usec":started,
		"actual_finished_usec":finished, "actual_Main_elapsed_usec":finished-started, "actual_Main_CPU_usec":cpu_finish-cpu_start,
		"queue_wait_usec":started-int(command.source_clock.presentation_submitted_usec),
		"actual_event_claimed_usec":_actual_event_claimed_usec,"queue_residence_usec":_actual_event_claimed_usec-int(command.source_clock.presentation_submitted_usec),
		"dispatch_wait_usec":started-_actual_event_claimed_usec, "actual_node_id":int(applied.get("actual_node_id",0))}
	for key: String in applied:
		if key != "success": receipt[key] = applied[key]
	_last_command = copied.value; _last_reply = receipt; _awaiting_reply = true
	var submitted := _submit_current_reply()
	if submitted.get("status") != "READY": return submitted
	_awaiting_reply = false
	return {"status":"APPLIED", "success":true, "receipt":receipt}

func _pins_intact() -> bool:
	if _proof.is_empty(): return false
	if not Gate.is_active(_proof.catalog_lease): return false
	if _proof.get("contract_id") == "world.caster.presentation.owner.v2": return _actual_code_inputs_current()
	for path: String in _paths:
		if not Registry.frame_texture_is_resident(path) or Registry.request_animation_frame_texture(path) != _textures[path]: return false
	return true
func _actual_cast(payload: Dictionary) -> Node2D:
	var identity: Dictionary = payload.get("identity", {})
	var id: int = identity.get("runtime_id", 0)
	if id <= 0 or identity.get("world") != _world: return null
	if _casts.has(id) and _casts[id].identity == identity: return _casts[id].node
	return null
func _install_cast(payload: Dictionary, type: String) -> Dictionary:
	var identity: Dictionary = payload.get("identity", {})
	var id: int = identity.get("runtime_id", 0)
	if id <= 0 or int(identity.get("life_generation", 0)) <= 0 or identity.get("world") != _world or _casts.has(id): return _failure("caster_actual_cast_birth_identity")
	var node: Node2D = Projectile.new() if type == "projectile" else Ground.new()
	_assign_state(node, payload.state)
	_casts[id] = {"identity":identity, "node":node}
	node.tree_exited.connect(_on_cast_tree_exited.bind(id))
	_root.add_child(node)
	return {"success":true, "identity":identity, "actual_node_id":_remember_node(node), "has_visual":node.get("_sprite") != null, "rejection_reason":node.get("visual_rejection_reason")}
func _assign_state(node: Node2D, state: Dictionary) -> void:
	node.global_position = state.position_screen_px
	for key: String in state:
		if key in ["skill_id", "release_id", "direction_screen_px", "visual_muzzle_offset_px", "projectile_color", "visual_radius_px", "effect_color", "duration"]: node.set(key, state[key])
func bind_projectile(payload: Dictionary) -> Dictionary:
	_main()
	var applied := _install_cast(payload, "projectile")
	if applied.get("success") != true: return applied
	var node: Node2D = _actual_cast(payload)
	var binding: Dictionary = Structure.binding(_metadata.metadata,node.get("skill_id"))
	if binding.is_empty(): return _failure("actual_published_projectile_metadata_required")
	var expected: Dictionary = Structure.projectile_structure(binding.original_profile,node.get("direction_screen_px"))
	if node.get("_projectile_role_valid") != expected.role_valid or node.get("visual_rejection_reason") != expected.rejection_reason or (node.get("_sprite") != null) != expected.animation_accepted: return _failure("actual_original_projectile_structure_differs_from_Source")
	return applied
func prepare_projectile_visual(payload: Dictionary) -> Dictionary:
	_main()
	return bind_projectile(payload)
func bind_ground(payload: Dictionary) -> Dictionary:
	_main()
	return _install_cast(payload, "ground")
func prepare_ground_visual(payload: Dictionary) -> Dictionary:
	_main()
	return bind_ground(payload)
func cast_has_visual(payload: Dictionary) -> Dictionary:
	_main()
	var node := _actual_cast(payload)
	return {"success":true, "has_visual":node.get("_sprite") != null} if node != null else _failure("caster_ground_visual_identity_missing")
func redraw_cast(payload: Dictionary) -> Dictionary:
	_main()
	if payload.size() != (2 if payload.has("only_without_sprite") else 1) or not payload.get("identity") is Dictionary: return _failure("actual_redraw_payload_schema_required")
	var node := _actual_cast(payload)
	if node == null: return _failure("caster_redraw_identity_missing")
	if payload.has("only_without_sprite"):
		if not payload.only_without_sprite is bool or payload.only_without_sprite != true or node.get_script() != Ground: return _failure("actual_ground_conditional_redraw_required")
		if node.get("_sprite") != null: return {"success":true,"actual_redraw_without_sprite":false}
	node.queue_redraw()
	return {"success":true,"actual_redraw_without_sprite":true} if payload.has("only_without_sprite") else {"success":true}
func projectile_audio_phase(payload: Dictionary) -> Dictionary:
	_main()
	if _actual_cast(payload) == null or payload.get("phase") not in ["launch","impact"]: return _failure("caster_audio_identity_or_phase")
	# Same original event/context; the S projectile owns original once flags.
	var service: Node = _root.get_tree().get_first_node_in_group("audio_runtime_service")
	if service != null and service.has_method("play_event"):
		service.play_event("skill.%s.%s" % [payload.state.skill_id,payload.phase], {"source":"skill_projectile",
			"release_id":payload.state.release_id, "runtime_map_id":payload.state.runtime_map_id, "terminal_reason":payload.terminal_reason})
	return {"success":true}
func set_cast_y_sort(payload: Dictionary) -> Dictionary:
	_main()
	var identity: Dictionary = payload.identity
	var id: int = identity.runtime_id
	if identity.world != _world or id <= 0 or _casts.has(id): return _failure("caster_wall_birth_identity")
	var node := Node2D.new(); node.y_sort_enabled = bool(payload.enabled)
	_casts[id] = {"identity":identity, "node":node}; _batches[id] = Batch.new()
	node.tree_exited.connect(_on_cast_tree_exited.bind(id)); _root.add_child(node)
	return {"success":true, "actual_node_id":_remember_node(node)}
func create_fire_wall_cell(payload: Dictionary) -> Dictionary:
	_main()
	var controller := _actual_cast(payload)
	var id: int = payload.visual_id
	if controller == null or id <= 0 or _cells.has(id): return _failure("caster_fire_wall_cell_identity")
	var state: Dictionary = payload.state
	var cell := Ground.new()
	cell.global_position = state.position_screen_px; cell.skill_id = state.skill_id
	cell.release_id = state.release_id; cell.duration = state.duration
	cell.visual_radius_px = state.visual_radius_px; cell.effect_color = state.color
	_cells[id] = cell; _cell_controller[id] = int(payload.identity.runtime_id)
	cell.tree_exited.connect(_on_visual_tree_exited.bind(id, true)); controller.add_child(cell)
	return {"success":true, "actual_node_id":_remember_node(cell)}
func activate_fire_wall_cells(payload: Dictionary) -> Dictionary:
	_main()
	var controller := _actual_cast(payload)
	if controller == null or not _batches.has(payload.identity.runtime_id): return _failure("caster_batch_controller_missing")
	var batch: RefCounted = _batches[payload.identity.runtime_id]
	for id: int in payload.cells:
		if not _cells.has(id) or _cell_controller[id] != payload.identity.runtime_id: return _failure("caster_batch_foreign_cell")
		var sprite: Sprite2D = _cells[id]._sprite
		if sprite is CasterSkillAnimationPlayer: batch.add_player(sprite)
	return {"success":true, "identity":payload.identity, "animation_batch":batch.diagnostics()}
func synchronize_fire_wall_cells(payload: Dictionary) -> Dictionary:
	_main()
	if _actual_cast(payload) == null or not _batches.has(payload.identity.runtime_id) or not is_finite(float(payload.clock_ms)) or float(payload.clock_ms) < 0.0: return _failure("caster_source_animation_clock_invalid")
	var batch: RefCounted = _batches[payload.identity.runtime_id]
	batch.synchronize(float(payload.clock_ms)) # The original S clock, no Main advance.
	return {"success":true, "identity":payload.identity, "animation_batch":batch.diagnostics()}
func fire_wall_animation_diagnostics(payload: Dictionary) -> Dictionary:
	_main()
	return {"success":true, "identity":payload.identity, "animation_batch":_batches[payload.identity.runtime_id].diagnostics()} if _actual_cast(payload) != null and _batches.has(payload.identity.runtime_id) else _failure("caster_actual_batch_missing")
func create_visual_model(payload: Dictionary) -> Dictionary:
	_main()
	var id: int = payload.visual_id
	var binding: Dictionary = Structure.binding(_metadata.metadata,payload.skill_id)
	if id <= 0 or _visuals.has(id) or binding.is_empty() or payload.profile != binding.factory_profile: return _failure("caster_actual_visual_factory_profile")
	var target: Node2D
	if not payload.target_identity.is_empty():
		target = _resolve_actor.call(payload.target_identity)
		if target == null: return _failure("MISSING:actual_Main_actor_attachment_readonly_view")
	var visual = Factory.create(payload.profile)
	visual.setup(payload.position_screen_px,payload.skill_id,payload.radius,payload.lifetime,payload.direction,target,payload.phase_id,payload.geometry)
	_visuals[id] = visual
	visual.tree_exited.connect(_on_visual_tree_exited.bind(id, false)); _root.add_child(visual)
	return {"success":true, "actual_node_id":_remember_node(visual)}
func sync_cast(payload: Dictionary) -> Dictionary:
	_main()
	var node := _actual_cast(payload)
	if node == null: return _failure("caster_sync_identity_missing")
	_assign_state(node, payload.state)
	return {"success":true}
func retire_cast(payload: Dictionary) -> Dictionary:
	_main()
	var node := _actual_cast(payload)
	if node == null: return _failure("caster_retire_identity_missing")
	node.queue_free() # Original deferred Node retirement; lease release is real _exit_tree.
	return {"success":true}
func discard_visual(payload: Dictionary) -> Dictionary:
	_main()
	if not _visuals.has(payload.visual_id): return _failure("caster_discard_visual_missing")
	_visuals[payload.visual_id].queue_free()
	return {"success":true}
func refresh_cell_lifetime(payload: Dictionary) -> Dictionary:
	_main()
	if not _cells.has(payload.visual_id): return _failure("caster_refresh_cell_missing")
	_cells[payload.visual_id].duration = maxf(0.1,float(payload.duration))
	return {"success":true}
func _on_cast_tree_exited(id: int) -> void:
	_casts.erase(id); _batches.erase(id)
func _on_visual_tree_exited(id: int, cell: bool) -> void:
	if cell: _cells.erase(id); _cell_controller.erase(id)
	else: _visuals.erase(id)
func _remember_node(node: Node2D) -> int:
	var id: int = node.get_instance_id()
	_created_nodes[id] = weakref(node)
	return id
func execute_original_journal_event(event: Dictionary) -> Dictionary:
	_main()
	if event.get("kind") != "original_world_presentation" or event.get("operation") != &"caster_presentation" or not event.get("arguments") is Array or event.arguments.size() != 1 or not event.get("reply_identity") is Dictionary: return _failure("caster_original_event_schema")
	if _claimed_event.is_empty():
		var claimed: Dictionary = _host.claim_original_caster_event(event.reply_identity,event)
		if claimed.get("status") == "PENDING": return {"status":"PENDING"}
		if claimed.get("status") != "READY": return _failure("caster_actual_prefix_event_claim_failed")
		_claimed_event = event.duplicate(true); _claimed_ticket = event.reply_identity.duplicate(true)
		_actual_event_claimed_usec = Time.get_ticks_usec()
	elif _claimed_event != event: return _failure("caster_changed_pending_event")
	if not _execution_failure.is_empty(): return _execution_failure
	var actual := execute(event.arguments[0])
	if actual.get("status") == "INVALID": _execution_failure = actual.duplicate(true)
	if actual.get("status") == "APPLIED": _claimed_event = {}; _claimed_ticket = {}
	return actual
func _submit_current_reply() -> Dictionary:
	var submitted: Dictionary = _host.submit_original_caster_event_reply(_claimed_ticket,_last_reply)
	if submitted.get("status") == "PENDING": return {"status":"PENDING"}
	if submitted.get("status") != "READY": return _failure("caster_native_reply_rejected")
	if int(_last_reply.actual_node_id) != 0: _live_reply_nodes[str(_claimed_ticket)] = {"ticket":_claimed_ticket.duplicate(true), "node_id":_last_reply.actual_node_id}
	return {"status":"READY"}
func verify_actual_original_caster_reply(ticket: Dictionary, receipt: Dictionary) -> bool:
	_main()
	if ticket != _claimed_ticket or receipt != _last_reply: return false
	var id: int = receipt.get("actual_node_id",0)
	return id == 0 or _created_nodes.has(id)
func flush_original_notifications() -> bool:
	_main()
	for key: String in _live_reply_nodes.keys():
		var actual: Dictionary = _host.ack_original_caster_node_retired(_live_reply_nodes[key].ticket)
		if actual.get("status") == "PENDING": continue
		if actual.get("status") != "READY": return false
		_created_nodes.erase(int(_live_reply_nodes[key].node_id))
		_live_reply_nodes.erase(key)
	return _live_reply_nodes.is_empty()

func release_loading_closure(closure_id: int) -> bool:
	_main()
	if _proof.is_empty() or closure_id != _proof.closure_id or _awaiting_reply or not _casts.is_empty() or not _visuals.is_empty() or not _cells.is_empty() or not flush_original_notifications() or not _claimed_event.is_empty(): return false
	if _warm_main != null and not _warm_main.release_original_warm_owner(): return false
	if _interactable != null and not _interactable.release_original_loading_pins(closure_id): return false
	if _loading_sequence_lease_held: Registry.release_sequence_lease(_paths); _loading_sequence_lease_held = false
	_paths.clear(); _textures.clear(); _closed = true
	# Drop only our actual references. The original code retention owner remains
	# responsible for its own later lease retirement; never retire it twice here.
	_code_result = {}; _code_objects.clear(); _code_object_sources.clear(); _code_content = null
	_host = null; _main_cpu_sampler = Callable()
	return true
func inspect_actual_original_loading_pins(closure: Dictionary) -> Dictionary:
	_main()
	if _proof.is_empty() or closure != _proof or _closed or not _pins_intact(): return _failure("actual_caster_closure_or_lease_mismatch")
	var consumer: Node = _actual_code_consumer()
	return {"success":true, "actual_main_executor_id":get_instance_id(), "actual_closure":_proof,
		"actual_sequence_lease_paths":_paths.duplicate(), "actual_retained_texture_count":_textures.size(),
		"actual_retained_code_resource_count":_code_objects.size(),"actual_current_code_consumer_id":consumer.get_instance_id() if is_instance_valid(consumer) else 0,"actual_code_inputs_current":_actual_code_inputs_current() if not _code_result.is_empty() else false}
func release_original_loading_pin_closure(closure_id: int) -> Dictionary:
	return {"success":release_loading_closure(closure_id)}

func install_original_warm_Main_leaf(leaf: RefCounted) -> bool:
	_main()
	if _warm_main != null or leaf == null: return false
	_warm_main = leaf
	return true
func inspect_actual_original_caster_warm_io() -> Dictionary:
	_main()
	return _warm_main.inspect_actual_original_caster_warm_io() if _warm_main != null else _failure("MISSING:actual_warm_Main_IO_owner")


var _original_audio_service: Node
var _original_audio_projection: Callable
var _original_audio_delivery_capture: Callable
func install_original_audio_main(service: Node, projection: Callable, actual_delivery_capture: Callable) -> bool:
	_main()
	if _original_audio_service!=null or not is_instance_valid(service) or service.get_tree()!=_root.get_tree() or service.get_script()!=preload("res://scripts/audio_runtime_service.gd") or not projection.is_valid() or not actual_delivery_capture.is_valid() or actual_delivery_capture.get_object() != projection.get_object(): return false
	_original_audio_service=service;_original_audio_projection=projection;_original_audio_delivery_capture=actual_delivery_capture
	return service.configure_original_source_owner_projection(projection,_world)
func _original_audio(payload: Dictionary, method: StringName) -> Dictionary:
	if _original_audio_service==null or not payload.get("actor_identity") is Dictionary or payload.get("service_id")!=_original_audio_service.get_instance_id() or not payload.get("arguments") is Array: return _failure("actual_audio_command_schema")
	if payload.arguments.size() != (3 if method == &"play_monster_event" else 2) or not payload.arguments[-1] is Dictionary: return _failure("actual_audio_argument_context")
	var observed: Dictionary = _original_audio_delivery_capture.call(_claimed_event)
	if observed.get("status") == "REJECTED_STALE_OWNER": return {"success":true,"actual_node_id":0,"audio_result":{"status":"rejected","reason":"stale_audio_owner","actual_owner_observation":observed}}
	if observed.get("status") != "OBSERVED": return _failure("actual_audio_delivery_observation_missing:"+str(observed.get("error","")))
	var audible: bool = observed.visible and observed.visible_in_tree and observed.viewport_available
	if audible: audible = observed.visible_rect.has_point(observed.global_transform_with_canvas.origin)
	if not audible: return {"success":true,"actual_node_id":0,"audio_result":{"status":"rejected","reason":"outside_actual_Main_audibility","actual_canvas":observed}}
	var projected: Dictionary=_original_audio_projection.call(payload.actor_identity)
	if projected.get("actor_identity")!=payload.actor_identity or projected.get("world_context")!=_world or projected.get("present")!=true: return _failure("actual_audio_source_projection_identity")
	var args: Array=payload.arguments.duplicate(true)
	var context: Dictionary=args[-1]
	context["original_source_actor_identity"]=payload.actor_identity
	context["original_source_world_context"]=_world
	args[-1]=context
	var result: Dictionary=_original_audio_service.callv(method,args)
	return {"success":true,"actual_node_id":0,"audio_result":result,"actual_canvas":observed}
func monster_audio(payload: Dictionary) -> Dictionary: return _original_audio(payload,&"play_monster_event")
func player_physical_contact_audio(payload: Dictionary) -> Dictionary: return _original_audio(payload,&"play_player_physical_contact")


var _interactable: RefCounted
func bind_original_interactable_leaf(leaf: RefCounted) -> bool:
	_main()
	if _interactable!=null or leaf==null or not leaf.has_method("execute_leaf") or not leaf.has_method("inspect_actual_original_interactable_io"): return false
	_interactable=leaf; return true
