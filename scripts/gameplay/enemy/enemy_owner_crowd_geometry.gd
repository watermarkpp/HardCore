extends RefCounted

## S-local native numeric preparation. This owns no pose, index, eligibility,
## HP, RNG, cadence, planner, timer or budget. The original caller owns order.
const GU := preload("res://scripts/ground_unit_space.gd")
const Step := preload("res://scripts/monster_source176/source_step_plan.gd")
const REQUIRED_WORLD_METHODS := [
	"owner_thread_id", "current_clock_frame", "freeze_crowd_geometry",
	"read_crowd_geometry_stamp", "crowd_kernel_deadline_usec", "on_crowd_kernel_receipt",
]
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _native: RefCounted
var _configured := false
var _last_queries: Array = []
var _last_scope: Dictionary = {}

func owner_thread_id() -> int:
	return _owner

func configure_owner(world: RefCounted, max_peers: int, max_queries: int, worker_tasks: int) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner or _owner == OS.get_main_thread_id():
		push_error("crowd numeric preparation requires its sole S owner")
		return false
	if world == null or world is Resource:
		return false
	for method: String in REQUIRED_WORLD_METHODS:
		if not world.has_method(method):
			push_error("crowd WorldCore ABI MISSING: " + method)
			return false
	if world.owner_thread_id() != _owner or not ClassDB.class_exists("HardCoreCrowdGeometry"):
		return false
	_native = ClassDB.instantiate("HardCoreCrowdGeometry")
	if not _native.configure_owner(max_peers, max_queries, worker_tasks, GU.EPSILON_GU):
		return false
	_world = weakref(world)
	_configured = true
	return true

func _owned() -> RefCounted:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	var world: RefCounted = _world.get_ref()
	assert(world != null and world.owner_thread_id() == _owner)
	return world

func _stamp(actor: Object) -> Dictionary:
	var stamp: Dictionary = _owned().read_crowd_geometry_stamp(actor)
	for field: String in ["runtime_id", "life", "pose_revision", "radius_revision", "map"]:
		assert(stamp.get(field) is int, "crowd stamp MISSING: " + field)
	assert(stamp.runtime_id > 0 and stamp.life > 0 and stamp.pose_revision > 0 and stamp.radius_revision > 0)
	assert(stamp.get("position") is Vector2 and stamp.position.is_finite())
	assert(stamp.get("radius") is float and is_finite(stamp.radius))
	assert(stamp.get("margin") is float and is_finite(stamp.margin))
	assert(stamp.get("scope") is Dictionary and stamp.get("world_context") is Dictionary and stamp.has("map_instance_identity"))
	assert(stamp.world_context == stamp.scope.world_context and stamp.map_instance_identity == stamp.scope.map_instance_identity)
	return stamp

func _query(kind: int, a: Vector2, b: Vector2, radius: float, margin := 0.0) -> Dictionary:
	return {"kind":kind, "a":a, "b":b, "own_radius":radius, "own_margin":margin}

func prepare_queries(actor: Object, queries: Array, caller: StringName) -> bool:
	var world := _owned()
	var own := _stamp(actor)
	var frozen: Dictionary = world.freeze_crowd_geometry(own.map)
	assert(frozen.get("scope") is Dictionary and frozen.get("peers") is Array)
	assert(frozen.scope == own.scope)
	var frame: Dictionary = world.current_clock_frame()
	assert(frame.get("epoch") is int and frame.get("next_release_usec") is int)
	var deadline: int = world.crowd_kernel_deadline_usec(actor, caller)
	# It is an original consumer cutoff. Do not choose now+16ms or use an
	# entire remaining frame for each actor. The commit/publish tail stays S.
	assert(deadline > 0 and deadline <= frame.next_release_usec)
	var generation: int = frozen.scope.geometry_generation
	assert(generation > 0)
	var receipt: Dictionary = _native.prepare(queries, frozen.peers, frozen.scope, frame.epoch, generation, deadline)
	receipt["clock_frame"] = frame
	receipt["caller"] = caller
	receipt["actor_runtime_id"] = own.runtime_id
	world.on_crowd_kernel_receipt(receipt)
	if not bool(receipt.get("success", false)):
		# No accepted input is discarded; native preparation retires accepted
		# work before returning. Correctness uses the same scalar native row.
		_last_queries.clear()
		return false
	_last_queries = queries.duplicate(true)
	_last_scope = frozen.scope.duplicate(true)
	# A deadline FAIL remains a FAIL in the owner's receipt even though its
	# necessary completed data can still preserve original gameplay facts.
	return true

