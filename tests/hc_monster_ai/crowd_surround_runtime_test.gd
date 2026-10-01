extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Dense one-sided arrival. Attack-ready front actors keep attacking; only
## blocked rear actors wait for the bounded side retry. This checks that the
## crowd still deals real damage while the spatial-query load stays bounded.

class QueryProbe extends EnemyActor:
	var motion_queries := 0
	var attack_queries := 0
	var flank_batches := 0
	func _hc_motion_clear(a: Vector2, b: Vector2) -> bool:
		motion_queries += 1
		return super._hc_motion_clear(a, b)
	func _hc_frontline_at(a: Vector2, b: Vector2, hit_target: Node2D) -> int:
		attack_queries += 1
		return super._hc_frontline_at(a, b, hit_target)
	func _hc_prepare_flank_batch(current: Vector2, anchor: Vector2, cell: Vector2i) -> bool:
		flank_batches += 1
		return super._hc_prepare_flank_batch(current, anchor, cell)

func _spawn(mid: int, position: Vector2) -> EnemyActor:
	serial += 1
	var actor := QueryProbe.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"d3_fixture_spawn")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	return actor

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var actors: Array[EnemyActor] = []
	for index_value: int in range(30):
		var row := index_value / 5
		var column := index_value % 5
		var position := CENTER + Vector2(3.0 + float(column), -2.5 + float(row))
		var actor := _spawn(24, position)
		actor.dormant = false
		actor.target = player
		actor._retarget_timer = 999.0
		actors.append(actor)
	for actor: EnemyActor in actors:
		actor.set_physics_process(true)
	var started_usec := Time.get_ticks_usec()
	for frame: int in range(600):
		await get_tree().physics_frame
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var left_count := 0
	var engaged := 0
	var starts := 0
	for actor: EnemyActor in actors:
		var ground := _screen_to_ground(actor.global_position)
		assert(ground.is_finite(), "crowd actor lost its ground position")
		starts += actor._hc_starts
		if ground.x < CENTER.x - 0.5:
			left_count += 1
		if ground.distance_to(CENTER) <= 1.5:
			engaged += 1
	var query_count := index.index_enemy_node_segment_query_count
	var damage := player.max_hp - player.current_hp
	print("CROWD_BLOCKED_RETRY_METRICS left=%d engaged=%d starts=%d damage=%d queries=%d elapsed_ms=%.1f" % [left_count, engaged, starts, damage, query_count, elapsed_ms])
	var counts := {"motion": 0, "attack": 0, "flank": 0}
	for actor in actors:
		counts.motion += actor.motion_queries
		counts.attack += actor.attack_queries
		counts.flank += actor.flank_batches
	print("CROWD_QUERY_OWNERS ", counts)
	assert(engaged > 0 and starts > 0 and damage > 0, "bounded retry suppressed real melee")
	assert(query_count < 15000, "stationary blocked crowd repeated excessive segment queries")
	for actor: EnemyActor in actors:
		actor.set_physics_process(false)
		index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("CROWD_BLOCKED_RETRY_PASS left=%d engaged=%d starts=%d damage=%d queries=%d elapsed_ms=%.1f enemy_physics_usec=%d" % [left_count, engaged, starts, damage, query_count, elapsed_ms, RuntimeDiagnostics.performance_counter(&"enemy_physics_usec")])
	get_tree().quit(0)
