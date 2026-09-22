class_name WorldSpatialRules
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

# One collision contract for every runtime actor.  These values are bit masks,
# not the editor's one-based layer numbers.
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4

const WORLD_MASK := WORLD_LAYER
const PLAYER_MASK := WORLD_LAYER | ENEMY_LAYER
const ENEMY_MASK := WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER

const ACTOR_FOOTPRINT_CONTRACT_ID := "world.actor_footprint.iso_ellipse.v1"
const ACTOR_GROUND_FOOTPRINT_CONTRACT_ID := (
	"world.actor_footprint.ground_circle_gu.v1"
)
const SAFE_ZONE_CONTEXT_CONTRACT_ID := (
	"world.safe_zone.compiled_absolute_ground_gu.v1"
)
const SAFE_ZONE_GEOMETRY_EPSILON_GU := 0.000001
const ACTOR_FOOTPRINT_Y_RATIO := 0.5
const ACTOR_FOOTPRINT_SEGMENTS := 16
const SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU := (
	GroundUnitSpaceScript.HALF_TILE_SIZE_PX.x * sqrt(2.0)
)
static var _actor_footprint_unit_directions: PackedVector2Array = PackedVector2Array()


static func _actor_footprint_directions() -> PackedVector2Array:
	if _actor_footprint_unit_directions.is_empty():
		for index: int in range(ACTOR_FOOTPRINT_SEGMENTS):
			var angle := TAU * float(index) / float(ACTOR_FOOTPRINT_SEGMENTS)
			_actor_footprint_unit_directions.append(Vector2(
				cos(angle),
				sin(angle),
			))
	return _actor_footprint_unit_directions


static func actor_footprint_offset_px(
	index: int,
	collision_radius_px: float
) -> Vector2:
	var sample_radius_px := maxf(0.0, collision_radius_px)
	if sample_radius_px <= 0.0:
		return Vector2.ZERO
	var directions := _actor_footprint_directions()
	var direction := directions[posmod(index, directions.size())]
	return Vector2(
		direction.x * sample_radius_px,
		direction.y * sample_radius_px * ACTOR_FOOTPRINT_Y_RATIO,
	)


static func point_inside_safe_zone_ground_gu(
	point_ground_gu: Vector2,
	zone: Dictionary
) -> bool:
	if not point_ground_gu.is_finite():
		return false
	var shape := str(zone.get("shape", "circle"))
	if shape == "polygon":
		var raw_polygon: Variant = zone.get(
			"polygon_ground_gu", PackedVector2Array()
		)
		# A malformed polygon is never silently reinterpreted as a circle. The
		# compiler rejects formal authored data; this guard also keeps legacy
		# callers fail-closed when they bypass the compiler.
		if raw_polygon is PackedVector2Array:
			var polygon_ground_gu := raw_polygon as PackedVector2Array
			if polygon_ground_gu.size() < 3:
				return false
			return Geometry2D.is_point_in_polygon(
				point_ground_gu, polygon_ground_gu
			)
		if raw_polygon is Array:
			return _point_inside_safe_zone_polygon_array(
				point_ground_gu,
				raw_polygon as Array,
			)
		return false
	if shape != "circle":
		return false
	var center_variant: Variant = zone.get(
		"center_ground_gu", Vector2.INF
	)
	if not center_variant is Vector2:
		return false
	var center_ground_gu := center_variant as Vector2
	var radius_result := _safe_zone_float(zone.get("radius_gu", null))
	var radius_gu := float(radius_result.get("value", NAN))
	if (
		not center_ground_gu.is_finite()
		or not bool(radius_result.get("valid", false))
		or not is_finite(radius_gu)
		or radius_gu <= 0.0
	):
		return false
	return GroundUnitSpaceScript.is_within_range_gu(
		center_ground_gu,
		point_ground_gu,
		radius_gu
	)


