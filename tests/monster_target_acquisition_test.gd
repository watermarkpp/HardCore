extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const AcquisitionPolicy := preload("res://scripts/monster_target_acquisition_policy.gd")

var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	await _test_view_five_runtime_boundaries(player)
	await _test_exact_special_view_ranges(player)
	await _test_runtime_classification_floors(player)
	await _test_data_hold_runtime_fail_closed(player)
	await _test_current_center_and_nearest_manhattan(player)
	await _test_target_retention_authority(player)
	_test_policy_fail_closed_contract()

	player.queue_free()
	print("MONSTER_TARGET_ACQUISITION_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _test_view_five_runtime_boundaries(player: PlayerCharacter) -> void:
	var enemy := await _make_enemy(18, player)
	assert(not enemy._target_acquisition_authority_failed_closed)
	assert(enemy._target_acquisition_policy.view_range_cells == 5)
	_checks += 2

	_assert_acquisition(enemy, player, Vector2(5.0, 0.0), true, "axis boundary 5")
	_assert_acquisition(enemy, player, Vector2(5.001, 0.0), false, "axis beyond 5")
	_assert_acquisition(enemy, player, Vector2(5.0, 5.0), true, "square corner 5,5")
	_assert_acquisition(enemy, player, Vector2(5.001, 5.0), false, "square x beyond 5")
	_assert_acquisition(enemy, player, Vector2(0.0, 5.001), false, "square y beyond 5")
	_assert_acquisition(enemy, player, Vector2(10.0, 0.0), false, "ordinary 10 rejected")

	# M02A applies only when there is no current target. Existing pursuit and
	# retarget semantics remain frozen and therefore retain this target at 10 GU.
	player.global_position = _ground_position_from_enemy(enemy, Vector2(10.0, 0.0))
	enemy.target = player
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player, "first-acquisition view cleared an existing target")
	_checks += 1

	enemy.queue_free()
	await get_tree().process_frame


func _test_exact_special_view_ranges(player: PlayerCharacter) -> void:
	var view_seven_enemy := await _make_enemy(153, player)
	assert(view_seven_enemy._target_acquisition_policy.view_range_cells == 7)
	_assert_acquisition(
		view_seven_enemy, player, Vector2(7.0, 7.0), true, "exact view 7 corner"
	)
	_assert_acquisition(
		view_seven_enemy, player, Vector2(7.001, 0.0), false, "exact view 7 overflow"
	)
	view_seven_enemy.queue_free()
	await get_tree().process_frame

	var view_nine_enemy := await _make_enemy(182, player)
	assert(view_nine_enemy._target_acquisition_policy.view_range_cells == 9)
	_assert_acquisition(
		view_nine_enemy, player, Vector2(9.0, 9.0), true, "exact view 9 corner"
	)
	_assert_acquisition(
		view_nine_enemy, player, Vector2(0.0, 9.001), false, "exact view 9 overflow"
	)
	view_nine_enemy.queue_free()
	await get_tree().process_frame
	_checks += 2


func _test_runtime_classification_floors(player: PlayerCharacter) -> void:
	var authority_file := FileAccess.open("res://assets/data/monster_runtime_authority_v1.json", FileAccess.READ)
	assert(authority_file != null, "runtime authority must be readable for classification floors")
	var payload: Variant = JSON.parse_string(authority_file.get_as_text())
	assert(payload is Dictionary)
	var records: Array = (payload as Dictionary).get("records", [])
	for raw_record: Variant in records:
		assert(raw_record is Dictionary)
		var record: Dictionary = raw_record
		if not bool(record.get("runtime_allowed", false)):
			continue
		var classification := str(record.get("classification", ""))
		var minimum_view := 0
		if classification == "elite":
			minimum_view = 7
		elif classification == "boss":
			minimum_view = 9
		if minimum_view <= 0:
			continue
		var targeting: Dictionary = record.get("targeting", {})
		if str(targeting.get("acquisition_status", "")) == "DATA_HOLD":
			continue
		assert(
			int(targeting.get("view_range_cells", 0)) >= minimum_view,
			"active %s must honor classification floor: monster_id=%s view=%s floor=%d"
			% [classification, record.get("monster_id", -1), targeting.get("view_range_cells"), minimum_view],
		)
		_checks += 1

	var dark_skeleton_spirit := await _make_enemy(238, player)
	assert(dark_skeleton_spirit._target_acquisition_policy.view_range_cells == 9)
	_assert_acquisition(
		dark_skeleton_spirit,
		player,
		Vector2(9.0, 0.0),
		true,
		"ID 238 boss classification floor axis boundary 9",
	)
	_assert_acquisition(
		dark_skeleton_spirit,
		player,
		Vector2(9.0, 9.0),
		true,
		"ID 238 boss classification floor square boundary 9",
	)
	_assert_acquisition(
		dark_skeleton_spirit,
		player,
		Vector2(9.001, 0.0),
		false,
		"ID 238 boss classification floor beyond 9",
	)
	dark_skeleton_spirit.queue_free()
	await get_tree().process_frame
	_checks += 4


func _test_data_hold_runtime_fail_closed(player: PlayerCharacter) -> void:
	var enemy := await _make_enemy(228, player)
	assert(enemy._target_acquisition_authority_failed_closed)
	assert(enemy._target_acquisition_policy.failed_closed)
	assert(
		enemy._target_acquisition_policy.rejection_reason
		== "acquisition_status_not_runnable:DATA_HOLD"
	)
	player.global_position = _ground_position_from_enemy(enemy, Vector2.ZERO)
	enemy.target = null
	enemy._threat_table.clear()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == null, "ID 228 DATA_HOLD acquired a runtime target")
	_checks += 4
	enemy.queue_free()
	await get_tree().process_frame


