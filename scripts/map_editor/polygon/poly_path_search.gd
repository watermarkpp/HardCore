extends RefCounted
## Resumable A* on convex navigation faces, delegated by HCMonsterPathSearch.
## advance() returns SEARCHING until all search/reconstruction/smoothing is done.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Graph := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const MAX_RECORDS := 8192
const LOOKAHEAD := 8
var state := "PREPARING"
var path := PackedVector2Array()
var expansions := 0
var graph: Graph
var index: Index
var origin := Vector2.INF
var radius := 0.0
var goal_builder := Callable()
var goals: Array = []
var start_attachment: Dictionary = {}
var heap: Array = []
var scores: Dictionary = {}
var parents: Dictionary = {}
var closed: Dictionary = {}
var best_cost := INF
var best_goal: Dictionary = {}
var phase := "PREPARING"
var reverse_faces: Array[int] = []
var chain_cursor := -1
var face_chain: Array[int] = []
var raw_path := PackedVector2Array()
var assemble_index := -1
var smooth_anchor := Vector2.ZERO
var smooth_index := 0
var smooth_probe := -1
var pending_goal_points: Array = []
var goal_prepare_index := 0

func configure(context_value: Dictionary, start_gu: Vector2, builder: Callable, radius_gu: float) -> void:
	origin = start_gu
	radius = radius_gu
	goal_builder = builder
	var key := Graph.key_for_radius(radius)
	if not bool(context_value.get("valid", false)) or not origin.is_finite() or not is_finite(radius) or radius < 0.0:
		state = "INVALID_CONTEXT"
		return
	index = context_value.get("poly_index", null)
	graph = context_value.get("poly_graphs", {}).get(key, null)
	if index == null or graph == null or not graph.ready:
		state = "UNSUPPORTED_POLYGON_RADIUS"
		return
	# Attachment is charged to advance(), not synchronous configure().

func _prepare() -> void:
	if not goal_builder.is_valid():
		state = "INVALID_CONTEXT"
		return
	var raw: Variant = goal_builder.call()
	goal_builder = Callable()
	if not raw is Dictionary or raw.size() > 512:
		state = "INVALID_CONTEXT"
		return
	pending_goal_points = raw.values()
	state = "SEARCHING"
	phase = "ATTACH_START"

func _prepare_goal_one() -> void:
	if goal_prepare_index < pending_goal_points.size():
		var point: Variant = pending_goal_points[goal_prepare_index]
		goal_prepare_index += 1
		if point is Vector2 and point.is_finite():
			var attachment := graph.attach(point, index, radius)
			if not attachment.is_empty():
				attachment["goal"] = point
				goals.append(attachment)
		return
	pending_goal_points.clear()
	if goals.is_empty():
		state = "NO_VALID_GOAL_IN_CURRENT_SAMPLE"
		return
	var start_id: int = start_attachment.face
	var score: float = origin.distance_to(start_attachment.point) + start_attachment.point.distance_to(graph.centers[start_id])
	scores[start_id] = score
	_push([score + _heuristic(start_id), score, start_id])
	phase = "SEARCH"

