class_name CombatTargetQueryService

## R1-A (GPT audit 2026-09-15): the single production target-query authority.
## One service owns the shape semantics so skills stop inventing their own
## target loops. The query is two-phase:
##   1. broadphase: one conservative AABB against the shared
##      RuntimeCombatSpatialIndex (the index adds every registered actor's
##      own bounds on top, so phase 1 is always a superset);
##   2. exact: the shape predicate decides the final target set, in absolute
##      ground GU.
## The service never mutates state, never delivers damage and never scans
## scene-tree groups; consumers receive ordered candidates and apply their
## own claim/damage gates (CombatDamagePipeline authority).
##
## Supported shapes (GPT dimension 1):
##   "single"  — the point hits the target's own combat footprint.
##   "circle"  — radius_gu around origin_ground_gu.
##   "sector"  — radius_gu arc around direction_ground with half_angle_rad.
##   "capsule" — segment origin..end with half_width_gu (LINE/LINE_SKILL).
##   "cross"   — two orthogonal capsules through origin with arm_gu each.
## Unknown or under-specified shapes fail closed (empty result + reason).

const SHAPE_SINGLE := "single"
const SHAPE_CIRCLE := "circle"
const SHAPE_SECTOR := "sector"
const SHAPE_CAPSULE := "capsule"
const SHAPE_CROSS := "cross"
## Snapshot/rect pass-through: the envelope IS the request bounds and the
## exact predicate is delegated to the consumer (e.g. the fire wall
## controller's canonical snapshot gate). Exists so every production query
## enters through this service without inventing a second shape semantics.
const SHAPE_AABB := "aabb"

const BROADPHASE_EPSILON_GU := 0.05

var _combat_spatial_index: RuntimeCombatSpatialIndex
var _runtime_map_id: int
var _last_rejection_reason := ""


func _init(spatial_index: RuntimeCombatSpatialIndex, runtime_map_id: int) -> void:
	_combat_spatial_index = spatial_index
	_runtime_map_id = runtime_map_id


func last_rejection_reason() -> String:
	return _last_rejection_reason


## Runs one shape query. request: Dictionary with shape-specific keys in
## absolute ground GU. Returns an ordered Array[Dictionary] exactly like the
## index emits (node / actor_runtime_id / stable_combat_order / bounds_gu);
## on rejection returns an empty array and last_rejection_reason() explains.
func query(request: Dictionary) -> Array[Dictionary]:
	_last_rejection_reason = ""
	var shape := str(request.get("shape", ""))
	var origin: Vector2 = request.get("origin_ground_gu", Vector2.INF)
	if _combat_spatial_index == null or not is_instance_valid(
		_combat_spatial_index
	):
		_last_rejection_reason = "spatial_index_unavailable"
		return []
	if _runtime_map_id < 0:
		_last_rejection_reason = "runtime_map_unavailable"
		return []
	# The aabb pass-through shape is envelope-only and needs no origin; every
	# other shape is anchored at one and must receive a finite origin.
	if shape != SHAPE_AABB and not origin.is_finite():
		_last_rejection_reason = "origin_invalid"
		return []
	var bounds := _broadphase_bounds(shape, request, origin)
	if bounds.size.x < 0.0:
		_last_rejection_reason = str(
			request.get("rejection_reason", "shape_under_specified")
		)
		return []
	## R1-B: the default epsilon guards float edges for anchored shapes.
	## Envelope pass-through consumers that reconstruct a legacy index
	## envelope bit-for-bit pass 0.0 so the broadphase candidate set stays
	## exactly the one the replaced direct index query produced.
	var epsilon := maxf(
		0.0,
		float(request.get("broadphase_epsilon_gu", BROADPHASE_EPSILON_GU))
	)
	var candidates: Array[Dictionary] = _combat_spatial_index.query_aabb_candidates(
		_runtime_map_id, bounds, epsilon
	)
	var result: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var node: Node = candidate.get("node")
		if node == null or not is_instance_valid(node):
			continue
		if node.is_queued_for_deletion():
			continue
		var target_ground_gu := _candidate_position_gu(candidate)
		if not target_ground_gu.is_finite():
			continue
		var target_bounds := maxf(
			0.0, float(candidate.get("bounds_gu", 0.0))
		)
		if not _exact_hit(shape, request, origin, target_ground_gu, target_bounds):
			continue
		result.append(candidate)
	return result


