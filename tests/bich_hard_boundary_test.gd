extends Node


func _ready() -> void:
	var runtime := MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data("比奇省", {"mapId":4,"name":"比奇省"})
	await get_tree().process_frame
	await get_tree().process_frame
	var boundary_count := _boundary_shape_count(background)
	assert(boundary_count == 4, "地图四边实体碰撞未完整生成")

	var raw_size: Array = runtime.design.design_size
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var center_tile := (Vector2(size) - Vector2.ONE) * 0.5
	var center := MapEditorCoordinate.tile_to_world(center_tile, size)
	var edge := MapEditorCoordinate.tile_to_world(Vector2(float(size.x) * 0.5 - 0.5, -0.5), size)
	var outward := center.direction_to(edge)

	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().physics_frame
	player.global_position = edge - outward * (ArtSpec.PLAYER_COLLISION_RADIUS + 4.0)
	var player_collision := player.move_and_collide(outward * 160.0)
	assert(player_collision != null, "玩家可越过地图外部黑区硬边界")
	assert(player.global_position.distance_to(center) < edge.distance_to(center))
	player.queue_free()
	await get_tree().process_frame

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster("稻草人"), null, false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.global_position = edge - outward * (enemy.collision_radius + 4.0)
	var enemy_collision := enemy.move_and_collide(outward * 160.0)
	assert(enemy_collision != null, "怪物可越过地图外部黑区硬边界")
	assert(enemy.global_position.distance_to(center) < edge.distance_to(center))
	print("BICH_HARD_BOUNDARY_PASS：玩家与怪物均被四边实体边界阻挡")
	get_tree().quit(0)


func _boundary_shape_count(background: WorldBackground) -> int:
	var count := 0
	for body: Node in background.get_children():
		if body is StaticBody2D:
			for shape: Node in body.get_children():
				if shape is CollisionShape2D and shape.name.begins_with("MapBoundary"):
					count += 1
	return count
