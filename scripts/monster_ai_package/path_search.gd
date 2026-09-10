class_name HCMonsterPathSearch
extends RefCounted

const HCM30ContextTokenScript := preload("res://scripts/monster_ai_package/m30/context_token.gd")

# Resumable, bounded A*. World occupancy remains owned by the existing policy.
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const MAX_RECORDS := 8192
const DIAGONAL_COST := 1.4142135623730951
const MAX_SHARED_HEURISTIC_SETS := 64
const MAX_SHARED_HEURISTIC_CELLS_PER_SET := MAX_RECORDS
const MAX_SHARED_WALKABLE_SETS := 64
const MAX_SHARED_GOAL_FIELDS := 16
static var shared_heuristics: Dictionary = {}
static var shared_heuristic_order: Array[String] = []
static var shared_walkability: Dictionary = {}
static var shared_walkability_order: Array = []
static var shared_goal_fields: Dictionary = {}
static var shared_goal_field_order: Array = []
static var diagnostic_frontier_rebuilds := 0
static var diagnostic_frontier_rebuild_usec := 0
static var diagnostic_frontier_rebuild_max_cells := 0
static var diagnostic_shared_field_services := 0
static var diagnostic_shared_field_expansions := 0
static var diagnostic_shared_field_fallbacks := 0

static func reset_diagnostics() -> void:
	diagnostic_frontier_rebuilds = 0
	diagnostic_frontier_rebuild_usec = 0
	diagnostic_frontier_rebuild_max_cells = 0
	diagnostic_shared_field_services = 0
	diagnostic_shared_field_expansions = 0
	diagnostic_shared_field_fallbacks = 0

static func diagnostics() -> Dictionary:
	return {
		"m30_frontier_rebuilds": diagnostic_frontier_rebuilds,
		"m30_frontier_rebuild_usec": diagnostic_frontier_rebuild_usec,
		"m30_frontier_rebuild_max_cells": diagnostic_frontier_rebuild_max_cells,
		"shared_field_services": diagnostic_shared_field_services,
		"shared_field_expansions": diagnostic_shared_field_expansions,
		"shared_field_fallbacks": diagnostic_shared_field_fallbacks,
	}
var context: Dictionary
var radius := 0.0
var start := Vector2i.ZERO
var goals: Dictionary = {}
var edge_blocked := Callable()
var heap: Array = []
var g: Dictionary = {}
var heuristic_cache: Dictionary = {}
var walkable_cache: Dictionary = {}
var parent: Dictionary = {}
var closed: Dictionary = {}
var state := "QUEUED"
var path := PackedVector2Array()
var expansions := 0
var goal_builder := Callable()
var shared_static_scope: Array = []
var shared_goal_field: StaticGoalField
var shared_peer_waited := false

