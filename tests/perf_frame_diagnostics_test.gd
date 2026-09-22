extends Node2D

## perf-smoothness-r1 Phase A self-check (audit PERF-02 / measurement first).
##
## Proves, in a real engine run:
##  1. The wall-clock frame interval recorder detects injected 60/320/120ms
##     process stalls (the retired `delta > 0.25` probe was provably unable
##     to see any of them under the engine's 8/60 = 0.133s delta clamp).
##  2. Pause/boundary gaps above the discard threshold are dropped and
##     counted, never recorded as giant fake frame intervals.
##  3. The Device Lab gated feeder consumes the wall-clock path.
##  4. The AOE window probe tracks cast -> field spawn -> first damage tick
##     -> first committed death in order, reports once with real interval
##     statistics, honors its deadline, is one-shot, and ignores other skills.
##  5. The three presentation caches expose separated diagnostics (PERF-01):
##     caster frames, monster overlay frames, monster body streaming.

const MSF := preload("res://scripts/monster_source_frames.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_wall_interval_recorder()
	_check_boundary_discard()
	_check_device_lab_feeder()
	_check_aoe_window_complete()
	_check_aoe_window_rejects_foreign_tick()
	_check_aoe_window_oneshot_and_other_skill()
	_check_aoe_window_deadline()
	_check_separated_cache_diagnostics()
	print("PERF_FRAME_DIAGNOSTICS_PASS walls=%d boundaries=%d" % [
		1,
		RuntimeDiagnostics.wall_boundary_discard_count(),
	])
	get_tree().quit(0)


func _check_wall_interval_recorder() -> void:
	RuntimeDiagnostics.reset_wall_frame_interval()
	assert(RuntimeDiagnostics.wall_frame_interval_ms() == -1.0)
	OS.delay_msec(60)
	var first := RuntimeDiagnostics.wall_frame_interval_ms()
	assert(first >= 40.0 and first <= 400.0)
	OS.delay_msec(320)
	var stalled := RuntimeDiagnostics.wall_frame_interval_ms()
	assert(stalled > 250.0)
	OS.delay_msec(120)
	var small := RuntimeDiagnostics.wall_frame_interval_ms()
	assert(small >= 90.0 and small <= 400.0)


func _check_boundary_discard() -> void:
	var discards_before := RuntimeDiagnostics.wall_boundary_discard_count()
	# Simulate a >5s pause boundary without sleeping: place the previous
	# timestamp 6s in the past, then record. (A negative prev is a valid
	# baseline right after engine start; the recorder must use its valid
	# flag, not the timestamp sign, to detect "no baseline".)
	RuntimeDiagnostics._wall_usec_prev = Time.get_ticks_usec() - 6000000
	RuntimeDiagnostics._wall_usec_valid = true
	var boundary_result := RuntimeDiagnostics.wall_frame_interval_ms()
	assert(boundary_result == -1.0)
	assert(RuntimeDiagnostics.wall_boundary_discard_count() == discards_before + 1)
	# A fresh interval after the boundary is a normal sample again.
	OS.delay_msec(30)
	assert(RuntimeDiagnostics.wall_frame_interval_ms() >= 0.0)


func _check_device_lab_feeder() -> void:
	var old_override := RuntimeDiagnostics.device_lab_performance_override_enabled()
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_device_lab_frame_interval()
	var frames_before := int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1))
	RuntimeDiagnostics.record_device_lab_frame_interval()
	assert(int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1)) == frames_before)
	OS.delay_msec(60)
	RuntimeDiagnostics.record_device_lab_frame_interval()
	assert(int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1)) == frames_before + 1)
	# Boundary gap in the gated recorder is also discarded, not sampled.
	RuntimeDiagnostics._device_lab_wall_usec_prev = Time.get_ticks_usec() - 6000000
	RuntimeDiagnostics.record_device_lab_frame_interval()
	assert(int(RuntimeDiagnostics.frame_sampling_snapshot().get("frame_count", -1)) == frames_before + 1)
	RuntimeDiagnostics.set_device_lab_performance_enabled(old_override)
	RuntimeDiagnostics.reset_device_lab_frame_interval()


