class_name AoeEngagementWindow
extends RefCounted

## AOE first-engagement window probe (perf-smoothness-r1 Phase A).
##
## Replaces the retired 12-process-delta [FW-FIRST-CAST] probe. The old probe
## had two defects found by the 2026-09-18 remote audit:
##  1. It recorded clamped `_process(delta)` values, and the engine clamps
##     process delta at max_physics_steps_per_frame / physics_ticks_per_second
##     (8/60 = 0.133s by default), so a real 300ms stall records as 133ms.
##  2. A 12-frame window (~0.2s at 60Hz) cannot cover the actual first AOE
##     engagement: field spawn, first damage tick and the first batch death
##     all happen after the windup and were never observed.
##
## This probe instead records the real wall-clock frame intervals (fed by
## GameRoot from Time.get_ticks_usec, never from clamped delta) between the
## first wizard.fire_wall cast and the first committed enemy death, with a
## hard window deadline. It is a one-shot per process, prints exactly one
## summary line, and keeps a bounded sample array. Release builds are a
## complete no-op. It is diagnostics only: no gameplay, damage, audio, or
## save side effects, and no per-frame print.

const FIRE_WALL_SKILL_ID := "wizard.fire_wall"
## ~25s of 60Hz frames; overflowing only truncates the retained percentile
## window and is disclosed via frames_dropped, never a memory leak.
const MAX_SAMPLES := 1500
const DEFAULT_WINDOW_DEADLINE_MS := 12000.0
const REASON_COMPLETE := "complete"
const REASON_DEADLINE := "deadline"

static var _active := false
static var _reported := false
static var _cast_start_usec := 0
static var _deadline_ms := DEFAULT_WINDOW_DEADLINE_MS
static var _cast_to_field_ms := -1.0
static var _cast_to_tick_ms := -1.0
static var _cast_to_death_ms := -1.0
static var _frame_intervals_ms: Array[float] = []
static var _frames_dropped := 0
static var _last_report: Dictionary = {}


static func on_skill_cast(stable_skill_id: String) -> void:
	if not OS.is_debug_build() or _reported or _active:
		return
	if stable_skill_id != FIRE_WALL_SKILL_ID:
		return
	_active = true
	_cast_start_usec = Time.get_ticks_usec()
	_cast_to_field_ms = -1.0
	_cast_to_tick_ms = -1.0
	_cast_to_death_ms = -1.0
	_frame_intervals_ms.clear()
	_frames_dropped = 0


static func on_field_spawned(stable_skill_id: String) -> void:
	if not OS.is_debug_build() or not _active:
		return
	if stable_skill_id != FIRE_WALL_SKILL_ID or _cast_to_field_ms >= 0.0:
		return
	_cast_to_field_ms = _elapsed_ms()


static func on_ground_damage_tick(stable_skill_id: String) -> void:
	if not OS.is_debug_build() or not _active:
		return
	# perf-smoothness-r1 C-R1 (PERF-R2 R9): the tick milestone must actually
	# gate on the fire-wall skill id - an unrelated ground tick from another
	# skill must not open this window's milestone.
	if stable_skill_id != FIRE_WALL_SKILL_ID:
		return
	if _cast_to_tick_ms >= 0.0:
		return
	_cast_to_tick_ms = _elapsed_ms()


## perf-smoothness-r1 C-R1 (PERF-R2 R9): NON-CAUSAL milestone. The current
## death pipeline carries no reliable source_skill_id, so this records
## first_any_death_after_fire_wall_cast - NOT fire_wall_caused_death. It
## must never be used as evidence that the fire wall caused the kill.
static func on_enemy_death_committed() -> void:
	if not OS.is_debug_build() or not _active or _cast_to_death_ms >= 0.0:
		return
	_cast_to_death_ms = _elapsed_ms()
	_maybe_report()


## Called once per rendered frame by GameRoot while the window is active.
## A negative interval means the frame-gap recorder discarded the sample
## (process boundary such as app pause), so the window skips it.
static func record_frame_interval_ms(interval_ms: float) -> void:
	if not _active:
		return
	if float(Time.get_ticks_usec() - _cast_start_usec) / 1000.0 > _deadline_ms:
		_report(REASON_DEADLINE)
		return
	if interval_ms < 0.0:
		return
	if _frame_intervals_ms.size() >= MAX_SAMPLES:
		_frames_dropped += 1
		return
	_frame_intervals_ms.append(interval_ms)
	if _cast_to_death_ms >= 0.0:
		_maybe_report()


static func window_active() -> bool:
	return _active


static func is_reported() -> bool:
	return _reported


static func last_report() -> Dictionary:
	return _last_report.duplicate()


static func _elapsed_ms() -> float:
	return float(Time.get_ticks_usec() - _cast_start_usec) / 1000.0


static func _maybe_report() -> void:
	if _cast_to_field_ms < 0.0 or _cast_to_tick_ms < 0.0 or _cast_to_death_ms < 0.0:
		return
	_report(REASON_COMPLETE)


static func _report(reason: String) -> void:
	_active = false
	_reported = true
	var samples: Array[float] = _frame_intervals_ms
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var p95 := 0.0
	var max_ms := 0.0
	var over33 := 0
	var over50 := 0
	var over100 := 0
	for sample in sorted:
		max_ms = maxf(max_ms, sample)
		if sample > 33.3: over33 += 1
		if sample > 50.0: over50 += 1
		if sample > 100.0: over100 += 1
	if not sorted.is_empty():
		p95 = sorted[clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)]
	_last_report = {
		"reason": reason,
		"cast_to_field_ms": _cast_to_field_ms,
		"cast_to_tick_ms": _cast_to_tick_ms,
		# NON-CAUSAL (PERF-R2 R9): first death of ANY monster after the cast,
		# not evidence of a fire-wall-caused kill.
		"cast_to_first_any_death_ms": _cast_to_death_ms,
		"milestone_causality": "non_causal_first_any_death",
		"frames": sorted.size(),
		"frames_dropped": _frames_dropped,
		"over33": over33,
		"over50": over50,
		"over100": over100,
		"p95_ms": p95,
		"max_ms": max_ms,
	}
	print(
		"[AOE-WINDOW] reason=%s cast_to_field_ms=%.1f cast_to_tick_ms=%.1f cast_to_first_any_death_ms=%.1f(non-causal) frames=%d frames_dropped=%d over33=%d over50=%d over100=%d p95_ms=%.1f max_ms=%.1f"
		% [
			reason,
			_cast_to_field_ms,
			_cast_to_tick_ms,
			_cast_to_death_ms,
			sorted.size(),
			_frames_dropped,
			over33,
			over50,
			over100,
			p95,
			max_ms,
		]
	)
	_frame_intervals_ms.clear()


## ---- Test-only helpers (no production caller) ----

static func reset_for_tests() -> void:
	_active = false
	_reported = false
	_cast_start_usec = 0
	_deadline_ms = DEFAULT_WINDOW_DEADLINE_MS
	_cast_to_field_ms = -1.0
	_cast_to_tick_ms = -1.0
	_cast_to_death_ms = -1.0
	_frame_intervals_ms.clear()
	_frames_dropped = 0
	_last_report = {}


static func set_window_deadline_ms(deadline_ms: float) -> void:
	# Test injection only: production keeps DEFAULT_WINDOW_DEADLINE_MS.
	_deadline_ms = maxf(1.0, deadline_ms)
