extends Node
## Non-HC melee / ranged / boss pursuit adapter. It shares the EXISTING global
## scheduler with ordinary HC melee. Attack decisions and cadence stay in Enemy.
const Runtime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const Search := preload("res://scripts/monster_ai_package/path_search.gd")
const Scheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
var actor_ref: WeakRef
var scheduler: Scheduler
var context_value: Dictionary = {}
var target_ref: WeakRef
var map_id := -1
var generation := -1
var revision := -1
var actor_life := -1
var target_life := -1
var radius := 0.0
var token := 0
var pending := false
var anchor := Vector2.INF
var route := PackedVector2Array()
var route_index := 0
var retry_msec := 0

func setup(actor: Node) -> void:
	actor_ref = weakref(actor)

func reset() -> void:
	token += 1
	pending = false
	route.clear()
	route_index = 0
	retry_msec = 0
	if is_instance_valid(scheduler):
		scheduler.cancel(get_instance_id())

func _exit_tree() -> void:
	reset()

func choose(context: Dictionary, current: Vector2, destination: Vector2, target_actor: Node2D, exact_radius: float) -> Vector2:
	var actor: Variant = actor_ref.get_ref() if actor_ref != null else null
	if not is_instance_valid(actor) or not is_instance_valid(target_actor):
		reset()
		return Vector2.INF
	var current_map: int = actor.runtime_map_id
	var current_generation: int = int(actor.get_meta("zone_generation", -1))
	var current_revision: int = int(actor.call("_hc_environment_revision"))
	var old_target: Variant = target_ref.get_ref() if target_ref != null else null
	var current_actor_life: int = int(actor.get_meta("hc_combat_life_epoch", -1))
	var current_target_life: int = int(target_actor.get_meta("hc_combat_life_epoch", -1))
	if not is_same(context_value, context) or current_map != map_id or current_generation != generation or current_revision != revision or old_target != target_actor or exact_radius != radius or current_actor_life != actor_life or current_target_life != target_life:
		reset()
		context_value = context
		map_id = current_map
		generation = current_generation
		revision = current_revision
		actor_life = current_actor_life
		target_life = current_target_life
		radius = exact_radius
		target_ref = weakref(target_actor)
	if Runtime.segment_walkable(context_value, current, destination, radius):
		if pending:
			reset()
		route.clear()
		return _bounded_step(current, destination)
	while route_index < route.size() and current.distance_to(route[route_index]) <= 0.005:
		route_index += 1
	if route_index < route.size():
		var next := _bounded_step(current, route[route_index])
		if Runtime.segment_walkable(context_value, current, next, radius):
			return next
		reset()
	if pending or Time.get_ticks_msec() < retry_msec:
		return Vector2.INF
	anchor = destination
	token += 1
	scheduler = Scheduler.for_tree(get_tree())
	if not is_instance_valid(scheduler):
		return Vector2.INF
	var search := Search.new()
	search.set_polygon_origin(current)
	search.configure_deferred(context_value, Vector2i(floori(current.x), floori(current.y)),
		Callable(self, "_build_goals"), radius, Callable())
	pending = true
	scheduler.submit(self, token, search)
	return Vector2.INF

static func _bounded_step(current: Vector2, destination: Vector2) -> Vector2:
	var delta := destination - current
	if delta.length_squared() <= 0.00000001:
		return Vector2.INF
	return current + delta.normalized() * minf(1.0, delta.length())

func _build_goals() -> Dictionary:
	var goals: Dictionary = {}
	if Runtime.point_walkable(context_value, anchor, radius):
		goals[0] = anchor
	## A player's exact center can be too close to terrain for a larger monster.
	## Nearby legal goals are movement candidates ONLY; no attack range changes.
	for i: int in range(16):
		var point := anchor + Vector2.from_angle(TAU * float(i) / 16.0)
		if Runtime.point_walkable(context_value, point, radius) and Runtime.segment_walkable(context_value, point, anchor, 0.0):
			goals[i + 1] = point
	return goals

func _hc_path_job_current(candidate_token: int) -> bool:
	var actor: Variant = actor_ref.get_ref() if actor_ref != null else null
	var target_actor: Variant = target_ref.get_ref() if target_ref != null else null
	var valid := candidate_token == token and pending and is_inside_tree() and is_instance_valid(actor) and is_instance_valid(target_actor)
	if valid:
		valid = actor.is_inside_tree() and not actor.is_queued_for_deletion() and target_actor.is_inside_tree() and not target_actor.is_queued_for_deletion() and actor.target == target_actor and int(actor.get_meta("hc_combat_life_epoch", -1)) == actor_life and int(target_actor.get_meta("hc_combat_life_epoch", -1)) == target_life
	if valid:
		valid = actor.runtime_map_id == map_id and int(actor.get_meta("zone_generation", -1)) == generation and int(actor.call("_hc_environment_revision")) == revision and is_same(actor._terrain_navigation_context, context_value)
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
		retry_msec = Time.get_ticks_msec() + 500 + int(posmod(get_instance_id(), 7)) * 17
		var actor: Variant = actor_ref.get_ref()
		if is_instance_valid(actor):
			actor.set_meta("polygon_path_status", status)
