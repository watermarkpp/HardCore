extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const AcquisitionPolicy := preload("res://scripts/monster_target_acquisition_policy.gd")
const NeighborPolicy := preload("res://scripts/monster_neighbor_step_policy.gd")
const TerrainPolicy := preload("res://scripts/monster_terrain_navigation_policy.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const PlayerCharacterScript := preload("res://scripts/player.gd")
const SkillProjectileScript := preload("res://scripts/skill_projectile.gd")

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
	await _test_runtime_map_id_fast_paths(player)
	await _test_current_center_and_nearest_manhattan(player)
	await _test_target_retention_authority(player)
	await _test_formal_terrain_los_and_bounded_detour(player)
	_test_all_released_terrain_contexts()
	_test_terrain_policy_budget_and_corner_contract()
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


func _test_formal_terrain_los_and_bounded_detour(player: PlayerCharacter) -> void:
	var enemy := await _make_enemy(18, player)
	enemy.configure_runtime_map_projection(
		990001,
		func(ground_gu: Vector2) -> Vector2:
			return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_gu),
		func(screen_px: Vector2) -> Vector2:
			return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_px),
	)
	enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(2.5, 5.5)
	)
	enemy.set_meta("spawn_position", enemy.global_position)
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(4.5, 5.5)
	)

	# Missing exact formal terrain identity is fail-closed, and a canonical wall
	# inside the existing 5-GU square blocks first acquisition.
	enemy.target = null
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == null)
	enemy.configure_terrain_navigation_context(_terrain_context(["3,5"]))
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == null)
	enemy.configure_terrain_navigation_context(_terrain_context([]))
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player)
	_checks += 3
	TerrainPolicy.reset_diagnostics()
	var open_neighbor := enemy._terrain_neighbor_for_pursuit(
		Vector2(2.5, 5.5),
		player,
		Vector2i.RIGHT,
	)
	assert(open_neighbor == Vector2i.RIGHT)
	assert(int(TerrainPolicy.diagnostics().path_queries) == 0)
	_checks += 2

	# Threat keeps the target through a wall. A long wall forces several cached
	# detour steps; a temporarily clear direct neighbor must not discard the
	# route while static LOS remains blocked.
	var long_wall: Array = []
	for y in range(2, 8):
		long_wall.append("3,%d" % y)
	enemy.configure_terrain_navigation_context(_terrain_context(long_wall))
	enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(2.5, 5.5)
	)
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(6.5, 5.5)
	)
	enemy._add_threat(player, 1.0)
	TerrainPolicy.reset_diagnostics()
	EnemyActor.reset_performance_diagnostics()
	var current_ground := Vector2(2.5, 5.5)
	for step_index in range(4):
		var desired := player.global_position - enemy.global_position
		var desired_ground := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(desired)
		var direct_neighbor := NeighborPolicy.neighbor_for_desired_ground_direction(desired_ground)
		var detour_neighbor := enemy._terrain_neighbor_for_pursuit(
			current_ground,
			player,
			direct_neighbor,
		)
		assert(detour_neighbor != Vector2i.ZERO)
		var next_cell := NeighborPolicy.temporary_cell(current_ground) + detour_neighbor
		current_ground = NeighborPolicy.cell_center_ground_gu(next_cell)
		enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			current_ground
		)
		_checks += 1
	assert(int(TerrainPolicy.diagnostics().path_queries) == 1)
	assert(int(EnemyActor.performance_diagnostics().retarget_target_group_scans) == 0)
	_checks += 2

	# Sealed terrain performs one bounded query, starts no movement event, then
	# observes the instance-staggered >=500 ms cooldown on the immediate retry.
	enemy.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(2.5, 5.5)
	)
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(6.5, 5.5)
	)
	enemy.configure_terrain_navigation_context(_terrain_context([
		"1,4", "2,4", "3,4",
		"1,5",        "3,5",
		"1,6", "2,6", "3,6",
	]))
	enemy.target = player
	TerrainPolicy.reset_diagnostics()
	var started := enemy._begin_autonomous_step_without_cadence(
		Vector2.RIGHT, 1.0, false, &"pursuit", player
	)
	assert(not started and not enemy._movement_step_active)
	var queries_after_failure := int(TerrainPolicy.diagnostics().path_queries)
	assert(queries_after_failure == 1)
	started = enemy._begin_autonomous_step_without_cadence(
		Vector2.RIGHT, 1.0, false, &"pursuit", player
	)
	assert(not started and not enemy._movement_step_active)
	assert(int(TerrainPolicy.diagnostics().path_queries) == queries_after_failure)
	_checks += 4

	enemy.queue_free()
	await get_tree().process_frame


