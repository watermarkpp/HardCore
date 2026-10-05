extends RefCounted
## Pure same-physics-frame substep arithmetic, not a movement implementation.
## The caller owns collision and must NOT pass a full physics delta to repeated
## move_and_slide(). No carry/debt may make a future frame exceed v*delta.
const MAX_SUBSTEPS: int = 4

static func desired_motion(origin: Vector2, endpoint: Vector2, speed_gu_per_sec: float, remaining_seconds: float) -> Vector2:
    if not origin.is_finite() or not endpoint.is_finite():
        return Vector2.ZERO
    if not is_finite(speed_gu_per_sec) or not is_finite(remaining_seconds):
        return Vector2.ZERO
    if speed_gu_per_sec <= 0.0 or remaining_seconds <= 0.0:
        return Vector2.ZERO
    var d: Vector2 = endpoint - origin
    var distance: float = d.length()
    if distance <= 0.000001:
        return Vector2.ZERO
    return d / distance * minf(distance, speed_gu_per_sec * remaining_seconds)

static func after_arrival(remaining_seconds: float, actual_legal_distance: float, speed_gu_per_sec: float) -> float:
    ## ONLY after unblocked arrival at the intended end of this substep.
    ## On collision/attack/control/new source wait, caller stops this frame.
    if not is_finite(remaining_seconds) or not is_finite(actual_legal_distance) or not is_finite(speed_gu_per_sec):
        return 0.0
    if remaining_seconds <= 0.0 or actual_legal_distance < 0.0 or speed_gu_per_sec <= 0.0:
        return 0.0
    return maxf(0.0, remaining_seconds - actual_legal_distance / speed_gu_per_sec)