## Compile authored safe-zone geometry once at map/content load. Callers keep
## this returned context by reference for the lifetime of the loaded map;
## runtime checks consume the packed polygon/AABB directly and never rebuild
## geometry in a monster hot loop.
static func compile_safe_zone_context(
	runtime_map_id: int,
	revision: int,
	generation: int,
	raw_zones: Variant,
) -> Dictionary:
	var context := {
		"contract_id": SAFE_ZONE_CONTEXT_CONTRACT_ID,
		"map_id": runtime_map_id,
		"revision": revision,
		"generation": generation,
		"valid": true,
		"failure_reason": "",
		"zones": [],
		"aabb_ground_gu": Rect2(),
	}
	if runtime_map_id < 0:
		return _invalid_safe_zone_context(context, "map_id_invalid")
	if not raw_zones is Array:
		return _invalid_safe_zone_context(context, "zones_not_array")
	var compiled_zones: Array = []
	var union_aabb := Rect2()
	var has_union_aabb := false
	for zone_index: int in range((raw_zones as Array).size()):
		var raw_zone: Variant = (raw_zones as Array)[zone_index]
		var compiled := _compile_safe_zone(
			raw_zone,
			zone_index,
		)
		if not bool(compiled.get("valid", false)):
			return _invalid_safe_zone_context(
				context,
				str(compiled.get("failure_reason", "zone_invalid")),
			)
		var zone := compiled.get("zone", {}) as Dictionary
		compiled_zones.append(zone)
		var zone_aabb: Rect2 = zone.get("aabb_ground_gu", Rect2())
		if not has_union_aabb:
			union_aabb = zone_aabb
			has_union_aabb = true
		else:
			union_aabb = union_aabb.merge(zone_aabb)
	context["zones"] = compiled_zones
	if has_union_aabb:
		context["aabb_ground_gu"] = union_aabb
	return context


static func _invalid_safe_zone_context(
	context: Dictionary,
	reason: String,
) -> Dictionary:
	context["valid"] = false
	context["failure_reason"] = reason
	context["zones"] = []
	context["aabb_ground_gu"] = Rect2()
	return context


static func _compile_safe_zone(
	raw_zone: Variant,
	zone_index: int,
) -> Dictionary:
	if not raw_zone is Dictionary:
		return {"valid": false, "failure_reason": "zone_not_dictionary"}
	var source := raw_zone as Dictionary
	if not source.has("shape"):
		return {"valid": false, "failure_reason": "shape_missing"}
	var shape := str(source.get("shape", "circle"))
	var zone := {
		"zone_index": zone_index,
		"zone_id": str(source.get(
			"area_id",
			source.get("semantic_id", "safe_zone_%d" % zone_index),
		)),
		"shape": shape,
		"center_ground_gu": Vector2.ZERO,
		"radius_gu": 0.0,
		"polygon_ground_gu": PackedVector2Array(),
		"aabb_ground_gu": Rect2(),
		"blocks_monster_damage": bool(source.get("blocks_monster_damage", false)),
		"blocks_monster_entry": bool(source.get("blocks_monster_entry", false)),
		"blocks_pvp": bool(source.get("blocks_pvp", false)),
		"return_anchor": bool(source.get("return_anchor", false)),
		"policy_override": str(source.get("policy_override", "")),
		"flags": {
			"blocks_monster_damage": bool(source.get("blocks_monster_damage", false)),
			"blocks_monster_entry": bool(source.get("blocks_monster_entry", false)),
			"blocks_pvp": bool(source.get("blocks_pvp", false)),
		},
		"policy": str(source.get("policy_override", "")),
	}
	var aabb := Rect2()
	if shape == "circle":
		var center_variant: Variant = source.get("center_ground_gu", null)
		var center_result := _safe_zone_vector2(center_variant)
		var radius_result := _safe_zone_float(source.get("radius_gu", null))
		var radius_gu := float(radius_result.get("value", NAN))
		if (
			not bool(center_result.get("valid", false))
			or not bool(radius_result.get("valid", false))
			or not is_finite(radius_gu)
			or radius_gu <= 0.0
		):
			return {"valid": false, "failure_reason": "circle_geometry_invalid"}
		var center_ground_gu: Vector2 = center_result.get("value", Vector2.INF)
		zone["center_ground_gu"] = center_ground_gu
		zone["radius_gu"] = radius_gu
		aabb = Rect2(
			center_ground_gu - Vector2.ONE * radius_gu,
			Vector2.ONE * radius_gu * 2.0,
		)
	elif shape == "polygon":
		var polygon_result := _safe_zone_polygon(
			source.get("polygon_ground_gu", null),
		)
		if not bool(polygon_result.get("valid", false)):
			return {
				"valid": false,
				"failure_reason": str(
					polygon_result.get("failure_reason", "polygon_geometry_invalid")
				),
			}
		var polygon: PackedVector2Array = polygon_result.get(
			"value",
			PackedVector2Array(),
		)
		zone["polygon_ground_gu"] = polygon
		var center_ground_gu := _safe_zone_polygon_centroid(polygon)
		if source.has("center_ground_gu"):
			var center_result := _safe_zone_vector2(
				source.get("center_ground_gu", null),
			)
			if not bool(center_result.get("valid", false)):
				return {"valid": false, "failure_reason": "polygon_center_invalid"}
			center_ground_gu = center_result.get(
				"value",
				Vector2.INF,
			)
		zone["center_ground_gu"] = center_ground_gu
		var minimum := polygon[0]
		var maximum := polygon[0]
		for point: Vector2 in polygon:
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
		aabb = Rect2(minimum, maximum - minimum)
	else:
		return {"valid": false, "failure_reason": "shape_unknown:%s" % shape}
	zone["aabb_ground_gu"] = aabb
	return {"valid": true, "zone": zone}


