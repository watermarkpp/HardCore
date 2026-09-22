extends Node

const Rules := preload("res://scripts/world_spatial_rules.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for frame in range(240):
		await get_tree().process_frame
		if not game._world_bootstrap_in_progress and game._target_spatial_query_ready():
			break
	assert(game._target_spatial_query_ready(), "Formal map must be query ready")
	game.set_process(false)
	var runtime := Bridge.load_map(game.current_map_id)
	var size: Array = runtime.design.design_size
	var origin: Vector2 = game.player.global_position
	var origin_ground: Vector2 = game._canonical_screen_px_to_ground_gu(origin)
	game._rng.seed = 20260906
	var quadrants := {}
	var successes := 0
	var far_count := 0
	for attempt in range(128):
		var point: Vector2 = game._find_valid_random_teleport_position(origin)
		if point == origin:
			continue
		var ground: Vector2 = game._canonical_screen_px_to_ground_gu(point)
		assert(ground.x >= 0.0 and ground.x < float(size[0]))
		assert(ground.y >= 0.0 and ground.y < float(size[1]))
		assert(not Rules.environment_blocks_actor_screen_px(game.background, point, ArtSpec.PLAYER_COLLISION_RADIUS_PX))
		quadrants[Vector2i(int(ground.x >= float(size[0]) / 2.0), int(ground.y >= float(size[1]) / 2.0))] = true
		if ground.distance_to(origin_ground) > 16.25:
			far_count += 1
		successes += 1
	assert(successes >= 120, "Unexpected rejection rate on the formal Bich map")
	assert(far_count >= 32, "Random teleport remains constrained to the old local radius")
	assert(quadrants.size() == 4, "Full-map sampling must reach all four quarters")
	var map_before: int = game.current_map_id
	game.current_map_id = -12345
	assert(game._find_valid_random_teleport_position(origin) == origin, "Invalid map must fail closed")
	game.current_map_id = map_before
	game.queue_free()
	await get_tree().process_frame
	print("RANDOM_TELEPORT_MAP_EXTENT_PASS: full-map legal landings and invalid-map rejection")
	get_tree().quit(0)