class StaticGoalField:
	extends RefCounted
	var context: Dictionary
	var radius := 0.0
	var goals: Dictionary = {}
	var heap: Array = []
	var distance: Dictionary = {}
	var next_toward_goal: Dictionary = {}
	var closed: Dictionary = {}
	var walkable_cache: Dictionary = {}
	var state := "SEARCHING"
	var expansions := 0
	var attached_searches := 0
	var registered_starts: Dictionary = {}
	var active_start := Vector2i(-2147483648, -2147483648)
	var active_start_expansions := 0

	func _init(ctx: Dictionary, r: float, destinations: Dictionary, shared_walkable: Dictionary) -> void:
		context = ctx
		radius = r
		goals = destinations
		walkable_cache = shared_walkable
		var ordered_goals: Array = goals.keys()
		ordered_goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x)
		)
		for goal: Vector2i in ordered_goals:
			if not _cell_walkable(goal):
				continue
			distance[goal] = 0.0
			_push([0.0, 0.0, goal.y, goal.x, goal])
		if heap.is_empty():
			state = "NO_ROUTE_FOR_CURRENT_GRAPH"

	func attach(from_cell: Vector2i) -> void:
		attached_searches += 1
		registered_starts[from_cell] = int(registered_starts.get(from_cell, 0)) + 1
		if active_start.x == -2147483648 and state == "SEARCHING":
			_rotate_active_start()

	func detach(from_cell: Vector2i) -> void:
		attached_searches = maxi(0, attached_searches - 1)
		var remaining := int(registered_starts.get(from_cell, 0)) - 1
		if remaining > 0:
			registered_starts[from_cell] = remaining
		else:
			registered_starts.erase(from_cell)
		if state == "SEARCHING" and from_cell == active_start and not registered_starts.has(from_cell):
			_rotate_active_start()

	func advance_to(target: Vector2i, limit: int, deadline_usec: int) -> String:
		if closed.has(target):
			return "FOUND"
		if state != "SEARCHING":
			return state
		var used := 0
		var pops := 0
		while not heap.is_empty() and used < limit and pops < limit * 4:
			if deadline_usec > 0 and used > 0 and (used & 7) == 0 and Time.get_ticks_usec() >= deadline_usec:
				break
			pops += 1
			var item: Array = _pop()
			var cell: Vector2i = item[4]
			if closed.has(cell) or float(item[1]) > float(distance.get(cell, INF)) + 0.000001:
				continue
			var reached_active_start := cell == active_start
			closed[cell] = true
			used += 1
			expansions += 1
			active_start_expansions += 1
			for step: Vector2i in Terrain.NEIGHBORS:
				var neighbor := cell + step
				if closed.has(neighbor) or not _can_traverse_neighbor(cell, neighbor):
					continue
				var score := float(distance[cell]) + (DIAGONAL_COST if step.x != 0 and step.y != 0 else 1.0)
				if score >= float(distance.get(neighbor, INF)) - 0.000001:
					continue
				if not distance.has(neighbor) and distance.size() >= MAX_RECORDS:
					state = "SEARCH_CAPACITY_LIMIT"
					return state
				distance[neighbor] = score
				next_toward_goal[neighbor] = cell
				_push([score + _active_heuristic(neighbor), score, neighbor.y, neighbor.x, neighbor])
			if reached_active_start:
				_rotate_active_start()
				if closed.has(target):
					return "FOUND"
			elif registered_starts.size() > 1 and active_start_expansions >= Terrain.MAX_PATH_EXPANSIONS:
				# One difficult or unreachable start gets at most one formal expansion
				# quantum before another live registered start owns the heuristic.
				_rotate_active_start()
		if heap.is_empty():
			state = "NO_ROUTE_FOR_CURRENT_GRAPH"
		return "FOUND" if closed.has(target) else state

	func _rotate_active_start() -> void:
		var candidates: Array = []
		for candidate: Vector2i in registered_starts:
			if not closed.has(candidate):
				candidates.append(candidate)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x)
		)
		if candidates.is_empty():
			active_start = Vector2i(-2147483648, -2147483648)
			active_start_expansions = 0
			return
		var next_index := 0
		var current_index := candidates.find(active_start)
		if current_index >= 0:
			next_index = (current_index + 1) % candidates.size()
		active_start = candidates[next_index]
		active_start_expansions = 0
		_rebuild_frontier_priorities()

	func _active_heuristic(cell: Vector2i) -> float:
		if active_start.x == -2147483648:
			return 0.0
		var delta := (active_start - cell).abs()
		return float(maxi(delta.x, delta.y)) + (DIAGONAL_COST - 1.0) * float(mini(delta.x, delta.y))

	func _rebuild_frontier_priorities() -> void:
		var m30_started: int = Time.get_ticks_usec()
		heap.clear()
		for raw_cell: Variant in distance:
			var cell: Vector2i = raw_cell
			if closed.has(cell):
				continue
			var score := float(distance[cell])
			_push([score + _active_heuristic(cell), score, cell.y, cell.x, cell])
		HCMonsterPathSearch.diagnostic_frontier_rebuilds += 1
		HCMonsterPathSearch.diagnostic_frontier_rebuild_usec += Time.get_ticks_usec() - m30_started
		HCMonsterPathSearch.diagnostic_frontier_rebuild_max_cells = maxi(HCMonsterPathSearch.diagnostic_frontier_rebuild_max_cells, distance.size())


	func path_from(from_cell: Vector2i) -> PackedVector2Array:
		var result := PackedVector2Array()
		var cell := from_cell
		var guard := 0
		while not goals.has(cell) and guard < MAX_RECORDS:
			guard += 1
			if not next_toward_goal.has(cell):
				return PackedVector2Array()
			cell = next_toward_goal[cell]
			result.append(Vector2(cell) + Vector2(.5, .5))
		if not goals.has(cell):
			return PackedVector2Array()
		var exact_goal: Vector2 = goals[cell]
		if result.is_empty():
			result.append(exact_goal)
		else:
			result[result.size() - 1] = exact_goal
		return result

	func _cell_walkable(cell: Vector2i) -> bool:
		if walkable_cache.has(cell):
			return bool(walkable_cache[cell])
		var result := Terrain.cell_walkable(context, cell, radius)
		if walkable_cache.size() < MAX_RECORDS:
			walkable_cache[cell] = result
		return result

	func _can_traverse_neighbor(from_cell: Vector2i, to_cell: Vector2i) -> bool:
		var delta := to_cell - from_cell
		if delta == Vector2i.ZERO or abs(delta.x) > 1 or abs(delta.y) > 1:
			return false
		if not _cell_walkable(to_cell):
			return false
		if delta.x != 0 and delta.y != 0:
			return _cell_walkable(from_cell + Vector2i(delta.x, 0)) and _cell_walkable(from_cell + Vector2i(0, delta.y))
		return true

	static func _less(a: Array, b: Array) -> bool:
		if a[0] != b[0]: return a[0] < b[0]
		if a[1] != b[1]: return a[1] < b[1]
		if a[2] != b[2]: return a[2] < b[2]
		return a[3] < b[3]

	func _push(item: Array) -> void:
		heap.append(item)
		var index := heap.size() - 1
		while index > 0:
			var up: int = (index - 1) >> 1
			if not _less(item, heap[up]): break
			heap[index] = heap[up]
			index = up
		heap[index] = item

	func _pop() -> Array:
		var first: Array = heap[0]
		var last: Array = heap.pop_back()
		if heap.is_empty(): return first
		var index := 0
		while true:
			var left := index * 2 + 1
			if left >= heap.size(): break
			var right := left + 1
			var best := right if right < heap.size() and _less(heap[right], heap[left]) else left
			if not _less(heap[best], last): break
			heap[index] = heap[best]
			index = best
		heap[index] = last
		return first

