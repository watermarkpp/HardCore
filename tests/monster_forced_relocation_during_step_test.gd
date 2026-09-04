extends Node2D

## M01B integration: forced relocation during an active autonomous step.
## Verifies set_combat_position with a non-M01B reason cancels the step,
## the forced position is preserved, no rollback on the next physics frame,
## and control_time mid-step cancels without rollback.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"

var _records_by_id: Dictionary = {}
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_load_authority_records()

	await _test_set_combat_position_cancels_step()
	await _test_position_stays_at_forced()
	await _test_next_physics_frame_no_pullback()
	await _test_control_mid_step_cancels_no_rollback()

	print("MONSTER_FORCED_RELOCATION_DURING_STEP_PASS checks=%d" % _checks)
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
	add_child(enemy)
	await get_tree().physics_frame
	_checks += 1
	return enemy


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_px_to_ground_gu(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


# ---------------------------------------------------------------------------
# Test 1: Active step, set_combat_position(forced, non-M01B reason) → step
#         immediately cancelled.
# ---------------------------------------------------------------------------

func _test_set_combat_position_cancels_step() -> void:
	var enemy := await _make_enemy(18)
	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 1000

	# Start a step.
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "step must be granted for forced-relocation test")
	assert(enemy._movement_step_active, "step must be active after grant")

	# Force a relocation with a non-M01B reason (any reason that is NOT one of
	# the internal_reasons: autonomous_step_arrival, autonomous_step_rollback,
	# entrapment_boundary_revert, safe_zone_revert, environment_revert).
	var forced_screen_px := _ground_gu_to_screen_px(Vector2(5.0, 3.0))
	enemy.set_combat_position(forced_screen_px, &"external_force")
	_checks += 1

	# After the forced relocation, the step must be cancelled.
	assert(
		not enemy._movement_step_active,
		"step must be cancelled after forced relocation with non-M01B reason"
	)
	assert(
		enemy._movement_step_target_ground_gu == Vector2.INF,
		"step target must be cleared after forced relocation"
	)
	assert(
		enemy.global_position.distance_squared_to(forced_screen_px) <= 0.0001,
		"enemy must be at the forced position after set_combat_position"
	)
	_checks += 3

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 2: Position stays at forced position (no rollback).
# ---------------------------------------------------------------------------

func _test_position_stays_at_forced() -> void:
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
	assert(started, "step must be granted for position-stays test")
	assert(enemy._movement_step_active, "step must be active")

	var forced_screen_px := _ground_gu_to_screen_px(Vector2(-2.0, 4.5))
	enemy.set_combat_position(forced_screen_px, &"external_force")

	# Immediately after the forced relocation, the position should be at
	# the forced position, not at the step_start.
	assert(
		enemy.global_position.distance_squared_to(forced_screen_px) <= 0.0001,
		"enemy must be at forced position immediately after relocation"
	)
	assert(
		not enemy._movement_step_active,
		"step must be cancelled"
	)
	_checks += 2

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 3: Next physics frame not pulled back by old step.
# ---------------------------------------------------------------------------

func _test_next_physics_frame_no_pullback() -> void:
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
	assert(started, "step must be granted for no-pullback test")
	assert(enemy._movement_step_active, "step must be active")

	# Force relocation.
	var forced_screen_px := _ground_gu_to_screen_px(Vector2(10.0, -5.0))
	enemy.set_combat_position(forced_screen_px, &"external_force")
	assert(
		not enemy._movement_step_active,
		"step must be cancelled after forced relocation"
	)

	# Advance physics frame.  The old step must not pull the position back.
	enemy._advance_autonomous_step(1.0 / 60.0)
	await get_tree().physics_frame

	assert(
		not enemy._movement_step_active,
		"step must remain inactive after physics frame"
	)
	assert(
		enemy.global_position.distance_squared_to(forced_screen_px) <= 0.0001,
		"enemy must not be pulled back by old step after physics frame: expected=%s actual=%s" % [forced_screen_px, enemy.global_position]
	)
	_checks += 3

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 4: Control mid-step: cancel step, no rollback.
# ---------------------------------------------------------------------------

func _test_control_mid_step_cancels_no_rollback() -> void:
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
	assert(started, "step must be granted for control test")
	assert(enemy._movement_step_active, "step must be active")

	# Record the current position.
	var position_before_control := enemy.global_position

	# Set control_time > 0.0 to immobilize the enemy.
	enemy.control_time = 1.0

	# _advance_autonomous_step checks control_time and cancels the step.
	enemy._advance_autonomous_step(1.0 / 60.0)

	# The step must be cancelled, but there should be NO rollback to
	# step_start.  The position should remain at the current position
	# (the control anchor is set separately in _physics_process).
	assert(
		not enemy._movement_step_active,
		"step must be cancelled when control_time is set"
	)
	assert(
		enemy.global_position == position_before_control,
		"enemy must NOT be rolled back to step_start when control cancels step"
	)
	assert(
		enemy.velocity.length_squared() <= 0.0001,
		"velocity must be zero after control cancels step"
	)
	_checks += 4

	enemy.queue_free()
	await get_tree().physics_frame