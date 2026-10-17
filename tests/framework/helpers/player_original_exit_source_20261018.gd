extends "res://tests/framework/helpers/player_birth_life_source_20261015.gd"
## COMPONENT: original PlayerModel, production Runtime/ports and Native body.
const ActorRuntime := preload("res://scripts/gameplay/actors/actor_runtime_instance.gd")
const ActorPorts := preload("res://scripts/gameplay/actors/actor_runtime_ports.gd")
const ActorMotion := preload("res://scripts/gameplay/actors/actor_native_motion_port.gd")
var _exit_checked := false
var _actor_runtime: RefCounted
func actor_runtime_is_faulted(_id: int) -> bool: return false
func update_actor_spatial(id: int, view: Dictionary) -> bool:
	return id == _record.get_instance_id() and view == _record.runtime_actor_view()
func _ground(screen: Vector2) -> Vector2: return screen
func on_phase(phase: String, frame: Dictionary) -> bool:
	if phase == "PUBLISH" and _done and not _exit_checked:
		_exit_checked = true
		_exercise_actual_exit_once()
	return super.on_phase(phase,frame)
func _exercise_actual_exit_once() -> void:
	var ports := ActorPorts.new(self,_registry,_record,_model,_host,_ground,0.5,false,false)
	var motion := ActorMotion.new(self,_native,_motion,ports)
	ports.bind_motion(motion)
	_actor_runtime = ActorRuntime.new(_model,_record,ports,motion,_registry,_native,&"player")
	_check(_actor_runtime.has_method("apply_original_world_exit_once"),"real Player runtime supplies original exit checkpoint method")
	if not _actor_runtime.has_method("apply_original_world_exit_once"):
		_actor_runtime = null
		return
	var epoch: int = _model.combat_epoch
	_model.combat_actions.pending_action_active = true
	_model.combat_actions.pending_action_committed = true
	_model.combat_actions.pending_action_kind = "attack"
	_model.set("_pending_attack_context",{"component":true})
	_model.set("_pending_skill_context",{"component":true})
	_check(_record.is_inside_world(),"actual registered Player is inside before source exit checkpoint")
	_check(_actor_runtime.apply_original_world_exit_once(),"real original Player exit executes at explicit checkpoint")
	_check(_model.combat_epoch == epoch+1 and not _model.combat_actions.pending_action_active and _model.get("_pending_attack_context").is_empty() and _model.get("_pending_skill_context").is_empty(),"original exit increments combat epoch and clears actual pending actions")
	_check(_record.is_inside_world(),"original Player exit does not move membership ahead of tree-exiting/group removal")
	_check(_actor_runtime.apply_original_world_exit_once() and _model.combat_epoch == epoch+1,"repeated original exit checkpoint does not repeat gameplay teardown")
	_check(_actor_runtime.leave_world() and not _record.is_inside_world() and _model.combat_epoch == epoch+1,"membership leave reuses same completed original exit")
	_check(_actor_runtime.enter_world(1,true,true) and _record.is_inside_world(),"same Player reenters through real runtime pose/qualification path")
	_check(_actor_runtime.apply_original_world_exit_once() and _model.combat_epoch == epoch+2,"a real new entry gets a fresh original exit exactly once")
	_check(_actor_runtime.enter_world(1,true,true) and _actor_runtime.apply_original_world_exit_once() and _model.combat_epoch == epoch+2,"duplicate enter while already inside cannot rearm a completed exit")
	if _first_action != null: _first_action.dispose_domain(); _first_action = null
	if _link != null: _link.dispose(); _link = null
	_check(_actor_runtime.final_retire() and _model.combat_epoch == epoch+2,"actual Native/Registry final retirement does not repeat original Player exit")
	_check(_registry.remaining_actor_count() == 0 and _registry.remaining_lease_count() == 0,"real retired Player leaves no registry actor or accepted lease")
	_check(_actor_runtime.final_retire() and _model.combat_epoch == epoch+2,"idempotent final retirement preserves original one-time exit")
	_model.motion = null
	_motion = null; _record = null; _actor_runtime = null
