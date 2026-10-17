extends RefCounted

var _owner = OS.get_thread_caller_id()
var deps: Dictionary
var _configured = false
func owner_thread_id() -> int:
	return _owner

var actors: RefCounted
var _service_handle: Object
var _service_registry_ref: WeakRef
func configure_owner(bindings: Dictionary, actor_access: RefCounted, service_handle: Object, service_registry: RefCounted) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner or service_handle == null or service_handle is Node or service_handle is RefCounted or service_handle.get_instance_id() <= 0:
		push_error("polygon pursuit requires independent positive service Object handle")
		return false
	if service_registry == null or not service_registry.has_method("resolve_service") or service_registry.resolve_service(service_handle.get_instance_id()) != service_handle:
		push_error("polygon pursuit service identity is not canonical")
		return false
	if actor_access == null or actor_access.owner_thread_id() != _owner:
		push_error("polygon pursuit actor access belongs to another owner")
		return false
	for key in ["Runtime", "Search", "Scheduler", "Time"]:
		if not bindings.get(key) is RefCounted or not bindings[key].has_method("owner_thread_id") or bindings[key].owner_thread_id() != _owner:
			push_error("polygon pursuit owner dependency missing: " + key)
			return false
	deps = bindings
	actors = actor_access
	_service_handle = service_handle
	_service_registry_ref = weakref(service_registry)
	_configured = true
	return true
## Non-HC melee / ranged / boss pursuit adapter. It shares the EXISTING global
## scheduler with ordinary HC melee. Attack decisions and cadence stay in Enemy.
var actor_ref: RefCounted
var scheduler: RefCounted
var context_value: Dictionary = {}
var target_ref: RefCounted
var map_id = -1
var generation = -1
var revision = -1
var actor_life = -1
var target_life = -1
var radius = 0.0
var token = 0
var pending = false
var anchor = Vector2.INF
var route = PackedVector2Array()
var route_index = 0
var retry_msec = 0

func setup(actor: Object) -> void:
	actor_ref = actors.capture(actor)

func reset() -> void:
	token += 1
	pending = false
	route.clear()
	route_index = 0
	retry_msec = 0
	if scheduler != null and _service_registry_ref.get_ref() != null and _service_registry_ref.get_ref().service_model_runtime_present(scheduler):
		scheduler.cancel(_service_handle.get_instance_id())

func retire() -> void:
	reset()

func choose(context: Dictionary, current: Vector2, destination: Vector2, target_actor: Object, exact_radius: float) -> Vector2:
	var actor: Variant = actors.resolve(actor_ref) if actor_ref != null else null
	if not actors.is_present(actor) or not actors.is_present(target_actor):
		reset()
		return Vector2.INF
	var current_map: int = actors.read_property(actor, &"runtime_map_id")
	var current_generation: int = int(actors.invoke(actor, &"read_meta", ["zone_generation", -1]))
	var current_revision: int = int(actors.invoke_call(actor, ["_hc_environment_revision"]))
	var old_target: Variant = actors.resolve(target_ref) if target_ref != null else null
	var current_actor_life: int = int(actors.invoke(actor, &"read_meta", ["hc_combat_life_epoch", -1]))
	var current_target_life: int = int(actors.invoke(target_actor, &"read_meta", ["hc_combat_life_epoch", -1]))
	if not is_same(context_value, context) or current_map != map_id or current_generation != generation or current_revision != revision or old_target != target_actor or exact_radius != radius or current_actor_life != actor_life or current_target_life != target_life:
		reset()
		context_value = context
		map_id = current_map
		generation = current_generation
		revision = current_revision
		actor_life = current_actor_life
		target_life = current_target_life
		radius = exact_radius
		target_ref = actors.capture(target_actor)
	if deps.Runtime.segment_walkable(context_value, current, destination, radius):
		if pending:
			reset()
		route.clear()
		return _bounded_step(current, destination)
	while route_index < route.size() and current.distance_to(route[route_index]) <= 0.005:
		route_index += 1
	if route_index < route.size():
		var next = _bounded_step(current, route[route_index])
		if deps.Runtime.segment_walkable(context_value, current, next, radius):
			return next
		reset()
	if pending or deps.Time.get_ticks_msec() < retry_msec:
		return Vector2.INF
	anchor = destination
	token += 1
	scheduler = deps.Scheduler.get_shared()
	if scheduler == null:
		return Vector2.INF
	var search = deps.Search.create_search()
	search.set_polygon_origin(current)
	search.configure_deferred(context_value, Vector2i(floori(current.x), floori(current.y)),
		Callable(self, "_build_goals"), radius, Callable())
	pending = true
	scheduler.submit(self, token, search)
	return Vector2.INF

static func _bounded_step(current: Vector2, destination: Vector2) -> Vector2:
	var delta = destination - current
	if delta.length_squared() <= 0.00000001:
		return Vector2.INF
	return current + delta.normalized() * minf(1.0, delta.length())

func _build_goals() -> Dictionary:
	var goals: Dictionary = {}
	if deps.Runtime.point_walkable(context_value, anchor, radius):
		goals[0] = anchor
	## A player's exact center can be too close to terrain for a larger monster.
	## Nearby legal goals are movement candidates ONLY; no attack range changes.
	for i: int in range(16):
		var point = anchor + Vector2.from_angle(TAU * float(i) / 16.0)
		if deps.Runtime.point_walkable(context_value, point, radius) and deps.Runtime.segment_walkable(context_value, point, anchor, 0.0):
			goals[i + 1] = point
	return goals

func _hc_path_job_current(candidate_token: int) -> bool:
	var actor: Variant = actors.resolve(actor_ref) if actor_ref != null else null
	var target_actor: Variant = actors.resolve(target_ref) if target_ref != null else null
	var valid = candidate_token == token and pending and _service_handle.is_inside_world() and actors.is_present(actor) and actors.is_present(target_actor)
	if valid:
		valid = actors.canonical(actor).is_inside_world() and not actors.canonical(actor).is_queued_for_retirement() and actors.canonical(target_actor).is_inside_world() and not actors.canonical(target_actor).is_queued_for_retirement() and actors.read_property(actor, &"target") == target_actor and int(actors.invoke(actor, &"read_meta", ["hc_combat_life_epoch", -1])) == actor_life and int(actors.invoke(target_actor, &"read_meta", ["hc_combat_life_epoch", -1])) == target_life
	if valid:
		valid = actors.read_property(actor, &"runtime_map_id") == map_id and int(actors.invoke(actor, &"read_meta", ["zone_generation", -1])) == generation and int(actors.invoke_call(actor, ["_hc_environment_revision"])) == revision and is_same(actors.read_property(actor, &"_terrain_navigation_context"), context_value)
	if not valid and candidate_token == token:
		pending = false
		token += 1
	return valid

func _hc_path_completed(candidate_token: int, status: String, path: PackedVector2Array) -> void:
	if not _hc_path_job_current(candidate_token):
		return
	pending = false
	if status == "FOUND":
		route = path
		route_index = 0
	else:
		retry_msec = deps.Time.get_ticks_msec() + 500 + int(posmod(_service_handle.get_instance_id(), 7)) * 17
		var actor: Variant = actors.resolve(actor_ref)
		if actors.is_present(actor):
			actors.invoke(actor, &"write_meta", ["polygon_path_status", status])