## PERF-1: allocation-conscious envelope fast path for per-frame hot
## callers. Delegates to the index caller-owned node query (query-stamp
## dedup, inline live filter, stable order by insertion): no request
## Dictionary, no candidate records, no per-query seen/sort collections.
## epsilon_gu widens the caller envelope before the index adds its own max
## actor bounds, so epsilon_gu=0 reproduces the legacy direct node-query
## envelope bit-for-bit and epsilon_gu=0.05 reproduces the record-query
## universe (bounds + epsilon + max bounds). Rejection semantics mirror
## query(): the output is cleared in every case and last_rejection_reason()
## explains a false return. Ordering defaults to stable combat order;
## existence probes may pass stable_order=false.
func query_envelope_into(
	bounds_ground_gu: Rect2,
	output: Array,
	stable_order: bool = true,
	epsilon_gu: float = 0.0,
) -> bool:
	output.clear()
	_last_rejection_reason = ""
	if _combat_spatial_index == null or not is_instance_valid(
		_combat_spatial_index
	):
		_last_rejection_reason = "spatial_index_unavailable"
		return false
	if _runtime_map_id < 0:
		_last_rejection_reason = "runtime_map_unavailable"
		return false
	if (
		not bounds_ground_gu.position.is_finite()
		or not bounds_ground_gu.size.is_finite()
		or bounds_ground_gu.size.x < 0.0
		or bounds_ground_gu.size.y < 0.0
	):
		_last_rejection_reason = "bounds_invalid"
		return false
	var envelope := bounds_ground_gu
	var epsilon := maxf(0.0, epsilon_gu)
	if epsilon > 0.0:
		envelope = envelope.grow(epsilon)
	_combat_spatial_index.query_enemy_nodes_aabb_into(
		_runtime_map_id, envelope, output, stable_order
	)
	return true


func _broadphase_bounds(
	shape: String,
	request: Dictionary,
	origin: Vector2
) -> Rect2:
	## Conservative superset envelope per shape; the index adds the registered
	## actor bounds on top of whatever envelope this returns.
	match shape:
		SHAPE_SINGLE:
			return Rect2(origin - Vector2.ONE, Vector2(2.0, 2.0))
		SHAPE_CIRCLE:
			var radius := float(request.get("radius_gu", -1.0))
			if not is_finite(radius) or radius < 0.0:
				request["rejection_reason"] = "radius_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			return _rect_around(origin, radius)
		SHAPE_SECTOR:
			var radius := float(request.get("radius_gu", -1.0))
			if not is_finite(radius) or radius < 0.0:
				request["rejection_reason"] = "radius_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			if not _direction_valid(request):
				request["rejection_reason"] = "direction_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			return _rect_around(origin, radius)
		SHAPE_CAPSULE:
			var start: Vector2 = request.get(
				"start_ground_gu", Vector2.INF
			)
			var end: Vector2 = request.get("end_ground_gu", Vector2.INF)
			var half_width := float(request.get("half_width_gu", -1.0))
			if not start.is_finite() or not end.is_finite():
				request["rejection_reason"] = "segment_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			if not is_finite(half_width) or half_width < 0.0:
				request["rejection_reason"] = "half_width_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			var min_gu := Vector2(
				minf(start.x, end.x), minf(start.y, end.y)
			) - Vector2.ONE * half_width
			var max_gu := Vector2(
				maxf(start.x, end.x), maxf(start.y, end.y)
			) + Vector2.ONE * half_width
			return Rect2(min_gu, max_gu - min_gu)
		SHAPE_CROSS:
			var arm := float(request.get("arm_gu", -1.0))
			var half_width := float(request.get("half_width_gu", -1.0))
			if not is_finite(arm) or arm < 0.0:
				request["rejection_reason"] = "arm_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			if not is_finite(half_width) or half_width < 0.0:
				request["rejection_reason"] = "half_width_invalid"
				return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
			var reach := arm + half_width
			return _rect_around(origin, reach)
		SHAPE_AABB:
			var bounds: Variant = request.get("bounds_ground_gu", null)
			if (
				bounds is Rect2
				and (bounds as Rect2).size.x >= 0.0
				and (bounds as Rect2).size.y >= 0.0
				and (bounds as Rect2).position.is_finite()
				and (bounds as Rect2).size.is_finite()
			):
				return bounds
			request["rejection_reason"] = "bounds_invalid"
			return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
		_:
			return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))


