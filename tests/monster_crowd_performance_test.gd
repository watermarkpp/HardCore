extends Node


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")
const ENEMY_COUNT := 96
const GROUP_COUNT := 4
const ENEMIES_PER_GROUP := ENEMY_COUNT / GROUP_COUNT
const CROWD_MAP_ID := 1

var _index: SpatialIndexScript


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_index = SpatialIndexScript.new()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(50000, 50000)
	var enemies := _spawn_groups(player, 0)
	await get_tree().process_frame
	print("MONSTER_CROWD_STAGE spawned")

	EnemyActor.reset_performance_diagnostics()
	for enemy: EnemyActor in enemies:
		var indexed := enemy._crowd_separation()
		var naive := _naive_separation(enemy, enemies)
		assert(indexed.distance_to(naive) < 0.001, "spatial crowd result changed separation behavior")
	var crowd_metrics := EnemyActor.performance_diagnostics()
	assert(int(crowd_metrics.crowd_grid_builds) == 0, "crowd retained a private grid build")
	assert(int(crowd_metrics.crowd_grid_actor_scans) == 0, "crowd retained a full actor scan")
	assert(RuntimeDiagnostics.performance_counter(&"crowd_full_group_scans") == 0, "crowd scanned the enemies group")
	assert(int(crowd_metrics.crowd_query_candidates) <= ENEMY_COUNT * 28, "crowd queries regressed toward O(N^2): %s" % crowd_metrics)
	assert(_index.index_neighbor_query_count == ENEMY_COUNT, "crowd did not use one shared neighbor query per actor")
	assert(_index.index_neighbor_candidate_count <= ENEMY_COUNT * 28, "crowd candidate count regressed toward full-map work")
	var ordered_a := _query_neighbor_instance_ids(Vector2.ZERO)
	var ordered_b := _query_neighbor_instance_ids(Vector2.ZERO)
	assert(ordered_a == ordered_b, "shared crowd query order was not deterministic")
	print("MONSTER_CROWD_STAGE indexed %s" % crowd_metrics)

	# Retargeting is a decision tick, not a render/physics tick. Existing targets
	# remain authoritative between decisions, and taking threat switches target
	# immediately in _add_threat().
	EnemyActor.reset_performance_diagnostics()
	for step in range(60):
		for enemy: EnemyActor in enemies:
			enemy._retarget(1.0 / 60.0)
	var far_metrics := EnemyActor.performance_diagnostics()
	assert(int(far_metrics.retarget_full_scans) <= ENEMY_COUNT * 5, "far retarget scans were not bounded: %s" % far_metrics)
	var near_enemy: EnemyActor = enemies[0]
	player.global_position = near_enemy.global_position + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(2.5, 0.0))
	near_enemy.target = player
	near_enemy._retarget_timer = 0.0
	EnemyActor.reset_performance_diagnostics()
	for step in range(60):
		near_enemy._retarget(1.0 / 60.0)
	assert(int(EnemyActor.performance_diagnostics().retarget_full_scans) <= 7, "near-field target decisions ran at render rate: %s" % EnemyActor.performance_diagnostics())
	print("MONSTER_CROWD_STAGE retarget %s" % EnemyActor.performance_diagnostics())

	# Model a dense tomb room: 96 pursuing actors remain smooth at physics rate,
	# but collision steering is recomputed at 10 Hz and re-used between ticks.
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(3.0, 3.0))
	for enemy: EnemyActor in enemies:
		enemy.target = player
		enemy._crowd_steering_timer = EnemyActor.CROWD_STEERING_INTERVAL_SECONDS * float(posmod(enemy.get_instance_id(), 7)) / 7.0
	EnemyActor.reset_performance_diagnostics()
	for step in range(60):
		for enemy: EnemyActor in enemies:
			enemy._crowd_separation_for_motion(1.0 / 60.0)
	var dense_metrics := EnemyActor.performance_diagnostics()
	assert(int(dense_metrics.crowd_steering_evaluations) <= ENEMY_COUNT * 12, "dense steering still ran per actor per frame: %s" % dense_metrics)
	assert(int(dense_metrics.crowd_grid_actor_scans) == 0, "dense crowd retained full actor scans")
	print("MONSTER_CROWD_STAGE dense %s" % dense_metrics)

	# Action budget: all 96 monsters advance for half a second, while imported
	# occupancy fallback checks stay at 10 Hz rather than 60 Hz. Enemy-to-enemy
	# collision is absent from the mask; world/player collision remains physical.
	EnemyActor.reset_performance_diagnostics()
	for step in range(30):
		for enemy: EnemyActor in enemies:
			enemy.velocity = GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(Vector2.RIGHT, enemy.move_speed_gu_per_sec)
			enemy._move_with_spatial_rules(1.0 / 60.0)
	var movement_metrics := EnemyActor.performance_diagnostics()
	assert(int(movement_metrics.physics_moves) == ENEMY_COUNT * 30, "moving crowd skipped playable motion ticks: %s" % movement_metrics)
	assert(int(movement_metrics.environment_guard_checks) <= ENEMY_COUNT * 6, "occupancy fallback returned to per-frame sampling: %s" % movement_metrics)
	for enemy: EnemyActor in enemies:
		assert(enemy.collision_mask == EnemyActor.ENEMY_MOTION_MASK and enemy.collision_mask == 3, "dense actor still participates in enemy mutual physics")
	print("MONSTER_CROWD_STAGE moving %s" % movement_metrics)

	# A forced relocation crosses buckets before another physics tick. The
	# caller-owned neighbor query must see the new bucket immediately and stop
	# returning the old one.
	var moved_enemy := enemies[0]
	var old_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		moved_enemy.global_position
	)
	var new_ground_gu := old_ground_gu + Vector2(8.0, 8.0)
	moved_enemy.set_combat_position(
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(new_ground_gu),
		&"crowd_cross_bucket",
	)
	var moved_ids := _query_neighbor_instance_ids(new_ground_gu)
	var old_ids := _query_neighbor_instance_ids(old_ground_gu)
	assert(moved_ids.has(moved_enemy.get_instance_id()), "cross-bucket crowd move was not immediately indexed")
	assert(not old_ids.has(moved_enemy.get_instance_id()), "cross-bucket crowd move remained in the old bucket")

	# Actors without an active target only wake four times per second, even when
	# near the player. The background decision tick still acquires the player,
	# after which the existing close-target foreground path resumes next frame.
	player.global_position = Vector2(50000, 50000)
	var background_enemy: EnemyActor = enemies[1]
	background_enemy.target = player
	assert(background_enemy._can_use_background_ai(), "far idle actor did not enter background AI tier")
	player.global_position = background_enemy.global_position + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(2.5, 0.0))
	background_enemy.target = null
	background_enemy._retarget_timer = 0.0
	assert(background_enemy._can_use_background_ai(), "near untargeted ordinary actor did not enter background AI tier")
	background_enemy._physics_process(1.0 / 60.0)
	assert(background_enemy._background_deep_sleeping, "background actor did not enter timer sleep")
	background_enemy._background_last_wakeup_msec = (
		Time.get_ticks_msec()
		- int(EnemyActor.BACKGROUND_AI_INTERVAL_SECONDS * 1000.0)
	)
	# Force the shared target-grid fixture to observe the deliberate player move;
	# this test is about crowd/index lifecycle, not target-grid refresh timing.
	EnemyActor._target_grid_last_refresh_msec = -1
	background_enemy._on_background_wakeup_timeout()
	assert(background_enemy.target == player, "background decision tick did not acquire the nearby player")
	assert(not background_enemy._can_use_background_ai(), "near acquired player target did not resume foreground AI")
	background_enemy.target = enemies[2]
	assert(not background_enemy._can_use_background_ai(), "alternate-target actor was incorrectly background-throttled")
	background_enemy._add_threat(player, 10.0)
	background_enemy.target = null
	assert(not background_enemy._can_use_background_ai(), "threatened actor was incorrectly background-throttled")
	background_enemy._threat_table.clear()
	print("MONSTER_CROWD_STAGE background")

	# Simulate a leveling pass that kills one quarter of the population, then a
	# respawn pass. The next frame must rebuild once without retaining dead actors.
	for index in range(0, enemies.size(), 4):
		enemies[index].take_damage(enemies[index].max_hp, player)
	await get_tree().process_frame
	var survivors: Array[EnemyActor] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			survivors.append(node)
	assert(survivors.size() == ENEMY_COUNT * 3 / 4, "kill pass did not remove the expected enemies")
	var respawned := _spawn_groups(player, 1000, ENEMY_COUNT / 4)
	await get_tree().process_frame
	survivors.append_array(respawned)
	assert(_index.registered_actor_count() == ENEMY_COUNT, "death/unregister/respawn left stale crowd entries")
	EnemyActor.reset_performance_diagnostics()
	for enemy: EnemyActor in survivors:
		enemy._crowd_separation()
	var respawn_metrics := EnemyActor.performance_diagnostics()
	assert(int(respawn_metrics.crowd_grid_builds) == 0, "respawned crowd rebuilt a private grid")
	assert(int(respawn_metrics.crowd_grid_actor_scans) == 0, "dead actors triggered a full crowd scan")
	assert(int(respawn_metrics.crowd_query_candidates) <= ENEMY_COUNT * 32, "respawned crowd query count became unbounded")
	_index.clear_map(CROWD_MAP_ID)
	assert(_index.registered_actor_count() == 0, "map clear retained old crowd entries")

	print("MONSTER_CROWD_PERFORMANCE_PASS 96 moving enemies use crowd authority; occupancy guard <=10Hz; retarget/respawn bounded")
	get_tree().quit(0)


