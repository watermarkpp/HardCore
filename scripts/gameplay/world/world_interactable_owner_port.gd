extends RefCounted

var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _proof: Dictionary
var _faulted := false
var _bound: Dictionary = {}
var _header_command_accepted := false
func owner_thread_id() -> int: return _owner
func configure_owner(world: RefCounted,proof: Dictionary) -> bool:
	if _world_ref!=null or _owner==OS.get_main_thread_id() or world.owner_thread_id()!=_owner: return false
	if proof.get("contract_id")!="world.interactable.loading.v1" or proof.get("world_context")!=world.current_world_identity() or not proof.get("npc_profiles") is Dictionary or not proof.get("session_diagnostics") is Dictionary or not proof.get("session_diagnostics_header_printed") is bool: return false
	if not proof.get("closure_id") is int or proof.closure_id<=0 or not proof.get("main_executor_id") is int or proof.main_executor_id==0: return false
	var session: RefCounted=world.original_source_session()
	if session==null or not session.has_method("verify_original_interactable_loading_publication"): return false
	var admitted: Dictionary=session.verify_original_interactable_loading_publication(proof)
	if admitted.get("status")!="READY" or admitted.get("publication")!=proof: return false
	if not world.cast_presentation.has_method("emit_original_interactable") or not world.cast_presentation.has_method("matches_original_interactable_loading"): return false
	if not world.cast_presentation.matches_original_interactable_loading(proof): return false
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	if graph==null: return false
	var copy: Dictionary=graph.capture(proof,true,false)
	if copy.get("success")!=true: return false
	_proof=copy.value; _header_command_accepted=proof.session_diagnostics_header_printed; _world_ref=weakref(world); return true
func faulted() -> bool: return _faulted
func _world() -> RefCounted: return _world_ref.get_ref() if _world_ref!=null else null
func fail(code: String) -> void:
	_faulted=true
	if _world()!=null: _world().fault(code,{})
func _handle(model: RefCounted) -> Object:
	assert(OS.get_thread_caller_id()==_owner)
	return _world().actor_handle_for_model(model)
func publish_pose(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	if handle==null: return false
	var ground: Vector2=_world().skills._canonical_screen_px_to_ground_gu(model.global_position)
	return ground.is_finite() and handle.set_pose(model.global_position,ground,0.0)
func add_to_group(model: RefCounted,group: StringName) -> bool:
	return group in [&"interactable",&"zone_content"] and _world().enter_actor_group(_handle(model),group)
func queue_retirement(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	return handle!=null and _world().queue_actor_retirement(handle.get_instance_id())
func _emit(operation: StringName,payload: Dictionary) -> bool:
	if _faulted or _world()==null: return false
	return _world().cast_presentation.emit_original_interactable(operation,payload)
func create_npc_visual(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	if handle==null or not _proof.npc_profiles.has(model.appearance): fail("actual_npc_Loading_profile_missing"); return false
	var payload: Dictionary={"identity":handle.identity(),"state":{"position_screen_px":model.global_position,"npc_name":model.npc_name,"npc_kind":model.npc_kind,"appearance":model.appearance,"facing":model.facing,"default_facing":model.default_facing,"service_identity_id":model.service_identity_id}}
	if not _emit(&"source_interactable::spawn_npc",payload): return false
	_bound[handle.get_instance_id()]={"identity":handle.identity(),"model":weakref(model),"ready":false}
	return true
func create_portal_visual(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	if handle==null: return false
	var payload: Dictionary={"identity":handle.identity(),"state":{"position_screen_px":model.global_position,"target_zone":model.target_zone,"target_map_id":model.target_map_id,"display_name":model.display_name,"portal_role":model.portal_role,"portal_data":model.portal_data}}
	if not _emit(&"source_interactable::spawn_portal",payload): return false
	_bound[handle.get_instance_id()]={"identity":handle.identity(),"model":weakref(model),"ready":false}
	return true
func refresh_npc_facing(model: RefCounted) -> void:
	var handle: Object=_handle(model)
	# Original first face_toward occurs before visual/name_label construction.
	if handle==null or not _bound.has(handle.get_instance_id()): return
	if not _emit(&"source_interactable::face_npc",{"identity":handle.identity(),"facing":model.facing,"default_facing":model.default_facing}): fail("actual_npc_facing_journal_failed")
func npc_uses_final_art(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	return handle!=null and _bound.has(handle.get_instance_id()) and _bound[handle.get_instance_id()].ready and bool(_proof.npc_profiles[model.appearance].uses_final_art)
func consume_actual_main_receipt(receipt: Dictionary) -> bool:
	# Called only by Caster after native exact accepted-ticket verification.
	var command: Dictionary=receipt.source_command
	var op: StringName=command.operation
	if op==&"source_interactable::session_diagnostics": return true
	var identity: Dictionary=command.payload.identity
	var id: int=identity.runtime_id
	if not _bound.has(id) or _bound[id].identity!=identity: return false
	if op in [&"source_interactable::spawn_npc",&"source_interactable::spawn_portal"]:
		if not receipt.get("actual_node_id") is int or receipt.actual_node_id<=0 or receipt.get("actual_ready")!=true: return false
		var model: RefCounted=_bound[id].model.get_ref()
		if model!=null and op==&"source_interactable::spawn_npc" and receipt.get("uses_final_art")!=_proof.npc_profiles[model.appearance].uses_final_art: return false
		_bound[id].ready=true
		if model!=null: model._visual_bound=true
	elif op==&"source_interactable::retire": _bound.erase(id)
	return true
func retire_visual_at_original_free(model: RefCounted) -> bool:
	var handle: Object=_handle(model)
	if handle==null: return false
	if not _bound.has(handle.get_instance_id()): return true # Original unentered constructor has no visual child.
	return _emit(&"source_interactable::retire",{"identity":handle.identity()})
func original_loading_visuals_ready() -> bool:
	for item: Dictionary in _bound.values():
		var model: Object=item.model.get_ref()
		if model!=null and model.is_inside_tree() and not item.ready: return false
	return true
func flush_facts() -> bool: return not _faulted
func print_session_diagnostics() -> bool:
	return _emit(&"source_interactable::session_diagnostics",{"facts":_proof.session_diagnostics})
func header_already_printed() -> bool: return _header_command_accepted
func mark_header_command_accepted(value: bool) -> void:
	assert(OS.get_thread_caller_id()==_owner and value)
	_header_command_accepted=value