func _test_runtime_map_id_fast_paths(player: PlayerCharacter) -> void:
	const TEST_RUNTIME_MAP_ID := 93001
	var enemy := await _make_enemy(18, player)
	enemy.runtime_map_id = TEST_RUNTIME_MAP_ID
	player.remove_meta("runtime_map_id")
	assert(player.get_script() == PlayerCharacterScript)
	var player_property_count := player.get_property_list().size()
	assert(player_property_count > 0, "real PlayerCharacter must expose inherited properties")

	var summon := SummonActor.new()
	summon.setup(player, "骷髅", 10, 1, "taoist.summon_skeleton", 35)
	summon.runtime_map_id = TEST_RUNTIME_MAP_ID
	add_child(summon)
	await get_tree().process_frame
	var enemy_property_count := enemy.get_property_list().size()
	var summon_property_count := summon.get_property_list().size()
	assert(enemy_property_count > 0 and summon_property_count > 0)

	EnemyActor.reset_runtime_map_id_diagnostics()
	assert(enemy._runtime_map_id_for_area_target(player) == TEST_RUNTIME_MAP_ID)
	assert(enemy._runtime_map_id_for_area_target(enemy) == TEST_RUNTIME_MAP_ID)
	assert(enemy._runtime_map_id_for_area_target(summon) == TEST_RUNTIME_MAP_ID)
	assert(
		int(EnemyActor.runtime_map_id_diagnostics().get("property_list_scans", -1)) == 0,
		"typed Player/Enemy/Summon paths must not scan property lists",
	)

	# Metadata remains the highest-priority identity source. Negative metadata
	# falls back to the live typed/attacker map instead of poisoning identity.
	summon.set_meta("runtime_map_id", TEST_RUNTIME_MAP_ID + 1)
	assert(enemy._runtime_map_id_for_area_target(summon) == TEST_RUNTIME_MAP_ID + 1)
	summon.set_meta("runtime_map_id", -1)
	assert(enemy._runtime_map_id_for_area_target(summon) == TEST_RUNTIME_MAP_ID)
	summon.remove_meta("runtime_map_id")
	summon.runtime_map_id = TEST_RUNTIME_MAP_ID + 2
	assert(enemy._runtime_map_id_for_area_target(summon) == TEST_RUNTIME_MAP_ID + 2)

	# A script with a runtime_map_id property remains on the generic compatibility
	# path, including live value mutation without caching.
	var generic := SkillProjectileScript.new()
	generic.runtime_map_id = TEST_RUNTIME_MAP_ID
	var generic_property_count := generic.get_property_list().size()
	assert(generic_property_count > 0)
	EnemyActor.reset_runtime_map_id_diagnostics()
	assert(enemy._runtime_map_id_for_area_target(generic) == TEST_RUNTIME_MAP_ID)
	assert(
		int(EnemyActor.runtime_map_id_diagnostics().get("property_list_scans", -1)) == 1,
		"generic typed property must retain one compatibility scan",
	)
	generic.runtime_map_id = TEST_RUNTIME_MAP_ID + 3
	assert(enemy._runtime_map_id_for_area_target(generic) == TEST_RUNTIME_MAP_ID + 3)
	var no_property := Node2D.new()
	EnemyActor.reset_runtime_map_id_diagnostics()
	assert(enemy._runtime_map_id_for_area_target(no_property) == TEST_RUNTIME_MAP_ID)
	assert(int(EnemyActor.runtime_map_id_diagnostics().get("property_list_scans", -1)) == 1)

	# Same-map rejection must observe map mutation immediately; no identity cache
	# may outlive a transition or an explicit metadata update.
	player.set_meta("runtime_map_id", TEST_RUNTIME_MAP_ID + 4)
	assert(not enemy._target_candidate_is_live(player))
	player.set_meta("runtime_map_id", TEST_RUNTIME_MAP_ID)
	assert(enemy._target_candidate_is_live(player))
	player.set_meta("runtime_map_id", -1)
	assert(enemy._target_candidate_is_live(player))
	player.remove_meta("runtime_map_id")

	# Compare real-object property-list sizes and elapsed helper work without a
	# brittle wall-time threshold. The operation count is the acceptance gate.
	const ITERATIONS := 256
	EnemyActor.reset_runtime_map_id_diagnostics()
	var typed_started_usec := Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		enemy._runtime_map_id_for_area_target(player)
		enemy._runtime_map_id_for_area_target(enemy)
		enemy._runtime_map_id_for_area_target(summon)
	var typed_elapsed_usec := Time.get_ticks_usec() - typed_started_usec
	var typed_scans := int(EnemyActor.runtime_map_id_diagnostics().get("property_list_scans", -1))
	assert(typed_scans == 0)

	EnemyActor.reset_runtime_map_id_diagnostics()
	var generic_started_usec := Time.get_ticks_usec()
	for _iteration in range(ITERATIONS):
		enemy._runtime_map_id_for_area_target(generic)
	var generic_elapsed_usec := Time.get_ticks_usec() - generic_started_usec
	var generic_scans := int(EnemyActor.runtime_map_id_diagnostics().get("property_list_scans", -1))
	assert(generic_scans == ITERATIONS)
	print(
		(
			"MONSTER_RUNTIME_MAP_ID_FAST_PATH_PASS player_properties=%d enemy_properties=%d "
			+ "summon_properties=%d generic_properties=%d typed_usec=%d generic_usec=%d "
			+ "typed_scans=%d generic_scans=%d"
		)
		% [
			player_property_count,
			enemy_property_count,
			summon_property_count,
			generic_property_count,
			typed_elapsed_usec,
			generic_elapsed_usec,
			typed_scans,
			generic_scans,
		]
	)

	no_property.free()
	generic.free()
	summon.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _test_all_released_terrain_contexts() -> void:
	var released_ids := RuntimeBridge.released_map_ids()
	assert(not released_ids.is_empty())
	for runtime_map_id: int in released_ids:
		var runtime := RuntimeBridge.load_map(runtime_map_id)
		var context := TerrainPolicy.build_context(
			runtime_map_id,
			runtime,
			TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		)
		assert(TerrainPolicy.context_valid(context, runtime_map_id))
		assert(str(context.build_sha256) == str(runtime.build_sha256))
		var raw_size: Array = runtime.design.design_size
		assert(context.design_size == Vector2i(int(raw_size[0]), int(raw_size[1])))
		assert(int(context.blocked_count) == runtime.collision.blocked_tiles.size())
		assert(context.is_read_only())
		assert((context.blocked_cells as Dictionary).is_read_only())
		_checks += 6
	_checks += 1


