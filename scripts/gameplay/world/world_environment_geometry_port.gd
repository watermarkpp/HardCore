extends RefCounted

## Exact WorldSkill geometry facade: mapper/map_data are the same services used
## by environment and Enemy navigation, never independent Script caches.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _world_ref: WeakRef
var _world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null
var _environment: Object
var _spatial: Object
var mapper: Object
var map_data: Object

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(world: Object, environment: Object, spatial: Object, coordinate_mapper: Object, runtime_maps: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		return false
	for port: Object in [world, environment, spatial, coordinate_mapper, runtime_maps]:
		if port == null or port is Node or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner_thread:
			return false
	if not world.has_method("fault") or not environment.has_method("is_environment_point_blocked") or not environment.has_method("is_environment_actor_blocked") or not environment.has_method("is_environment_segment_blocked_ground") or not spatial.has_method("environment_blocks_actor_screen_px"):
		return false
	_world = world
	_environment = environment
	_spatial = spatial
	mapper = coordinate_mapper
	map_data = runtime_maps
	_configured = true
	return true

func is_present() -> bool:
	# The original legacy facade asks Object validity independently of tree/life.
	return _configured and _world != null and is_instance_valid(_environment)

func _require_environment() -> bool:
	if not is_present() or OS.get_thread_caller_id() != _owner_thread:
		if _world != null:
			_world.fault("environment_geometry_provider_unavailable", {})
		return false
	return true

func environment_blocks_actor_screen_px(_provider: Object, position: Vector2, radius: float) -> bool:
	if not _require_environment():
		return true
	return _spatial.environment_blocks_actor_screen_px(_environment, position, radius)

func is_environment_point_blocked(position: Vector2) -> bool:
	if not _require_environment():
		return true
	return _environment.is_environment_point_blocked(position)

func is_environment_actor_blocked(position: Vector2, radius: float) -> bool:
	if not _require_environment():
		return true
	return _environment.is_environment_actor_blocked(position, radius)

func is_environment_segment_blocked_ground(a: Vector2, b: Vector2, step_gu := 0.25) -> bool:
	if not _require_environment():
		return true
	return _environment.is_environment_segment_blocked_ground(a, b, step_gu)

func environment_collision_revision() -> int:
	if not _require_environment():
		return -1
	return _environment.environment_collision_revision()