func _test_current_center_and_nearest_manhattan(player: PlayerCharacter) -> void:
	var enemy := await _make_enemy(18, player)
	# The monster may already have walked far from spawn. First acquisition is
	# still centered on its current Ground-GU cell and is not spawn-leash gated.
	enemy.global_position = _ground_position_from_enemy(enemy, Vector2(30.0, 0.0))
	# This scenario translates the actor 30 GU before round-tripping through the
	# isometric projection. Stay one float epsilon inside the already-tested
	# inclusive 5-GU boundary so the assertion measures leash behavior only.
	player.global_position = _ground_position_from_enemy(enemy, Vector2(4.99999, 0.0))
	enemy.target = null
	enemy._threat_table.clear()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player, "spawn leash narrowed current-cell ViewRange")
	_checks += 1

	var alternate := Node2D.new()
	add_child(alternate)
	alternate.add_to_group("combat_targets")
	# Euclidean would pick (3,3); original nearest-Manhattan must pick (5,0).
	player.global_position = _ground_position_from_enemy(enemy, Vector2(3.0, 3.0))
	alternate.global_position = _ground_position_from_enemy(enemy, Vector2(4.99999, 0.0))
	enemy.target = null
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == alternate, "first acquisition did not choose nearest Manhattan")
	_checks += 1

	# Equal Manhattan distance preserves candidate order; primary_target is first.
	player.global_position = _ground_position_from_enemy(enemy, Vector2(2.99999, 2.0))
	alternate.global_position = _ground_position_from_enemy(enemy, Vector2(4.99999, 0.0))
	enemy.target = null
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player, "equal Manhattan distance changed stable first-seen order")
	_checks += 1

	alternate.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _test_target_retention_authority(player: PlayerCharacter) -> void:
	var enemy := await _make_enemy(18, player)
	assert(enemy._target_focus_timeout_ms == 30000)
	assert(enemy._target_disengage_axis_cells == 15)

	# The original contract is an inclusive per-axis boundary, not the old
	# 12-GU Euclidean aggro circle. Its (15,15) corner must remain engaged.
	player.global_position = _ground_position_from_enemy(enemy, Vector2(15.0, 15.0))
	enemy.target = player
	enemy._target_focus_tick_ms = 1000
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player, "12-GU aggro circle cleared the 15-axis target")
	assert(not enemy._target_should_disengage(player, 31000), "30-second focus boundary must be inclusive")
	assert(enemy._target_should_disengage(player, 31001), "focus must expire strictly after 30 seconds")

	# Crossing either axis is sufficient to disengage, even when the other axis
	# remains aligned.
	enemy._target_focus_tick_ms = Time.get_ticks_msec()
	player.global_position = _ground_position_from_enemy(enemy, Vector2(16.0, 0.0))
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == null, "target beyond the 15-axis boundary was retained")
	_checks += 6

	enemy.queue_free()
	await get_tree().process_frame


func _test_policy_fail_closed_contract() -> void:
	var missing := AcquisitionPolicy.new()
	assert(not missing.configure({"monster_id": 18}, 18))
	assert(not missing.contains_ground_delta_gu(Vector2.ZERO))
	var invalid_zero := AcquisitionPolicy.new()
	assert(not invalid_zero.configure({
		"monster_id": 18,
		"targeting": {
			"acquisition_status": "CANDIDATE",
			"view_range_cells": 0,
		},
	}, 18))
	var invalid_type := AcquisitionPolicy.new()
	assert(not invalid_type.configure({
		"monster_id": 18,
		"targeting": {
			"acquisition_status": "CANDIDATE",
			"view_range_cells": "5",
		},
	}, 18))
	var data_hold_with_positive_view := AcquisitionPolicy.new()
	assert(not data_hold_with_positive_view.configure({
		"monster_id": 18,
		"targeting": {
			"acquisition_status": "DATA_HOLD",
			"view_range_cells": 5,
		},
	}, 18))
	var unknown_with_positive_view := AcquisitionPolicy.new()
	assert(not unknown_with_positive_view.configure({
		"monster_id": 18,
		"targeting": {
			"acquisition_status": "UNKNOWN",
			"view_range_cells": 5,
		},
	}, 18))
	var mismatched := AcquisitionPolicy.new()
	assert(not mismatched.configure({
		"monster_id": 24,
		"targeting": {
			"acquisition_status": "CANDIDATE",
			"view_range_cells": 5,
		},
	}, 18))
	_checks += 7


func _make_enemy(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
	assert(enemy.target == null, "setup must not pre-assign primary_target")
	_checks += 1
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().process_frame
	# Runtime scheduling may legitimately perform the first acquisition after
	# the actor enters the tree. Each scenario starts from an explicit null target.
	enemy.target = null
	enemy._threat_table.clear()
	return enemy


func _assert_acquisition(
	enemy: EnemyActor,
	player: PlayerCharacter,
	delta_ground_gu: Vector2,
	expected: bool,
	label: String
) -> void:
	player.global_position = _ground_position_from_enemy(enemy, delta_ground_gu)
	enemy.target = null
	enemy._threat_table.clear()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(
		(enemy.target == player) == expected,
		"%s expected=%s actual_target=%s" % [label, expected, enemy.target],
	)
	_checks += 1


func _ground_position_from_enemy(enemy: EnemyActor, delta_ground_gu: Vector2) -> Vector2:
	return enemy.global_position + (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(delta_ground_gu)
	)
