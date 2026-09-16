extends Node

## Editor single-key shortcuts contract:
##   W / S -- scale the selected placed instance (same 10% step as the
##            instance context menu); hint when nothing is selected.
##   R     -- single-cell manual collision draw (forces the cell shape).
##   T     -- single-cell collision erase.
##   E     -- selection tool.
## The keys reach the app through _unhandled_key_input, so LineEdit/SpinBox
## editing consumes printable keys first and never toggles tools.

const InstanceService := preload("res://scripts/map_editor/map_editor_instance_service.gd")


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _shape_index(option: OptionButton, metadata: String) -> int:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1


func _instance_scale(instance: Dictionary) -> float:
	var scale_array: Array = instance.get("scale", [1.0, 1.0])
	return float(scale_array[0])


func _ready() -> void:
	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	editor.current_document = MapEditorTypes.new_map(
		"editor_shortcuts", 990013, "Editor Shortcuts", Vector2i(32, 32)
	)
	# Keep every autosave inside the runner's isolated user-data tree.
	# _resolved_current_document_path() only honors current_document_path when
	# the file name equals "<map_id>.editor.json" (map_id is the string key);
	# the ground service derives its workspace root from editor_meta.workspace
	# (and rewrites ground.workspace_* from it), so that is the authoritative
	# redirect target.
	editor.current_document_path = "user://mse_editor_shortcut_test/editor_shortcuts.editor.json"
	var editor_meta: Dictionary = editor.current_document.get("editor_meta", {})
	editor_meta["workspace"] = "user://mse_editor_shortcut_test"
	editor.current_document["editor_meta"] = editor_meta
	editor.preview.set_document(editor.current_document)
	await get_tree().process_frame

	# R -- force single-cell manual collision draw even when another shape was selected.
	var rect_index := _shape_index(editor.collision_shape_option, "rect")
	assert(rect_index >= 0)
	editor.collision_shape_option.select(rect_index)
	editor._on_collision_shape_selected(rect_index)
	assert(editor._selected_collision_shape() == "rect")
	editor._unhandled_key_input(_key(KEY_R))
	assert(editor.active_tool_mode == "manual_collision", "R must enter manual collision draw")
	assert(editor.preview.interaction_mode == "manual_collision")
	assert(editor.collision_draw_toggle.button_pressed)
	assert(editor._selected_collision_shape() == "cell", "R must force the single-cell shape")

	# T -- single-cell collision erase.
	editor._unhandled_key_input(_key(KEY_T))
	assert(editor.active_tool_mode == "manual_collision_erase", "T must enter single-cell erase")
	assert(editor.preview.interaction_mode == "manual_collision_erase")
	assert(editor.collision_erase_toggle.button_pressed and not editor.collision_draw_toggle.button_pressed)

	# E -- selection tool from any mode.
	editor._unhandled_key_input(_key(KEY_E))
	assert(editor.active_tool_mode == "select", "E must activate the selection tool")
	assert(editor.preview.interaction_mode == "select")
	assert(not editor.collision_erase_toggle.button_pressed and not editor.collision_draw_toggle.button_pressed)

	# W/S -- resize the selected placed instance; hint when nothing is selected.
	editor.preview.selected_selectable_id = ""
	editor._unhandled_key_input(_key(KEY_W))
	assert(
		"选择工具" in editor.status_label.text,
		"W without a selected instance must show the selection hint"
	)
	# Pick a placeable non-ground asset from the catalog (same predicate as the
	# resize regression test) instead of hardcoding one asset id.
	var resize_asset_id := ""
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var footprint: Array = asset.get("footprint_tiles", [0, 0])
		if bool(asset.get("placeable", false)) and str(asset.get("asset_type", "")) != "ground_brush" and mini(int(footprint[0]), int(footprint[1])) >= 2:
			resize_asset_id = str(asset.get("asset_id", ""))
			break
	assert(not resize_asset_id.is_empty(), "需要一个可缩放且非地面的地图素材")
	var created := InstanceService.create_instance(
		editor.current_document,
		resize_asset_id,
		"building",
		Vector2i(20, 20)
	)
	assert(created.ok, str(created.get("errors", [])))
	var instance_id := str(created.instance.get("instance_id", ""))
	assert(instance_id.begins_with("inst_"))
	editor.preview.selected_selectable_id = instance_id
	var before_scale := _instance_scale(
		InstanceService._locate(editor.current_document, instance_id).instance
	)
	editor._unhandled_key_input(_key(KEY_W))
	var after_w: Dictionary = InstanceService._locate(editor.current_document, instance_id).instance
	assert(
		_instance_scale(after_w) > before_scale,
		"W must scale the selected instance up by one 10% step"
	)
	editor._unhandled_key_input(_key(KEY_S))
	var after_s: Dictionary = InstanceService._locate(editor.current_document, instance_id).instance
	assert(
		is_equal_approx(_instance_scale(after_s), before_scale),
		"S must scale the selected instance back down"
	)

	print("MSE_EDITOR_SINGLE_KEY_SHORTCUTS_PASS")
	get_tree().quit(0)
