extends Node


func _ready() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	editor.current_document = MapEditorTypes.new_map(
		"clipboard_input_regression",
		990191,
		"Clipboard Input Regression",
		Vector2i(32, 32)
	)
	editor.preview.set_document(editor.current_document)
	await get_tree().process_frame
	await get_tree().process_frame

	var monster_index := _option_index(editor.semantic_kind_option, "monster_spawn")
	assert(monster_index >= 0)
	editor.semantic_kind_option.select(monster_index)
	editor._on_semantic_kind_selected(monster_index)
	var source_tile := Vector2i(4, 4)
	_click_preview_tile(editor, source_tile)
	assert(editor.current_document.layers.monster_spawn.size() == 1)
	var source_id := str(editor.current_document.layers.monster_spawn[0].semantic_id)
	editor.preview.selected_selectable_id = source_id

	var copy_shortcut := _key(KEY_C, true)
	var paste_shortcut := _key(KEY_V, true)
	editor._unhandled_key_input(copy_shortcut)
	editor._unhandled_key_input(paste_shortcut)
	assert(editor.preview.is_clipboard_paste_active())

	# A physical click may be delivered as duplicate pressed events.  The
	# second pressed must not become a second semantic paste after the first
	# callback ends the paste preview.
	var repeated_press := _mouse_for_editor(Vector2i(9, 8), editor)
	editor.preview._gui_input(repeated_press)
	editor.preview._gui_input(repeated_press)
	assert(editor.current_document.layers.monster_spawn.size() == 2)
	repeated_press.pressed = false
	editor.preview._gui_input(repeated_press)
	assert(not editor.preview.is_clipboard_paste_active())

	# A double-click marker is a second physical click, not another paste.
	editor._unhandled_key_input(paste_shortcut)
	var double_click := _mouse_for_editor(Vector2i(12, 8), editor)
	double_click.double_click = true
	editor.preview._gui_input(double_click)
	assert(editor.current_document.layers.monster_spawn.size() == 2)
	double_click.pressed = false
	editor.preview._gui_input(double_click)
	assert(editor.preview.is_clipboard_paste_active())

	# Once the ignored double-click is released, the next independent click is
	# still allowed to paste exactly once.
	var independent_click := _mouse_for_editor(Vector2i(13, 8), editor)
	editor.preview._gui_input(independent_click)
	assert(editor.current_document.layers.monster_spawn.size() == 3)
	independent_click.pressed = false
	editor.preview._gui_input(independent_click)
	assert(not editor.preview.is_clipboard_paste_active())

	# A paste preview owns an invalid/outside click too; it must not fall
	# through to semantic placement.  Delete cancels the preview and leaves the
	# copied source entry intact.
	editor._unhandled_key_input(paste_shortcut)
	var invalid_press := InputEventMouseButton.new()
	invalid_press.button_index = MOUSE_BUTTON_LEFT
	invalid_press.pressed = true
	invalid_press.position = Vector2(-50, -50)
	editor.preview._gui_input(invalid_press)
	assert(editor.current_document.layers.monster_spawn.size() == 3)
	assert(editor.preview.is_clipboard_paste_active())
	invalid_press.pressed = false
	editor.preview._gui_input(invalid_press)
	var delete_key := _key(KEY_DELETE)
	editor.preview._gui_input(delete_key)
	assert(not editor.preview.is_clipboard_paste_active())
	assert(editor.current_document.layers.monster_spawn.size() == 3)
	assert(MapEditorGameplaySemanticService.find_entry(editor.current_document, source_id).size() > 0)

	# Only the ground layer supports motion painting.  Object and terrain stamp
	# placement remain single-shot even when the button mask stays held.
	var placement := MapEditorCanvasPreview.new()
	placement.size = Vector2(800, 600)
	add_child(placement)
	placement.set_document(MapEditorTypes.new_map("placement_input_regression", 990192, "Placement Input Regression", Vector2i(32, 32)))
	await get_tree().process_frame
	await get_tree().process_frame
	placement._draw()
	var paints: Array = []
	placement.paint_requested.connect(func(tile: Vector2i, asset_id: String) -> void: paints.append([tile, asset_id]))
	placement.set_placement_layer("object_base")
	var object_click := _mouse_for_preview(Vector2i(2, 2), placement)
	placement._gui_input(object_click)
	object_click.pressed = false
	placement._gui_input(object_click)
	var object_motion := _motion(Vector2i(3, 2), placement, true)
	placement._gui_input(object_motion)
	assert(paints.size() == 1)

	placement.set_placement_layer("ground_base")
	var ground_click := _mouse_for_preview(Vector2i(4, 2), placement)
	placement._gui_input(ground_click)
	ground_click.pressed = false
	placement._gui_input(ground_click)
	var ground_motion := _motion(Vector2i(5, 2), placement, true)
	placement._gui_input(ground_motion)
	assert(paints.size() == 3)

	print("MSE_CLIPBOARD_INPUT_REGRESSION_PASS semantic_single_shot=3 object_motion=1 ground_motion=2")
	get_tree().quit()


func _option_index(option: OptionButton, metadata: String) -> int:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1


func _mouse_for_editor(tile: Vector2i, editor: MapEditorApp) -> InputEventMouseButton:
	return _mouse_for_preview(tile, editor.preview)


func _mouse_for_preview(tile: Vector2i, preview: MapEditorCanvasPreview) -> InputEventMouseButton:
	var design_size_raw: Array = preview.document.design.design_size
	var design_size := Vector2i(int(design_size_raw[0]), int(design_size_raw[1]))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = preview._draw_offset + MapEditorCoordinate.cell_center_to_ground_px(Vector2(tile), design_size) * preview._draw_scale
	return event


func _click_preview_tile(editor: MapEditorApp, tile: Vector2i) -> void:
	var event := _mouse_for_editor(tile, editor)
	editor.preview._gui_input(event)
	event.pressed = false
	editor.preview._gui_input(event)


func _motion(tile: Vector2i, preview: MapEditorCanvasPreview, left_held: bool) -> InputEventMouseMotion:
	var design_size_raw: Array = preview.document.design.design_size
	var design_size := Vector2i(int(design_size_raw[0]), int(design_size_raw[1]))
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if left_held else 0
	event.position = preview._draw_offset + MapEditorCoordinate.cell_center_to_ground_px(Vector2(tile), design_size) * preview._draw_scale
	return event


func _key(keycode: Key, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	return event