static func _safe_zone_vector2(raw_value: Variant) -> Dictionary:
	var value := Vector2.INF
	if raw_value is Vector2:
		value = raw_value as Vector2
	elif raw_value is Array and (raw_value as Array).size() >= 2:
		var raw_array := raw_value as Array
		var x_result := _safe_zone_float(raw_array[0])
		var y_result := _safe_zone_float(raw_array[1])
		if bool(x_result.get("valid", false)) and bool(y_result.get("valid", false)):
			value = Vector2(
				float(x_result.get("value", NAN)),
				float(y_result.get("value", NAN)),
			)
	if not value.is_finite():
		return {"valid": false, "value": Vector2.INF}
	return {"valid": true, "value": value}


static func _safe_zone_float(raw_value: Variant) -> Dictionary:
	var value_type := typeof(raw_value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return {"valid": false, "value": NAN}
	var value := float(raw_value)
	if not is_finite(value):
		return {"valid": false, "value": NAN}
	return {"valid": true, "value": value}


static func _safe_zone_polygon(raw_points: Variant) -> Dictionary:
	if not raw_points is Array and not raw_points is PackedVector2Array:
		return {"valid": false, "failure_reason": "polygon_not_array"}
	var polygon := PackedVector2Array()
	if raw_points is PackedVector2Array:
		polygon = raw_points as PackedVector2Array
	else:
		for raw_point: Variant in raw_points as Array:
			var point_result := _safe_zone_vector2(raw_point)
			if not bool(point_result.get("valid", false)):
				return {"valid": false, "failure_reason": "polygon_point_invalid"}
			polygon.append(point_result.get("value", Vector2.INF))
	if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	if polygon.size() < 3:
		return {"valid": false, "failure_reason": "polygon_too_few_points"}
	for point: Vector2 in polygon:
		if not point.is_finite():
			return {"valid": false, "failure_reason": "polygon_point_nonfinite"}
	var signed_area := 0.0
	for index: int in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		signed_area += polygon[index].cross(polygon[next_index])
		if polygon[index].distance_squared_to(polygon[next_index]) <= SAFE_ZONE_GEOMETRY_EPSILON_GU:
			return {"valid": false, "failure_reason": "polygon_degenerate_edge"}
	if absf(signed_area) <= SAFE_ZONE_GEOMETRY_EPSILON_GU:
		return {"valid": false, "failure_reason": "polygon_degenerate_area"}
	for first_index: int in range(polygon.size()):
		var first_next := (first_index + 1) % polygon.size()
		for second_index: int in range(first_index + 1, polygon.size()):
			var second_next := (second_index + 1) % polygon.size()
			if (
				first_index == second_index
				or first_next == second_index
				or second_next == first_index
			):
				continue
			if _safe_zone_segments_intersect(
				polygon[first_index],
				polygon[first_next],
				polygon[second_index],
				polygon[second_next],
			):
				return {"valid": false, "failure_reason": "polygon_self_intersecting"}
	return {"valid": true, "value": polygon}


static func _safe_zone_polygon_centroid(
	polygon: PackedVector2Array,
) -> Vector2:
	var total := Vector2.ZERO
	for point: Vector2 in polygon:
		total += point
	return total / float(maxi(1, polygon.size()))


static func _point_inside_safe_zone_polygon_array(
	point_ground_gu: Vector2,
	polygon: Array,
) -> bool:
	if polygon.size() < 3:
		return false
	var previous_result := _safe_zone_vector2(polygon[polygon.size() - 1])
	if not bool(previous_result.get("valid", false)):
		return false
	var previous: Vector2 = previous_result.get("value", Vector2.INF)
	var inside := false
	for raw_point: Variant in polygon:
		var current_result := _safe_zone_vector2(raw_point)
		if not bool(current_result.get("valid", false)):
			return false
		var current: Vector2 = current_result.get("value", Vector2.INF)
		if _safe_zone_point_on_segment(
			point_ground_gu,
			previous,
			current,
		):
			return true
		var crosses := (
			(previous.y > point_ground_gu.y)
			!= (current.y > point_ground_gu.y)
		)
		if crosses:
			var intersection_x := (
				(current.x - previous.x)
				* (point_ground_gu.y - previous.y)
				/ (current.y - previous.y)
				+ previous.x
			)
			if point_ground_gu.x < intersection_x:
				inside = not inside
		previous = current
	return inside


static func _safe_zone_segments_intersect(
	first_start: Vector2,
	first_end: Vector2,
	second_start: Vector2,
	second_end: Vector2,
	) -> bool:
	var first_a := (first_end - first_start).cross(second_start - first_start)
	var first_b := (first_end - first_start).cross(second_end - first_start)
	var second_a := (second_end - second_start).cross(first_start - second_start)
	var second_b := (second_end - second_start).cross(first_end - second_start)
	var epsilon := SAFE_ZONE_GEOMETRY_EPSILON_GU
	if absf(first_a) <= epsilon and _safe_zone_point_on_segment(
		second_start, first_start, first_end
	):
		return true
	if absf(first_b) <= epsilon and _safe_zone_point_on_segment(
		second_end, first_start, first_end
	):
		return true
	if absf(second_a) <= epsilon and _safe_zone_point_on_segment(
		first_start, second_start, second_end
	):
		return true
	if absf(second_b) <= epsilon and _safe_zone_point_on_segment(
		first_end, second_start, second_end
	):
		return true
	return (
		((first_a > epsilon and first_b < -epsilon) or (first_a < -epsilon and first_b > epsilon))
		and ((second_a > epsilon and second_b < -epsilon) or (second_a < -epsilon and second_b > epsilon))
	)


static func _safe_zone_point_on_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2,
	) -> bool:
	return (
		point.x >= minf(segment_start.x, segment_end.x) - SAFE_ZONE_GEOMETRY_EPSILON_GU
		and point.x <= maxf(segment_start.x, segment_end.x) + SAFE_ZONE_GEOMETRY_EPSILON_GU
		and point.y >= minf(segment_start.y, segment_end.y) - SAFE_ZONE_GEOMETRY_EPSILON_GU
		and point.y <= maxf(segment_start.y, segment_end.y) + SAFE_ZONE_GEOMETRY_EPSILON_GU
	)


