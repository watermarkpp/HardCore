extends RefCounted

## Presentation-only integration. A render frame advances this state once;
## Camera2D canvas queries and transform notifications never advance time.
const RESPONSE_PER_SECOND := 7.0

static func advance(center: Vector2, target: Vector2, delta: float) -> Vector2:
	if not target.is_finite():
		return center
	if not center.is_finite():
		return target
	if not is_finite(delta) or delta <= 0.0:
		return center
	# Exact first-order response: identical elapsed time for a fixed target has
	# identical results at any refresh rate; even a long frame cannot overshoot.
	return center.lerp(target, 1.0 - exp(-RESPONSE_PER_SECOND * delta))
