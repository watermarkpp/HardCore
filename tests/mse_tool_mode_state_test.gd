extends Node


func _ready() -> void:
	var editor := MapEditorApp.new()
	add_child(editor)
	editor._build_ui()
	editor.current_document = MapEditorTypes.new_map("tool_mode_state", 990012, "Tool Mode State", Vector2i(32, 32))
	editor.preview.set_document(editor.current_document)
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
	editor.collision_draw_toggle.set_pressed_no_signal(true)
	editor._on_collision_draw_toggled(true)
	assert(editor.active_tool_mode == "manual_collision" and editor.preview.interaction_mode == "manual_collision")
	editor.semantic_content_option.pressed.emit()
	assert(editor.active_tool_mode == "semantic" and not editor.collision_draw_toggle.button_pressed)
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
