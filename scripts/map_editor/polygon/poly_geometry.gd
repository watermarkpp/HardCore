extends RefCounted
## HC-POLY-R1. Pure geometry. All arguments are map-global Ground GU.
## No screen pixels, grid rounding, resources, scene nodes or mutable globals.
const EPS := 0.000001
const MAX_VERTICES := 128
const MAX_PARTS := 16384
const AUTHORITY := "hc_polygon_v1"
const CONTRACT := "hc.map.polygon_ground_gu.v1"
const PHYSICS_SOURCE := "published_convex_polygon_parts_gu.v1"

static func enabled(document: Dictionary) -> bool:
	return str(document.get("editor_meta", {}).get("collision_authority", "")) == AUTHORITY

static func runtime_enabled(runtime: Dictionary) -> bool:
	var collision: Variant = runtime.get("collision", {})
	return collision is Dictionary and str(collision.get("coordinate_contract_id", "")) == CONTRACT

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func parse_size(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i.ZERO
	for v: Variant in value:
		if not numeric(v) or float(v) <= 0.0 or float(v) != floorf(float(v)) or float(v) > 4096.0:
			return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))

static func encode(points: PackedVector2Array) -> Array:
	var result: Array = []
	for p: Vector2 in points:
		result.append([p.x, p.y])
	return result

static func decode(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for raw: Variant in value:
		if not raw is Array or raw.size() != 2 or not numeric(raw[0]) or not numeric(raw[1]):
			return PackedVector2Array()
		result.append(Vector2(float(raw[0]), float(raw[1])))
	return result

static func area(points: PackedVector2Array) -> float:
	var result := 0.0
	for i: int in range(points.size()):
		result += points[i].cross(points[(i + 1) % points.size()])
	return result * 0.5

static func validate(raw: Variant, design_size: Vector2i) -> Dictionary:
	var p := decode(raw)
	var errors: Array[String] = []
	if design_size.x <= 0 or design_size.y <= 0:
		errors.append("polygon_design_size_invalid")
	if p.size() < 3 or p.size() > MAX_VERTICES:
		errors.append("polygon_vertex_count_or_coordinate_invalid")
		return {"ok": false, "errors": errors, "points": p}
	for i: int in range(p.size()):
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		var c := p[(i + 2) % p.size()]
		if a.x < -EPS or a.y < -EPS or a.x > design_size.x + EPS or a.y > design_size.y + EPS:
			errors.append("polygon_outside_map")
		if a.distance_squared_to(b) <= EPS * EPS:
			errors.append("polygon_duplicate_adjacent_vertex")
		if absf((b - a).cross(c - b)) <= EPS and (b - a).dot(c - b) < 0.0:
			errors.append("polygon_backtracking_edge")
		for j: int in range(i + 1, p.size()):
			if j == i + 1 or (i == 0 and j == p.size() - 1):
				continue
			if segments_touch(a, b, p[j], p[(j + 1) % p.size()]):
				errors.append("polygon_self_intersection")
	if absf(area(p)) <= EPS:
		errors.append("polygon_zero_area")
	if errors.is_empty() and Geometry2D.is_polygon_clockwise(p):
		p.reverse()
	return {"ok": errors.is_empty(), "errors": errors, "points": p}

static func convex(points: PackedVector2Array) -> bool:
	var sign_value := 0.0
	for i: int in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var c := points[(i + 2) % points.size()]
		var turn := (b - a).cross(c - b)
		if absf(turn) <= EPS:
			continue
		if sign_value != 0.0 and sign_value * turn < 0.0:
			return false
		sign_value = turn
	return sign_value != 0.0

static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		box = box.expand(p)
	return box

static func distance_squared_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var length_squared := d.length_squared()
	if length_squared <= EPS * EPS:
		return p.distance_squared_to(a)
	return p.distance_squared_to(a + d * clampf((p - a).dot(d) / length_squared, 0.0, 1.0))

static func nearest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var delta := b - a
	if delta.length_squared() <= EPS * EPS:
		return a
	return a + delta * clampf((p - a).dot(delta) / delta.length_squared(), 0.0, 1.0)

static func segments_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var x := (b - a).cross(c - a)
	var y := (b - a).cross(d - a)
	var z := (d - c).cross(a - c)
	var w := (d - c).cross(b - c)
	if ((x > EPS and y < -EPS) or (x < -EPS and y > EPS)) and ((z > EPS and w < -EPS) or (z < -EPS and w > EPS)):
		return true
	return (absf(x) <= EPS and distance_squared_to_segment(c, a, b) <= EPS * EPS
		or absf(y) <= EPS and distance_squared_to_segment(d, a, b) <= EPS * EPS
		or absf(z) <= EPS and distance_squared_to_segment(a, c, d) <= EPS * EPS
		or absf(w) <= EPS and distance_squared_to_segment(b, c, d) <= EPS * EPS)

static func segment_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if segments_touch(a, b, c, d):
		return 0.0
	return minf(minf(distance_squared_to_segment(a, c, d), distance_squared_to_segment(b, c, d)),
		minf(distance_squared_to_segment(c, a, b), distance_squared_to_segment(d, a, b)))

static func capsule_hits_polygon(a: Vector2, b: Vector2, radius_gu: float, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(a, polygon) or Geometry2D.is_point_in_polygon(b, polygon):
		return true
	var inner_radius := maxf(0.0, radius_gu - EPS)
	for i: int in range(polygon.size()):
		var c := polygon[i]
		var d := polygon[(i + 1) % polygon.size()]
		if segments_touch(a, b, c, d):
			return true
		if radius_gu > 0.0 and segment_distance_squared(a, b, c, d) < inner_radius * inner_radius:
			return true
	return false

static func convex_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	## Separating-axis test; exact tangency is not penetration.
	for polygon: PackedVector2Array in [a, b]:
		for i: int in range(polygon.size()):
			var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
			var axis := Vector2(-edge.y, edge.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for point: Vector2 in a:
				var projection := point.dot(axis)
				amin = minf(amin, projection)
				amax = maxf(amax, projection)
			for point: Vector2 in b:
				var projection := point.dot(axis)
				bmin = minf(bmin, projection)
				bmax = maxf(bmax, projection)
			if amax <= bmin + EPS or bmax <= amin + EPS:
				return false
	return true

static func rectangle_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

static func subtract_rectangle(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var intersection := rect.intersection(cut)
	if not intersection.has_area():
		return [rect]
	var result: Array[Rect2] = []
	var candidates: Array[Rect2] = [
		Rect2(rect.position, Vector2(rect.size.x, intersection.position.y - rect.position.y)),
		Rect2(Vector2(rect.position.x, intersection.end.y), Vector2(rect.size.x, rect.end.y - intersection.end.y)),
		Rect2(Vector2(rect.position.x, intersection.position.y), Vector2(intersection.position.x - rect.position.x, intersection.size.y)),
		Rect2(Vector2(intersection.end.x, intersection.position.y), Vector2(rect.end.x - intersection.end.x, intersection.size.y)),
	]
	for piece: Rect2 in candidates:
		if piece.size.x > EPS and piece.size.y > EPS:
			result.append(piece)
	return result
