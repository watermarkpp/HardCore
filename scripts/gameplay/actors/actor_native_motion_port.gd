extends RefCounted

## A boundary around the ONE native motion controller. No HP, life or pose copy.
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
var _world: Object
var _native: Object
var _ports: WeakRef
var _physics_delta := 0.0
var _failed := false

func _init(core: RefCounted, world: Object, native_motion: Object, ports: RefCounted) -> void:
	_core = weakref(core)
	_world = world
	_native = native_motion
	_ports = weakref(ports)

func _owned() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return OS.get_thread_caller_id() == _owner

func faulted() -> bool:
	return not _owned() or _failed or _ports.get_ref().faulted()

func _fault(code: String, details: Dictionary) -> void:
	_failed = true
	_ports.get_ref().fail(code, details)

func _result(value: Variant, operation: String) -> Dictionary:
	if not value is Dictionary or value.get("ok") != true:
		_fault("actor_native_motion_failed", {"operation":operation,"result":value})
		return {"ok":false}
	return value

func set_physics_delta(delta: float) -> bool:
	if faulted() or not is_finite(delta) or delta <= 0.0:
		_fault("actor_physics_delta_invalid", {"delta":delta})
		return false
	_physics_delta = delta
	return true

func position_screen_px() -> Vector2:
	assert(_owned())
	return _native.call("position_screen_px")

func velocity_screen_px_per_sec() -> Vector2:
	assert(_owned())
	return _native.call("velocity_screen_px_per_sec")

func set_position_screen_px(value: Vector2) -> void:
	if faulted(): return
	if not bool(_native.call("set_position_screen_px", value)):
		_fault("actor_position_write_failed", {"position":value})
		return
	_ports.get_ref().publish_pose()

func set_velocity_screen_px_per_sec(value: Vector2) -> void:
	if faulted(): return
	if not bool(_native.call("set_velocity_screen_px_per_sec", value)):
		_fault("actor_velocity_write_failed", {"velocity":value})

func stop_velocity() -> void:
	if faulted(): return
	if not bool(_native.call("stop_velocity")):
		_fault("actor_velocity_stop_failed", {})

func safe_margin() -> float:
	assert(_owned())
	return _native.call("safe_margin")

func collide_motion(motion_px: Vector2, test_only: bool, margin: float, recovery_as_collision := false) -> Dictionary:
	if faulted(): return {"ok":false}
	var result := _result(_native.call("collide_motion", motion_px, test_only, margin, recovery_as_collision), "collide_motion")
	if result.ok and not test_only and not _ports.get_ref().publish_pose(): return {"ok":false}
	return result

func move_and_slide() -> Dictionary:
	if faulted(): return {"ok":false}
	if _physics_delta <= 0.0:
		_fault("actor_slide_outside_physics", {})
		return {"ok":false}
	var result := _result(_native.call("slide", _physics_delta), "slide")
	if result.ok and not _ports.get_ref().publish_pose(): return {"ok":false}
	return result

func collision_layer() -> int:
	assert(_owned())
	return PhysicsServer2D.body_get_collision_layer(_native.call("get_body_rid"))

func collision_mask() -> int:
	assert(_owned())
	return PhysicsServer2D.body_get_collision_mask(_native.call("get_body_rid"))

func set_collision_layer(value: int) -> void:
	if faulted(): return
	if not bool(_world.call("set_body_collision_filters", _native.call("get_body_rid"), value, collision_mask())):
		_fault("actor_collision_layer_write_failed", {"value":value})

func set_collision_mask(value: int) -> void:
	if faulted(): return
	if not bool(_world.call("set_body_collision_filters", _native.call("get_body_rid"), collision_layer(), value)):
		_fault("actor_collision_mask_write_failed", {"value":value})

func environment_blocks_actor_screen_px(position: Vector2, radius: float) -> bool:
	if faulted(): return true
	var result: Variant = _core.get_ref().call("environment_blocks_actor_screen_px", position, radius)
	if not result is Dictionary or result.get("ok") != true or not result.get("blocked") is bool:
		_fault("actor_environment_query_failed", {"result":result})
		return true
	return result.blocked

func world_path_clear(origin: Vector2, target: Vector2) -> bool:
	if faulted(): return false
	# Original summon ray: world mask 1, bodies AND areas, no exclusions.
	var result := _result(_world.call("intersect_ray", origin, target, 1, [], true, true, false), "world_path_clear")
	return result.ok and not result.collided

func native_motion() -> Object:
	assert(_owned())
	return _native

func replace_retired_native(world: Object, native: Object) -> bool:
	if faulted() or world == null or native == null: return false
	# WorldCore has retired the prior body before this call. This wrapper keeps
	# exactly one current controller; no position/velocity authority is copied.
	_world = world
	_native = native
	_physics_delta = 0.0
	return true

func detach() -> void:
	assert(_owned())
	_native = null
	_world = null
	_core = null
	_ports = null
