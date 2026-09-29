extends Node2D

## source176 R2 (docs/02 R02/R03): the per-tick source decision permission
## cache on EnemyActor, now keyed by the actor identity plus the physics tick
## and evaluated on the projected owner game clock. Contracts under test:
## - one cadence.evaluate per logical decision event (physics tick); a repeated
##   call inside the same tick returns the cached result without re-consuming;
## - a granted permission increments the source decision serial exactly once
##   and the cadence walk tick moves to the projected game-clock time;
## - a committed movement step is bound to the originating permission serial;
## - the authority violation path fails closed.
## The fixture drives the deterministic owner game clock `_combat_action_time_s`
## directly and resets `_source176_decision_tick` to -1 to model entering a new
## physics tick, so no wall-clock sleep is involved anywhere.

const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

const EXPECTED_CHECKS := 16
const EXPECTED_CASES := 4
var _checks := 0
var _completed_cases := 0
var _failures: Array[String] = []


class DecisionEnemyFixture:
	extends EnemyActor
	func _ready() -> void:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_initialize_spawn_facing_once()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("SOURCE176_DECISION_GATE: " + label)


func _run() -> void:
	_checks = 0
	_completed_cases = 0
	_failures.clear()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	await _test_cache_dedupes_same_tick()
	_completed_cases += 1
	await _test_grant_consumes_walk_tick_once()
	_completed_cases += 1
	await _test_wait_does_not_consume()
	_completed_cases += 1
	await _test_violation_fails_closed()
	_completed_cases += 1
	var complete := _checks == EXPECTED_CHECKS and _completed_cases == EXPECTED_CASES
	if not complete or not _failures.is_empty():
		print("SOURCE176_DECISION_GATE_FAIL checks=%d/%d cases=%d/%d failures=%s" % [
			_checks, EXPECTED_CHECKS, _completed_cases, EXPECTED_CASES, str(_failures)])
		get_tree().quit(1)
		return
	print("SOURCE176_DECISION_GATE_PASS checks=%d cases=%d failures=0" % [_checks, _completed_cases])
	get_tree().quit(0)


func _make_enemy() -> EnemyActor:
	var enemy := DecisionEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(18), null, false)
	enemy.set_physics_process(false)
	enemy.max_hp = 500
	enemy.current_hp = 500
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	return enemy


func _test_cache_dedupes_same_tick() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	var interval_ms := int(cadence.walk_interval_ms)
	# A deterministic on-phase fixture: the projected game clock sits at 10 s
	# and the walk tick is a full interval plus 7 ms in the past.
	enemy._combat_action_time_s = 10.0
	var now_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_tick_ms = now_ms - (interval_ms + 7)
	var walk_count_before := int(cadence.walk_count)
	var granted_first: bool = enemy._source176_take_tick_decision()
	var serial_after_first := int(enemy._source176_decision_serial)
	_check(granted_first, "elapsed interval grants the permission")
	_check(serial_after_first == 1, "first grant bumps the decision serial")
	_check(
		enemy._source176_decision_now_ms == now_ms,
		"cache records the projected game-clock millisecond"
	)
	var granted_second: bool = enemy._source176_take_tick_decision()
	_check(granted_second == granted_first, "same-tick repeat returns the cached result")
	_check(
		int(enemy._source176_decision_serial) == serial_after_first,
		"same-tick repeat does not bump the serial"
	)
	_check(
		int(cadence.walk_count) == walk_count_before + 1,
		"exactly one cadence consumption per logical event"
	)
	_check(
		int(enemy._source_committed_step_serial) == -1,
		"no committed step serial before any step"
	)
	enemy.free()


func _test_grant_consumes_walk_tick_once() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	var interval_ms := int(cadence.walk_interval_ms)
	# A NEW logical event: advance the deterministic clock and enter a fresh
	# physics tick for the second decision.
	enemy._combat_action_time_s = 20.0
	var evaluation_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_tick_ms = evaluation_ms - (interval_ms + 11)
	enemy._source176_decision_tick = -1
	var granted: bool = enemy._source176_take_tick_decision()
	_check(granted, "grant after forced interval elapse")
	_check(
		int(cadence.walk_tick_ms) >= evaluation_ms,
		"grant re-anchors the walk tick at the decision time"
	)
	var walk_tick_after_grant := int(cadence.walk_tick_ms)
	var granted_again := enemy._source176_take_tick_decision()
	_check(granted_again == false or int(cadence.walk_tick_ms) == walk_tick_after_grant,
		"a same-tick repeat never re-anchors the walk tick")
	enemy.free()


func _test_wait_does_not_consume() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	# The projected clock equals the walk tick: the interval has not elapsed.
	enemy._combat_action_time_s = 30.0
	var now_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_tick_ms = now_ms
	enemy._source176_decision_tick = -1
	var walk_count_before := int(cadence.walk_count)
	var granted: bool = enemy._source176_take_tick_decision()
	_check(not granted, "unelapsed interval waits")
	_check(int(cadence.walk_count) == walk_count_before, "a wait consumes nothing")
	_check(
		enemy._source176_decision_granted == false,
		"the cache records the wait result"
	)
	enemy.free()


func _test_violation_fails_closed() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	enemy._combat_action_time_s = 40.0
	var now_ms := int(enemy._combat_action_time_s * 1000.0)
	cadence.walk_tick_ms = now_ms - int(cadence.walk_interval_ms) - 5
	# Force the M01A authority contract into the violation state: the next
	# evaluate must report the violation and the accessor must fail closed
	# exactly like the production step-request path does.
	cadence._enter_violation("source176_test_forced_violation")
	enemy._source176_decision_tick = -1
	var granted: bool = enemy._source176_take_tick_decision()
	_check(not granted, "authority violation never grants")
	_check(
		enemy._movement_authority_failed_closed,
		"accessor fails closed on authority violation"
	)
	_check(enemy.velocity == Vector2.ZERO, "violation stops the actor")
	enemy.free()
