extends Node2D

## M01B integration: EnemyActor cadence-governed movement with an ACCEPTED_CANDIDATE
## monster (ID 18, walk_interval_ms=900).  Exercises the full cycle of request,
## advance, arrival, and cadence interval.

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const NeighborPolicy := preload("res://scripts/monster_neighbor_step_policy.gd")
const Cadence := preload("res://scripts/monster_movement_cadence.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"


class RuntimeEnemyFixture extends EnemyActor:
	func _ready() -> void:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_initialize_spawn_facing_once()


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
	await _test_multi_step_visual_continuity()
	await _test_scaled_step_keeps_continuous_motion()
	await _test_next_event_waits_for_cadence_interval()
	await _test_1500ms_pursuit_is_continuous_and_scan_free()
	await _test_live_target_turns_at_next_cell()
	await _test_id70_speed_unit_contract()
	await _test_seeded_spawn_facing_is_legal_and_varied()
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
	var enemy := RuntimeEnemyFixture.new()
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
	enemy.set_physics_process(false)
	_checks += 1
	return enemy


func _make_unready_enemy(monster_id: int) -> EnemyActor:
	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), null, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.attack_range_gu = 1.5
	enemy.aggro_radius_gu = 12.0
	enemy.environment_blocker = null
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
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
	var enemy := _make_unready_enemy(18)
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

	enemy.free()


func _test_1500ms_pursuit_is_continuous_and_scan_free() -> void:
	var player := PlayerCharacter.new()
	player.name = "ContinuousPursuitPlayer"
	player.set_physics_process(false)
	add_child(player)
	await get_tree().physics_frame
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = _ground_gu_to_screen_px(Vector2(12.5, 0.5))

	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(19), player, false)
	enemy.environment_blocker = null
	enemy.aggro_radius_gu = 20.0
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(0.5, 0.5)), &"test_setup")
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("safe_zones", [])
	enemy.target = player
	enemy.primary_target = player
	assert(enemy._movement_cadence.walk_interval_ms == 1500, "fixture must retain 21CQ 1500ms history")
	assert(is_equal_approx(enemy.move_speed_gu_per_sec, 1.8125), "fixture must use exact runtime speed")
	_force_cadence_ready(enemy)
	EnemyActor.reset_performance_diagnostics()
	var before_diagnostics := EnemyActor.performance_diagnostics()
	assert(enemy._request_autonomous_step(Vector2.RIGHT, 1.0, false, &"pursuit", -1, player))
	var start_ground := _screen_px_to_ground_gu(enemy.global_position)
	var physics_delta := 1.0 / 60.0
	for _frame in range(90):
		assert(enemy._movement_step_active, "continuous pursuit must not idle between cells")
		enemy._advance_autonomous_step(physics_delta)
	var travelled_gu := start_ground.distance_to(_screen_px_to_ground_gu(enemy.global_position))
	assert(absf(travelled_gu - 2.71875) <= 0.08, "1.5s at 1.8125 GU/s must travel about 2.7 GU: %f" % travelled_gu)
	var after_diagnostics := EnemyActor.performance_diagnostics()
	assert(int(after_diagnostics.retarget_full_scans) == int(before_diagnostics.retarget_full_scans))
	assert(int(after_diagnostics.retarget_target_group_scans) == int(before_diagnostics.retarget_target_group_scans))
	_checks += 7
	enemy.queue_free()
	player.queue_free()
	await get_tree().physics_frame


