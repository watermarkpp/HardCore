extends RefCounted

## WorldCore owns this aggregate, then removes it at the original delete queue
## boundary. Models, canonical handles and native RIDs have distinct lifetimes.
var _owner := OS.get_thread_caller_id()
var model: RefCounted
var handle: Object
var ports: RefCounted
var motion: RefCounted
var _registry: WeakRef
var _world: Object
var _kind: StringName
var _closed := false

func _init(p_model: RefCounted, p_handle: Object, p_ports: RefCounted, p_motion: RefCounted, registry: RefCounted, world: Object, kind: StringName) -> void:
	model = p_model
	handle = p_handle
	ports = p_ports
	motion = p_motion
	_registry = weakref(registry)
	_world = world
	_kind = kind

func healthy() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return not _closed and not ports.faulted() and not motion.faulted()

func step_process(delta: float) -> bool:
	if not healthy(): return false
	var view: Dictionary = handle.runtime_actor_view()
	if view.inside_world and view.can_process and _kind == &"summon":
		model.step_process(delta)
	return healthy()

func step_physics(delta: float) -> bool:
	if not healthy(): return false
	var view: Dictionary = handle.runtime_actor_view()
	if not view.inside_world or not view.can_process or not view.physics_processing_enabled:
		return true
	if not motion.set_physics_delta(delta): return false
	model.step_physics(delta)
	return healthy()

func flush_facts() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return ports.flush_facts()

func capture_link() -> RefCounted:
	return ports.capture_actor(handle)

func capture_accepted_actor_ref() -> RefCounted:
	return ports.capture_accepted_actor_ref()

func accept_numeric_visual_publication(publication: Dictionary) -> bool:
	if not healthy() or _kind != &"summon": return false
	# Input admission associates this imported-art update with the SAME actor,
	# world and summon template. No Texture or other Object may enter this value.
	for key: String in ["runtime_id", "world", "summon_id", "timing_profile", "profile_complete", "preview_active"]:
		if not publication.has(key): return false
	if publication.runtime_id != handle.get_instance_id() or publication.world != handle.identity().world or publication.summon_id != model.summon_id: return false
	if not publication.timing_profile is Dictionary or not publication.profile_complete is bool or not publication.preview_active is bool: return false
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.call("validate", publication, true).success: return false
	model.activate_numeric_visual_profile(publication.timing_profile)
	model._visual_profile_complete = publication.profile_complete
	model._visual_preview_active = publication.preview_active
	return true

func leave_world() -> bool:
	if not healthy(): return false
	if not handle.is_inside_world(): return true
	if _kind == &"player": model.on_world_exit()
	return handle.set_world_membership(false)

func rehome_player(new_world: Dictionary, clock_generation: String, native_world: Object, configuration: Dictionary, screen_to_ground: Callable) -> bool:
	if not healthy() or _kind != &"player" or handle.is_inside_world() or handle.is_queued_for_retirement(): return false
	if native_world == null or native_world.get_class() != "HardCoreSimulationWorld2D" or not screen_to_ground.is_valid(): return false
	var id: int = handle.get_instance_id()
	# Registry invalidates old accepted world identity and preserves this exact
	# ObjectID/model/leases. Player remains outside until enter_world succeeds.
	if not _registry.get_ref().rebind_world_with_player(id, new_world, clock_generation):
		ports.fail("player_world_rebind_failed", {"runtime_id":id})
		return false
	if not bool(_world.call("retire_actor", id)):
		ports.fail("player_previous_native_retirement_failed", {"runtime_id":id})
		return false
	var replacement: Object = native_world.call("create_actor", id, configuration)
	if replacement == null:
		ports.fail("player_rehome_native_creation_failed", {"runtime_id":id})
		return false
	if not motion.replace_retired_native(native_world, replacement) or not ports.rebind_projection(screen_to_ground, handle.runtime_actor_view().combat_radius_gu):
		ports.fail("player_rehome_controller_binding_failed", {"runtime_id":id})
		return false
	_world = native_world
	return true

func enter_world(parent_scope: int, can_process: bool, physics_enabled: bool) -> bool:
	if not healthy() or not handle.set_runtime_qualification(parent_scope, can_process, physics_enabled): return false
	if not handle.set_world_membership(true): return false
	return ports.publish_pose()

func final_retire() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if _closed: return true
	# Reliable presentation/observer obligations must be accepted before storage
	# destruction. Queue failure leaves the exact facts and this instance alive.
	if not ports.flush_facts(): return false
	var id: int = handle.get_instance_id()
	if _kind == &"player":
		model.on_world_exit()
		model.release_profile_subscription()
	else:
		model.owner_link = null
		model.current_target_link = null
		model.pending_attack_target_link = null
	if not bool(_world.call("retire_actor", id)):
		ports.fail("actor_native_retirement_failed", {"runtime_id":id})
		return false
	if not _registry.get_ref().retire_runtime_actor(id):
		ports.fail("actor_registry_retirement_failed", {"runtime_id":id})
		return false
	# The registry may retain the model through accepted or persistent leases.
	# Ports retain no model/registry/core strongly, so there is no ownership cycle.
	motion.detach()
	_closed = true
	handle = null
	_world = null
	return true
