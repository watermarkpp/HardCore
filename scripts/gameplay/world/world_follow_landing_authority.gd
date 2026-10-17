extends RefCounted

const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _summon_link: RefCounted
var _owner_link: RefCounted
var _accepted_summon: RefCounted
var _accepted_owner: RefCounted
var _world: Dictionary
var _map_id: int
var _generation: int

static func capture(world: RefCounted, summon: Object, map_id: int, generation: int) -> RefCounted:
	if OS.get_thread_caller_id() != world.owner_thread_id() or not world.skills._main_pet_follow_context_is_current(summon): return null
	var result := new()
	result._world_ref = weakref(world)
	result._summon_link = world.skill_actors.capture(summon)
	result._owner_link = world.skill_actors.capture(world.skill_actors.owner_model(summon))
	result._accepted_summon = ActorRef.capture_domain(world.registry,world.actor_handle_for_model(summon))
	result._accepted_owner = ActorRef.capture_domain(world.registry,world.player_handle())
	if result._summon_link == null or result._owner_link == null or result._accepted_summon == null or result._accepted_owner == null:
		result.dispose()
		return null
	result._world = world.current_world_identity()
	result._map_id = map_id
	result._generation = generation
	return result

func matches_current(world: RefCounted, summon: Object, map_id: int, generation: int) -> bool:
	if OS.get_thread_caller_id() != _owner or _world_ref == null or _world_ref.get_ref() != world or _world != world.current_world_identity() or _map_id != map_id or _generation != generation: return false
	if _summon_link == null or _owner_link == null or _accepted_summon == null or _accepted_owner == null: return false
	var record: Object = _accepted_summon.resolve_record()
	var owner_record: Object = _accepted_owner.resolve_record()
	return record != null and owner_record != null and record.model() == summon and _summon_link.borrow_model() == summon and _owner_link.borrow_model() == owner_record.model() and world.player_handle() == owner_record and world.skills._main_pet_follow_context_is_current(summon)

func dispose() -> void:
	if OS.get_thread_caller_id() != _owner: return
	if _summon_link != null: _summon_link.dispose()
	if _owner_link != null: _owner_link.dispose()
	if _accepted_summon != null: _accepted_summon.dispose_domain()
	if _accepted_owner != null: _accepted_owner.dispose_domain()
	_summon_link = null
	_owner_link = null
	_accepted_summon = null
	_accepted_owner = null
	_world_ref = null
