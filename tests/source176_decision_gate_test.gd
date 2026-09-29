extends Node2D

## source176 Task 2 (docs/02 D2): the per-tick source decision permission
## cache on EnemyActor. Contracts under test:
## - one cadence.evaluate per logical millisecond; a repeated call in the
##   same millisecond returns the cached result without re-consuming it;
## - a granted permission increments the source decision serial exactly once
##   and the cadence walk tick moves to the evaluation time;
## - a committed movement step is bound to the originating permission serial;
## - the authority violation path fails closed.

const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")

var _checks := 0


class DecisionEnemyFixture:
	extends EnemyActor
	func _ready() -> void:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_initialize_spawn_facing_once()


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	assert(condition, "SOURCE176_DECISION_GATE: " + label)
	_checks += 1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	_test_cache_dedupes_same_millisecond()
	_test_grant_consumes_walk_tick_once()
	_test_wait_does_not_consume()
	_test_violation_fails_closed()
	print("SOURCE176_DECISION_GATE_PASS checks=%d" % _checks)
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


func _test_cache_dedupes_same_millisecond() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	var interval_ms := int(cadence.walk_interval_ms)
	cadence.walk_tick_ms = Time.get_ticks_msec() - (interval_ms + 7)
	var walk_count_before := int(cadence.walk_count)
	var granted_first: bool = enemy._source176_take_tick_decision()
	var serial_after_first := int(enemy._source176_decision_serial)
	_check(granted_first, "elapsed interval grants the permission")
	_check(serial_after_first == 1, "first grant bumps the decision serial")
	_check(
		enemy._source176_decision_now_ms == Time.get_ticks_msec(),
		"cache records the decision millisecond"
	)
	var granted_second: bool = enemy._source176_take_tick_decision()
	_check(granted_second == granted_first, "same-millisecond repeat returns the cached result")
	_check(
		int(enemy._source176_decision_serial) == serial_after_first,
		"same-millisecond repeat does not bump the serial"
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
	var evaluation_ms := Time.get_ticks_msec() + 3
	cadence.walk_tick_ms = evaluation_ms - (interval_ms + 11)
	while Time.get_ticks_msec() < evaluation_ms:
		await get_tree().process_frame
	var granted: bool = enemy._source176_take_tick_decision()
	_check(granted, "grant after forced interval elapse")
	_check(
		int(cadence.walk_tick_ms) >= evaluation_ms,
		"grant re-anchors the walk tick at the decision time"
	)
	var walk_tick_after_grant := int(cadence.walk_tick_ms)
	var granted_again := enemy._source176_take_tick_decision()
	_check(granted_again == false or int(cadence.walk_tick_ms) == walk_tick_after_grant,
		"a same-millisecond repeat never re-anchors the walk tick")
	enemy.free()


func _test_wait_does_not_consume() -> void:
	var enemy := await _make_enemy()
	var cadence = enemy._movement_cadence
	var interval_ms := int(cadence.walk_interval_ms)
	cadence.walk_tick_ms = Time.get_ticks_msec()
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
	cadence.walk_tick_ms = Time.get_ticks_msec() - int(cadence.walk_interval_ms) - 5
	# Force the M01A authority contract into the violation state: the next
	# evaluate must report the violation and the accessor must fail closed
	# exactly like the production step-request path does.
	cadence._enter_violation("source176_test_forced_violation")
	var granted: bool = enemy._source176_take_tick_decision()
	_check(not granted, "authority violation never grants")
	_check(
		enemy._movement_authority_failed_closed,
		"accessor fails closed on authority violation"
	)
	_check(enemy.velocity == Vector2.ZERO, "violation stops the actor")
	enemy.free()
