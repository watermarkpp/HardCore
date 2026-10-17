extends RefCounted
## Reuses the Caster journal/reply producer. Queue admission is not playback.
class ServiceReference extends RefCounted:
	var token: int
	func _init(id: int) -> void: token = id
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _caster: RefCounted
var _publication: Dictionary
var _references: Dictionary = {}
var _pending: Dictionary = {}
var _projection: RefCounted
signal actual_audio_result(source_id: int, semantic: String, action_serial: int, life: int, result: Dictionary)
func owner_thread_id() -> int: return _owner
func configure_owner(core: RefCounted, caster: RefCounted, publication: Dictionary, projection: RefCounted) -> bool:
	if _core != null or _owner == OS.get_main_thread_id() or core.owner_thread_id() != _owner or caster.owner_thread_id() != _owner: return false
	if publication.get("contract_id") != "world.audio.actual_Main_services.v1" or publication.get("world_context") != core.current_world_identity() or not publication.get("services") is Array: return false
	if not caster.has_method("submit_original_audio") or not caster.has_signal("original_audio_completed"): return false
	if projection==null or projection.owner_thread_id()!=_owner or not projection.has_method("capture_original_audio_source") or not publication.get("equipment_visual_catalog") is Dictionary: return false
	_core = weakref(core); _caster = caster; _publication = publication; _projection=projection
	_caster.original_audio_completed.connect(_actual_completed)
	return true
func adopt_registered_service(descriptor: Dictionary) -> RefCounted:
	if not descriptor.get("token") is int: return null
	var id: int = descriptor.token
	if not service_state(id).present: return null
	if not _references.has(id): _references[id] = ServiceReference.new(id)
	return _references[id]
func service_state(token: int) -> Dictionary:
	for entry: Dictionary in _publication.services:
		if entry.token == token: return entry.state
	return {"present":false,"inside_tree":false,"same_tree":false,"methods":[]}
func find_services_in_original_group_order() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for entry: Dictionary in _publication.services: result.append(adopt_registered_service({"token":entry.token}))
	return result
func reference_has_method(token: int, method: StringName) -> bool: return method in service_state(token).methods
func classic_weapon_shape(actor_id: int) -> int:
	var actor: Object = _core.get_ref().actor_model_for_runtime_id(actor_id)
	if actor == null or not _core.get_ref().skill_actors.is_kind(actor,&"player"): return -1
	var weapon: Variant=_core.get_ref().profile.equipment.get("hc.slot.weapon",{})
	if not weapon is Dictionary or weapon.is_empty(): return 0
	var stable_item_id:=_audio_stable_equipped_item_id(weapon)
	if stable_item_id<0: return -1
	var items: Variant=_publication.equipment_visual_catalog.get("itemsById",{})
	if not items is Dictionary: return -1
	var item: Variant=items.get(str(stable_item_id),{})
	if not item is Dictionary: return -1
	var wear: Variant=item.get("worldWear",{})
	return int(wear.get("shape",-1)) if wear is Dictionary and wear.has("shape") else -1
func _audio_stable_equipped_item_id(record: Dictionary) -> int:
	for field_name: String in ["item_id","itemId"]:
		var raw_id: Variant=record.get(field_name,null)
		if raw_id is int or raw_id is float:
			var numeric_id:=int(raw_id)
			if numeric_id>=0: return numeric_id
		var text_id:=str(raw_id)
		if text_id.is_valid_int() and text_id.to_int()>=0: return text_id.to_int()
	return -1
func invoke_service(token: int, method: StringName, arguments: Array) -> Variant:
	if not reference_has_method(token,method): return {"status":"rejected","reason":"actual_audio_method_absent"}
	if method == &"retire_monster_audio_owner":
		return _core.get_ref().emit_original_main_event(&"original_audio_retire",[token,arguments])
	var operation: StringName
	if method == &"play_monster_event": operation = &"monster_audio"
	elif method == &"play_player_physical_contact": operation = &"player_physical_contact_audio"
	else: return {"status":"rejected","reason":"actual_audio_method_unmapped"}
	if arguments.size() != 3 and operation == &"monster_audio" or arguments.size() != 2 and operation == &"player_physical_contact_audio": return {"status":"rejected","reason":"actual_audio_arguments"}
	var context: Dictionary = arguments[-1]
	var actor_id: int = int(context.get("source_instance_id",0))
	var handle: Object=_core.get_ref().actor_handle_for_runtime_id(actor_id)
	if handle==null: return {"status":"rejected","reason":"actual_audio_actor_retired"}
	var identity: Dictionary = handle.identity()
	var source: Dictionary = _projection.capture_original_audio_source(actor_id)
	if not preload("res://scripts/gameplay/world/world_audio_source_contract.gd").accepts(source) or source.actor_identity != identity or source.monster_id != context.get("monster_id") or identity.get("life_generation") != context.get("source_life"): return {"status":"rejected","reason":"actual_audio_Source_input_mismatch"}
	var payload := {"service_id":token,"actor_identity":identity,"source_pose":source,"arguments":arguments.duplicate(true)}
	var id: int = _caster.submit_original_audio(operation,payload)
	if id <= 0: return {"status":"rejected","reason":"actual_audio_admission_failed"}
	_pending[id] = {"source_id":actor_id,"actor_identity":identity.duplicate(true),"combat_epoch":context.get("combat_epoch"),"life":int(context.get("source_life",-1)),"semantic":str(context.get("semantic_event","player_physical_contact")),"action_serial":int(str(context.get("release_id","attack:-1")).get_slice(":",1))}
	return {"status":"PENDING","command_id":id}
func _actual_completed(id: int, result: Dictionary) -> void:
	if not _pending.has(id): _core.get_ref().fault("actual_audio_unknown_reply",{}); return
	var held: Dictionary = _pending[id]
	_pending.erase(id)
	# Settle the actual ticket even when its old map/life has gone. It cannot
	# update the current observer merely because runtime ID/serial match.
	var handle: Object = _core.get_ref().actor_handle_for_runtime_id(held.source_id)
	if handle == null or handle.identity() != held.actor_identity: return
	var model: Object = handle.model()
	if held.combat_epoch != null and (model == null or model._audio_combat_epoch() != held.combat_epoch): return
	actual_audio_result.emit(held.source_id,held.semantic,held.action_serial,held.life,result)
func detach_at_original_world_exit() -> bool:
	if not _pending.is_empty(): return false
	if _caster.original_audio_completed.is_connected(_actual_completed): _caster.original_audio_completed.disconnect(_actual_completed)
	return true
