extends RefCounted
## Source-family integer oracle + EXPLICIT continuous project adapter.
## No scene, damage, collision or map ownership. Never floor live GU positions.
const CONTRACT_ID := "monster.source176.relative_cell_reach.adapter.v1"
const HALF_EXTENT_GU: float = 1.0
const EPSILON_GU: float = 0.0001

static func source_adjacent(a: Vector2i, b: Vector2i) -> bool:
    var offset: Vector2i = b - a
    return offset != Vector2i.ZERO and absi(offset.x) <= 1 and absi(offset.y) <= 1

static func continuous_adjacent(offset: Vector2, epsilon: float = EPSILON_GU) -> bool:
    if not offset.is_finite() or not is_finite(epsilon) or epsilon < 0.0:
        return false
    var extent: float = maxf(absf(offset.x), absf(offset.y))
    return extent > epsilon and extent <= HALF_EXTENT_GU + epsilon

static func broadphase_radius_gu() -> float:
    ## Candidate bound ONLY, not the attack predicate.
    return sqrt(2.0) * (HALF_EXTENT_GU + EPSILON_GU)

static func closest_goal(origin: Vector2, target: Vector2) -> Vector2:
    ## A static candidate. The caller must check WORLD, bodies and target access.
    if not origin.is_finite() or not target.is_finite():
        return Vector2.INF
    var d: Vector2 = origin - target
    return target + Vector2(clampf(d.x, -1.0, 1.0), clampf(d.y, -1.0, 1.0))

static func boundary_on_ray(direction: Vector2) -> Vector2:
    if not direction.is_finite():
        return Vector2.INF
    var extent: float = maxf(absf(direction.x), absf(direction.y))
    if extent <= EPSILON_GU:
        return Vector2.INF
    return direction / extent
