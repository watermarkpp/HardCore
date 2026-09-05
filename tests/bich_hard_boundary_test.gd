extends Node

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

func _ready() -> void:
	var runtime := MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	var bich_map_id := _runtime_map_id("world_bich_province")
	assert(bich_map_id == int(runtime.runtime_map_id))
	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data(
		"比奇省", GameData.get_map_by_id(bich_map_id)
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var boundary_count := _boundary_shape_count(background)
	assert(boundary_count == 4, "地图四边实体碰撞未完整生成")

	var raw_size: Array = runtime.design.design_size
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var visual_boundary: PackedVector2Array = CollisionGeometry.map_inner_boundary_world(size)
	var edge_direction: Vector2 = visual_boundary[1] - visual_boundary[0]
	var outward: Vector2 = Vector2(edge_direction.y, -edge_direction.x).normalized()
	# Probe the actual published boundary edge.  The old half-cell ground point
	# was already outside this polygon, so its nominal "inside" start overlapped
	# the boundary body before move_and_collide ran.
	var edge: Vector2 = visual_boundary[0].lerp(visual_boundary[1], 0.5)
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().physics_frame
	var expected_player_position := (
		CollisionGeometry.project_player_foot_inside_boundary(edge, size)
	)
	player.global_position = expected_player_position - outward * 8.0
	var player_collision := player.move_and_collide(outward * 160.0)
	assert(player_collision != null, "玩家可越过地图外部黑区硬边界")
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
	var straw_man := GameData.get_monster_by_id(21)
	assert(
		int(straw_man.get("monster_id", -1)) == 21
		and str(straw_man.get("canonical_name", "")) == "稻草人"
	)
	enemy.setup(straw_man, null, false)
	add_child(enemy)
	await get_tree().physics_frame
	var expected_enemy_position := (
		CollisionGeometry.project_world_envelope_inside_visible_boundary(
			edge,
			size,
			WorldSpatialRules.actor_footprint_polygon_px(
				enemy.collision_radius_px
			)
		)
	)
	enemy.global_position = expected_enemy_position - outward * 8.0
	var enemy_collision := enemy.move_and_collide(outward * 160.0)
	assert(enemy_collision != null, "怪物可越过地图外部黑区硬边界")
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


func _runtime_map_id(map_key: String) -> int:
	for raw_map: Variant in GameData.get_available_maps(true):
		if (
			raw_map is Dictionary
			and str((raw_map as Dictionary).get("formalMapKey", "")) == map_key
		):
			return int((raw_map as Dictionary).get("mapId", -1))
	return -1
