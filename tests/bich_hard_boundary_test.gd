extends Node

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

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
	var edge := MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(float(size.x) * 0.5 - 0.5, -0.5), size)
	var visual_boundary := CollisionGeometry.map_inner_boundary_world(size)
	var edge_direction := visual_boundary[1] - visual_boundary[0]
	var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().physics_frame
	player.global_position = edge - outward * (ArtSpec.PLAYER_COLLISION_RADIUS_PX + 4.0)
	var player_collision := player.move_and_collide(outward * 160.0)
	assert(player_collision != null, "玩家可越过地图外部黑区硬边界")
	var expected_player_position := (
		CollisionGeometry.project_player_foot_inside_boundary(edge, size)
	)
	assert(
		player.global_position.distance_to(expected_player_position) <= 1.5,
		"玩家物理坐标与脚底边界投影不一致"
	)
	assert(
		CollisionGeometry.player_foot_inside_boundary(
			player.global_position, size
		),
		"玩家脚底仍可进入地图外部黑区"
	)
	player.queue_free()
	await get_tree().process_frame

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster("稻草人"), null, false)
	add_child(enemy)
	await get_tree().physics_frame
	enemy.global_position = edge - outward * (enemy.collision_radius_px + 4.0)
	var enemy_collision := enemy.move_and_collide(outward * 160.0)
	assert(enemy_collision != null, "怪物可越过地图外部黑区硬边界")
	var expected_enemy_position := (
		CollisionGeometry.project_world_envelope_inside_visible_boundary(
			edge,
			size,
			WorldSpatialRules.actor_footprint_polygon_px(
				enemy.collision_radius_px
			)
		)
	)
	assert(
		enemy.global_position.distance_to(expected_enemy_position) <= 1.5,
		"怪物物理坐标与脚底边界投影不一致"
	)
	print("BICH_HARD_BOUNDARY_PASS：玩家与怪物完整脚底均被同一可见地面边界阻挡")
	get_tree().quit(0)


func _boundary_shape_count(background: WorldBackground) -> int:
	var count := 0
	for body: Node in background.get_children():
		if body is StaticBody2D:
			for shape: Node in body.get_children():
				if shape is CollisionShape2D and shape.name.begins_with("MapBoundary"):
					count += 1
	return count
