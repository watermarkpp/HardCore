extends Node


func _ready() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	editor.current_document = MapEditorTypes.new_map("tool_mode_state", 990012, "Tool Mode State", Vector2i(32, 32))
	editor.preview.set_document(editor.current_document)
	await get_tree().process_frame
	var monster_index := -1
	for index in editor.semantic_kind_option.item_count:
		if str(editor.semantic_kind_option.get_item_metadata(index)) == "monster_spawn":
			monster_index = index
			break
	assert(monster_index >= 0)
	editor.semantic_kind_option.select(monster_index)
	editor._on_semantic_kind_selected(monster_index)
	assert(editor.active_tool_mode == "semantic")
	assert(editor.preview.interaction_mode == "semantic")
	var original_monster_id := editor.semantic_content_id.text
	assert(not original_monster_id.is_empty())
	editor.random_region_fill_toggle.set_pressed_no_signal(true)
	editor._on_lasso_mode_toggled(true)
	assert(editor.active_tool_mode == "lasso")
	assert(editor.preview.interaction_mode == "place" and editor.preview._region_paint_mode)
	assert(not editor.semantic_place_toggle.button_pressed)
	# Opening the already-selected monster menu must re-arm semantic placement;
	# selecting a different monster is no longer required.
	editor.semantic_content_option.pressed.emit()
	assert(editor.semantic_content_id.text == original_monster_id)
	assert(editor.active_tool_mode == "semantic")
	assert(editor.preview.interaction_mode == "semantic" and not editor.preview._region_paint_mode)
	assert(editor.semantic_place_toggle.button_pressed and not editor.random_region_fill_toggle.button_pressed)
	editor.point_erase_toggle.set_pressed_no_signal(true)
	editor._on_point_erase_toggled(true)
	assert(editor.active_tool_mode == "erase" and editor.preview.interaction_mode == "erase")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and not editor.point_erase_toggle.button_pressed)
	var ellipse_index := _option_index(editor.collision_shape_option, "ellipse")
	assert(ellipse_index >= 0)
	editor.collision_shape_option.select(ellipse_index)
	editor._on_collision_shape_selected(ellipse_index)
	assert(editor.active_tool_mode == "manual_collision" and editor.preview.interaction_mode == "manual_collision")
	assert(editor.collision_draw_toggle.button_pressed)
	assert("椭圆" in editor.collision_instruction_label.text)
	_click_preview_tile(editor, Vector2i(3, 4), MOUSE_BUTTON_LEFT)
	assert(editor.manual_collision_start == Vector2i(3, 4))
	assert(editor.preview._manual_collision_start == Vector2i(3, 4))
	_click_preview_tile(editor, Vector2i(5, 6), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 1)
	assert(editor.current_document.layers.collision[0].shape == "ellipse")
	assert(editor.manual_collision_start == Vector2i(-1, -1))
	var rect_index := _option_index(editor.collision_shape_option, "rect")
	editor.collision_shape_option.select(rect_index)
	editor._on_collision_shape_selected(rect_index)
	_click_preview_tile(editor, Vector2i(7, 8), MOUSE_BUTTON_LEFT)
	assert(editor.manual_collision_start == Vector2i(7, 8))
	var cancel_collision := InputEventMouseButton.new()
	cancel_collision.button_index = MOUSE_BUTTON_RIGHT
	cancel_collision.pressed = true
	cancel_collision.position = Vector2(100, 100)
	editor.preview._gui_input(cancel_collision)
	assert(editor.manual_collision_start == Vector2i(-1, -1))
	assert(editor.manual_polygon_points.is_empty())
	assert(editor.active_tool_mode == "manual_collision" and editor.preview.interaction_mode == "manual_collision")
	assert(editor.collision_draw_toggle.button_pressed)
	_click_preview_tile(editor, Vector2i(7, 8), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(9, 10), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 2)
	assert(editor.current_document.layers.collision[1].shape == "rect")
	editor.preview._gui_input(cancel_collision)
	assert(editor.active_tool_mode == "place" and editor.preview.interaction_mode == "place")
	assert(not editor.collision_draw_toggle.button_pressed)
	var polygon_index := _option_index(editor.collision_shape_option, "polygon")
	editor.collision_shape_option.select(polygon_index)
	editor._on_collision_shape_selected(polygon_index)
	assert(editor.active_tool_mode == "manual_collision")
	assert("多边形" in editor.collision_instruction_label.text)
	_click_preview_tile(editor, Vector2i(10, 10), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(13, 10), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(11, 13), MOUSE_BUTTON_LEFT)
	assert(editor.manual_polygon_points.size() == 3)
	var finish_polygon := InputEventKey.new()
	finish_polygon.keycode = KEY_ENTER
	finish_polygon.pressed = true
	editor._unhandled_key_input(finish_polygon)
	assert(editor.current_document.layers.collision.size() == 3)
	assert(editor.current_document.layers.collision[2].shape == "polygon")
	assert(editor.manual_polygon_points.is_empty())
	editor.collision_erase_toggle.set_pressed_no_signal(true)
	editor._on_collision_erase_toggled(true)
	assert(editor.active_tool_mode == "manual_collision_erase")
	assert(editor.preview.interaction_mode == "manual_collision_erase")
	assert(editor.collision_erase_toggle.button_pressed and not editor.collision_draw_toggle.button_pressed)
	var colliding_asset := MapEditorInstanceService.create_instance(editor.current_document, "terrain.palisade_wall_01", "terrain", Vector2i(20, 20), "terrain_base")
	assert(colliding_asset.ok)
	var colliding_asset_origin := MapEditorCollisionService._collision_origin(colliding_asset.instance)
	_click_preview_tile(editor, colliding_asset_origin, MOUSE_BUTTON_LEFT)
	assert(MapEditorInstanceService.all_instances(editor.current_document)[0].collision_policy == "none")
	_click_preview_tile(editor, Vector2i(8, 9), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 2)
	assert(editor.current_document.layers.collision.all(func(entry: Dictionary) -> bool: return entry.shape != "rect"))
	_click_preview_tile(editor, Vector2i(8, 9), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 2)
	editor.preview._gui_input(cancel_collision)
	assert(editor.active_tool_mode == "place" and editor.preview.interaction_mode == "place")
	assert(not editor.collision_erase_toggle.button_pressed)
	editor.collision_shape_option.select(rect_index)
	editor._on_collision_shape_selected(rect_index)
	_click_preview_tile(editor, Vector2i(15, 15), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(16, 16), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 3)
	assert(editor.current_document.layers.collision[2].collision_id == "manual_000004")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and not editor.collision_draw_toggle.button_pressed and not editor.collision_erase_toggle.button_pressed)
	editor._activate_normal_placement()
	assert(editor.active_tool_mode == "place" and editor.preview.interaction_mode == "place")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic")
	editor._activate_select_tool()
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	editor.semantic_kind_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and editor.preview.interaction_mode == "semantic")
	var linked_document := MapEditorTypes.new_map("linked_semantic", 990013, "Linked Semantic", Vector2i(32, 32))
	linked_document["layers"]["door_points"] = [{
		"semantic_id": "door_000001",
		"tile": [4, 6],
		"linked_visual_instance_id": "inst_000001",
	}]
	var sync_result := MapEditorGameplaySemanticService.sync_linked_instance_tile(linked_document, "inst_000001", Vector2i(2, 3))
	assert(sync_result.ok and sync_result.updated == 1)
	assert(linked_document["layers"]["door_points"][0]["tile"] == [2, 3])
	assert(MapEditorGameplaySemanticService.delete_linked_instance_entries(linked_document, "inst_000001") == 1)
	assert(linked_document["layers"]["door_points"].is_empty())
	editor.queue_free()
	print("MSE_TOOL_MODE_STATE_PASS")
	get_tree().quit()


func _option_index(option: OptionButton, metadata: String) -> int:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1


func _click_preview_tile(editor: MapEditorApp, tile: Vector2i, button: MouseButton) -> void:
	var design_size_raw: Array = editor.current_document.design.design_size
	var design_size := Vector2i(int(design_size_raw[0]), int(design_size_raw[1]))
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = editor.preview._draw_offset + MapEditorCoordinate.tile_to_ground_px(Vector2(tile), design_size) * editor.preview._draw_scale
	editor.preview._gui_input(event)
