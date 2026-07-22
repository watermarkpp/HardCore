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
	assert(safe_zone.get("center") == MapEditorRuntimeBridge.home_position(), "Safe area center differs from the resurrection point")
	assert(is_equal_approx(float(safe_zone.get("radius")), 9.0 * ArtSpec.TILE_SIZE), "Safe area radius is not nine logical cells")

	var runtime := MapEditorRuntimeBridge.load_bich()
	var outside := MapEditorRuntimeBridge.tile_to_world(runtime, [-1.0, 0.0])
	assert(game.background.is_environment_point_blocked(outside), "Map exterior is not part of unified occupancy")
	var first_blocked := str(runtime.get("collision", {}).get("blocked_tiles", [])[0]).split(",")
	var obstacle := MapEditorRuntimeBridge.cell_to_world(runtime, [float(first_blocked[0]), float(first_blocked[1])])
	assert(game.background.is_environment_point_blocked(obstacle), "Editor obstacle is not part of unified occupancy")

	var probe := enemies[0] as EnemyActor
	probe.global_position = safe_zone.center
	game._enforce_bich_safe_zone()
	assert(not SpatialRules.point_inside_safe_zones(probe.global_position, zones), "Monster remained inside the safe area")
	assert(probe.global_position.distance_to(safe_zone.center) >= float(safe_zone.radius) + probe.collision_radius, "Safe-area ejection ignored actor radius")

	print("WORLD_SPATIAL_CONTRACT_PASS: movement, occupancy, safe area and hard boundary use one contract")
	get_tree().quit(0)
