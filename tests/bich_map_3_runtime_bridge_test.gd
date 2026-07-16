extends Node


func _ready() -> void:
	var runtime := MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.collision.blocked_tiles.size() > 0)
	var content := MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size() == runtime.semantics.get("monster_spawn", []).size())
	assert(content.npcs.size() == runtime.semantics.get("npc_points", []).size())
	assert(content.portals.size() == 0, "未配置目标的门点不得进入运行时")
	var safe: Dictionary = runtime.semantics.safe_area[0]
	assert(MapEditorRuntimeBridge.home_position() == MapEditorRuntimeBridge.tile_to_world(runtime, safe.return_tile))
	var background := WorldBackground.new(); add_child(background)
	background.set_zone_data("比奇省", {"mapId":4,"name":"比奇省"})
	await get_tree().process_frame
	await get_tree().process_frame
	var chunk_sprites := 0
	for child: Node in background.get_children():
		if child is Sprite2D and bool(child.get_meta("editor_runtime_chunk", false)): chunk_sprites += 1
	var visual_file := FileAccess.open("res://assets/data/runtime/map_editor/bich_province.visual.json", FileAccess.READ)
	var visual_manifest: Variant = JSON.parse_string(visual_file.get_as_text()) if visual_file != null else null
	assert(visual_manifest is Dictionary and chunk_sprites == visual_manifest.get("chunks", []).size())
	var boundary_shapes := 0
	for body: Node in background.get_children():
		if body is StaticBody2D:
			for shape: Node in body.get_children():
				if shape is CollisionShape2D and shape.name.begins_with("MapBoundary"):
					boundary_shapes += 1
	assert(boundary_shapes == 4, "地图四边实体碰撞未完整生成")
	print("BICH_MAP_3_RUNTIME_BRIDGE_PASS chunks=%d collision_shapes=%d" % [chunk_sprites, background.source_collision_shape_count()])
	get_tree().quit()