func _test_live_target_turns_at_next_cell() -> void:
	var player := PlayerCharacter.new()
	player.name = "LiveTurnPlayer"
	player.set_physics_process(false)
	add_child(player)
	await get_tree().physics_frame
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = _ground_gu_to_screen_px(Vector2(12.5, 0.5))

	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(19), player, false)
	enemy.environment_blocker = null
	enemy.aggro_radius_gu = 20.0
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(0.5, 0.5)), &"test_setup")
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("safe_zones", [])
	enemy.target = player
	enemy.primary_target = player
	_force_cadence_ready(enemy)
	assert(enemy._request_autonomous_step(Vector2.RIGHT, 1.0, false, &"pursuit", -1, player))
	var first_target := enemy._movement_step_target_ground_gu
	for _frame in range(8):
		enemy._advance_autonomous_step(1.0 / 60.0)
	player.global_position = _ground_gu_to_screen_px(Vector2(first_target.x, -10.0))
	var turn_elapsed := 8.0 / 60.0
	while enemy._movement_step_target_ground_gu == first_target and turn_elapsed < 1.0:
		enemy._advance_autonomous_step(1.0 / 60.0)
		turn_elapsed += 1.0 / 60.0
	assert(enemy._movement_step_active, "pursuit must continue after the first cell")
	assert(enemy._movement_step_neighbor == Vector2i(0, -1), "next cell must use the target's current position")
	assert(turn_elapsed <= 0.60, "1.8125 GU/s monster must correct within one cell: %f" % turn_elapsed)
	_checks += 4
	enemy.queue_free()
	player.queue_free()
	await get_tree().physics_frame


func _test_id70_speed_unit_contract() -> void:
	var profile_file := FileAccess.open("res://assets/data/monster_behavior_profiles.json", FileAccess.READ)
	assert(profile_file != null)
	var profiles: Dictionary = JSON.parse_string(profile_file.get_as_text())
	var flame_profile: Dictionary = profiles.get("profiles", {}).get("flame_wooma", {})
	assert(is_equal_approx(float(flame_profile.get("runtimeProjection", {}).get("move_speed_gu_per_sec", 0.0)), 1.4375))
	var authority := _record(70)
	assert(is_equal_approx(float(authority.get("movement", {}).get("current_runtime_move_speed_gu_per_sec", 0.0)), 1.4375))
	assert(int(authority.get("movement", {}).get("walk_interval_ms", 0)) == 800)
	var runtime_enemy := EnemyActor.new()
	runtime_enemy.setup(GameData.get_monster_by_id(70), null, false)
	assert(is_equal_approx(runtime_enemy.move_speed_gu_per_sec, 1.4375), "46px/s must never become 46GU/s")
	runtime_enemy.queue_free()
	_checks += 5


func _test_seeded_spawn_facing_is_legal_and_varied() -> void:
	var legal := EnemyActor.legal_spawn_facing_directions()
	assert(legal.size() == 8, "spawn facing must expose exactly eight candidates")
	var observed: Array[Vector2] = []
	for seed_value in range(24):
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(18), null, false)
		enemy.set_spawn_facing_seed_for_test(seed_value)
		enemy._initialize_spawn_facing_once()
		var legal_match := false
		for candidate: Vector2 in legal:
			if enemy.facing.is_equal_approx(candidate):
				legal_match = true
				break
		assert(legal_match, "seeded spawn facing must stay in the legal 8-direction set")
		assert(enemy.movement_facing.is_equal_approx(enemy.facing), "initial visual and movement facings must match")
		var already_seen := false
		for candidate: Vector2 in observed:
			if enemy.facing.is_equal_approx(candidate):
				already_seen = true
				break
		if not already_seen:
			observed.append(enemy.facing)
		enemy.free()
	assert(observed.size() > 1, "multiple deterministic seeds must produce varied spawn facings")
	_checks += 50


# ---------------------------------------------------------------------------
# Test 2: After grant → only one neighbor step starts
# ---------------------------------------------------------------------------

func _test_grant_starts_one_step() -> void:
	var enemy := _make_unready_enemy(18)
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

	enemy.free()


# ---------------------------------------------------------------------------
# Test 3: target moves mid-step → current step target stays the same
# ---------------------------------------------------------------------------

