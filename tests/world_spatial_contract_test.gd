extends Node

const SpatialRules := preload("res://scripts/world_spatial_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.travel_to_map(4)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(game.player.collision_layer == SpatialRules.PLAYER_LAYER, "Player collision layer bypasses the spatial contract")
	assert(game.player.collision_mask == SpatialRules.PLAYER_MASK, "Player collision mask bypasses the spatial contract")
	assert(game.player.environment_blocker == game.background, "Player does not use the active world occupancy provider")
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(not enemies.is_empty(), "Spatial contract test requires an authored monster")
	for enemy: EnemyActor in enemies:
		assert(enemy.collision_layer == SpatialRules.ENEMY_LAYER or enemy.collision_layer == 0, "Enemy collision layer bypasses the spatial contract")
		assert(enemy.environment_blocker == game.background, "Enemy does not use the active world occupancy provider")

	var content := MapEditorRuntimeBridge.game_content()
	var zones: Array = content.get("safe_areas", [])
	assert(zones.size() == 1, "Bich must expose one authoritative safe area")
	var safe_zone: Dictionary = zones[0]
	assert(safe_zone.get("shape") == "circle", "Bich safe area must be circular")
	assert(safe_zone.get("center_ground_gu") == MapEditorRuntimeBridge.home_position_ground_gu(), "Safe area center differs from the resurrection point")
	assert(is_equal_approx(float(safe_zone.get("radius_gu")), 9.0), "Safe area radius is not nine GU")
	var compiled_context: Dictionary = game.safe_zone_runtime_context()
	assert(bool(compiled_context.get("valid", false)), "safe-zone context is not valid")
	assert(int(compiled_context.get("map_id", -1)) == game.current_map_id)
	assert(int(compiled_context.get("revision", -1)) > 0)
	assert((compiled_context.get("zones", []) as Array).size() == 1)
	assert(compiled_context.get("zones", [])[0].get("aabb_ground_gu") is Rect2)
	var cache_before: Dictionary = game.get("_player_safe_zone_cache")
	assert(bool(cache_before.get("valid", false)), "player safe-zone cache not primed")
	var runtime := MapEditorRuntimeBridge.load_bich()
	var home_screen_px := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime,
		safe_zone.center_ground_gu,
	)
	game._set_player_world_position(home_screen_px)
	assert(game._player_inside_active_safe_zone(), "player cache missed teleport into safe area")
	var cache_after: Dictionary = game.get("_player_safe_zone_cache")
	assert(
		(cache_after.get("ground_position_gu") as Vector2).is_equal_approx(
			safe_zone.center_ground_gu,
		),
		"player safe-zone cache did not refresh on teleport",
	)

	var outside := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime, Vector2(-1.0, 0.0))
	assert(game.background.is_environment_point_blocked(outside), "Map exterior is not part of unified occupancy")
	var first_blocked := str(runtime.get("collision", {}).get("blocked_tiles", [])[0]).split(",")
	var obstacle := MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime, [float(first_blocked[0]), float(first_blocked[1])])
	assert(game.background.is_environment_point_blocked(obstacle), "Editor obstacle is not part of unified occupancy")

	var probe := enemies[0] as EnemyActor
	probe.set_combat_position(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime,
		safe_zone.center_ground_gu
	), &"test_safe_zone_probe")
	game._enforce_bich_safe_zone()
	var probe_ground_gu := MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(
		runtime,
		probe.global_position
	)
	assert(not SpatialRules.point_inside_safe_zones_ground_gu(probe_ground_gu, zones), "Monster remained inside the safe area")
	assert(probe_ground_gu.distance_to(safe_zone.center_ground_gu) >= float(safe_zone.radius_gu) + probe.combat_radius_gu - 0.001, "Safe-area ejection ignored actor radius")

	print("WORLD_SPATIAL_CONTRACT_PASS: movement, occupancy, safe area and hard boundary use one contract")
	get_tree().quit(0)