func prepare_motion(actor: Object, a: Vector2, b: Vector2, radius: float) -> void:
	var query := _query(0, a, b, radius)
	# Reuse already prepared numeric rows only; peer mutations are validated
	# by exact live consumption, never by bucket membership alone.
	if query in _last_queries and _stamp(actor).scope == _last_scope:
		return
	prepare_queries(actor, [query], &"enemy_motion_candidates")

func prepare_destination(actor: Object, point: Vector2, radius: float) -> void:
	var query := _query(1, point, point, radius)
	if query in _last_queries and _stamp(actor).scope == _last_scope:
		return
	prepare_queries(actor, [query], &"enemy_flank_destination")

func prepare_far_options(actor: Object, current: Vector2, cell: Vector2i, directions: Array, radius: float) -> void:
	var queries: Array = []
	# Pure candidate arithmetic only. Original ordering, broadphase queries,
	# target-body checks, static gates and earliest-direction short circuit
	# execute below in the original S caller. Both existing movement variants
	# are prepared; unused numeric rows have no gameplay observations.
	for raw: Variant in directions:
		var point := Vector2(cell + Vector2i(raw)) + Vector2(0.5, 0.5)
		queries.append(_query(0, current, point, radius))
		var leg: Vector2 = Step.next_leg(current, point, 1.0, GU.EPSILON_GU)
		if leg.is_finite():
			queries.append(_query(0, current, leg, radius))
		queries.append(_query(1, point, point, radius))
	if not queries.is_empty():
		prepare_queries(actor, queries, &"enemy_far_approach")

func prepare_contact_options(actor: Object, origin: Vector2, directions: Array) -> void:
	var own := _stamp(actor)
	var queries: Array = []
	for raw: Variant in directions:
		queries.append(_query(2, origin, Vector2(raw), own.radius, own.margin))
	if not queries.is_empty():
		prepare_queries(actor, queries, &"enemy_contact_flank")

func prepare_flank_options(actor: Object, motion_queries: Array, destination_queries: Array) -> void:
	var queries: Array = []
	for query: Dictionary in motion_queries:
		queries.append(_query(0, query.a, query.b, query.own_radius))
	for query: Dictionary in destination_queries:
		queries.append(_query(1, query.b, query.b, query.own_radius))
	if not queries.is_empty():
		prepare_queries(actor, queries, &"enemy_blocked_flank")

func motion_row(other: Object, a: Vector2, b: Vector2, center: Vector2, own_radius: float, peer_radius: float) -> Dictionary:
	var stamp := _stamp(other)
	return _native.motion_row(a, b, center, own_radius, peer_radius, stamp, stamp.scope)

func destination_blocks(other: Object, point: Vector2, center: Vector2, own_radius: float, peer_radius: float) -> bool:
	var stamp := _stamp(other)
	return _native.destination_row(point, center, own_radius, peer_radius, stamp, stamp.scope)

func contact_limit(other: Object, origin: Vector2, direction: Vector2, center: Vector2, effective_radius: float) -> float:
	var stamp := _stamp(other)
	return _native.contact_limit(origin, direction, center, effective_radius, stamp, stamp.scope)

func close_owner() -> bool:
	_owned()
	if not _native.close_owner():
		return false
	_last_queries.clear()
	_last_scope.clear()
	_native = null
	_configured = false
	return true
