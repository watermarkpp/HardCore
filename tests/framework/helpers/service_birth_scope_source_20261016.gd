extends RefCounted
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
var _host: Object
var _scopes: Array[RefCounted] = []
var _checks: Array[Dictionary] = []
func _check(ok: bool,label: String) -> void: _checks.append({"passed":ok,"label":label})
func _init(host: Object,publication: Dictionary) -> void:
	_host = host
	_check(OS.get_thread_caller_id() != OS.get_main_thread_id() and OS.get_thread_caller_id() == host.owner_thread_id(),"genuine Native Source receives original Main constructor publications")
	for kind: String in publication.service_birth_scopes:
		var scope := Scope.new()
		var origin: Dictionary = publication.service_birth_scopes[kind]
		_check(scope.configure_source(origin),"real Source temporal scope consumes original constructor flags:"+kind)
		_check(scope.owner_thread_id() == host.owner_thread_id() and scope.runtime_object_is_present() and not scope.is_inside_world() and not scope.can_process(),"Source keeps constructor presence separate from original future child entry:"+kind)
		for field: String in ["life_generation","process_processing_enabled","physics_processing_enabled","process_priority","physics_priority","process_mode"]:
			_check(scope.get(field) == origin[field],"original constructor field survives actual Main/Native/Source transfer:"+kind+":"+field)
		_scopes.append(scope)
	for kind: String in publication.actor_birth_templates:
		var template: Dictionary = publication.actor_birth_templates[kind]
		var scope := Scope.new()
		_check(scope.configure_source(template.scope),"actual Source consumes original actor constructor scope:"+kind)
		_check(not scope.apply_original_implicit_ready(template.source_callbacks),"implicit READY cannot execute before actual Source child entry:"+kind)
		# Controlled qualification component, not an actor/World admission.
		scope.inside_world = true
		_check(scope.apply_original_implicit_ready(template.source_callbacks),"actual Source executes original implicit method qualification at READY once:"+kind)
		_check(scope.process_processing_enabled == template.source_callbacks.has("_process") and scope.physics_processing_enabled == template.source_callbacks.has("_physics_process"),"original callback declarations determine exact READY enablement:"+kind)
		scope.set_process_processing_enabled(false)
		_check(not scope.apply_original_implicit_ready(template.source_callbacks) and not scope.process_processing_enabled,"later explicit process disable is never overwritten by a second READY:"+kind)
		_scopes.append(scope)
	var player := preload("res://scripts/gameplay/actors/player_actor_model.gd").new()
	_check(player.current_life() == 0,"actual original Source Player constructor preserves combat_epoch zero")
func on_inputs(_domain: String,_packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	return _host.publish_snapshot({"done":true,"checks":_checks},[]) if phase == "PUBLISH" else true
func close_session() -> bool:
	_scopes.clear()
	return true
