extends Node

## R1-A correctness oracle (GPT audit deliverable 10): the
## CombatTargetQueryService must be set-equivalent to an independent
## reference implementation for every shape, across randomized actors and
## randomized query parameters, including boundary-inclusive cases and
## fail-closed rejections. The reference below is deliberately written from
## the shape contract, not by calling the service.

const CombatTargetQueryServiceScript := preload(
	"res://scripts/layers/runtime/combat_target_query_service.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ACTOR_COUNT := 60
const QUERIES_PER_SHAPE := 160


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	var index: RuntimeCombatSpatialIndex = (
		RuntimeCombatSpatialIndexScript.new()
	)
	var actors: Array[Dictionary] = []
	for actor_index: int in range(ACTOR_COUNT):
		var actor := Node2D.new()
		add_child(actor)
		var position := Vector2(
			rng.randf_range(0.0, 100.0), rng.randf_range(0.0, 100.0)
		)
		actor.global_position = position
		var bounds := rng.randf_range(0.0, 1.0)
		index.register(
			actor_index + 1, 0, position, bounds, actor_index + 1, actor,
			Callable(actor, "get_global_position")
		)
		actors.append({
			"id": actor_index + 1,
			"position": position,
			"bounds": bounds,
		})

	var service: CombatTargetQueryService = (
		CombatTargetQueryServiceScript.new(index, 0)
	)

	# 1) Randomized set equivalence per shape, including boundary-inclusive
	#    membership (<=), footprint-aware radii and stable ordering.
	for shape: String in [
		"circle", "sector", "capsule", "cross", "single"
	]:
		for query_index: int in range(QUERIES_PER_SHAPE):
			var request := _random_request(rng, shape)
			var service_result := service.query(request)
			var reference := _reference_set(actors, shape, request)
			var service_ids := _id_set(service_result)
			assert(
				_service_ids_equal(service_ids, reference),
				"%s query #%d set mismatch: service=%s reference=%s" % [
					shape, query_index, str(service_ids), str(reference)
				]
			)
			_assert_ordered(service_result)

	# 2) Boundary-inclusive circle: an actor exactly on the radius edge plus
	#    its own bounds must be hit.
	var edge_request := {
		"shape": "circle",
		"origin_ground_gu": Vector2(50.0, 50.0),
		"radius_gu": 10.0,
	}
	var edge_result := service.query(edge_request)
	var edge_reference := _reference_set(actors, "circle", edge_request)
	assert(
		_service_ids_equal(_id_set(edge_result), edge_reference),
		"boundary circle query diverged from the reference set"
	)

	# 3) Zero-radius circle still honours target footprints.
	var zero_request := {
		"shape": "circle",
		"origin_ground_gu": Vector2(50.0, 50.0),
		"radius_gu": 0.0,
	}
	var zero_result := service.query(zero_request)
	var zero_reference := _reference_set(actors, "circle", zero_request)
	assert(
		_service_ids_equal(_id_set(zero_result), zero_reference),
		"zero-radius circle query diverged from the reference set"
	)

	# 4) Fail-closed rejections: unknown shape, invalid radius, invalid
	#    direction, unavailable index/map.
	assert(
		service.query({"shape": "chain", "origin_ground_gu": Vector2.ZERO,
			"radius_gu": 5.0}).is_empty(),
		"unknown shape must fail closed"
	)
	assert(
		service.last_rejection_reason() != "",
		"unknown shape must report a rejection reason"
	)
	assert(
		service.query({"shape": "circle", "origin_ground_gu": Vector2.ZERO,
			"radius_gu": -1.0}).is_empty(),
		"negative radius must fail closed"
	)
	assert(
		service.query({"shape": "sector", "origin_ground_gu": Vector2.ZERO,
			"radius_gu": 5.0, "direction_ground": "not_a_vector"})
			.is_empty(),
		"invalid direction must fail closed"
	)
	var broken_service: CombatTargetQueryService = (
		CombatTargetQueryServiceScript.new(index, -1)
	)
	assert(
		broken_service.query({"shape": "circle",
			"origin_ground_gu": Vector2.ZERO, "radius_gu": 5.0}).is_empty(),
		"unavailable map must fail closed"
	)

	print("COMBAT_TARGET_QUERY_SERVICE_ORACLE_PASS")
	get_tree().quit(0)


func _random_request(rng: RandomNumberGenerator, shape: String) -> Dictionary:
	var origin := Vector2(
		rng.randf_range(-5.0, 105.0), rng.randf_range(-5.0, 105.0)
	)
	match shape:
		"circle":
			return {
				"shape": shape,
				"origin_ground_gu": origin,
				"radius_gu": rng.randf_range(0.0, 30.0),
			}
		"sector":
			return {
				"shape": shape,
				"origin_ground_gu": origin,
				"radius_gu": rng.randf_range(0.0, 30.0),
				"direction_ground": Vector2.RIGHT.rotated(
					rng.randf_range(-PI, PI)
				),
				"half_angle_rad": rng.randf_range(0.0, PI),
			}
		"capsule":
			var start := Vector2(
				rng.randf_range(-5.0, 105.0),
				rng.randf_range(-5.0, 105.0)
			)
			var end := Vector2(
				rng.randf_range(-5.0, 105.0),
				rng.randf_range(-5.0, 105.0)
			)
			return {
				"shape": shape,
				"origin_ground_gu": start,
				"start_ground_gu": start,
				"end_ground_gu": end,
				"half_width_gu": rng.randf_range(0.0, 8.0),
			}
		"cross":
			return {
				"shape": shape,
				"origin_ground_gu": origin,
				"arm_gu": rng.randf_range(0.0, 20.0),
				"half_width_gu": rng.randf_range(0.0, 6.0),
			}
		"single":
			return {
				"shape": shape,
				"origin_ground_gu": origin,
			}
	return {}


func _reference_set(
	actors: Array[Dictionary], shape: String, request: Dictionary
) -> Dictionary:
	var origin: Vector2 = request.get("origin_ground_gu", Vector2.INF)
	var hit: Dictionary = {}
	for actor: Dictionary in actors:
		var position: Vector2 = actor["position"]
		var bounds: float = actor["bounds"]
		var inside := false
		match shape:
			"circle":
				inside = origin.distance_to(position) <= (
					float(request["radius_gu"]) + bounds
				)
			"sector":
				var radius := float(request["radius_gu"])
				var half_angle := float(request["half_angle_rad"])
				if origin.distance_to(position) <= radius + bounds:
					if position == origin:
						inside = true
					else:
						var direction: Vector2 = request["direction_ground"]
						var delta := absf(wrapf(
							(position - origin).angle() - direction.angle(),
							-PI, PI
						))
						inside = delta <= half_angle
			"capsule":
				var start: Vector2 = request["start_ground_gu"]
				var end: Vector2 = request["end_ground_gu"]
				inside = _ref_segment_distance(position, start, end) <= (
					float(request["half_width_gu"]) + bounds
				)
			"cross":
				var arm := float(request["arm_gu"])
				var half_width := float(request["half_width_gu"])
				var horizontal := _ref_segment_distance(
					position, origin + Vector2(-arm, 0.0),
					origin + Vector2(arm, 0.0)
				)
				var vertical := _ref_segment_distance(
					position, origin + Vector2(0.0, -arm),
					origin + Vector2(0.0, arm)
				)
				inside = minf(horizontal, vertical) <= (
					half_width + bounds
				)
			"single":
				inside = origin.distance_to(position) <= bounds
		if inside:
			hit[actor["id"]] = true
	return hit


func _ref_segment_distance(
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


func _id_set(result: Array[Dictionary]) -> Dictionary:
	var ids: Dictionary = {}
	for candidate: Dictionary in result:
		ids[int(candidate["actor_runtime_id"])] = true
	return ids


func _service_ids_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a.keys():
		if not b.has(key):
			return false
	return true


func _assert_ordered(result: Array[Dictionary]) -> void:
	var previous := -1
	for candidate: Dictionary in result:
		var order := int(candidate["stable_combat_order"])
		assert(
			order >= previous,
			"service results must stay in stable combat order"
		)
		previous = order