func configure(ctx: Dictionary, from: Vector2i, destinations: Dictionary, r: float, edge: Callable) -> void:
	detach_shared_goal_field()
	context = ctx
	start = from
	goals = destinations.duplicate()
	radius = r
	edge_blocked = edge
	heap.clear()
	g.clear()
	heuristic_cache = {}
	walkable_cache = {}
	parent.clear()
	closed.clear()
	path.clear()
	expansions = 0
	state = "SEARCHING"
	if not Terrain.context_valid(context):
		state = "INVALID_CONTEXT"
		return
	if goals.is_empty():
		state = "NO_VALID_GOAL_IN_CURRENT_SAMPLE"
		return
	# Built map contexts are deeply read-only and represent one exact authored
	# collision snapshot. Share only the static footprint result for that exact
	# context/radius; per-actor edge_blocked remains outside this cache.
	var blocked: Variant = context.get("blocked_cells")
	if context.is_read_only() and blocked is Dictionary and (blocked as Dictionary).is_read_only():
		var walkable_scope := [HCM30ContextTokenScript.token(context), radius]
		if shared_walkability.has(walkable_scope):
			walkable_cache = shared_walkability[walkable_scope]
		else:
			if shared_walkability_order.size() >= MAX_SHARED_WALKABLE_SETS:
				shared_walkability.erase(shared_walkability_order.pop_front())
			shared_walkability_order.append(walkable_scope)
			shared_walkability[walkable_scope] = walkable_cache
	var signature := _goal_signature()
	if shared_heuristics.has(signature):
		heuristic_cache = shared_heuristics[signature]
	else:
		if shared_heuristic_order.size() >= MAX_SHARED_HEURISTIC_SETS:
			shared_heuristics.erase(shared_heuristic_order.pop_front())
		shared_heuristic_order.append(signature)
		shared_heuristics[signature] = heuristic_cache
	g[start] = 0.0
	_push([_heuristic(start), 0.0, start.y, start.x, start])

