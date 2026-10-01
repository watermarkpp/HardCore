extends RefCounted
## TEST ONLY. Independent expectations; never call this from production.
const EPS := 0.0001

static func in_box(offset: Vector2, extent := 1.0) -> bool:
	if not offset.is_finite() or not is_finite(extent) or extent <= 0.0:
		return false
	var magnitude := maxf(absf(offset.x), absf(offset.y))
	return magnitude > EPS and magnitude <= extent + EPS

static func next_leg(origin: Vector2, waypoint: Vector2) -> Vector2:
	if not origin.is_finite() or not waypoint.is_finite():
		return Vector2.INF
	var d := waypoint - origin
	var sx := 0.0 if absf(d.x) <= 0.000001 else signf(d.x)
	var sy := 0.0 if absf(d.y) <= 0.000001 else signf(d.y)
	if sx != 0.0 and sy != 0.0:
		return origin + Vector2(sx, sy) * minf(1.0, minf(absf(d.x), absf(d.y)))
	if sx != 0.0:
		return origin + Vector2(sx * minf(1.0, absf(d.x)), 0.0)
	if sy != 0.0:
		return origin + Vector2(0.0, sy * minf(1.0, absf(d.y)))
	return waypoint

static func parallel_forward(actual: Vector2, expected: Vector2) -> bool:
	if not actual.is_finite() or not expected.is_finite():
		return false
	if actual.length_squared() <= 0.0000000001 or expected.length_squared() <= 0.0000000001:
		return false
	return actual.dot(expected) > 0.0 and absf(actual.normalized().cross(expected.normalized())) <= 0.0001
