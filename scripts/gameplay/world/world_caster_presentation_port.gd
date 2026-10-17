extends RefCounted

const Display := preload("res://scripts/gameplay/world/world_caster_display_model.gd")
const Structure := preload("res://scripts/gameplay/world/world_caster_visual_structure.gd")
const ValueGraph := preload("res://scripts/gameplay/content/content_value_graph.gd")
var _owner := OS.get_thread_caller_id()
var _world: RefCounted
var _proof: Dictionary
var _metadata: Dictionary
var _graph: RefCounted
var _host: Object
var _serial := 0
var _visual_serial := 0
var _visuals: Dictionary = {}
var _casts: Dictionary = {}
var _main_diagnostics: Dictionary = {}
var _pending_receipts: Dictionary = {}
var _warm_consumer: RefCounted

func configure_owner(world: RefCounted, metadata: Dictionary, proof: Dictionary) -> bool:
	if _world != null or world == null or OS.get_thread_caller_id() == OS.get_main_thread_id(): return false
	if proof.get("contract_id") != "world.caster.presentation.owner.v2" or proof.get("world_context") != world.current_world_identity(): return false
	if proof.get("catalog_lease") != metadata.get("catalog_lease") or proof.get("metadata_sha256") != metadata.get("metadata_sha256") or proof.get("timing_profiles_sha256") != metadata.get("timing_profiles_sha256"): return false
	if metadata.get("contract_id") != "world.skill.visual_metadata.v1" or not metadata.get("metadata") is Dictionary or ValueGraph.fingerprint(metadata.metadata) != metadata.get("metadata_sha256") or metadata.metadata.get("structure_contract_id") != Structure.CONTRACT: return false
	if not metadata.metadata.get("profiles") is Dictionary or not metadata.metadata.get("visual_profiles") is Dictionary: return false
	if not proof.get("code_input_receipt") is Dictionary or proof.code_input_receipt.get("actual_code_lease_verified") != true or not proof.get("loading_checkpoint_receipt") is Dictionary or proof.loading_checkpoint_receipt.get("success") != true or int(proof.get("closure_id", 0)) <= 0 or int(proof.get("main_executor_id", 0)) == 0 or int(proof.get("command_capacity", 0)) <= 0: return false
	_graph = ClassDB.instantiate("HardCoreContentValueGraph")
	if _graph == null: return false
	var captured: Dictionary = _graph.capture(proof, true, false)
	if captured.get("success") != true: return false
	var captured_metadata: Dictionary = _graph.capture(metadata.metadata,true,false)
	if captured_metadata.get("success") != true: return false
	_proof = captured.value
	_metadata = captured_metadata.value
	_world = world
	_host = world.original_caster_reply_host()
	return true

func owner_thread_id() -> int: return _owner
func _check() -> void: assert(_world != null and OS.get_thread_caller_id() == _owner)
func _fault(code: String) -> void: _world.fault(code, {})
func _emit(operation: StringName, payload: Dictionary) -> bool:
	_check()
	if _pending_receipts.size() >= 4 * int(_proof.command_capacity): _fault("caster_actual_command_capacity_exceeded"); return false
	var frame: Dictionary = _world.current_clock_frame()
	if not frame.has("epoch") or not frame.has("next_release_usec"): _fault("caster_original_clock_frame_missing"); return false
	frame = frame.duplicate(true)
	frame.presentation_submitted_usec = Time.get_ticks_usec()
	var command := {"contract_id":"world.caster.presentation.command.v1", "world_context":_world.current_world_identity(),
		"closure_id":_proof.closure_id, "main_executor_id":_proof.main_executor_id, "command_id":_serial + 1,
		"operation":operation, "payload":payload, "source_clock":frame}
	var copied: Dictionary = _graph.capture(command, true, false)
	if copied.get("success") != true:
		_fault("caster_original_journal_admission_failed")
		return false
	var admitted: Dictionary = _world.emit_original_caster_main_event(copied.value)
	if admitted.get("status") != "ACCEPTED":
		_fault("caster_original_journal_admission_failed")
		return false
	_serial += 1
	_pending_receipts[_serial] = {"command":copied.value, "ticket":admitted.reply_identity, "applied":false}
	return true

