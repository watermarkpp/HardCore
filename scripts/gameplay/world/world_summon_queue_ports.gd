extends RefCounted
## Borrow actual Source qualifications and canonical IDs; never create actors.
var _owner:=OS.get_thread_caller_id()
var _world: WeakRef
var _host: WeakRef
func owner_thread_id() -> int:return _owner
func configure_owner(world: RefCounted,host: RefCounted) -> bool:
	if _world!=null or _owner==OS.get_main_thread_id() or world.owner_thread_id()!=_owner or host.owner_thread_id()!=_owner or not is_same(world.get("_root_numeric"),host):return false
	_world=weakref(world);_host=weakref(host)
	return true
func original_clock() -> RefCounted:return _world.get_ref().original_source_session().original_source_session_clock()
func _same(host: Object) -> bool:return OS.get_thread_caller_id()==_owner and _host!=null and is_same(_host.get_ref(),host) and _world.get_ref()!=null
func host_present(host: Object) -> bool:return _same(host) and _world.get_ref().original_source_scope("game_root").runtime_object_is_present()
func host_inside(host: Object) -> bool:return _same(host) and _world.get_ref().original_source_scope("game_root").is_inside_world()
func host_queued(host: Object) -> bool:return not _same(host) or _world.get_ref().original_source_scope("game_root").is_queued_for_retirement()
func actor_present(actor: Object) -> bool:return OS.get_thread_caller_id()==_owner and _world!=null and _world.get_ref()!=null and _world.get_ref().skill_actors.is_runtime_present(actor)
func is_enemy(actor: Object) -> bool:return _world.get_ref().skill_actors.is_kind(actor,&"enemy")
func runtime_id(actor: Object) -> int:return _world.get_ref().skill_actors.runtime_actor_id(actor)
func actor_inside(actor: Object) -> bool:return _world.get_ref().skill_actors.is_inside_world(actor)
func actor_queued(actor: Object) -> bool:return _world.get_ref().skill_actors.is_queued_for_retirement(actor)
func actor_in_host(actor: Object,host: Object) -> bool:return _same(host) and _world.get_ref().skill_actors.is_in_parent_scope(actor)
func connect_child_signal(child: Object,name: StringName,callback: Callable,flags: int) -> bool:return _world.get_ref().connect_original_actor_signal(child,name,callback,flags)
func fault(code: String) -> void:
	if _world!=null and _world.get_ref()!=null:_world.get_ref().fault(code,{"source":"scripts/monster_ai_package/m30/summon_queue.gd"})
