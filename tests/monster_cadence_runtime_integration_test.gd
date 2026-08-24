extends Node2D

## M01B integration: EnemyActor cadence-governed movement with an ACCEPTED_CANDIDATE
## monster (ID 18, walk_interval_ms=900).  Exercises the full cycle of request,
## advance, arrival, and cadence interval.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const NeighborPolicy := preload("res://scripts/monster_neighbor_step_policy.gd")
const Cadence := preload("res://scripts/monster_movement_cadence.gd")
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
	await _test_stationary_and_compatibility_runtime()
	await _test_quantized_facing_matches_neighbor()
	await _test_engagement_completion_does_not_rollback()
	await _test_return_to_spawn_uses_cadence()
	await _test_safe_zone_return_uses_cadence()
	await _test_crowd_evaluation_only_on_grant()

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
	enemy.set_physics_process(false)
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


func _set_cadence_waiting(enemy: EnemyActor) -> void:
	var cadence = enemy._movement_cadence
	assert(cadence != null, "enemy must own a configured cadence")
	var now_ms := Time.get_ticks_msec()
	cadence.walk_wait_locked = false
	cadence.walk_tick_ms = now_ms
	cadence.walk_wait_tick_ms = now_ms
	cadence.last_evaluated_ms = now_ms - 1


func _force_cadence_ready(enemy: EnemyActor) -> void:
	var cadence = enemy._movement_cadence
	assert(cadence != null, "enemy must own a configured cadence")
	var now_ms := Time.get_ticks_msec()
	cadence.walk_wait_locked = false
	cadence.walk_tick_ms = now_ms - cadence.walk_interval_ms - 1
	cadence.walk_wait_tick_ms = now_ms
	cadence.last_evaluated_ms = now_ms - 1


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
	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame

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

	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame

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

	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame

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
# ---------------------------------------------------------------------------
# Additional Sol-review runtime coverage
# ---------------------------------------------------------------------------

func _test_stationary_and_compatibility_runtime() -> void:
	var stationary := await _make_enemy(30)
	assert(stationary._movement_cadence != null)
	assert(stationary._movement_cadence.source_status == Cadence.STATUS_LOCKED)
	_force_cadence_ready(stationary)
	assert(
		not stationary._request_autonomous_step(Vector2.RIGHT, 1.0, false, &"stationary_test"),
		"LOCKED stationary monster must never start a movement step",
	)
	assert(not stationary._movement_step_active)
	_checks += 3
	stationary.queue_free()
	await get_tree().physics_frame

	var compatibility := await _make_enemy(41)
	assert(compatibility._movement_cadence != null)
	assert(compatibility._movement_cadence.source_status == Cadence.STATUS_COMPATIBILITY_HOLD)
	_force_cadence_ready(compatibility)
	assert(
		compatibility._request_autonomous_step(Vector2.RIGHT, 1.0, false, &"compatibility_test"),
		"COMPATIBILITY_HOLD must execute its explicit M00R-bound cadence",
	)
	assert(compatibility._movement_step_active)
	compatibility._cancel_autonomous_step(true)
	_checks += 4
	compatibility.queue_free()
	await get_tree().physics_frame


func _test_quantized_facing_matches_neighbor() -> void:
	var enemy := await _make_enemy(18)
	_force_cadence_ready(enemy)
	assert(enemy._request_autonomous_step(Vector2(100.0, -0.01), 1.0, false, &"facing_test"))
	assert(enemy._movement_step_neighbor == Vector2i(1, -1), "desired direction must quantize to the diagonal neighbor")
	var expected_facing := enemy._screen_facing_for_ground_direction(
		NeighborPolicy.desired_ground_direction(Vector2i(1, -1))
	)
	assert(enemy.movement_facing.is_equal_approx(expected_facing), "walk animation facing must follow the actual quantized neighbor")
	_checks += 3
	enemy.queue_free()
	await get_tree().physics_frame