func _binding(skill: String) -> Dictionary:
	_check()
	var binding: Dictionary = Structure.binding(_metadata,skill)
	if binding.is_empty(): _fault("caster_actual_published_skill_metadata_missing")
	return binding
func _record(model: Object, kind: String) -> Dictionary:
	_check()
	if not model is RefCounted or model is Resource: _fault("caster_S_model_boundary"); return {}
	var handle: Object = _world.actor_handle_for_model(model)
	if handle == null or handle.model() != model: _fault("caster_actual_actor_identity_missing"); return {}
	var id: int = handle.get_instance_id()
	if not _casts.has(id):
		_casts[id] = {"model":weakref(model), "identity":handle.identity(), "kind":kind}
		model.retired.connect(_on_cast_retired.bind(id))
	elif _casts[id].model.get_ref() != model or _casts[id].kind != kind:
		_fault("caster_duplicate_actor_binding")
		return {}
	return _casts[id]
func _snapshot(record: Dictionary) -> Dictionary:
	var model: RefCounted = record.model.get_ref()
	var state := {"position_screen_px":model.global_position}
	if record.kind == "projectile":
		state.merge({"skill_id":model.skill_id, "release_id":model.release_id, "runtime_map_id":model.runtime_map_id,
			"direction_screen_px":model.direction_screen_px, "visual_muzzle_offset_px":model.visual_muzzle_offset_px,
			"projectile_color":model.projectile_color, "projection_rejection_reason":model.projection_rejection_reason})
	elif record.kind == "ground":
		state.merge({"skill_id":model.skill_id, "release_id":model.release_id, "visual_radius_px":model.visual_radius_px,
			"effect_color":model.effect_color, "duration":model.duration})
	return {"identity":record.identity, "kind":record.kind, "state":state}

func bind_projectile(model: Object) -> bool:
	var record := _record(model, "projectile")
	return not record.is_empty() and _emit(&"bind_projectile", _snapshot(record))
func bind_ground(model: Object) -> bool:
	var record := _record(model, "ground")
	return not record.is_empty() and _emit(&"bind_ground", _snapshot(record))
func prepare_projectile_visual(model: Object) -> Dictionary:
	var binding := _binding(model.skill_id)
	if binding.is_empty(): return {}
	var structure: Dictionary = Structure.projectile_structure(binding.original_profile,model.direction_screen_px)
	if not bind_projectile(model): return {}
	return structure
func prepare_ground_visual(model: Object) -> void:
	if _binding(model.skill_id).is_empty(): return
	bind_ground(model)
func redraw_ground_if_without_sprite(model: Object) -> void:
	var handle: Object = _world.actor_handle_for_model(model)
	if handle == null or not _casts.has(handle.get_instance_id()) or _casts[handle.get_instance_id()].kind != "ground": _fault("caster_ground_redraw_identity_missing"); return
	_emit(&"redraw_cast",{"identity":_casts[handle.get_instance_id()].identity,"only_without_sprite":true})
func redraw_cast(model: Object) -> void:
	var handle: Object = _world.actor_handle_for_model(model)
	if handle == null or not _casts.has(handle.get_instance_id()): _fault("caster_redraw_identity_missing"); return
	_emit(&"redraw_cast", {"identity":_casts[handle.get_instance_id()].identity})
func projectile_audio_phase(model: Object, phase: String, reason: String) -> void:
	if phase not in ["launch", "impact"]: _fault("caster_audio_phase_invalid"); return
	var record := _record(model, "projectile")
	if record.is_empty(): return
	var payload := _snapshot(record)
	payload.merge({"phase":phase, "terminal_reason":reason})
	_emit(&"projectile_audio_phase", payload)
