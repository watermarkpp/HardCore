extends RefCounted

## Single owner of the original MonsterVisual action FIFO and struck interval.
## All time and owner state arrive as values; this object has no scene, clock,
## autoload, resource or actor reference. The legacy visual and S actor model
## use the same rule implementation, never independent countdowns.
const QUEUE_CAPACITY := 16
const STRUCK := 0
const ATTACK := 1

var presentation_kind := PackedByteArray()
var presentation_duration := PackedFloat32Array()
var presentation_step_barrier := PackedInt32Array()
var presentation_head := 0
var presentation_tail := 0
var presentation_count := 0
var pending_struck_count := 0
var hit_remaining := 0.0
var hit_duration := 0.22
var attack_remaining := 0.0
var attack_duration := 0.46
var attack_action_id := -1
var motion_overridden_attack_action_id := -1

# Value results consumed by the adapter after a rule operation. Starting more
# than one hit in a single interval leaves the final authored duration here.
# The render-only resets (walk pose and frame elapsed) are idempotent.
var hit_start_serial := 0
var dequeued_duration := 0.0
var last_backpressure_collapsed := 0
var last_enqueue_overflow := false


func _init() -> void:
	presentation_kind.resize(QUEUE_CAPACITY)
	presentation_duration.resize(QUEUE_CAPACITY)
	presentation_step_barrier.resize(QUEUE_CAPACITY)


func clear_queue() -> void:
	presentation_head = 0
	presentation_tail = 0
	presentation_count = 0
	pending_struck_count = 0


func merge_pending_struck_feedback() -> int:
	if presentation_count <= 0:
		return 0
	var merged := 0
	var kept_kind := -1
	var kept_duration := 0.0
	var kept_barrier := -1
	for i in presentation_count:
		var idx := (presentation_head + i) % QUEUE_CAPACITY
		var kind: int = presentation_kind[idx]
		if kind == STRUCK:
			# Oldest -> newest iteration deliberately overwrites every match.
			kept_kind = kind
			kept_duration = presentation_duration[idx]
			kept_barrier = presentation_step_barrier[idx]
		merged += 1
	clear_queue()
	if kept_kind == STRUCK:
		presentation_kind[0] = kept_kind
		presentation_duration[0] = kept_duration
		presentation_step_barrier[0] = kept_barrier
		presentation_head = 0
		presentation_tail = 1
		presentation_count = 1
		pending_struck_count = 1
	return merged


func enqueue(kind: int, duration: float, step_barrier := -1) -> void:
	last_backpressure_collapsed = 0
	last_enqueue_overflow = false
	if presentation_count >= QUEUE_CAPACITY and pending_struck_count > 0:
		var collapsed := merge_pending_struck_feedback()
		if collapsed > 1:
			last_backpressure_collapsed = collapsed - 1
	if presentation_count >= QUEUE_CAPACITY:
		last_enqueue_overflow = true
		return
	presentation_kind[presentation_tail] = kind
	presentation_duration[presentation_tail] = duration
	presentation_step_barrier[presentation_tail] = step_barrier
	presentation_tail = (presentation_tail + 1) % QUEUE_CAPACITY
	presentation_count += 1
	if kind == STRUCK:
		pending_struck_count += 1


func start_struck(duration: float) -> void:
	hit_remaining = duration
	hit_duration = duration
	hit_start_serial += 1


func start_attack(duration: float) -> void:
	attack_remaining = duration
	attack_duration = float(duration)


func try_start_next(logic_bound: bool, owner_attack_active: bool, death_blocked: bool) -> int:
	if presentation_count <= 0:
		return -1
	if hit_remaining > 0.0 or attack_remaining > 0.0:
		return -1
	if logic_bound and owner_attack_active:
		return -1
	if death_blocked:
		return -1
	var kind: int = presentation_kind[presentation_head]
	dequeued_duration = presentation_duration[presentation_head]
	presentation_head = (presentation_head + 1) % QUEUE_CAPACITY
	presentation_count -= 1
	if kind == STRUCK:
		pending_struck_count -= 1
		start_struck(dequeued_duration)
	return kind


func refresh_attack_remaining(visual_attack_age: float) -> void:
	attack_remaining = maxf(0.0, attack_duration - visual_attack_age)


func advance_visual_attack_cache(visual_attack_age: float) -> void:
	if attack_remaining > 0.0:
		if motion_overridden_attack_action_id == attack_action_id:
			attack_remaining = 0.0
		else:
			refresh_attack_remaining(visual_attack_age)


func advance_preview_hit(delta: float, speed_multiplier: float) -> void:
	hit_remaining = maxf(0.0, hit_remaining - delta * speed_multiplier)


## The owner has already advanced its H clock and closed completed attacks.
## Count only the part of this interval outside the committed attack. Each
## queued hit consumes its full authored duration, without backlog speedup.
func advance_struck(
	delta: float,
	clock_now: float,
	owner_attack_active: bool,
	owner_action_start: float,
	owner_action_duration: float,
	visual_attack_age: float,
	death_blocked: bool,
) -> float:
	var available := maxf(0.0, delta)
	if available <= 0.0 or death_blocked:
		return 0.0
	if owner_attack_active:
		attack_remaining = 0.0 if motion_overridden_attack_action_id == attack_action_id else maxf(
			0.0, attack_duration - visual_attack_age
		)
		return 0.0
	var interval_start := clock_now - available
	var action_duration := maxf(0.0, owner_action_duration)
	var action_end := owner_action_start + action_duration
	var attack_left := 0.0
	if action_duration > 0.0 and owner_action_start >= 0.0:
		var overlap_start := maxf(interval_start, owner_action_start)
		var overlap_end := minf(clock_now, action_end)
		var attack_overlap := maxf(0.0, overlap_end - overlap_start)
		attack_left = attack_overlap
		if motion_overridden_attack_action_id != attack_action_id:
			refresh_attack_remaining(visual_attack_age)
	if attack_left > 0.0:
		available -= attack_left
	if available <= 0.0:
		return 0.0
	var paused := 0.0
	while available > 0.0:
		if hit_remaining <= 0.0:
			if presentation_count <= 0:
				break
			if presentation_kind[presentation_head] != STRUCK:
				break
			var duration := presentation_duration[presentation_head]
			presentation_head = (presentation_head + 1) % QUEUE_CAPACITY
			presentation_count -= 1
			pending_struck_count = maxi(0, pending_struck_count - 1)
			start_struck(duration)
		var consumed := minf(available, hit_remaining)
		hit_remaining = maxf(0.0, hit_remaining - consumed)
		available -= consumed
		paused += consumed
		if consumed <= 0.0:
			break
	return paused


func is_struck_action_active() -> bool:
	return hit_remaining > 0.000001


func cancel_for_death() -> void:
	hit_remaining = 0.0
	attack_remaining = 0.0
	clear_queue()
