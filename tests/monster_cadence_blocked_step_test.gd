extends Node2D

## M01B integration: EnemyActor cadence step blocked by a WORLD collision.
## Verifies rollback to step_start, cleared step state, consumed grant, and
## no free retry within the same cadence interval.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
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

	await _await_blocked_step_rolls_back()
	await _test_grant_consumed_no_free_retry()

	print("MONSTER_CADENCE_BLOCKED_STEP_PASS checks=%d" % _checks)
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
	add_child(enemy)
	await get_tree().physics_frame
	_checks += 1
	return enemy


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu)


func _screen_px_to_ground_gu(screen_px: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px)


# ---------------------------------------------------------------------------
# Test 1: Grant happened, step hits a WORLD blocker.  Final: returns to
#         step_start, step inactive, velocity zero.
# ---------------------------------------------------------------------------

func _await_blocked_step_rolls_back() -> void:
	var enemy := await _make_enemy(18)
	var start_screen_px := enemy.global_position
	var start_ground_gu := _screen_px_to_ground_gu(start_screen_px)

	# Place a wall blocking the RIGHT neighbor step.
	# The step target for RIGHT from origin is:
	#   cell = Vector2i(0,0), center = (0.5, 0.5), target = (1.5, 0.5)
	# The wall should block the path between (0,0) and (1.5, 0.5) ground.
	#
	# Place the wall at ground_gu (0.75, 0.25) ≈ screen_px (16, 16).
	var wall_screen_px := _ground_gu_to_screen_px(Vector2(0.75, 0.25))
	var wall := StaticBody2D.new()
	wall.name = "BlockStepWall"
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12.0, 12.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = wall_screen_px
	add_child(wall)
	await get_tree().physics_frame

	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 1000

	# Request a step toward RIGHT.
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "step must be granted for blocked-step test")
	assert(enemy._movement_step_active, "step must be active after grant")
	assert(
		enemy._movement_step_start_screen_px.is_equal_approx(start_screen_px),
		"step start must be recorded at initial position"
	)

	# Advance physics so the step hits the wall.
	enemy.set_physics_process(true)
	for _frame in range(30):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.set_physics_process(false)

	# Verify rollback to step_start.
	assert(
		not enemy._movement_step_active,
		"step must be inactive after hitting a WORLD blocker"
	)
	assert(
		enemy._movement_step_target_ground_gu == Vector2.INF,
		"step target must be cleared after blocker"
	)
	assert(
		enemy.global_position.distance_squared_to(start_screen_px) <= 1.0,
		"enemy must return to step_start after blocked step: expected=%s actual=%s" % [start_screen_px, enemy.global_position]
	)
	assert(
		enemy.velocity.length_squared() <= 0.0001,
		"velocity must be zero after blocked step"
	)
	_checks += 5

	wall.queue_free()
	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 2: Grant consumed — no free retry within same cadence interval.
# ---------------------------------------------------------------------------

func _test_grant_consumed_no_free_retry() -> void:
	var enemy := await _make_enemy(18)
	var start_screen_px := enemy.global_position

	# Place the same wall blocker.
	var wall_screen_px := _ground_gu_to_screen_px(Vector2(0.75, 0.25))
	var wall := StaticBody2D.new()
	wall.name = "RetryBlockWall"
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12.0, 12.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = wall_screen_px
	add_child(wall)
	await get_tree().physics_frame

	var now_ms := Time.get_ticks_msec()
	var fake_now := now_ms + 1000

	# First step: hits the wall and fails.
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now
	)
	assert(started, "first step must be granted")

	enemy.set_physics_process(true)
	for _frame in range(30):
		if not enemy._movement_step_active:
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.set_physics_process(false)

	assert(
		not enemy._movement_step_active,
		"first step must be consumed by blocker"
	)

	# Attempt a second step with the same fake_now (same cadence interval).
	# The cadence should NOT grant because the interval hasn't elapsed since
	# the first grant consumed the cadence tick.
	var second_started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		1.0,
		false,
		&"test",
		fake_now + 100  # only 100ms after the grant → interval not elapsed
	)
	assert(
		not second_started,
		"second step must be rejected — grant consumed, cadence interval not elapsed"
	)

	# The enemy should still be at the rolled-back position.
	assert(
		enemy.global_position.distance_squared_to(start_screen_px) <= 1.0,
		"enemy must remain at step_start after failed retry"
	)
	_checks += 3

	wall.queue_free()
	enemy.queue_free()
	await get_tree().physics_frame