func _test_terrain_policy_budget_and_corner_contract() -> void:
	var corner_context := _terrain_context(["3,2", "2,3"])
	assert(not TerrainPolicy.can_traverse_neighbor(
		corner_context,
		Vector2i(2, 2),
		Vector2i(3, 3),
		0.25,
	))
	assert(not TerrainPolicy.cell_walkable(corner_context, Vector2i(2, 2), 0.75))
	TerrainPolicy.reset_diagnostics()
	var clear_context := _terrain_context([])
	var first := TerrainPolicy.find_bounded_path(
		clear_context, Vector2i(1, 1), Vector2i(2, 1), 0.25
	)
	var second := TerrainPolicy.find_bounded_path(
		clear_context, Vector2i(1, 2), Vector2i(2, 2), 0.25
	)
	var third := TerrainPolicy.find_bounded_path(
		clear_context, Vector2i(1, 3), Vector2i(2, 3), 0.25
	)
	assert(first.accepted and second.accepted)
	assert(not third.accepted and third.reason == "frame_budget_exhausted")
	var diagnostics := TerrainPolicy.diagnostics()
	assert(int(diagnostics.path_queries) == 2)
	assert(int(diagnostics.path_budget_rejections) == 1)
	assert(int(diagnostics.max_queries_per_physics_frame) == 2)
	assert(int(diagnostics.path_expansions) <= TerrainPolicy.MAX_PATH_EXPANSIONS * 2)
	_checks += 8


func _terrain_context(blocked_tiles: Array) -> Dictionary:
	return TerrainPolicy.build_context(
		990001,
		{
			"build_sha256": "c".repeat(64),
			"source": {"runtime_map_id": 990001},
			"design": {"design_size": [12, 12]},
			"collision": {"blocked_tiles": blocked_tiles},
		},
		TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
	)


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
