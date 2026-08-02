extends Node


func _ready() -> void:
	var runtime := MapEditorRuntimeBridge.load_bich()
	assert(not runtime.is_empty())
	assert(runtime.collision.blocked_tiles.size() > 0)
	var content := MapEditorRuntimeBridge.game_content()
	assert(content.spawns.size() == runtime.semantics.get("monster_spawn", []).size())
	assert(content.npcs.size() == runtime.semantics.get("npc_points", []).size())
	assert(content.portals.size() == 3, "沃玛森林、兽人古墓与矿区出口都应进入运行时")
	var portal_labels := {}
	for portal: Dictionary in content.portals:
		portal_labels[int(portal.target_map_id)] = str(portal.label)
	assert(portal_labels[217] == "进入兽人古墓一层")
	assert(portal_labels[268] == "前往沃玛森林")
	assert(portal_labels.has(406), "比奇省最下方矿区入口未进入主游戏运行时")
	var safe: Dictionary = runtime.semantics.safe_area[0]
	assert(not bool(safe.get("return_anchor", false)))
	assert(
		MapEditorRuntimeBridge.home_position().is_equal_approx(
			MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime, safe.tile)
		)
	)
	var background := WorldBackground.new(); add_child(background)
	background.set_zone_data("比奇省", {"mapId":4,"name":"比奇省"})
	await get_tree().process_frame
	await get_tree().process_frame
	var chunk_sprites := 0
	for child: Node in background.get_children():
		if child is Sprite2D and bool(child.get_meta("editor_runtime_chunk", false)): chunk_sprites += 1
	var visual_file := FileAccess.open("res://assets/data/runtime/map_editor/bich_province.visual.json", FileAccess.READ)
	var visual_manifest: Variant = JSON.parse_string(visual_file.get_as_text()) if visual_file != null else null
	assert(visual_manifest is Dictionary)
	assert(chunk_sprites == 0, "地表分块不应继续以按视野裁剪的 Sprite2D 形式加载")
	assert(background.editor_runtime_chunk_texture_count() == visual_manifest.get("chunks", []).size(), "runtime chunk textures=%d manifest chunks=%d" % [background.editor_runtime_chunk_texture_count(), visual_manifest.get("chunks", []).size()])
	assert(bool(visual_manifest.get("coverage", {}).get("complete", false)), "运行时地表分块覆盖不完整")
	var boundary_shapes := 0
	for body: Node in background.get_children():
		if body is StaticBody2D:
			for shape: Node in body.get_children():
				if shape is CollisionShape2D and shape.name.begins_with("MapBoundary"):
					boundary_shapes += 1
	assert(boundary_shapes == 4, "地图四边实体碰撞未完整生成")
	print("BICH_MAP_3_RUNTIME_BRIDGE_PASS chunks=%d collision_shapes=%d" % [background.editor_runtime_chunk_texture_count(), background.source_collision_shape_count()])
	get_tree().quit()
