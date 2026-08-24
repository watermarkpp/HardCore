extends Node2D

## M01B integration: EnemyActor cadence-governed movement with an ACCEPTED_CANDIDATE
## monster (ID 18, walk_interval_ms=900).  Exercises the full cycle of request,
## advance, arrival, and cadence interval.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const NeighborPolicy := preload("res://scripts/monster_neighbor_step_policy.gd")
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"

var _records_by_id: Dictionary = {}
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_load_authority_records()

	await _test_cadence_interval_not_elapsed()
	await _test_grant_starts_one_step()
	await _test_target_moves_mid_step()
	await _await_axis_step_reaches_exact_target()
	await _await_diagonal_step_reaches_exact_target()
	await _test_next_event_waits_for_cadence_interval()

	print("MONSTER_CADENCE_RUNTIME_INTEGRATION_PASS checks=%d" % _checks)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_authority_records() -> void:
	assert(FileAccess.file_exists(AUTHORITY_PATH), "M00R runtime authority must be present")
	var file := FileAccess.open(AUTHORITY_PATH, FileAccess.READ)
	assert(file != null, "M00R runtime authority must open")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "M00R runtime authority JSON must parse")
	for raw_record: Variant in parsed.get("records", []):
		assert(raw_record is Dictionary, "authority records must be dictionaries")
		var record: Dictionary = raw_record
		_records_by_id[str(record.get("monster_id", -1))] = record
	_checks += 1


func _record(id: int) -> Dictionary:
	var record: Dictionary = _records_by_id.get(str(id), _records_by_id.get("%d.0" % id, {}))
	assert(not record.is_empty(), "missing M00R record %d" % id)
	return record.duplicate(true)


func _make_enemy(monster_id: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), null, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.attack_range_gu = 1.5
	enemy.aggro_radius_gu = 12.0
	enemy.environment_blocker = null
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	# runtime_map_id == -1 means the identity projection fallback is used.
	add_child(enemy)
	# Let the enemy settle into the scene tree.
	await get_tree().physics_frame
	_checks += 1
	return enemy


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_px_to_ground_gu(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


# ---------------------------------------------------------------------------
# Test 1: ACCEPTED_CANDIDATE — interval not elapsed → position unchanged
# ---------------------------------------------------------------------------

func _test_cadence_interval_not_elapsed() -> void:
	var enemy := await _make_enemy(18)
	var start_position := enemy.global_position

	# Immediately request a step with the same timestamp that was used during
	# setup.  The cadence should reject because the interval hasn't elapsed.
	var now_ms := Time.get_ticks_msec()
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		now_ms  # same tick as setup → no grant
	)
	assert(not started, "cadence must reject step before interval elapses")
	assert(enemy.global_position == start_position, "position must not change without grant")
	assert(not enemy._movement_step_active, "step must not be active without grant")
	_checks += 3

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 2: After grant → only one neighbor step starts
# ---------------------------------------------------------------------------

func _test_grant_starts_one_step() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()

	# Advance the clock past the 900ms walk_interval so the cadence grants.
	var fake_now := now_ms + 1000
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "cadence must grant after walk_interval")
	assert(enemy._movement_step_active, "step must be active after grant")
	assert(
		enemy._movement_step_target_ground_gu.is_finite(),
		"step target must be set after grant"
	)

	# A second request while the step is active must be rejected.
	var second_started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now + 1
	)
	assert(not second_started, "second request must be rejected while step is active")
	_checks += 4

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 3: target moves mid-step → current step target stays the same
# ---------------------------------------------------------------------------

func _test_target_moves_mid_step() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 1000

	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "step must start for target-move test")

	var saved_target := enemy._movement_step_target_ground_gu

	# Move the enemy's target (primary_target).  The step target must not change.
	if enemy.primary_target != null:
		enemy.primary_target.global_position = _ground_gu_to_screen_px(Vector2(100.0, 100.0))

	# The step target is immutable once set.
	assert(
		enemy._movement_step_target_ground_gu == saved_target,
		"step target must not change when the game target moves"
	)
	_checks += 2

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 4: Axis step → eventually reaches exact neighbor target
# ---------------------------------------------------------------------------

func _await_axis_step_reaches_exact_target() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 1000

	# Direction RIGHT → neighbor (1, 0) → target = cell_center + (1, 0)
	var current_ground := _screen_px_to_ground_gu(enemy.global_position)
	var cell := NeighborPolicy.temporary_cell(current_ground)
	var expected_target := NeighborPolicy.cell_center_ground_gu(cell) + Vector2(1, 0)

	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "axis step must start")
	assert(
		enemy._movement_step_target_ground_gu.distance_squared_to(expected_target) <= 0.0001,
		"axis step target must be cell_center + (1, 0)"
	)

	# Advance physics until the step completes.
	enemy.set_physics_process(true)
	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.set_physics_process(false)

	assert(
		not enemy._movement_step_active,
		"axis step must complete within 120 frames"
	)
	var final_ground := _screen_px_to_ground_gu(enemy.global_position)
	assert(
		final_ground.distance_squared_to(expected_target) <= GroundUnitSpaceScript.EPSILON_GU,
		"axis step must reach exact neighbor target: expected=%s actual=%s" % [expected_target, final_ground]
	)
	_checks += 4

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 5: Diagonal step → eventually reaches exact neighbor target
# ---------------------------------------------------------------------------

func _await_diagonal_step_reaches_exact_target() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 2000  # well past cadence interval

	# Direction DOWN+RIGHT → neighbor (1, 1) → target = cell_center + (1, 1)
	var current_ground := _screen_px_to_ground_gu(enemy.global_position)
	var cell := NeighborPolicy.temporary_cell(current_ground)
	var expected_target := NeighborPolicy.cell_center_ground_gu(cell) + Vector2(1, 1)

	var started := enemy._request_autonomous_step(
		Vector2(1, 1),
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "diagonal step must start")
	assert(
		enemy._movement_step_target_ground_gu.distance_squared_to(expected_target) <= 0.0001,
		"diagonal step target must be cell_center + (1, 1)"
	)

	enemy.set_physics_process(true)
	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.set_physics_process(false)

	assert(
		not enemy._movement_step_active,
		"diagonal step must complete within 120 frames"
	)
	var final_ground := _screen_px_to_ground_gu(enemy.global_position)
	assert(
		final_ground.distance_squared_to(expected_target) <= GroundUnitSpaceScript.EPSILON_GU,
		"diagonal step must reach exact neighbor target: expected=%s actual=%s" % [expected_target, final_ground]
	)
	_checks += 4

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 6: Next movement event must wait for cadence interval
# ---------------------------------------------------------------------------

func _test_next_event_waits_for_cadence_interval() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()

	# Start and complete one step.
	var fake_now := now_ms + 1000
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "first step must start for cadence-wait test")

	enemy.set_physics_process(true)
	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.set_physics_process(false)

	assert(
		not enemy._movement_step_active,
		"first step must complete for cadence-wait test"
	)

	# The cadence's walk_tick_ms is now at fake_now.  Calling within 900ms of
	# that tick should be rejected.
	var early_attempt := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now + 500  # only 500ms after the grant → not elapsed
	)
	assert(not early_attempt, "step must be rejected before cadence interval elapses")

	# After the full interval, the next grant should work.
	var late_attempt := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now + 1000  # 1000ms after the grant → elapsed (strict > 900)
	)
	assert(late_attempt, "step must be granted after cadence interval elapses")
	_checks += 3

	enemy.queue_free()
	await get_tree().physics_frame