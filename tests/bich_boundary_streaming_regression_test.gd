extends Node


func _ready() -> void:
	var visual_file := FileAccess.open("res://assets/data/runtime/map_editor/bich_province.visual.json", FileAccess.READ)
	assert(visual_file != null)
	var visual: Variant = JSON.parse_string(visual_file.get_as_text())
	visual_file.close()
	assert(visual is Dictionary)
	assert(bool(visual.get("coverage", {}).get("complete", false)), "比奇地表分块覆盖不完整")
	assert(int(visual.get("coverage", {}).get("required_chunk_count", 0)) == 13)
	assert(int(visual.get("coverage", {}).get("packaged_chunk_count", 0)) == 13)
	assert(str(visual.get("render_mode", "")) == "batched_canvas_draw")

	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data("比奇省", {"mapId": 4, "name": "比奇省"})
	await get_tree().process_frame
	await get_tree().process_frame

	assert(background.editor_runtime_chunk_texture_count() == 13)
	var guard_bands: Array[Node] = []
	var chunk_sprites := 0
	for child: Node in background.get_children():
		if bool(child.get_meta("editor_runtime_guard_band", false)):
			guard_bands.append(child)
		if child is Sprite2D and bool(child.get_meta("editor_runtime_chunk", false)):
			chunk_sprites += 1
	assert(guard_bands.size() == 1, "地图外侧地表缓冲未创建")
	assert(chunk_sprites == 0, "地表仍使用可能触发逐块 GPU 上传的 Sprite2D")

	var guard := guard_bands[0] as Polygon2D
	var guard_bounds := Rect2(guard.polygon[0], Vector2.ZERO)
	for point: Vector2 in guard.polygon:
		guard_bounds = guard_bounds.expand(point)
	var runtime := MapEditorRuntimeBridge.load_bich()
	var edge_probes := [
		MapEditorRuntimeBridge.tile_to_world(runtime, [-1.0, 0.0]),
		MapEditorRuntimeBridge.tile_to_world(runtime, [80.0, 0.0]),
		MapEditorRuntimeBridge.tile_to_world(runtime, [80.0, 80.0]),
		MapEditorRuntimeBridge.tile_to_world(runtime, [0.0, 80.0]),
	]
	for probe: Vector2 in edge_probes:
		assert(guard_bounds.has_point(probe), "边缘镜头探针未被地表缓冲覆盖：%s" % probe)

	var initial_environment_count := background._environment_nodes.size()
	var initial_collision_count := background.source_collision_shape_count()
	for probe: Vector2 in edge_probes:
		background.set_focus_position(probe)
		await get_tree().process_frame
		assert(background._environment_nodes.size() == initial_environment_count)
		assert(background.source_collision_shape_count() == initial_collision_count)
		assert(background.editor_runtime_chunk_texture_count() == 13)
	assert(not background._collision_rebuild_pending, "编辑器运行时不应触发动态碰撞重建")
	assert(background._source_collision_nodes.is_empty(), "编辑器运行时不应生成流式碰撞节点")
	print("BICH_BOUNDARY_STREAMING_REGRESSION_PASS chunks=13 guard_band=1 streaming_rebuilds=0")
	get_tree().quit(0)