func set_cast_y_sort(model: Object, enabled: bool) -> void:
	var record := _record(model, "wall")
	if not record.is_empty(): _emit(&"set_cast_y_sort", {"identity":record.identity, "enabled":enabled})

func create_visual_model(profile: Dictionary) -> RefCounted:
	_check()
	_visual_serial += 1
	var display := Display.new()
	if not display.configure(self, _visual_serial, profile): return null
	_visuals[display.get_instance_id()] = display
	return display
func owns_visual_model(model: Object) -> bool:
	_check()
	return model is Display and _visuals.get(model.get_instance_id()) == model and not model.is_cell
func capture_visual_setup(display: RefCounted, position: Vector2, skill: String, radius: float, lifetime: float,
	direction: Vector2, target: Object, phase: String, geometry: Dictionary) -> Dictionary:
	if not owns_visual_model(display) or _binding(skill).is_empty(): return {}
	var actor_identity: Dictionary = {}
	if target != null:
		var handle: Object = _world.actor_handle_for_model(target)
		if handle == null: _fault("caster_follow_original_actor_identity_missing"); return {}
		actor_identity = handle.identity()
	var payload := {"visual_id":display.visual_id, "profile":display.profile, "position_screen_px":position,
		"skill_id":skill, "radius":radius, "lifetime":lifetime, "direction":direction,
		"target_identity":actor_identity, "phase_id":phase, "geometry":geometry}
	var copied: Dictionary = _graph.capture(payload, true, false)
	if copied.get("success") != true: _fault("caster_geometry_not_plain_at_original_projection_boundary"); return {}
	return copied.value
func enter_visual_model(model: Object) -> bool:
	if not owns_visual_model(model) or model._entered or model.setup_payload.is_empty(): return false
	if not _emit(&"create_visual_model", model.setup_payload): return false
	model._entered = true
	return true
func discard_visual_model(model: Object) -> bool:
	if not owns_visual_model(model): return false
	if model._entered and not _emit(&"discard_visual", {"visual_id":model.visual_id}): return false
	_visuals.erase(model.get_instance_id())
	return true
func create_fire_wall_cell(model: Object, state: Dictionary) -> RefCounted:
	var record := _record(model, "wall")
	if record.is_empty() or _binding(str(state.skill_id)).is_empty(): return null
	_visual_serial += 1
	var display := Display.new()
	if not display.configure(self, _visual_serial, {}, true): return null
	display.duration = float(state.duration)
	_visuals[display.get_instance_id()] = display
	if not _emit(&"create_fire_wall_cell", {"identity":record.identity, "visual_id":display.visual_id, "state":state}): return null
	return display
func refresh_fire_wall_cell(display: RefCounted, duration: float) -> void:
	if not display is Display or _visuals.get(display.get_instance_id()) != display or not display.is_cell: _fault("caster_foreign_fire_wall_cell"); return
	_emit(&"refresh_cell_lifetime", {"visual_id":display.visual_id, "duration":duration})
func _cells(cells: Array) -> Array[int]:
	var result: Array[int] = []
	for cell: Object in cells:
		if not cell is Display or not cell.is_cell or _visuals.get(cell.get_instance_id()) != cell: _fault("caster_foreign_fire_wall_cell"); return []
		result.append(cell.visual_id)
	return result
func activate_fire_wall_cells(model: Object, cells: Array) -> void:
	var record := _record(model, "wall")
	if not record.is_empty(): _emit(&"activate_fire_wall_cells", {"identity":record.identity, "cells":_cells(cells)})
func synchronize_fire_wall_cells(model: Object, cells: Array, clock_ms: float) -> void:
	var record := _record(model, "wall")
	if not record.is_empty(): _emit(&"synchronize_fire_wall_cells", {"identity":record.identity, "cells":_cells(cells), "clock_ms":clock_ms})
