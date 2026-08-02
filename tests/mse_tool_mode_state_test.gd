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
	assert(MapEditorInstanceService.all_instances(editor.current_document)[0].collision_policy == "terrain_stamp_generated")
	assert(not MapEditorCollisionService.build_walkability(editor.current_document).blocked_tiles.has("%d,%d" % [colliding_asset_origin.x, colliding_asset_origin.y]))
	_click_preview_tile(editor, Vector2i(8, 9), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 3)
	assert(not MapEditorCollisionService.build_walkability(editor.current_document).blocked_tiles.has("8,9"))
	_click_preview_tile(editor, Vector2i(8, 9), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision_erase.size() == 2)
	editor.preview._gui_input(cancel_collision)
	assert(editor.active_tool_mode == "place" and editor.preview.interaction_mode == "place")
	assert(not editor.collision_erase_toggle.button_pressed)
	var cell_index := _option_index(editor.collision_shape_option, "cell")
	assert(cell_index >= 0)
	editor.collision_shape_option.select(cell_index)
	editor._on_collision_shape_selected(cell_index)
	_click_preview_tile(editor, colliding_asset_origin, MOUSE_BUTTON_LEFT)
	assert(MapEditorCollisionService.build_walkability(editor.current_document).blocked_tiles.has("%d,%d" % [colliding_asset_origin.x, colliding_asset_origin.y]))
	assert(editor.current_document.layers.collision_erase.size() == 1)
	_click_preview_tile(editor, Vector2i(15, 15), MOUSE_BUTTON_LEFT)
	_drag_preview_tile(editor, Vector2i(16, 15))
	assert(editor.current_document.layers.collision.size() == 5)
	assert(editor.current_document.layers.collision[3].data.rect == [15, 15, 1, 1])
	assert(editor.current_document.layers.collision[4].data.rect == [16, 15, 1, 1])
	editor.collision_erase_whole_toggle.set_pressed_no_signal(true)
	editor._on_collision_erase_whole_toggled(true)
	assert(editor.active_tool_mode == "manual_collision_erase_whole")
	_click_preview_tile(editor, Vector2i(8, 9), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.collision.size() == 4)
	_click_preview_tile(editor, colliding_asset_origin, MOUSE_BUTTON_LEFT)
	assert(MapEditorInstanceService.all_instances(editor.current_document)[0].collision_policy == "none")
	editor.preview._gui_input(cancel_collision)
	assert(editor.active_tool_mode == "place")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and not editor.collision_draw_toggle.button_pressed and not editor.collision_erase_toggle.button_pressed and not editor.collision_erase_whole_toggle.button_pressed)
	editor._activate_normal_placement()
	assert(editor.active_tool_mode == "place" and editor.preview.interaction_mode == "place")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic")
	editor._activate_select_tool()
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	editor.semantic_kind_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and editor.preview.interaction_mode == "semantic")
	editor.semantic_kind_option.select(monster_index)
	editor._on_semantic_kind_selected(monster_index)
	_click_preview_tile(editor, Vector2i(5, 5), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.monster_spawn.size() == 1)
	var monster_semantic_id := str(editor.current_document.layers.monster_spawn[0].semantic_id)
	assert(editor.preview.selected_selectable_id == monster_semantic_id)
	var move_right := InputEventKey.new()
	move_right.keycode = KEY_RIGHT
	move_right.pressed = true
	editor.preview._gui_input(move_right)
	assert(editor.current_document.layers.monster_spawn[0].tile == [6, 5])
	assert(editor.active_tool_mode == "semantic")
	var copy_shortcut := InputEventKey.new()
	copy_shortcut.keycode = KEY_C
	copy_shortcut.ctrl_pressed = true
	copy_shortcut.pressed = true
	editor._unhandled_key_input(copy_shortcut)
	assert(str(editor.element_clipboard.get("element_type", "")) == "semantic")
	var paste_shortcut := InputEventKey.new()
	paste_shortcut.keycode = KEY_V
	paste_shortcut.ctrl_pressed = true
	paste_shortcut.pressed = true
	editor._unhandled_key_input(paste_shortcut)
	assert(editor.preview.is_clipboard_paste_active())
	_move_preview_mouse_to_tile(editor, Vector2i(10, 8))
	assert(editor.preview._hover_tile == Vector2i(10, 8))
	await get_tree().process_frame
	_click_preview_tile(editor, Vector2i(10, 8), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.monster_spawn.size() == 2)
	assert(editor.current_document.layers.monster_spawn[1].tile == [10, 8])
	assert(str(editor.current_document.layers.monster_spawn[1].semantic_id) != monster_semantic_id)
	assert(editor.preview.selected_selectable_id == str(editor.current_document.layers.monster_spawn[1].semantic_id))
	assert(not editor.preview.is_clipboard_paste_active())
	editor._unhandled_key_input(paste_shortcut)
	assert(editor.preview.is_clipboard_paste_active())
	var cancel_paste := InputEventMouseButton.new()
	cancel_paste.button_index = MOUSE_BUTTON_RIGHT
	cancel_paste.pressed = true
	editor.preview._gui_input(cancel_paste)
	assert(not editor.preview.is_clipboard_paste_active())
	assert(editor.current_document.layers.monster_spawn.size() == 2)
	editor._activate_select_tool()
	_click_preview_tile(editor, Vector2i(6, 5), MOUSE_BUTTON_LEFT)
	assert(editor.preview.selected_selectable_id == monster_semantic_id)
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	assert(editor.semantic_content_id.text == original_monster_id)
	var move_down := InputEventKey.new()
	move_down.keycode = KEY_DOWN
	move_down.pressed = true
	editor.preview._gui_input(move_down)
	assert(editor.current_document.layers.monster_spawn[0].tile == [6, 6])
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	_click_preview_tile(editor, Vector2i(10, 8), MOUSE_BUTTON_LEFT)
	assert(editor.preview.selected_selectable_id == str(editor.current_document.layers.monster_spawn[1].semantic_id))
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	var entrance_index := _option_index(editor.semantic_kind_option, "map_entrance")
	var exit_index := _option_index(editor.semantic_kind_option, "map_exit")
	var respawn_index := _option_index(editor.semantic_kind_option, "respawn_point")
	var safe_area_index := _option_index(editor.semantic_kind_option, "safe_area")
	assert(entrance_index >= 0 and exit_index >= 0 and respawn_index >= 0 and safe_area_index >= 0)
	editor.semantic_kind_option.select(entrance_index)
	editor._on_semantic_kind_selected(entrance_index)
	editor.semantic_display_name.text = "古墓入口"
	_click_preview_tile(editor, Vector2i(18, 18), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.map_entrance_points.size() == 1)
	assert(str(editor.current_document.layers.map_entrance_points[0].display_name) == "古墓入口")
	var delete_selected := InputEventKey.new()
	delete_selected.keycode = KEY_DELETE
	delete_selected.pressed = true
	assert(editor.preview.selected_selectable_id == str(editor.current_document.layers.map_entrance_points[0].semantic_id))
	assert(editor.active_tool_mode == "semantic")
	editor.preview._gui_input(delete_selected)
	assert(editor.current_document.layers.map_entrance_points.is_empty())
	assert(editor.preview.selected_selectable_id.is_empty())
	_click_preview_tile(editor, Vector2i(18, 18), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.map_entrance_points.size() == 1)
	editor._activate_select_tool()
	var entrance_semantic_id := str(editor.current_document.layers.map_entrance_points[0].semantic_id)
	editor.preview.selected_selectable_id = entrance_semantic_id
	editor._on_selectable_selected(entrance_semantic_id, false)
	assert(editor.preview.selected_selectable_id == entrance_semantic_id)
	assert(editor.active_tool_mode == "select" and editor.preview.interaction_mode == "select")
	editor.semantic_kind_option.select(exit_index)
	editor._on_semantic_kind_selected(exit_index)
	assert(editor.semantic_display_name.text.is_empty())
	assert(editor.semantic_content_id.text.is_empty())
	assert(editor.semantic_target_map.text.is_empty())
	assert(editor.semantic_target_entrance.text.is_empty())
	editor.semantic_display_name.text = "古墓墙门出口"
	editor.semantic_target_map.text = ""
	_click_preview_tile(editor, Vector2i(19, 18), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.map_exit_points.size() == 1)
	assert(
		not editor.current_document.layers.map_exit_points[0].has(
			"radius_gu"
		)
	)
	var exit_id := str(editor.current_document.layers.map_exit_points[0].semantic_id)
	editor.preview.selected_selectable_id = exit_id
	editor._on_selectable_selected(exit_id, false)
	editor.semantic_target_map.text = "wooma_forest"
	editor.semantic_target_entrance.text = "map_entrance_000001"
	editor._on_update_selected_semantic_pressed()
	assert(str(editor.current_document.layers.map_exit_points[0].target_map_id) == "wooma_forest")
	editor._unhandled_key_input(delete_selected)
	assert(editor.current_document.layers.map_exit_points.is_empty())
	assert(editor.preview.selected_selectable_id.is_empty())
	editor.semantic_kind_option.select(respawn_index)
	editor._on_semantic_kind_selected(respawn_index)
	_click_preview_tile(editor, Vector2i(20, 20), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(21, 20), MOUSE_BUTTON_LEFT)
	assert(editor.current_document.layers.respawn_points.size() == 2)
	assert(not bool(editor.current_document.layers.respawn_points[0].is_default))
	assert(bool(editor.current_document.layers.respawn_points[1].is_default))
	editor.semantic_kind_option.select(safe_area_index)
	editor._on_semantic_kind_selected(safe_area_index)
	_click_preview_tile(editor, Vector2i(22, 22), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(26, 22), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(26, 26), MOUSE_BUTTON_LEFT)
	_click_preview_tile(editor, Vector2i(22, 26), MOUSE_BUTTON_LEFT)
	assert(editor.safe_polygon_points.size() == 4)
	editor._unhandled_key_input(finish_polygon)
	assert(editor.current_document.layers.safe_area.size() == 1)
	assert(str(editor.current_document.layers.safe_area[0].shape) == "polygon")
	assert(editor.current_document.layers.safe_area[0].polygon_ground_gu.size() == 4)
	assert(editor.preview.selected_selectable_id == str(editor.current_document.layers.safe_area[0].semantic_id))
	editor.preview._gui_input(delete_selected)
	assert(editor.current_document.layers.safe_area.is_empty())
	_click_preview_tile(editor, Vector2i(24, 24), MOUSE_BUTTON_LEFT)
	assert(editor.safe_polygon_points.size() == 1)
	editor.preview._gui_input(cancel_collision)
	assert(editor.safe_polygon_points.is_empty())
	assert(editor.active_tool_mode == "semantic")
	editor.preview._gui_input(cancel_collision)
	assert(editor.active_tool_mode == "place")
	var brazier := MapEditorInstanceService.create_instance(
		editor.current_document,
		"cave_dungeon.brazier_01",
		"decoration",
		Vector2i(2, 28)
	)
	assert(brazier.ok, str(brazier.get("errors", [])))
	editor.preview.selected_selectable_id = str(brazier.instance.instance_id)
	editor._unhandled_key_input(copy_shortcut)
	assert(str(editor.element_clipboard.get("element_type", "")) == "instance")
	editor._unhandled_key_input(paste_shortcut)
	assert(editor.preview.is_clipboard_paste_active())
	_move_preview_mouse_to_tile(editor, Vector2i(4, 28))
	await get_tree().process_frame
	_click_preview_tile(editor, Vector2i(4, 28), MOUSE_BUTTON_LEFT)
	var pasted_brazier := MapEditorInstanceService._locate(
		editor.current_document,
		editor.preview.selected_selectable_id
	)
	assert(pasted_brazier.ok)
	assert(str(pasted_brazier.instance.asset_id) == "cave_dungeon.brazier_01")
	assert(pasted_brazier.instance.tile == [4, 28])
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
	event.position = editor.preview._draw_offset + MapEditorCoordinate.cell_center_to_ground_px(Vector2(tile), design_size) * editor.preview._draw_scale
	editor.preview._gui_input(event)


func _drag_preview_tile(editor: MapEditorApp, tile: Vector2i) -> void:
	var design_size_raw: Array = editor.current_document.design.design_size
	var design_size := Vector2i(int(design_size_raw[0]), int(design_size_raw[1]))
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = editor.preview._draw_offset + MapEditorCoordinate.cell_center_to_ground_px(Vector2(tile), design_size) * editor.preview._draw_scale
	editor.preview._gui_input(event)


func _move_preview_mouse_to_tile(editor: MapEditorApp, tile: Vector2i) -> void:
	var design_size_raw: Array = editor.current_document.design.design_size
	var design_size := Vector2i(int(design_size_raw[0]), int(design_size_raw[1]))
	var event := InputEventMouseMotion.new()
	event.position = editor.preview._draw_offset + MapEditorCoordinate.cell_center_to_ground_px(
		Vector2(tile),
		design_size
	) * editor.preview._draw_scale
	editor.preview._gui_input(event)