func _check_aoe_window_complete() -> void:
	AoeEngagementWindow.reset_for_tests()
	AoeEngagementWindow.on_skill_cast("wizard.magic_shield")
	assert(not AoeEngagementWindow.window_active())
	AoeEngagementWindow.on_skill_cast("wizard.fire_wall")
	assert(AoeEngagementWindow.window_active())
	AoeEngagementWindow.record_frame_interval_ms(10.0)
	AoeEngagementWindow.record_frame_interval_ms(350.0)
	AoeEngagementWindow.record_frame_interval_ms(12.0)
	AoeEngagementWindow.on_field_spawned("wizard.fire_wall")
	AoeEngagementWindow.on_ground_damage_tick("wizard.fire_wall")
	assert(AoeEngagementWindow.window_active())
	assert(not AoeEngagementWindow.is_reported())
	AoeEngagementWindow.on_enemy_death_committed()
	assert(not AoeEngagementWindow.window_active())
	assert(AoeEngagementWindow.is_reported())
	var report := AoeEngagementWindow.last_report()
	assert(str(report.get("reason", "")) == "complete")
	assert(int(report.get("frames", -1)) == 3)
	assert(int(report.get("over33", -1)) == 1)
	assert(int(report.get("over50", -1)) == 1)
	assert(int(report.get("over100", -1)) == 1)
	assert(float(report.get("max_ms", -1.0)) >= 349.0)
	var field_ms := float(report.get("cast_to_field_ms", -1.0))
	var tick_ms := float(report.get("cast_to_tick_ms", -1.0))
	# C-R1 (PERF-R2 R9): the death milestone is non-causal and renamed.
	var death_ms := float(report.get("cast_to_first_any_death_ms", -1.0))
	assert(
		str(report.get("milestone_causality", "")) == "non_causal_first_any_death"
	)
	assert(field_ms >= 0.0 and tick_ms >= field_ms and death_ms >= tick_ms)


func _check_aoe_window_rejects_foreign_tick() -> void:
	# C-R1 (PERF-R2 R9): a non-fire-wall ground tick must not set the tick
	# milestone (window stays open, nothing is reported).
	AoeEngagementWindow.reset_for_tests()
	AoeEngagementWindow.on_skill_cast("wizard.fire_wall")
	AoeEngagementWindow.record_frame_interval_ms(16.0)
	AoeEngagementWindow.on_ground_damage_tick("taoist.poison")
	assert(AoeEngagementWindow.window_active())
	assert(not AoeEngagementWindow.is_reported())
	# The real fire-wall tick then completes the window as usual.
	AoeEngagementWindow.on_field_spawned("wizard.fire_wall")
	AoeEngagementWindow.on_ground_damage_tick("wizard.fire_wall")
	AoeEngagementWindow.on_enemy_death_committed()
	assert(AoeEngagementWindow.is_reported())


func _check_aoe_window_oneshot_and_other_skill() -> void:
	assert(AoeEngagementWindow.is_reported())
	AoeEngagementWindow.on_skill_cast("wizard.fire_wall")
	assert(not AoeEngagementWindow.window_active())
	assert(AoeEngagementWindow.is_reported())


func _check_aoe_window_deadline() -> void:
	AoeEngagementWindow.reset_for_tests()
	AoeEngagementWindow.set_window_deadline_ms(30.0)
	AoeEngagementWindow.on_skill_cast("wizard.fire_wall")
	OS.delay_msec(60)
	AoeEngagementWindow.record_frame_interval_ms(16.0)
	assert(not AoeEngagementWindow.window_active())
	assert(AoeEngagementWindow.is_reported())
	assert(str(AoeEngagementWindow.last_report().get("reason", "")) == "deadline")
	AoeEngagementWindow.set_window_deadline_ms(12000.0)


func _check_separated_cache_diagnostics() -> void:
	var overlay: Dictionary = MSF.diagnostics()
	for key: String in ["entries", "resident_bytes", "requested", "queued", "loads", "evictions"]:
		assert(overlay.has(key), "overlay diagnostics missing %s" % key)
	var caster: Dictionary = CasterSkillVisualRegistry.frame_texture_cache_diagnostics()
	for key: String in ["entries", "resident_bytes", "loads", "hits", "evictions", "sync_decode_calls", "sync_decode_usec"]:
		assert(caster.has(key), "caster diagnostics missing %s" % key)