func _test_target_moves_mid_step() -> void:
	var enemy := _make_unready_enemy(18)
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

	enemy.free()


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
# Test 6: Runtime move speed, not walk_interval_ms, owns interpolation. Every
#         neighbor direction uses the same Ground-GU/s scalar; diagonal cells
#         therefore take sqrt(2) times the axis duration. Cadence still records
#         the high-level grant.
# ---------------------------------------------------------------------------

func _test_multi_step_visual_continuity() -> void:
	var directions := NeighborPolicy.allowed_neighbors()
	assert(directions.size() == 8, "runtime speed evidence must cover all eight neighbors")
	var player_run_speed := float(CombatUnitLegacyAdapterScript.PLAYER_MOVE_SPEED_GU_PER_SEC)
	var player_ground_direction := Vector2(1.0, 1.0).normalized()
	var player_screen_velocity := GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(
		player_ground_direction,
		player_run_speed,
	)
	var player_ground_velocity := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		player_screen_velocity,
	)
	assert(
		is_equal_approx(player_ground_velocity.length(), player_run_speed),
		"Player run projection must preserve normalized Ground-GU/s",
	)
	var measured_speeds: Array[float] = []
	var measured_durations: Array[float] = []
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var axis_duration := 0.0
	var diagonal_duration := 0.0
	for neighbor: Vector2i in directions:
		var enemy := await _make_enemy(18)
		enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(0.5, 0.5)), &"test_setup")
		var ready_ms := Time.get_ticks_msec() + 1000
		assert(
			enemy._request_autonomous_step(
				Vector2(neighbor),
				1.0,
				false,
				&"speed_test",
				ready_ms,
			)
		)
		var start_ground := _screen_px_to_ground_gu(enemy.global_position)
		var selected_distance := enemy._movement_step_distance_gu
		var expected_distance := start_ground.distance_to(enemy._movement_step_target_ground_gu)
		assert(
			is_equal_approx(selected_distance, expected_distance),
			"captured step distance must remain Ground-GU distance for %s" % neighbor,
		)
		var frames := 0
		while enemy._movement_step_active and frames < 120:
			enemy._advance_autonomous_step(physics_delta)
			frames += 1
		assert(not enemy._movement_step_active, "neighbor step must complete for %s" % neighbor)
		var final_ground := _screen_px_to_ground_gu(enemy.global_position)
		var travelled_gu := start_ground.distance_to(final_ground)
		var duration_seconds := float(frames) * physics_delta
		var measured_speed := travelled_gu / maxf(duration_seconds, physics_delta)
		assert(
			absf(measured_speed - enemy.move_speed_gu_per_sec)
			<= enemy.move_speed_gu_per_sec * 0.08,
			"Ground-GU/s must be direction invariant for %s: expected=%f measured=%f"
			% [neighbor, enemy.move_speed_gu_per_sec, measured_speed],
		)
		measured_speeds.append(measured_speed)
		measured_durations.append(duration_seconds)
		if neighbor.x == 0 or neighbor.y == 0:
			axis_duration = duration_seconds
		else:
			diagonal_duration = duration_seconds
		assert(
			int(enemy._movement_cadence.walk_tick_ms) == ready_ms,
			"cadence grant timestamp must remain authoritative history",
		)
		enemy.queue_free()
		await get_tree().physics_frame
	assert(axis_duration > 0.0 and diagonal_duration > 0.0)
	var diagonal_duration_ratio := diagonal_duration / axis_duration
	assert(
		diagonal_duration_ratio >= 1.30 and diagonal_duration_ratio <= 1.55,
		"diagonal Ground-GU step must take sqrt(2) times axis duration: ratio=%f"
		% diagonal_duration_ratio,
	)
	assert(measured_speeds.size() == 8 and measured_durations.size() == 8)
	_checks += 4 + directions.size() * 5


# ---------------------------------------------------------------------------
# Test 7: Existing speed scales multiply exact runtime speed.
# ---------------------------------------------------------------------------

