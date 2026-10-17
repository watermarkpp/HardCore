extends RefCounted

## Same native CharacterMotion2DState and PhysicsServer space as Player/Summon.
## Native collision dictionaries become source KinematicCollision views only.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _native_world: Object
var _native: Object
var _ports: WeakRef
var _configuration: Dictionary
var _prepared_radius := -1.0
var _footprint_committed := false
class CollisionView:
	extends RefCounted
	var result: Dictionary
	var access: RefCounted
	func get_remainder() -> Vector2: return result.remainder
	func get_travel() -> Vector2: return result.travel
	func get_normal() -> Vector2: return result.collision_normal
	func get_position() -> Vector2: return result.collision_point
	func get_collider_rid() -> RID: return result.collider_rid
	func get_collider() -> Object: return access.resolve_runtime(int(result.collider_id))
class RayParameters:
	extends RefCounted
	var origin: Vector2
	var destination: Vector2
	var collision_mask: int
	var exclude: Array
	var collide_with_bodies := true
	var collide_with_areas := false
	var hit_from_inside := false
class QueryPort:
	extends RefCounted
	var world: Object
	var access: RefCounted
	var core: WeakRef
	func intersect_ray(query: RefCounted) -> Dictionary:
		var result: Dictionary = world.intersect_ray(query.origin, query.destination, query.collision_mask,
			query.exclude, query.collide_with_bodies, query.collide_with_areas, query.hit_from_inside)
		if result.get("ok") != true:
			core.get_ref().fault("enemy_original_native_ray_failed", result)
			return {}
		if not result.collided: return {}
		var value: Dictionary = result.duplicate(false)
		value.collider = access.resolve_runtime(int(result.get("collider_id", 0)))
		return value
var _access: RefCounted
func _init(world: RefCounted, native_world: Object, native: Object, ports: RefCounted, access: RefCounted, configuration: Dictionary) -> void:
	assert(_owner != OS.get_main_thread_id())
	_world = weakref(world)
	_native_world = native_world
	_native = native
	_ports = weakref(ports)
	_access = access
	_configuration = configuration
func owner_thread_id() -> int: return _owner
func faulted() -> bool: return _ports.get_ref().faulted()
func _require(value: Dictionary, operation: String) -> bool:
	if value.get("ok") == true: return true
	_ports.get_ref().fail("enemy_original_native_motion_failed", {"operation": operation, "result": value})
	return false
func position_screen_px() -> Vector2: return _native.position_screen_px()
func set_position_screen_px(value: Vector2) -> void:
	if faulted(): return
	if not _native.set_position_screen_px(value):
		_ports.get_ref().fail("enemy_original_position_write_failed", {})
		return
	_ports.get_ref().publish_pose()
func velocity_screen_px_per_sec() -> Vector2: return _native.velocity_screen_px_per_sec()
func set_velocity_screen_px_per_sec(value: Vector2) -> void:
	if not faulted() and not _native.set_velocity_screen_px_per_sec(value): _ports.get_ref().fail("enemy_original_velocity_write_failed", {})
func safe_margin() -> float: return _native.safe_margin()
func collision_layer() -> int: return PhysicsServer2D.body_get_collision_layer(_native.get_body_rid())
func collision_mask() -> int: return PhysicsServer2D.body_get_collision_mask(_native.get_body_rid())
func set_collision_layer(value: int) -> void:
	if not faulted() and not _native_world.set_body_collision_filters(_native.get_body_rid(), value, collision_mask()): _ports.get_ref().fail("enemy_original_collision_layer_failed", {})
func set_collision_mask(value: int) -> void:
	if not faulted() and not _native_world.set_body_collision_filters(_native.get_body_rid(), collision_layer(), value): _ports.get_ref().fail("enemy_original_collision_mask_failed", {})
func configure_floating(margin: float, max_slides: int) -> void:
	# The source final constructor contract was applied to create_actor. This
	# source statement must confirm those exact settings, never silently no-op.
	var state: Dictionary = _native.state()
	if state.get("ok") != true or state.motion_mode != 1 or state.max_slides != max_slides or _configuration.safe_margin != margin or not is_equal_approx(float(state.safe_margin), margin):
		_ports.get_ref().fail("enemy_native_original_motion_configuration_mismatch", {"state": state})
func prepare_actor_footprint(radius: float) -> void:
	if radius != float(_configuration.screen_radius_px) or _configuration.footprint_points != preload("res://scripts/world_spatial_rules.gd").actor_footprint_polygon_px(radius):
		_ports.get_ref().fail("enemy_native_original_final_footprint_mismatch", {"radius": radius})
		return
	_prepared_radius = radius
func commit_actor_footprint() -> void:
	if _prepared_radius < 0.0 or _footprint_committed:
		_ports.get_ref().fail("enemy_original_footprint_commit_invalid", {})
		return
	_footprint_committed = true
func _collision(result: Dictionary) -> RefCounted:
	if not result.collided: return null
	var collision := CollisionView.new()
	collision.result = result
	collision.access = _access
	return collision
func collide_motion(motion: Vector2, test_only := false, margin := 0.08, recovery_as_collision := false) -> RefCounted:
	if faulted(): return null
	var result: Dictionary = _native.collide_motion(motion, test_only, margin, recovery_as_collision)
	if not _require(result, "collide_motion"): return null
	if not test_only: _ports.get_ref().publish_pose()
	return _collision(result)
func slide(delta: float) -> void:
	if faulted(): return
	var result: Dictionary = _native.slide(delta)
	if _require(result, "slide"): _ports.get_ref().publish_pose()
func slide_collision_count() -> int:
	var result: Dictionary = _native.state()
	return result.slide_collisions.size() if _require(result, "slide_collision_count") else 0
func slide_collision(index: int) -> RefCounted:
	var result: Dictionary = _native.state()
	if not _require(result, "slide_collision") or index < 0 or index >= result.slide_collisions.size(): return null
	return _collision(result.slide_collisions[index])
func ray_parameters(origin: Vector2, destination: Vector2, mask: int = 0xffffffff, excluded: Array = []) -> RefCounted:
	var query := RayParameters.new()
	query.origin = origin
	query.destination = destination
	query.collision_mask = mask
	query.exclude = excluded
	return query
func query_port() -> RefCounted:
	var result := QueryPort.new()
	result.world = _native_world
	result.access = _access
	result.core = _world
	return result
func detach() -> void:
	_native = null
	_native_world = null
	_ports = null
	_access = null

func stop_velocity() -> void: set_velocity_screen_px_per_sec(Vector2.ZERO)

func set_input_pickable(value: bool) -> bool:
	return OS.get_thread_caller_id()==_owner and not faulted() and _native_world.set_body_pickable(_native.get_body_rid(),value)

func actual_body_rid() -> RID:
	assert(OS.get_thread_caller_id()==_owner)
	return _native.get_body_rid()
