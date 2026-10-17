extends RefCounted

## Identity views delegate to existing owners. This object never increments
## a world/character generation or owns a second map/profile state.
const CONTRACT_ID := "hardcore.execution.world_context.v1"
var _world_owner := WeakRef.new()
var _profile_owner := WeakRef.new()
var _domain_registry: RefCounted
var _domain_owner := WeakRef.new()
var _domain_thread := 0

func configure_domain(registry: RefCounted, owner: RefCounted = null) -> bool:
	if registry == null or registry.capture_world().is_empty():
		return false
	_domain_registry = registry
	_domain_owner = weakref(owner) if owner != null else WeakRef.new()
	_domain_thread = OS.get_thread_caller_id()
	_world_owner = WeakRef.new()
	_profile_owner = WeakRef.new()
	return true

func configure(world_owner: Node, profile_owner: Node) -> void:
	_domain_registry = null
	_domain_owner = WeakRef.new()
	_domain_thread = 0
	_world_owner = weakref(world_owner)
	_profile_owner = weakref(profile_owner)

func capture_world() -> Dictionary:
	if _domain_registry != null:
		return _domain_registry.capture_world()
	var owner: Node = _world_owner.get_ref() as Node
	var profile: Node = _profile_owner.get_ref() as Node
	if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not is_instance_valid(profile):
		return {}
	var result := {"contract_id": CONTRACT_ID, "world_runtime_id": owner.get_instance_id(),
		"world_epoch": int(owner.get("_zone_generation")), "runtime_map_id": int(owner.get("current_map_id")),
		"profile_id": str(profile.get("active_profile_id"))}
	result.make_read_only()
	return result

func capture_profile() -> Dictionary:
	if _domain_registry != null:
		return _domain_registry.capture_profile()
	var owner: Node = _profile_owner.get_ref() as Node
	if not is_instance_valid(owner) or owner.is_queued_for_deletion():
		return {}
	var generation: Variant = owner.get("_world_clock_generation")
	if not preload("res://scripts/world_monster_clock_ledger.gd").valid_generation(generation):
		return {}
	var result := {"profile_id": str(owner.get("active_profile_id")),
		"world_clock_generation": generation}
	result.make_read_only()
	return result

func matches_world(identity: Dictionary) -> bool:
	var current := capture_world()
	return not identity.is_empty() and not current.is_empty() and identity == current

func matches_profile(identity: Dictionary) -> bool:
	var current := capture_profile()
	return not identity.is_empty() and not current.is_empty() and identity == current

func current_world_owner() -> Node:
	var owner: Node = _world_owner.get_ref() as Node
	return owner if is_instance_valid(owner) and not owner.is_queued_for_deletion() else null


func is_domain() -> bool: return _domain_registry != null

func actor_registry() -> RefCounted:
	assert(not is_domain() or OS.get_thread_caller_id() == _domain_thread)
	return _domain_registry

func current_effect_owner() -> Object:
	if not is_domain(): return current_world_owner()
	assert(OS.get_thread_caller_id() == _domain_thread)
	var owner: RefCounted = _domain_owner.get_ref() as RefCounted
	return owner if owner != null and bool(owner.call("feature_world_is_active")) else null

func feature_is_paused() -> bool:
	if not is_domain(): return current_world_owner().get_tree().paused
	var owner: Object = current_effect_owner()
	return owner == null or bool(owner.call("feature_world_paused"))

func capture_feature_actor(actor: Object, life_authority := "metadata:hc_combat_life_epoch") -> RefCounted:
	const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
	if is_domain():
		assert(OS.get_thread_caller_id() == _domain_thread)
		if _domain_registry.capture_actor_identity(actor).is_empty(): return null
		var owner: Object = current_effect_owner()
		if owner == null or not bool(owner.call("feature_actor_in_owner_scope",actor)): return null
		return Actor.capture_domain(_domain_registry, actor)
	return Actor.capture(self, actor as Node, life_authority)

func resolve_feature_actor(reference: RefCounted, require_alive := true) -> Object:
	if reference == null: return null
	if not is_domain(): return reference.resolve(require_alive)
	assert(OS.get_thread_caller_id() == _domain_thread)
	if not matches_world(reference.identity().get("world", {})): return null
	var actor: Object = reference.resolve_record(require_alive)
	var owner: Object = current_effect_owner()
	return actor if actor != null and owner != null and bool(owner.call("feature_actor_in_owner_scope",actor)) else null

func resolve_feature_spatial_actor(reference: RefCounted, require_alive := true) -> Object:
	var actor: Object = resolve_feature_actor(reference, require_alive)
	return actor if is_domain() or actor is Node2D else null

func feature_actor_model(actor: Object) -> Object:
	if not is_domain(): return actor
	assert(OS.get_thread_caller_id() == _domain_thread)
	var owner: Object = current_effect_owner()
	return actor.model() if actor != null and _domain_registry.resolve_runtime_actor(actor.get_instance_id()) == actor and owner != null and bool(owner.call("feature_actor_in_owner_scope",actor)) else null

func project_feature_commit(actor: Object) -> Dictionary:
	if is_domain():
		var owner: Object = current_effect_owner()
		if owner == null or actor == null or _domain_registry.capture_actor_identity(actor).is_empty(): return {"success":false}
		var result: Variant = owner.call("feature_actor_commit_projection", actor)
		if not result is Dictionary or result.get("success") != true or not result.get("value") is Vector2 or not result.value.is_finite(): return {"success":false}
		return result
	if not actor is Node2D or actor.get("runtime_map_id") != capture_world().runtime_map_id or not actor.has_method("try_screen_position_px_to_ground_position_gu"):
		return {"success":false}
	return actor.call("try_screen_position_px_to_ground_position_gu", actor.global_position)