func configure_deferred(ctx: Dictionary, from: Vector2i, builder: Callable, r: float, edge: Callable, static_scope: Array = []) -> void:
	detach_shared_goal_field()
	context = ctx
	start = from
	radius = r
	edge_blocked = edge
	shared_static_scope = static_scope
	goal_builder = builder
	state = "PREPARING"

func _heuristic(cell: Vector2i) -> float:
	var best := INF
	if heuristic_cache.has(cell):
		best = float(heuristic_cache[cell])
	else:
		for goal: Vector2i in goals:
			var d := (goal - cell).abs()
			best = minf(best, float(maxi(d.x, d.y)) + (DIAGONAL_COST - 1.0) * float(mini(d.x, d.y)))
		if heuristic_cache.size() < MAX_SHARED_HEURISTIC_CELLS_PER_SET:
			heuristic_cache[cell] = best
	return best

func _goal_signature() -> String:
	var cells: Array[String] = []
	for goal: Vector2i in goals:
		cells.append("%d,%d" % [goal.x, goal.y])
	cells.sort()
	return "|".join(cells)

func advance(limit := 384, deadline_usec := 0) -> String:
	if state == "PREPARING":
		if not goal_builder.is_valid():
			state = "INVALID_CONTEXT"
			return state
		var raw: Variant = goal_builder.call()
		goal_builder = Callable()
		if not raw is Dictionary:
			state = "INVALID_CONTEXT"
			return state
		configure(context, start, raw, radius, edge_blocked)
		_try_attach_shared_goal_field()
	if state != "SEARCHING":
		return state
	if shared_goal_field != null:
		if shared_goal_field.attached_searches < 2:
			if not shared_peer_waited:
				shared_peer_waited = true
				return "SEARCHING"
			detach_shared_goal_field()
			diagnostic_shared_field_fallbacks += 1
		else:
			diagnostic_shared_field_services += 1
			var before_shared := shared_goal_field.expansions
			var shared_result := shared_goal_field.advance_to(start, limit, deadline_usec)
			var shared_used := shared_goal_field.expansions - before_shared
			expansions += shared_used
			diagnostic_shared_field_expansions += shared_used
			if shared_result == "FOUND":
				path = shared_goal_field.path_from(start)
				if path.is_empty():
					detach_shared_goal_field()
					diagnostic_shared_field_fallbacks += 1
				else:
					state = "FOUND"
					return state
			elif shared_result == "NO_ROUTE_FOR_CURRENT_GRAPH":
				state = shared_result
				return state
			elif shared_result == "SEARCH_CAPACITY_LIMIT":
				detach_shared_goal_field()
				diagnostic_shared_field_fallbacks += 1
			else:
				return "SEARCHING"
	var used := 0
	var pops := 0
	while not heap.is_empty() and used < limit and pops < limit * 4:
		if deadline_usec > 0 and used > 0 and (used & 7) == 0 and Time.get_ticks_usec() >= deadline_usec:
			break
		pops += 1
		var item: Array = _pop()
		var cell: Vector2i = item[4]
		if closed.has(cell) or float(item[1]) > float(g.get(cell, INF)) + 0.000001:
			continue
		if goals.has(cell):
			_reconstruct(cell)
			if state == "SEARCHING":
				state = "FOUND"
			return state
		closed[cell] = true
		used += 1
		expansions += 1
		for step: Vector2i in Terrain.NEIGHBORS:
			var next := cell + step
			if closed.has(next):
				continue
			if not _can_traverse_neighbor(cell, next):
				continue
			if edge_blocked.is_valid():
				if bool(edge_blocked.call(cell, next)):
					continue
			var score := float(g[cell]) + (DIAGONAL_COST if step.x != 0 and step.y != 0 else 1.0)
			if score >= float(g.get(next, INF)) - 0.000001:
				continue
			if not g.has(next) and g.size() >= MAX_RECORDS:
				state = "SEARCH_CAPACITY_LIMIT"
				return state
			parent[next] = cell
			g[next] = score
			_push([score + _heuristic(next), score, next.y, next.x, next])
	if heap.is_empty():
		# A proof is for this graph, footprint, goal sample and revision ONLY.
		state = "NO_ROUTE_FOR_CURRENT_GRAPH"
	return state

