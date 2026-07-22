extends Node


const ENEMY_COUNT := 96
const GROUP_COUNT := 4
const ENEMIES_PER_GROUP := ENEMY_COUNT / GROUP_COUNT


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
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
	assert(int(crowd_metrics.crowd_grid_builds) == 1, "crowd grid rebuilt for each enemy")
	assert(int(crowd_metrics.crowd_grid_actor_scans) == ENEMY_COUNT, "crowd grid did not scan the active set exactly once")
	assert(int(crowd_metrics.crowd_query_candidates) <= ENEMY_COUNT * 28, "crowd queries regressed toward O(N^2): %s" % crowd_metrics)
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
	player.global_position = near_enemy.global_position + Vector2(80, 0)
	near_enemy.target = player
	near_enemy._retarget_timer = 0.0
	EnemyActor.reset_performance_diagnostics()
	for step in range(60):
		near_enemy._retarget(1.0 / 60.0)
	assert(int(EnemyActor.performance_diagnostics().retarget_full_scans) <= 7, "near-field target decisions ran at render rate: %s" % EnemyActor.performance_diagnostics())
	print("MONSTER_CROWD_STAGE retarget %s" % EnemyActor.performance_diagnostics())

	# Model a dense tomb room: 96 pursuing actors remain smooth at physics rate,
	# but collision steering is recomputed at 10 Hz and re-used between ticks.
	player.global_position = Vector2(108, 54)
	for enemy: EnemyActor in enemies:
		enemy.target = player
		enemy._crowd_steering_timer = EnemyActor.CROWD_STEERING_INTERVAL_SECONDS * float(posmod(enemy.get_instance_id(), 7)) / 7.0
	EnemyActor.reset_performance_diagnostics()
	for step in range(60):
		for enemy: EnemyActor in enemies:
			enemy._crowd_separation_for_motion(1.0 / 60.0)
	var dense_metrics := EnemyActor.performance_diagnostics()
	assert(int(dense_metrics.crowd_steering_evaluations) <= ENEMY_COUNT * 12, "dense steering still ran per actor per frame: %s" % dense_metrics)
	assert(int(dense_metrics.crowd_grid_actor_scans) <= ENEMY_COUNT * 22, "dense crowd grid still rebuilt every physics frame: %s" % dense_metrics)
	print("MONSTER_CROWD_STAGE dense %s" % dense_metrics)

	# Actors well outside both camera and aggro working sets only wake four times
	# per second. Status/threat/alternate-target actors must never take this path.
	player.global_position = Vector2(50000, 50000)
	var background_enemy: EnemyActor = enemies[1]
	background_enemy.target = player
	assert(background_enemy._can_use_background_ai(), "far idle actor did not enter background AI tier")
	background_enemy._add_threat(player, 10.0)
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
	EnemyActor.reset_performance_diagnostics()
	for enemy: EnemyActor in survivors:
		enemy._crowd_separation()
	var respawn_metrics := EnemyActor.performance_diagnostics()
	assert(int(respawn_metrics.crowd_grid_builds) == 1, "respawned crowd rebuilt the index more than once")
	assert(int(respawn_metrics.crowd_grid_actor_scans) == ENEMY_COUNT, "dead actors remained in the rebuilt crowd index")
	assert(int(respawn_metrics.crowd_query_candidates) <= ENEMY_COUNT * 32, "respawned crowd query count became unbounded")

	print("MONSTER_CROWD_PERFORMANCE_PASS 96 enemies use one spatial build; far retarget bounded; kill/respawn index clean")
	get_tree().quit(0)


func _spawn_groups(player: PlayerCharacter, id_offset: int, count := ENEMY_COUNT) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	for index in range(count):
		var group_index := index / ENEMIES_PER_GROUP
		var local_index := index % ENEMIES_PER_GROUP
		var position := Vector2(group_index * 1600 + (local_index % 6) * 36, (local_index / 6) * 36)
		var enemy := EnemyActor.new()
		enemy.setup({"monsterId": -10000 - id_offset - index, "name": "crowd_perf_%d" % (id_offset + index), "hp": 10}, player, false)
		enemy.global_position = position
		enemy.set_meta("spawn_position", position)
		add_child(enemy)
		enemy.set_physics_process(false)
		result.append(enemy)
	return result


func _naive_separation(enemy: EnemyActor, enemies: Array[EnemyActor]) -> Vector2:
	var separation := Vector2.ZERO
	for other: EnemyActor in enemies:
		if other == enemy or other.is_queued_for_deletion():
			continue
		var away := enemy.global_position - other.global_position
		var desired := enemy.collision_radius + other.collision_radius + 12.0
		var distance := away.length()
		if distance >= desired:
			continue
		if distance < 0.01:
			var angle := float(posmod(enemy.get_instance_id(), 16)) / 16.0 * TAU
			away = Vector2.from_angle(angle)
			distance = 1.0
		separation += away.normalized() * (1.0 - distance / desired)
	return separation.limit_length(1.0)