func _test_engagement_completion_does_not_rollback() -> void:
	var player := PlayerCharacter.new()
	player.name = "CadenceEngagementPlayer"
	add_child(player)
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.set_touch_vector(Vector2.ZERO)
	var player_ground := Vector2(0.5, 0.5)
	player.global_position = _ground_gu_to_screen_px(player_ground)

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.environment_blocker = null
	enemy.set_meta("safe_zones", [])
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame

	var contact_distance := enemy._contact_distance_gu_to_target(player)
	var start_ground := player_ground + Vector2(contact_distance + 0.60, 0.0)
	enemy.set_combat_position(_ground_gu_to_screen_px(start_ground), &"test_setup")
	enemy.set_meta("spawn_position", enemy.global_position)

	var start_screen := enemy.global_position
	_force_cadence_ready(enemy)

	assert(enemy._request_autonomous_step(Vector2.LEFT, 1.0, false, &"engagement_test", -1, player))
	assert(enemy._movement_step_active)

	for _frame in range(120):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame

	assert(not enemy._movement_step_active, "pursuit step must finish once the target becomes attack-ready")

	var final_ground := _screen_px_to_ground_gu(enemy.global_position)
	var final_distance := final_ground.distance_to(player_ground)
	var engagement_distance := maxf(enemy.attack_range_gu, contact_distance)
	assert(final_distance <= engagement_distance + 0.05, "monster must finish inside existing engagement geometry")
	assert(enemy.global_position.distance_to(start_screen) > 0.01, "target engagement must preserve movement progress instead of rolling back")

	_checks += 4

	enemy.queue_free()
	player.queue_free()
	await get_tree().physics_frame


func _test_return_to_spawn_uses_cadence() -> void:
	var enemy := await _make_enemy(18)
	enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(3.0, 0.0)), &"test_setup")
	enemy.set_meta("spawn_position", _ground_gu_to_screen_px(Vector2.ZERO))
	_set_cadence_waiting(enemy)
	enemy._return_to_spawn(1.0 / 60.0)
	assert(not enemy._movement_step_active, "return-to-spawn must not bypass a WAIT cadence")
	_force_cadence_ready(enemy)
	enemy._return_to_spawn(1.0 / 60.0)
	assert(enemy._movement_step_active, "return-to-spawn must start after cadence grant")
	assert(enemy._movement_step_reason == &"return_to_spawn", "return path must use the shared autonomous-step executor")
	_checks += 3
	enemy.queue_free()
	await get_tree().physics_frame


func _test_safe_zone_return_uses_cadence() -> void:
	var player := PlayerCharacter.new()
	player.name = "SafeZoneCadencePlayer"
	add_child(player)
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.set_touch_vector(Vector2.ZERO)
	var safe_center_ground := Vector2(5.0, 5.0)
	var safe_center_screen := _ground_gu_to_screen_px(safe_center_ground)
	player.global_position = _ground_gu_to_screen_px(Vector2(5.5, 5.0))

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.environment_blocker = null
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame

	enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(4.5, 5.0)), &"test_setup")
	enemy.set_meta("spawn_position", _ground_gu_to_screen_px(Vector2.ZERO))
	enemy.set_meta("safe_zones", [{"shape": "circle", "center": safe_center_screen, "center_ground_gu": safe_center_ground, "radius_gu": 2.0}])
	enemy.primary_target = player
	enemy.target = player
	enemy._retarget_timer = 999.0

	_set_cadence_waiting(enemy)
	enemy._physics_process(1.0 / 60.0)
	assert(not enemy._movement_step_active, "safe-zone return must respect cadence WAIT")

	_force_cadence_ready(enemy)
	enemy._physics_process(1.0 / 60.0)
	assert(enemy._movement_step_active, "safe-zone return must start after cadence grant")
	assert(enemy._movement_step_reason == &"safe_zone_return", "safe-zone branch must use the shared autonomous-step executor")

	_checks += 3

	enemy.queue_free()
	player.queue_free()
	await get_tree().physics_frame


func _test_crowd_evaluation_only_on_grant() -> void:
	EnemyActor.reset_performance_diagnostics()
	var enemy := await _make_enemy(18)

	_set_cadence_waiting(enemy)
	var before := EnemyActor.performance_diagnostics()
	var started_while_waiting := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"crowd_wait_test")
	var after_wait := EnemyActor.performance_diagnostics()
	assert(not started_while_waiting)
	assert(int(after_wait.crowd_steering_evaluations) == int(before.crowd_steering_evaluations), "cadence WAIT must not evaluate crowd steering")

	_force_cadence_ready(enemy)
	var started_after_grant := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"crowd_grant_test")
	var after_grant := EnemyActor.performance_diagnostics()
	assert(started_after_grant)
	assert(int(after_grant.crowd_steering_evaluations) == int(after_wait.crowd_steering_evaluations) + 1, "one granted movement event must evaluate crowd steering once")

	var second_request := enemy._request_autonomous_step(Vector2.RIGHT, 1.0, true, &"crowd_active_test")
	var after_active := EnemyActor.performance_diagnostics()
	assert(not second_request)
	assert(int(after_active.crowd_steering_evaluations) == int(after_grant.crowd_steering_evaluations), "active step must not reevaluate crowd steering")

	_checks += 6

	enemy.queue_free()
	await get_tree().physics_frame