func _try_attach_shared_goal_field() -> void:
	detach_shared_goal_field()
	if shared_static_scope.is_empty() or edge_blocked.is_valid():
		return
	var blocked: Variant = context.get("blocked_cells")
	if not context.is_read_only() or not blocked is Dictionary or not (blocked as Dictionary).is_read_only():
		return
	if not Terrain.cell_walkable(context, start, radius):
		return
	goals.make_read_only()
	var field_scope := [shared_static_scope, HCM30ContextTokenScript.token(context), radius, goals]
	if shared_goal_fields.has(field_scope):
		shared_goal_field = shared_goal_fields[field_scope]
	else:
		if shared_goal_field_order.size() >= MAX_SHARED_GOAL_FIELDS:
			shared_goal_fields.erase(shared_goal_field_order.pop_front())
		shared_goal_field_order.append(field_scope)
		shared_goal_field = StaticGoalField.new(context, radius, goals, walkable_cache)
		shared_goal_fields[field_scope] = shared_goal_field
	shared_goal_field.attach(start)

func detach_shared_goal_field() -> void:
	if shared_goal_field != null:
		shared_goal_field.detach(start)
		shared_goal_field = null

func _cell_walkable(cell: Vector2i) -> bool:
	if walkable_cache.has(cell):
		return bool(walkable_cache[cell])
	var result := Terrain.cell_walkable(context, cell, radius)
	if walkable_cache.size() < MAX_RECORDS:
		walkable_cache[cell] = result
	return result

func _can_traverse_neighbor(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var delta := to_cell - from_cell
	if delta == Vector2i.ZERO or abs(delta.x) > 1 or abs(delta.y) > 1:
		return false
	if not _cell_walkable(to_cell):
		return false
	if delta.x != 0 and delta.y != 0:
		return (
			_cell_walkable(from_cell + Vector2i(delta.x, 0))
			and _cell_walkable(from_cell + Vector2i(0, delta.y))
		)
	return true

func _reconstruct(goal: Vector2i) -> void:
	var reversed: Array[Vector2i] = []
	var cell := goal
	while cell != start:
		reversed.append(cell)
		if not parent.has(cell):
			state = "INVALID_PARENT_CHAIN"
			return
		cell = parent[cell]
		if reversed.size() > MAX_RECORDS:
			state = "INVALID_PARENT_CHAIN"
			return
	reversed.reverse()
	for index in range(reversed.size()):
		cell = reversed[index]
		path.append(Vector2(cell) + Vector2(0.5, 0.5))
	var exact_goal: Vector2 = goals[goal]
	if path.is_empty():
		path.append(exact_goal)
	else:
		path[path.size() - 1] = exact_goal

static func _less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	if a[2] != b[2]:
		return a[2] < b[2]
	return a[3] < b[3]

func _push(item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var up: int = (index - 1) >> 1
		if not _less(item, heap[up]):
			break
		heap[index] = heap[up]
		index = up
	heap[index] = item

func _pop() -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var best := left
		if right < heap.size() and _less(heap[right], heap[left]):
			best = right
		if not _less(heap[best], last):
			break
		heap[index] = heap[best]
		index = best
	heap[index] = last
	return first