static func point_inside_safe_zones_ground_gu(
	point_ground_gu: Vector2,
	zones: Array
) -> bool:
	for zone: Variant in zones:
		if (
			zone is Dictionary
			and point_inside_safe_zone_ground_gu(point_ground_gu, zone)
		):
			return true
	return false


static func project_outside_safe_zones_ground_gu(
	point_ground_gu: Vector2,
	zones: Array,
	padding_gu := 0.0
) -> Vector2:
	var projected_ground_gu := point_ground_gu
	for zone: Variant in zones:
		if (
			not zone is Dictionary
			or not point_inside_safe_zone_ground_gu(
				projected_ground_gu, zone
			)
		):
			continue
		if str(zone.get("shape", "circle")) != "circle":
			continue
		var center_ground_gu: Vector2 = zone.get(
			"center_ground_gu", Vector2.ZERO
		)
		var direction_ground := GroundUnitSpaceScript.normalized_ground_direction(
			center_ground_gu,
			projected_ground_gu
		)
		projected_ground_gu = GroundUnitSpaceScript.endpoint_ground_gu(
			center_ground_gu,
			direction_ground,
			maxf(0.0, float(zone.get("radius_gu", 0.0)))
			+ maxf(0.0, padding_gu)
		)
	return projected_ground_gu


