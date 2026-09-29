extends RefCounted
## Source GotoTargetXY heading structure. Fractional shortening is a project
## adapter. It does not authorize movement or spend another cadence grant.
const EPSILON: float = 0.000001

static func next_leg(origin: Vector2, stable_waypoint: Vector2, component_budget: float = 1.0) -> Vector2:
    if not origin.is_finite() or not stable_waypoint.is_finite():
        return Vector2.INF
    if not is_finite(component_budget) or component_budget <= 0.0:
        return Vector2.INF
    var d: Vector2 = stable_waypoint - origin
    var sx: float = 0.0 if absf(d.x) <= EPSILON else signf(d.x)
    var sy: float = 0.0 if absf(d.y) <= EPSILON else signf(d.y)
    if sx != 0.0 and sy != 0.0:
        var extent: float = minf(component_budget, minf(absf(d.x), absf(d.y)))
        return origin + Vector2(sx, sy) * extent
    if sx != 0.0:
        return origin + Vector2(sx * minf(absf(d.x), component_budget), 0.0)
    if sy != 0.0:
        return origin + Vector2(0.0, sy * minf(absf(d.y), component_budget))
    return stable_waypoint

static func octile_distance(offset: Vector2) -> float:
    if not offset.is_finite():
        return INF
    var a: Vector2 = offset.abs()
    return maxf(a.x, a.y) + (sqrt(2.0) - 1.0) * minf(a.x, a.y)

static func is_eight_way(offset: Vector2, epsilon: float = EPSILON) -> bool:
    if not offset.is_finite():
        return false
    return absf(offset.x) <= epsilon or absf(offset.y) <= epsilon or absf(absf(offset.x) - absf(offset.y)) <= epsilon