func _test_scaled_step_keeps_continuous_motion() -> void:
	var enemy := await _make_enemy(18)
	enemy.set_physics_process(false)
	enemy.set_combat_position(_ground_gu_to_screen_px(Vector2(0.5, 0.5)), &"test_setup")
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var speed_scale := 0.75
	var expected_duration_seconds := 1.0 / enemy.move_speed_gu_per_sec / speed_scale
	var expected_frames := int(ceil(expected_duration_seconds / physics_delta))
	var started := enemy._request_autonomous_step(
		Vector2.RIGHT,
		speed_scale,
		false,
		&"scaled_continuity_test",
		Time.get_ticks_msec() + 1000,
	)
	assert(started, "scaled step must start after cadence grant")
	var target_ground := enemy._movement_step_target_ground_gu
	var travelled_gu := 0.0
	for frame_index in range(expected_frames):
		assert(
			enemy._movement_step_active,
			"scaled step arrived before its scaled duration at frame %d/%d"
			% [frame_index, expected_frames],
		)
		var before_ground := _screen_px_to_ground_gu(enemy.global_position)
		enemy._advance_autonomous_step(physics_delta)
		var after_ground := _screen_px_to_ground_gu(enemy.global_position)
		var frame_motion := before_ground.distance_to(after_ground)
		assert(
			frame_motion > GroundUnitSpaceScript.EPSILON_GU,
			"scaled step must move every visual frame, including its final frame",
		)
		travelled_gu += frame_motion
	assert(not enemy._movement_step_active, "scaled step must finish")
	assert(
		_screen_px_to_ground_gu(enemy.global_position).distance_to(target_ground)
		<= GroundUnitSpaceScript.EPSILON_GU,
		"scaled step must finish at its selected neighbor",
	)
	assert(
		travelled_gu > GroundUnitSpaceScript.EPSILON_GU
		and expected_frames > int(ceil(1.0 / enemy.move_speed_gu_per_sec / physics_delta)),
		"scale 0.75 must preserve the existing slower runtime-speed semantics",
	)
	_checks += 4 + expected_frames * 2

	enemy.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 8: Next movement event must wait for cadence interval
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
	var stationary := _make_unready_enemy(30)
	assert(stationary._movement_cadence != null)
	assert(stationary._movement_cadence.source_status == Cadence.STATUS_LOCKED)
	_force_cadence_ready(stationary)
	assert(
		not stationary._request_autonomous_step(Vector2.RIGHT, 1.0, false, &"stationary_test"),
		"LOCKED stationary monster must never start a movement step",
	)
	assert(not stationary._movement_step_active)
	_checks += 3
	stationary.free()

	var compatibility := _make_unready_enemy(41)
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
	compatibility.free()


func _test_quantized_facing_matches_neighbor() -> void:
	var enemy := _make_unready_enemy(18)
	_force_cadence_ready(enemy)
	assert(enemy._request_autonomous_step(Vector2(100.0, -0.01), 1.0, false, &"facing_test"))
	assert(enemy._movement_step_neighbor == Vector2i(1, -1), "desired direction must quantize to the diagonal neighbor")
	var expected_facing := enemy._screen_facing_for_ground_direction(
		NeighborPolicy.desired_ground_direction(Vector2i(1, -1))
	)
	assert(enemy.movement_facing.is_equal_approx(expected_facing), "walk animation facing must follow the actual quantized neighbor")
	_checks += 3
	enemy.free()


func _test_engagement_completion_does_not_rollback() -> void:
	var player := PlayerCharacter.new()
	player.name = "CadenceEngagementPlayer"
	add_child(player)
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.set_touch_vector(Vector2.ZERO)
	var player_ground := Vector2(0.5, 0.5)
	player.global_position = _ground_gu_to_screen_px(player_ground)

	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.environment_blocker = null
	enemy.set_meta("safe_zones", [])
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)

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

	var enemy := RuntimeEnemyFixture.new()
	enemy.setup(GameData.get_monster_by_id(18), player, false)
	enemy.move_speed_gu_per_sec = 3.0
	enemy.environment_blocker = null
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.set_physics_process(false)

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