func _exact_hit(
	shape: String,
	request: Dictionary,
	origin: Vector2,
	target_ground_gu: Vector2,
	target_bounds: float
) -> bool:
	if not origin.is_finite() or not target_ground_gu.is_finite():
		return false
	if not is_finite(target_bounds) or target_bounds < 0.0:
		return false
	match shape:
		SHAPE_SINGLE:
			return origin.distance_to(target_ground_gu) <= target_bounds
		SHAPE_CIRCLE:
			var radius := float(request.get("radius_gu", 0.0))
			return is_finite(radius) and radius >= 0.0 and origin.distance_to(target_ground_gu) <= radius + target_bounds
		SHAPE_SECTOR:
			var radius := float(request.get("radius_gu", 0.0))
			var half_angle := float(request.get("half_angle_rad", 0.0))
			var raw_direction: Variant = request.get("direction_ground", Vector2.RIGHT)
			if not raw_direction is Vector2:
				return false
			var direction: Vector2 = raw_direction
			if not direction.is_finite() or direction.length_squared() <= 0.0:
				return false
			if not is_finite(radius) or radius < 0.0 or not is_finite(half_angle) or half_angle < 0.0 or half_angle > PI:
				return false
			var relative := target_ground_gu - origin
			var distance := relative.length()
			if distance <= target_bounds:
				return true
			if distance > radius + target_bounds:
				return false
			var angle_delta := absf(wrapf(relative.angle() - direction.angle(), -PI, PI))
			if angle_delta <= half_angle:
				return true
			var unit_direction := direction.normalized()
			# Distance to the CLOSED finite radial edges, not infinite rays.
			return (
				_point_segment_distance(target_ground_gu, origin, origin + unit_direction.rotated(-half_angle) * radius) <= target_bounds
				or _point_segment_distance(target_ground_gu, origin, origin + unit_direction.rotated(half_angle) * radius) <= target_bounds
			)
		SHAPE_CAPSULE:
			var start: Vector2 = request.get("start_ground_gu", origin)
			var end: Vector2 = request.get("end_ground_gu", origin)
			var half_width := float(request.get("half_width_gu", 0.0))
			return _point_segment_distance(target_ground_gu, start, end) <= half_width + target_bounds
		SHAPE_CROSS:
			var arm := float(request.get("arm_gu", 0.0))
			var half_width := float(request.get("half_width_gu", 0.0))
			var horizontal := _point_segment_distance(target_ground_gu, origin + Vector2(-arm, 0.0), origin + Vector2(arm, 0.0))
			if horizontal <= half_width + target_bounds:
				return true
			var vertical := _point_segment_distance(target_ground_gu, origin + Vector2(0.0, -arm), origin + Vector2(0.0, arm))
			return vertical <= half_width + target_bounds
		SHAPE_AABB:
			return true # Consumer's immutable snapshot remains the exact authority.
		_:
			return false



func _direction_valid(request: Dictionary) -> bool:
	var direction: Variant = request.get("direction_ground", null)
	return direction is Vector2 and (direction as Vector2).is_finite()


func _candidate_position_gu(candidate: Dictionary) -> Vector2:
	var position: Variant = candidate.get("position_ground_gu", Vector2.INF)
	if position is Vector2:
		return position
	return Vector2.INF


func _rect_around(origin: Vector2, radius: float) -> Rect2:
	return Rect2(
		origin - Vector2.ONE * radius, Vector2.ONE * (radius * 2.0)
	)


static func _point_segment_distance(
	point: Vector2, start: Vector2, end: Vector2
) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var t := clampf(
		(point - start).dot(segment) / length_squared, 0.0, 1.0
	)
	return point.distance_to(start + segment * t)