func advance(limit := 384, deadline_usec := 0) -> String:
	if state == "PREPARING":
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			return "SEARCHING"
		_prepare()
	if state != "SEARCHING":
		return state
	var work := 0
	while work < maxi(1, limit):
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec:
			return "SEARCHING"
		work += 1
		if phase == "ATTACH_START":
			start_attachment = graph.attach(origin, index, radius)
			if start_attachment.is_empty():
				state = "NO_ROUTE_FOR_CURRENT_GRAPH"
			else:
				phase = "ATTACH_GOALS"
		elif phase == "ATTACH_GOALS":
			_prepare_goal_one()
		elif phase == "RECONSTRUCT":
			_reconstruct_one()
		elif phase == "ASSEMBLE":
			_assemble_one()
		elif phase == "SMOOTH":
			_smooth_one()
		else:
			if not best_goal.is_empty() and (heap.is_empty() or float(heap[0][0]) >= best_cost - Geo.EPS):
				chain_cursor = int(best_goal.face)
				phase = "RECONSTRUCT"
				continue
			if heap.is_empty():
				state = "NO_ROUTE_FOR_CURRENT_GRAPH"
				return state
			var item := _pop()
			var face: int = item[2]
			if closed.has(face) or float(item[1]) > float(scores.get(face, INF)) + Geo.EPS:
				continue
			closed[face] = true
			expansions += 1
			for goal: Dictionary in goals:
				if int(goal.face) != face:
					continue
				var total: float = float(scores[face]) + graph.centers[face].distance_to(goal.point) + goal.point.distance_to(goal.goal)
				if total < best_cost:
					best_cost = total
					best_goal = goal
			for link: Dictionary in graph.links[face]:
				var neighbor: int = link.to
				if closed.has(neighbor):
					continue
				var score := float(scores[face]) + float(link.cost)
				if score >= float(scores.get(neighbor, INF)) - Geo.EPS:
					continue
				if not scores.has(neighbor) and scores.size() >= MAX_RECORDS:
					state = "SEARCH_CAPACITY_LIMIT"
					return state
				scores[neighbor] = score
				parents[neighbor] = {"from": face, "portal": link.portal}
				_push([score + _heuristic(neighbor), score, neighbor])
		if state != "SEARCHING":
			return state
	return "SEARCHING"

func _heuristic(face: int) -> float:
	var best := INF
	for goal: Dictionary in goals:
		best = minf(best, graph.centers[face].distance_to(goal.goal))
	return best

func _reconstruct_one() -> void:
	if reverse_faces.size() > MAX_RECORDS:
		state = "INVALID_PARENT_CHAIN"
		return
	reverse_faces.append(chain_cursor)
	if chain_cursor == int(start_attachment.face):
		face_chain = reverse_faces.duplicate()
		face_chain.reverse()
		raw_path.append(start_attachment.point)
		raw_path.append(graph.centers[face_chain[0]])
		assemble_index = 1
		phase = "ASSEMBLE"
		return
	if not parents.has(chain_cursor):
		state = "INVALID_PARENT_CHAIN"
		return
	chain_cursor = int(parents[chain_cursor].from)

func _assemble_one() -> void:
	if assemble_index < face_chain.size():
		var face: int = face_chain[assemble_index]
		raw_path.append(parents[face].portal)
		raw_path.append(graph.centers[face])
		assemble_index += 1
		return
	raw_path.append(best_goal.point)
	raw_path.append(best_goal.goal)
	smooth_anchor = origin
	smooth_index = 0
	smooth_probe = -1
	phase = "SMOOTH"

func _smooth_one() -> void:
	if smooth_index >= raw_path.size():
		state = "FOUND"
		return
	if smooth_anchor.distance_squared_to(raw_path[smooth_index]) <= Geo.EPS * Geo.EPS:
		smooth_index += 1
		smooth_probe = -1
		return
	if smooth_probe < smooth_index:
		smooth_probe = mini(raw_path.size() - 1, smooth_index + LOOKAHEAD)
	var candidate := raw_path[smooth_probe]
	if not index.capsule_blocked(smooth_anchor, candidate, radius):
		path.append(candidate)
		smooth_anchor = candidate
		smooth_index = smooth_probe + 1
		smooth_probe = -1
		return
	if smooth_probe == smooth_index:
		## Never return a route merely because a derived nav graph says so.
		state = "POLYGON_ROUTE_CLEARANCE_FAILED"
		path.clear()
		return
	smooth_probe -= 1

static func _less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]

func _push(item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent_index := (i - 1) >> 1
		if not _less(item, heap[parent_index]):
			break
		heap[i] = heap[parent_index]
		i = parent_index
	heap[i] = item

func _pop() -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return first
	var i := 0
	while i * 2 + 1 < heap.size():
		var child := i * 2 + 1
		if child + 1 < heap.size() and _less(heap[child + 1], heap[child]):
			child += 1
		if not _less(heap[child], last):
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return first
