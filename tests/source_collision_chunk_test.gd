extends Node

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	await _verify_map(game, 4, Vector2i(700, 700))
	await _verify_map(game, 217, Vector2i(400, 400))
	await _verify_map(game, 401, Vector2i(200, 200))
	await _verify_map(game, 402, Vector2i(100, 100))
	await _verify_map(game, 1578, Vector2i(30, 30))
	print("SOURCE_COLLISION_CHUNK_PASS：三种原MAP掩码与两种编辑器运行图碰撞、路线清空和切图重建正常")
	get_tree().quit(0)


func _verify_map(game: Node, map_id: int, expected_size: Vector2i) -> void:
	game.travel_to_map(map_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var background: WorldBackground = game.background
	var content := RegionContent.get_map_content(map_id)
	if map_id in [4, 217, 1578]:
		# 已发布地表的编辑器运行图以 runtime JSON 阻挡和四边硬边界为
		# 权威来源，不再加载旧原 MAP 位图掩码。
		assert(background.source_collision_mask_size() == Vector2i.ZERO, "地图%d仍错误加载旧原MAP掩码" % map_id)
		assert(background.source_collision_shape_count() >= 4, "地图%d编辑器阻挡或四边硬边界缺失" % map_id)
		assert(background.editor_runtime_ground_ready(), "地图%d编辑器运行时地表未就绪" % map_id)
		if map_id == 217:
			assert(background.editor_runtime_chunk_texture_count() == 5, "兽人古墓一层正式编辑器地表块未完整加载")
			assert(not background.uses_editor_runtime_fallback_ground(), "兽人古墓一层错误回退到旧地表")
			assert(background._editor_runtime_size == Vector2i(38, 38), "兽人古墓一层碰撞仍在使用旧400x400尺寸")
			assert(not background.is_environment_point_blocked(game.player.global_position), "兽人古墓一层出生点被阻挡")
		if map_id == 1578:
			assert(background.editor_runtime_chunk_texture_count() == 2, "尸王殿发布地表块未完整加载")
			assert(MapEditorRuntimeBridge.game_content_for_map(1578).portals.is_empty(), "尸王殿不应生成出口")
		return
	assert(background.source_collision_mask_size() == expected_size, "地图%d阻挡掩码尺寸错误" % map_id)
	assert(background.source_collision_shape_count() > 0 and background.source_collision_shape_count() <= 703, "地图%d局部合并碰撞数量异常：%d" % [map_id, background.source_collision_shape_count()])
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content.get(group_name, []):
			var source: Vector2i = entry.get("source_coordinate", Vector2i(-1, -1))
			assert(not background.source_mask_cell_blocked(source, true), "地图%d的%s安全点未从原阻挡清出" % [map_id, group_name])
	var focus_source := Vector2i(Mapper.world_to_source(game.player.global_position, expected_size).round())
	var raw_blocked := Vector2i(-1, -1)
	for y in range(maxi(0, focus_source.y - 18), mini(expected_size.y, focus_source.y + 19)):
		for x in range(maxi(0, focus_source.x - 18), mini(expected_size.x, focus_source.x + 19)):
			var candidate := Vector2i(x, y)
			if background.source_mask_cell_blocked(candidate, false) and background.source_mask_cell_blocked(candidate, true):
				raw_blocked = candidate
				break
		if raw_blocked.x >= 0:
			break
	assert(raw_blocked.x >= 0, "地图%d镜头块内没有保留任何原MAP阻挡" % map_id)
	assert(background.is_environment_point_blocked(Mapper.source_to_world(Vector2(raw_blocked), expected_size)), "地图%d原MAP阻挡没有进入运行查询" % map_id)
	if map_id == 4:
		await _verify_player_cannot_cross(game, background, focus_source, expected_size)


func _verify_player_cannot_cross(game: Node, background: WorldBackground, focus_source: Vector2i, source_size: Vector2i) -> void:
	var blocked := Vector2i(-1, -1)
	var start_source := Vector2i(-1, -1)
	for y in range(maxi(0, focus_source.y - 16), mini(source_size.y, focus_source.y + 17)):
		for x in range(maxi(0, focus_source.x - 16), mini(source_size.x, focus_source.x + 17)):
			var candidate := Vector2i(x, y)
			if not background.source_mask_cell_blocked(candidate, true):
				continue
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var approach_one := candidate + offset
				var approach_two := candidate + offset * 2
				if Mapper.contains_source(Vector2(approach_two), source_size) \
						and not background.source_mask_cell_blocked(approach_one, true) \
						and not background.source_mask_cell_blocked(approach_two, true):
					blocked = candidate
					start_source = approach_two
					break
			if blocked.x >= 0:
				break
		if blocked.x >= 0:
			break
	assert(blocked.x >= 0, "没有找到具有两格安全助跑距离的原MAP阻挡格")
	var start := Mapper.source_to_world(Vector2(start_source), source_size)
	var blocked_center := Mapper.source_to_world(Vector2(blocked), source_size)
	var direction := start.direction_to(blocked_center)
	game.player.global_position = start
	await get_tree().physics_frame
	game.player.set_touch_vector(direction)
	var entered_blocked_cell := false
	for _frame in range(30):
		await get_tree().physics_frame
		var current_source := Vector2i(Mapper.world_to_source(game.player.global_position, source_size).round())
		if background.source_mask_cell_blocked(current_source, true):
			entered_blocked_cell = true
			break
	game.player.set_touch_vector(Vector2.ZERO)
	assert(not entered_blocked_cell, "角色中心实际进入了原MAP阻挡格")
