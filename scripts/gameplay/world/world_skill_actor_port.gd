extends RefCounted

## S-only borrowed-model facade. ActorLink keeps storage leases; ActorRef
## continues to capture the accepted world/runtime_id/life identity.
const OwnerAccess := preload("res://scripts/gameplay/world/world_canonical_actor_access.gd")
const Link := preload("res://scripts/gameplay/foundation/actor_link.gd")
var _owner := OS.get_thread_caller_id()
var _registry: RefCounted
var _world_ref: WeakRef
var _world: RefCounted:
	get: return _world_ref.get_ref() if _world_ref != null else null
var _player: RefCounted
var _locked: RefCounted
var _magic_locked: RefCounted
var _cast_target: RefCounted

func configure(registry: RefCounted, world: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or _registry != null or registry == null or world == null: return false
	for method: String in ["actor_handle_for_model", "actors_in_group", "player_handle", "parent_scope_id", "fault"]:
		if not world.has_method(method): return false
	_registry = registry
	_world_ref = weakref(world)
	return true

func _owned() -> bool:
	var okay := _registry != null and OS.get_thread_caller_id() == _owner
	assert(okay, "WorldSkill actor port accessed outside S")
	return okay

func handle(actor: Object) -> Object:
	if not _owned() or not is_instance_valid(actor): return null
	if actor is Node or actor is Resource:
		_world.fault("world_skill_actor_object_boundary", {})
		return null
	var result: Object = _world.actor_handle_for_model(actor)
	return result if result != null and (result.model() == actor or actor is OwnerAccess.ActorView) else null

func capture(actor: Object) -> RefCounted:
	var record := handle(actor)
	return Link.capture(_registry, record) if record != null else null

func resolve_runtime_model(runtime_id: int) -> Object:
	if not _owned(): return null
	var record: Object = _registry.resolve_runtime_actor(runtime_id)
	return record.model() if record != null else null

func runtime_actor_id(actor: Object) -> int:
	var record := handle(actor)
	return record.get_instance_id() if record != null else 0

func is_runtime_present(actor: Object) -> bool:
	var record := handle(actor)
	return record != null and record.runtime_object_is_present()

func actor_view(actor: Object) -> Dictionary:
	var record := handle(actor)
	if record == null: return {}
	var value: Dictionary = record.runtime_actor_view().duplicate(false)
	# This is the original immediate pose read for the canonical planner,
	# before any later physics transform flush or presentation publication.
	value["position_screen_px"] = position_screen_px(actor)
	value.make_read_only()
	return value

func actors_in_group(group: StringName) -> Array[Object]:
	var result: Array[Object] = []
	if not _owned(): return result
	# WorldCore returns original group insertion order, including queued
	# actors until the original removal boundary. Each consumer gates life.
	for record: Object in _world.actors_in_group(group):
		if record != null and record.runtime_object_is_present(): result.append(record.model())
	return result

func is_kind(actor: Object, kind: StringName) -> bool:
	var record := handle(actor)
	if record == null: return false
	if kind == &"fire_wall":
		return record.kind() == &"field" and actor.has_method("fire_wall_controller_diagnostics")
	if kind == &"ground_effect":
		return record.kind() == &"field" and actor.has_method("runtime_target_is_inside")
	return record.kind() == kind

func is_inside_world(actor: Object) -> bool:
	var record := handle(actor)
	return record != null and record.is_inside_world()

func is_queued_for_retirement(actor: Object) -> bool:
	var record := handle(actor)
	return record == null or record.is_queued_for_retirement()

func can_process(actor: Object) -> bool:
	var record := handle(actor)
	return record != null and record.can_process()

func physics_processing(actor: Object) -> bool:
	var record := handle(actor)
	return record != null and record.is_physics_processing_enabled()

func parent_scope(actor: Object) -> int:
	var record := handle(actor)
	return record.parent_scope_id() if record != null else 0

func is_in_parent_scope(actor: Object) -> bool:
	var record := handle(actor)
	return record != null and record.parent_scope_id() == _world.parent_scope_id()

func position_screen_px(actor: Object) -> Vector2:
	var record := handle(actor)
	if record == null: return Vector2.INF
	if actor.has_method("position_screen_px"): return actor.position_screen_px()
	var motion: Object = actor.get("motion")
	if motion == null or not motion.has_method("position_screen_px"):
		_world.fault("world_skill_missing_motion", {"actor_runtime_id":record.get_instance_id()})
		return Vector2.INF
	return motion.position_screen_px()

func set_position_screen_px(actor: Object, value: Vector2) -> void:
	var record := handle(actor)
	if record == null or not value.is_finite():
		_world.fault("world_skill_position_rejected", {})
		return
	if actor.has_method("set_position_screen_px"):
		actor.set_position_screen_px(value)
		return
	var motion: Object = actor.get("motion")
	if motion == null or not motion.has_method("set_position_screen_px"):
		_world.fault("world_skill_missing_motion", {"actor_runtime_id":record.get_instance_id()})
		return
	motion.set_position_screen_px(value)

func stop_velocity(actor: Object) -> void:
	var record := handle(actor)
	if record == null: return
	var motion: Object = actor.get("motion")
	if motion == null or not motion.has_method("stop_velocity"):
		_world.fault("world_skill_missing_motion", {"actor_runtime_id":record.get_instance_id()})
		return
	motion.stop_velocity()

func player() -> Object:
	if not _owned(): return null
	var record: Object = _world.player_handle()
	return record.model() if record != null and record.runtime_object_is_present() else null

func owner_model(actor: Object) -> Object:
	if handle(actor) == null: return null
	var link: RefCounted = actor.get("owner_link")
	return link.borrow_model() if link != null else null

func locked_target() -> Object:
	return _locked.borrow_model() if _owned() and _locked != null else null

func set_locked_target(actor: Object) -> void:
	if not _owned(): return
	if _locked != null: _locked.dispose()
	_locked = capture(actor) if actor != null else null

func magic_locked_target() -> Object:
	return _magic_locked.borrow_model() if _owned() and _magic_locked != null else null

func set_magic_locked_target(actor: Object) -> void:
	if not _owned(): return
	if _magic_locked != null: _magic_locked.dispose()
	_magic_locked = capture(actor) if actor != null else null

func cast_target() -> Object:
	return _cast_target.borrow_model() if _owned() and _cast_target != null else null

func set_cast_target(actor: Object) -> void:
	if not _owned(): return
	if _cast_target != null: _cast_target.dispose()
	_cast_target = capture(actor) if actor != null else null

func magic_shield_auto_refresh_ratio() -> float:
	return 0.20

func close() -> void:
	if not _owned(): return
	for link: RefCounted in [_player, _locked, _magic_locked, _cast_target]:
		if link != null: link.dispose()
	_player = null
	_locked = null
	_magic_locked = null
	_cast_target = null

func read_meta(actor: Object, key: StringName, fallback: Variant = null) -> Variant:
	var record := handle(actor)
	return _world.actor_metadata_read(record, key, fallback) if record != null else fallback
func write_meta(actor: Object, key: StringName, value: Variant) -> void:
	var record := handle(actor)
	assert(record != null)
	_world.actor_metadata_write(record, key, value)
func contains_meta(actor: Object, key: StringName) -> bool:
	var record := handle(actor)
	return record != null and _world.actor_metadata_contains(record, key)
