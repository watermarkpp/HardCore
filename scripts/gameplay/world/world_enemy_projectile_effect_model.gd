extends RefCounted
## Original MonsterRangedProjectileEffect flight/contact algorithm, S owned.
## No ObjectDB: every owner/target resolves the canonical Source registry.
const Rules:=preload("res://scripts/world_spatial_rules.gd")
var _core: WeakRef
var _access: RefCounted
var _handle: Object
var release_descriptor: Dictionary
var origin_world_px: Vector2
var target_world_px: Vector2
var global_position: Vector2
var duration_seconds: float
var _previous_world_px: Vector2
var _elapsed_seconds:=0.0
var _finished:=false
var _blocked_by_world:=false
var _closed:=false
signal playback_finished(effect: RefCounted)
func configure_source(core: RefCounted, access: RefCounted, descriptor: Dictionary) -> bool:
	if descriptor.get("effect_id")!="monster.physical_arrow.v1" or descriptor.get("presentation_only")!=false or not descriptor.get("origin_world_px") is Vector2 or not descriptor.origin_world_px.is_finite() or not descriptor.get("target_world_px") is Vector2 or not descriptor.target_world_px.is_finite(): return false
	_core=weakref(core);_access=access;release_descriptor=descriptor.duplicate(true);release_descriptor.make_read_only()
	origin_world_px=descriptor.origin_world_px;target_world_px=descriptor.target_world_px;global_position=origin_world_px;_previous_world_px=origin_world_px
	duration_seconds=maxf(0.001,float(descriptor.get("duration_seconds",0.6)))
	_handle=core.allocate_cast_model(self,&"projectile")
	return _handle!=null
func initialize_gameplay() -> void:
	var core: RefCounted=_core.get_ref()
	core.enter_cast_group(self,&"zone_content")
	var scope: RefCounted=core._actor_scopes[_handle.get_instance_id()]
	scope.process_processing_enabled=false;scope.ordinary_p_enabled=false
	core.set_cast_physics_processing(self,true)
	core.emit_original_main_event(&"enemy_create_effect",[_handle.get_instance_id(),&"physical_projectile",release_descriptor,{}])
func _owner_model() -> Object:
	var handle: Object=_core.get_ref().registry.resolve_runtime_actor(int(release_descriptor.get("source_instance_id",0)))
	return handle.model() if handle!=null else null
func _physics_process(delta: float) -> void:
	if _finished: return
	var owner: Object=_owner_model()
	if owner==null or not owner.combat_enabled: _finish(false);return
	_elapsed_seconds=minf(duration_seconds,_elapsed_seconds+maxf(0.0,delta))
	var progress:=clampf(_elapsed_seconds/duration_seconds,0.0,1.0)
	var next_world_px:=origin_world_px.lerp(target_world_px,progress)
	var result: Dictionary=_core.get_ref().native_world.intersect_ray(_previous_world_px,next_world_px,Rules.WORLD_LAYER|Rules.PLAYER_LAYER,[],true,true,false)
	if result.get("ok")!=true: _core.get_ref().fault("enemy_projectile_native_ray_failed",result);return
	if result.get("collided")==true:
		global_position=result.get("position",next_world_px)
		var collider: Object=_access.resolve_runtime(int(result.get("collider_id",0)))
		var target_contact: bool=collider!=null and (_access.is_kind(collider,&"player") or _access.is_kind(collider,&"summon")) and int(result.get("collider_id",0))==int(release_descriptor.get("target_instance_id",0))
		_finish(not target_contact,target_contact)
		if target_contact:
			owner=_owner_model()
			if owner!=null:
				if str(release_descriptor.get("delivery_kind",""))=="guard_direct_projectile": owner._on_guard_projectile_contact(release_descriptor.get("release_record",{}),collider)
				else: owner._on_physical_projectile_contact(release_descriptor,collider)
		return
	global_position=next_world_px;_previous_world_px=next_world_px
	_publish_tick()
	if progress>=1.0: _finish(false)
func _publish_tick() -> void:
	_core.get_ref().emit_original_main_event(&"enemy_effect_tick",[_handle.get_instance_id(),{"elapsed":_elapsed_seconds,"duration":duration_seconds,"position":global_position,"blocked":_blocked_by_world,"finished":_finished}])
func _finish(blocked: bool, target_contact:=false) -> void:
	if _finished: return
	_finished=true;_blocked_by_world=blocked
	_core.get_ref().set_cast_physics_processing(self,false)
	_publish_tick()
	playback_finished.emit(self)
	if not target_contact and str(release_descriptor.get("delivery_kind",""))=="guard_direct_projectile":
		var owner: Object=_owner_model()
		if owner!=null: owner._on_guard_projectile_miss(release_descriptor.get("release_record",{}))
	_core.get_ref().queue_cast_retirement(self)
func close_effect() -> void:
	if _closed: return
	_closed=true
	_core.get_ref().emit_original_main_event(&"retire_enemy_effect",[_handle.get_instance_id()])