static func environment_blocks_actor_screen_px(
	provider: Node,
	position_screen_px: Vector2,
	collision_radius_px: float
) -> bool:
	var environment_started_usec := RuntimeDiagnostics.timing_start()
	RuntimeDiagnostics.increment_performance_counter(&"environment_guard_batches")
	if not is_instance_valid(provider):
		RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
		return false
	if provider.has_method("is_environment_actor_blocked"):
		var blocked := bool(provider.call(
			"is_environment_actor_blocked",
			position_screen_px,
			collision_radius_px,
		))
		RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
		return blocked
	if not provider.has_method("is_environment_point_blocked"):
		RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
		return false
	RuntimeDiagnostics.increment_performance_counter(&"environment_point_samples")
	if bool(provider.call("is_environment_point_blocked", position_screen_px)):
		RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
		return true
	# Physics remains authoritative for sliding.  These samples are the common
	# deterministic fallback used by both player and monsters when collision
	# chunks are rebuilt or a spawn/teleport bypasses move_and_slide().
	var sample_radius_px := maxf(0.0, collision_radius_px - 1.0)
	if sample_radius_px <= 0.0:
		RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
		return false
	for index: int in range(ACTOR_FOOTPRINT_SEGMENTS):
		var offset_px := actor_footprint_offset_px(index, sample_radius_px)
		RuntimeDiagnostics.increment_performance_counter(&"environment_point_samples")
		if bool(provider.call(
			"is_environment_point_blocked",
			position_screen_px + offset_px
		)):
			RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
			return true
	RuntimeDiagnostics.record_timing_usec(&"environment_query_usec", environment_started_usec)
	return false


static func actor_footprint_radii_px(collision_radius_px: float) -> Vector2:
	var horizontal_radius_px := maxf(0.0, collision_radius_px)
	return Vector2(
		horizontal_radius_px,
		horizontal_radius_px * ACTOR_FOOTPRINT_Y_RATIO
	)


static func actor_combat_radius_gu_from_screen_radius_px(
	screen_horizontal_radius_px: float
) -> float:
	return (
		maxf(0.0, screen_horizontal_radius_px)
		/ SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU
	)


static func actor_screen_radius_px_from_combat_radius_gu(
	combat_radius_gu: float
) -> float:
	return (
		maxf(0.0, combat_radius_gu)
		* SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU
	)


static func actor_footprint_ground_polygon_gu(
	combat_radius_gu: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var safe_radius_gu := maxf(0.0, combat_radius_gu)
	var count := maxi(8, segments)
	var points_ground_gu := PackedVector2Array()
	var directions := _actor_footprint_directions() if count == ACTOR_FOOTPRINT_SEGMENTS else PackedVector2Array()
	for index: int in range(count):
		if count == ACTOR_FOOTPRINT_SEGMENTS:
			points_ground_gu.append(directions[index] * safe_radius_gu)
		else:
			var angle := TAU * float(index) / float(count)
			points_ground_gu.append(
				Vector2.from_angle(angle) * safe_radius_gu
			)
	return points_ground_gu


static func actor_footprint_screen_polygon_px_from_combat_radius_gu(
	combat_radius_gu: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var points_screen_px := PackedVector2Array()
	for point_ground_gu: Vector2 in actor_footprint_ground_polygon_gu(
		combat_radius_gu,
		segments
	):
		points_screen_px.append(
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				point_ground_gu
			)
		)
	return points_screen_px


static func actor_footprint_polygon_px(
	collision_radius_px: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var radii_px := actor_footprint_radii_px(collision_radius_px)
	var count := maxi(8, segments)
	var points_px := PackedVector2Array()
	if count == ACTOR_FOOTPRINT_SEGMENTS:
		for index: int in range(count):
			points_px.append(actor_footprint_offset_px(index, radii_px.x))
		return points_px
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points_px.append(Vector2(
			cos(angle) * radii_px.x,
			sin(angle) * radii_px.y
		))
	return points_px


static func actor_footprint_shape_px(
	collision_radius_px: float
) -> ConvexPolygonShape2D:
	var shape := ConvexPolygonShape2D.new()
	shape.points = actor_footprint_polygon_px(collision_radius_px)
	return shape
