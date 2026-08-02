extends Node

const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _settle()
	for map_id: int in [4, 313, 217, 406]:
		game.travel_to_map(map_id)
		await _settle()
		var runtime := RuntimeBridge.load_map(map_id)
		var blocked: Array = runtime.collision.blocked_tiles
		assert(not blocked.is_empty(), "map %d has no blocked cells" % map_id)
		var parts := str(blocked[0]).split(",")
		var raw_cell := [float(parts[0]), float(parts[1])]
		var blocked_center := RuntimeBridge.grid_cell_to_screen_position_px(runtime, raw_cell)
		assert(game.background.is_environment_point_blocked(blocked_center), "software collision offset map %d" % map_id)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = blocked_center
		query.collision_mask = 1
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var space_state: PhysicsDirectSpaceState2D = (game as Node2D).get_world_2d().direct_space_state
		var hits: Array[Dictionary] = space_state.intersect_point(query, 8)
		assert(not hits.is_empty(), "Physics2D collision offset map %d" % map_id)
		var content := RuntimeBridge.game_content_for_map(map_id)
		var authored_spawns: Array = runtime.semantics.monster_spawn
		if not authored_spawns.is_empty():
			assert(not content.spawns.is_empty())
			assert((content.spawns[0].position as Vector2).is_equal_approx(
				RuntimeBridge.grid_cell_to_screen_position_px(runtime, authored_spawns[0].tile)
			), "spawn cell center offset map %d" % map_id)
	if game.current_map_id != 217:
		game.travel_to_map(217)
		await _settle()
	var occluders: Array[Node] = []
	for child: Node in game.get_children():
		if bool(child.get_meta("editor_runtime_actor_occluder", false)):
			occluders.append(child)
	assert(not occluders.is_empty(), "Orc wall fronts are not in actor Y-sort domain")
	for occluder: Node in occluders:
		assert(occluder.get_parent() == game)
		assert(occluder.get_child_count() == 1)
		var sprite := occluder.get_child(0) as Sprite2D
		assert(sprite != null and sprite.z_index == 0)
		assert(str(sprite.get_meta("editor_runtime_render_domain", "")) == "actor_y_sort")
	print("MAP_EDITOR_RUNTIME_ALIGNMENT_PASS maps=4,313,217,406 collision_y=+16 wall_occluders=%d" % occluders.size())
	get_tree().quit(0)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
