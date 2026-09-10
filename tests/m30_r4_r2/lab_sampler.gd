extends Node

# Late callbacks: NEVER sample current animation from the pre-physics signal.
# process cadence is NOT GPU time and physics cadence is NOT complete frame time.
signal after_physics
signal after_visual
var render_intervals_ms: Array[float] = []
var physics_intervals_ms: Array[float] = []
var capture: bool = false
var _last_render_usec: int = 0
var _last_physics_usec: int = 0

func _ready() -> void:
	process_priority = 1000000
	process_physics_priority = 1000000

func begin_window() -> void:
	render_intervals_ms.clear()
	physics_intervals_ms.clear()
	_last_render_usec = 0
	_last_physics_usec = 0
	capture = true

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if capture and _last_render_usec > 0:
		render_intervals_ms.append(float(now - _last_render_usec) / 1000.0)
	_last_render_usec = now
	after_visual.emit()

func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if capture and _last_physics_usec > 0:
		physics_intervals_ms.append(float(now - _last_physics_usec) / 1000.0)
	_last_physics_usec = now
	after_physics.emit()

static func statistics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"valid": false, "count": 0}
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	var above_33: int = 0
	var above_50: int = 0
	for value: float in ordered:
		if value > 1000.0 / 30.0:
			above_33 += 1
		if value > 50.0:
			above_50 += 1
	return {
		"valid": true, "count": ordered.size(),
		"p50_ms": ordered[maxi(0, ceili(0.50 * ordered.size()) - 1)],
		"p95_ms": ordered[maxi(0, ceili(0.95 * ordered.size()) - 1)],
		"p99_ms": ordered[maxi(0, ceili(0.99 * ordered.size()) - 1)],
		"max_ms": ordered[-1], "over_33p333_ms": above_33, "over_50_ms": above_50,
		"estimator": "nearest_rank_diagnostic_only",
	}