func fire_wall_animation_diagnostics(model: Object) -> Dictionary:
	_check()
	var handle: Object = _world.actor_handle_for_model(model)
	if handle == null or not _main_diagnostics.has(handle.get_instance_id()): return {"status":"PENDING", "reason":"actual_Main_batch_diagnostics_unpublished"}
	return _main_diagnostics[handle.get_instance_id()].duplicate(true)
func owns_cast_model(model: Object) -> bool:
	_check()
	var handle: Object = _world.actor_handle_for_model(model)
	return handle != null and _casts.has(handle.get_instance_id()) and _casts[handle.get_instance_id()].model.get_ref() == model
func synchronize_cast_pose(model: Object) -> bool:
	if not owns_cast_model(model): return false
	return _emit(&"sync_cast", _snapshot(_casts[_world.actor_handle_for_model(model).get_instance_id()]))
func _on_cast_retired(id: int) -> void:
	if not _casts.has(id): _fault("caster_unknown_original_retirement"); return
	if not _emit(&"retire_cast", {"identity":_casts[id].identity}): return
	_casts.erase(id)
	_main_diagnostics.erase(id)
func consume_main_receipt(receipt: Dictionary) -> bool:
	_check()
	if receipt.get("main_executor_id") != _proof.main_executor_id or receipt.get("closure_id") != _proof.closure_id: return false
	if receipt.get("contract_id") != "world.caster.presentation.receipt.v1": return false
	var id: int = receipt.get("command_id",0)
	if not _pending_receipts.has(id) or receipt.get("source_command") != _pending_receipts[id].command: return false
	if receipt.get("world_context") != _pending_receipts[id].command.world_context: return false
	if _pending_receipts[id].applied: return true
	if receipt.has("identity") and receipt.has("animation_batch"):
		var actor_id: int = receipt.identity.runtime_id
		if _casts.has(actor_id) and _casts[actor_id].identity == receipt.identity: _main_diagnostics[actor_id] = receipt.animation_batch.duplicate(true)
	if _pending_receipts[id].command.operation in [&"monster_audio",&"player_physical_contact_audio"]:
		if not receipt.get("audio_result") is Dictionary: return false
		original_audio_completed.emit(id,receipt.audio_result)

	if String(receipt.source_command.operation).begins_with("source_interactable::"):
		if _world.interactables == null or not _world.interactables.consume_actual_main_receipt(receipt): return false
	_pending_receipts[id].applied = true
	return true
func service_original_replies() -> bool:
	if _world == null: return true
	_check()
	for id: int in _pending_receipts.keys():
		var item: Dictionary = _pending_receipts[id]
		var actual: Dictionary = _host.poll_original_caster_event_reply(item.ticket)
		if actual.get("status") == "PENDING": continue
		if actual.get("status") == "READY" and str(item.command.operation).begins_with("source_caster_warm::") and not item.applied:
			if _warm_consumer == null: _fault("actual_warm_S_receipt_consumer_missing"); return false
			var charged: Dictionary = _warm_consumer.consume_original_warm_receipt(actual.reply,actual)
			if charged.get("status") == "PENDING": continue
			if charged.get("status") != "READY": _fault("actual_warm_budget_or_claim_receipt_invalid"); return false
		if actual.get("status") != "READY" or not consume_main_receipt(actual.reply): _fault("accepted_caster_actual_reply_mismatch"); return false
		var consumed: Dictionary = _host.consume_original_caster_event_reply(item.ticket)
		if consumed.get("status") == "PENDING": continue
		if consumed.get("status") != "READY": _fault("accepted_caster_reply_consume_failed"); return false
		var retired: Dictionary = _host.retire_original_caster_event_reply(item.ticket)
		if retired.get("status") == "PENDING": continue
		if retired.get("status") != "READY": _fault("accepted_caster_reply_retire_failed"); return false
		if not actual.actual_node_retired: continue # Return slot transferred to native persistent lifetime ledger.
		if int(actual.reply.get("actual_node_id",0)) != 0 and item.command.payload.has("visual_id"):
			for key: int in _visuals.keys():
				if _visuals[key].visual_id == item.command.payload.visual_id: _visuals.erase(key)
		_pending_receipts.erase(id)
	return _pending_receipts.is_empty()