func _spawn_groups(player: PlayerCharacter, id_offset: int, count := ENEMY_COUNT) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for index in range(count):
		var group_index := index / ENEMIES_PER_GROUP
		var local_index := index % ENEMIES_PER_GROUP
		var ground_position_gu := Vector2(
			float(group_index) * 50.0 + float(local_index % 6) * 1.125,
			float(local_index / 6) * 1.125
		)
		var position: Vector2 = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(ground_position_gu)
		var serial := id_offset + index + 1
		var enemy := EnemyActor.new()
		enemy.setup({"monsterId": 18, "name": "crowd_perf_%d" % serial, "hp": 10}, player, false)
		enemy.configure_runtime_map_projection(
			CROWD_MAP_ID,
			Callable(self, "_ground_to_screen"),
			Callable(self, "_screen_to_ground"),
		)
		enemy.configure_terrain_navigation_context(OpenTerrainFixture.build(CROWD_MAP_ID))
		enemy.configure_spatial_index(_index, serial)
		enemy.set_combat_position(position, &"crowd_spawn")
		enemy.set_meta("spawn_position", position)
		add_child(enemy)
		enemy.set_physics_process(false)
		_index.register(
			serial,
			CROWD_MAP_ID,
			ground_position_gu,
			enemy.combat_radius_gu,
			serial,
			enemy,
			Callable(enemy, "spatial_index_position"),
		)
		result.append(enemy)
	return result


func _naive_separation(enemy: EnemyActor, enemies: Array[EnemyActor]) -> Vector2:
	var separation := Vector2.ZERO
	for other: EnemyActor in enemies:
		if other == enemy or other.is_queued_for_deletion():
			continue
		var away := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(enemy.global_position - other.global_position)
		var desired := enemy.combat_radius_gu + other.combat_radius_gu + EnemyActor.CROWD_SEPARATION_GAP_GU
		var distance := away.length()
		if distance >= desired:
			continue
		if distance < 0.01:
			var angle := float(posmod(enemy.get_instance_id(), 16)) / 16.0 * TAU
			away = Vector2.from_angle(angle)
			distance = 1.0
		separation += away.normalized() * (1.0 - distance / desired)
	return separation.limit_length(1.0)


func _query_neighbor_instance_ids(center_ground_gu: Vector2) -> Array[int]:
	var nodes: Array[Node] = []
	_index.query_neighbor_enemy_nodes_into(
		CROWD_MAP_ID,
		center_ground_gu,
		2.0,
		nodes,
	)
	var result: Array[int] = []
	for node: Node in nodes:
		if is_instance_valid(node):
			result.append(node.get_instance_id())
	return result


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)
