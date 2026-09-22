extends Node2D

const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const MAP_ID := 913203


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.ensure_loaded())
	var runtime := MapEditorRuntimeBridge.load_map(MAP_ID)
	var context := Terrain.build_context(MAP_ID, runtime, "isometric_cell_center_64x32_v2")
	assert(context.has("poly_index"))
	var origin := Vector2.INF
	for y in range(4, 50):
		for x in range(4, 50):
			var point := Vector2(x, y) + Vector2(0.1, 0.1)
			if Terrain.point_walkable(context, point, 0.5) and Terrain.point_walkable(context, point + Vector2(6, 1.8), 0.5):
				origin = point
				break
		if origin.is_finite(): break
	assert(origin.is_finite())
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = _to_screen(origin + Vector2(6, 1.8))
	player.set_meta("runtime_map_id", MAP_ID)
	var checks := 0
	var index := RuntimeCombatSpatialIndex.new()
	var mismatches: Array[String] = []
	for mid: int in [110, 112, 116, 118, 120, 121]:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(mid), player, false)
		enemy.configure_runtime_map_projection(MAP_ID, _to_screen, _to_ground)
		enemy.configure_terrain_navigation_context(context)
		enemy.configure_spatial_index(index, mid)
		enemy.global_position = _to_screen(origin)
		enemy.target = player
		enemy.set_meta("safe_zones", [])
		# Run the production continuous path selection. No fake neighbour or
		# facing function: the actor computes both its endpoint and its pose.
		add_child(enemy)
		enemy.set_physics_process(false)
		enemy._hc_owned_movement_call = true
		enemy._hc_known_ground = origin + Vector2(6, 1.8)
		enemy._hc_known_target_id = player.get_instance_id()
		enemy._hc_observed = true
		enemy._hc_next_observation_ms = Time.get_ticks_msec() + 1000
		var started := enemy._begin_autonomous_step_without_cadence(Vector2(6, 1.8), 1.0, false, &"pursuit", player)
		if not started:
			print("STEP_NOT_STARTED mid=%d reason=%s origin=%s context=%s observed=%s known=%s" % [mid, enemy._hc_last_reason, origin, Terrain.context_valid(context, MAP_ID), enemy._hc_observed, enemy._hc_known_ground])
		if started:
			var delta := _to_screen(enemy._movement_step_target_ground_gu) - _to_screen(enemy._movement_step_start_ground_gu)
			checks += 1
			if not enemy.movement_facing.is_equal_approx(delta.normalized()):
				mismatches.append("mid=%d facing=%s movement=%s" % [mid, enemy.movement_facing, delta.normalized()])
		enemy.free()
	player.free()
	for mismatch: String in mismatches: print("STEP_FACING_MISMATCH ", mismatch)
	assert(checks >= 5, "fixture did not start the real movement steps")
	if not mismatches.is_empty():
		get_tree().quit(1)
		return
	print("MONSTER_CONTINUOUS_STEP_FACING_PASS checks=%d" % checks)
	get_tree().quit(0)


func _to_screen(point: Vector2) -> Vector2:
	return MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(MapEditorRuntimeBridge.load_map(MAP_ID), point)


func _to_ground(point: Vector2) -> Vector2:
	return MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(MapEditorRuntimeBridge.load_map(MAP_ID), point)