func close_owner_presentation() -> bool:
	if _world == null: return true
	_check()
	if not service_original_replies() or not _casts.is_empty() or not _visuals.is_empty(): return false
	if _warm_consumer != null and not _warm_consumer.finish_original_warm_owner(): return false
	_warm_consumer = null
	_world = null; _host = null
	return true

func original_loading_publication() -> Dictionary:
	_check()
	return _proof.duplicate(true)
func register_original_warm_owner(owner: RefCounted) -> bool:
	_check()
	if _warm_consumer != null or owner == null or owner.owner_thread_id() != _owner: return false
	_warm_consumer = owner
	return true
func begin_original_warm_commit_phase(frame: Dictionary) -> bool:
	_check()
	return _warm_consumer == null or _warm_consumer.begin_original_warm_commit_phase(frame)
func end_original_warm_commit_phase() -> bool:
	_check()
	return _warm_consumer == null or _warm_consumer.end_original_warm_commit_phase()
func has_pending_original_caster_event(command_id: int) -> bool:
	_check()
	return _pending_receipts.has(command_id)
func emit_original_source_warm_event(operation: String, payload: Dictionary) -> Dictionary:
	_check()
	if _warm_consumer == null or operation not in ["source_caster_warm::collect_admit","source_caster_warm::retire","source_caster_warm::loading_state","source_caster_warm::loading_claim_retire"]: return {"status":"INVALID"}
	if _pending_receipts.size() >= 4 * int(_proof.command_capacity): return {"status":"BACKPRESSURE"}
	var frame: Dictionary = _world.current_clock_frame().duplicate(true)
	frame.presentation_submitted_usec = Time.get_ticks_usec()
	var command := {"contract_id":"world.caster.presentation.command.v1","world_context":_world.current_world_identity(),
		"closure_id":_proof.closure_id,"main_executor_id":_proof.main_executor_id,"command_id":_serial+1,
		"operation":operation,"payload":payload,"source_clock":frame}
	var copied: Dictionary = _graph.capture(command,true,false)
	if copied.get("success") != true: return {"status":"INVALID"}
	var admitted: Dictionary = _world.emit_original_caster_main_event(copied.value)
	if admitted.get("status") != "ACCEPTED": return admitted
	_serial += 1
	_pending_receipts[_serial] = {"command":copied.value,"ticket":admitted.reply_identity,"applied":false}
	return {"status":"ACCEPTED","reply_identity":admitted.reply_identity,"command":copied.value}


signal original_audio_completed(command_id: int, result: Dictionary)
func submit_original_audio(operation: StringName, payload: Dictionary) -> int:
	if operation not in [&"monster_audio",&"player_physical_contact_audio"] or not _emit(operation,payload): return 0
	return _serial


func matches_original_interactable_loading(proof: Dictionary) -> bool:
	_check()
	return proof.get("world_context")==_proof.world_context and proof.get("closure_id")==_proof.closure_id and proof.get("main_executor_id")==_proof.main_executor_id and proof.get("actual_Loading_receipt") is Dictionary and proof.get("actual_terminal_receipt") is Dictionary
func emit_original_interactable(operation: StringName,payload: Dictionary) -> bool:
	if not operation in [&"source_interactable::spawn_npc",&"source_interactable::spawn_portal",&"source_interactable::face_npc",&"source_interactable::retire",&"source_interactable::session_diagnostics"]: return false
	return _emit(operation,payload) # ONE serial, journal and accepted return-slot owner.
