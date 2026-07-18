extends Node


func _ready() -> void:
	var bich := MapEditorTypes.new_map_from_catalog("bich_province")
	assert(bich.runtime_map_id == 4)
	assert(bich.design.design_size == [80, 80])
	assert(bich.design.size_status == "user_confirmed_final")
	assert(is_equal_approx(float(bich.design.scale_factor), 0.3125))
	assert(bich.design.tile_size == [64, 32])
	assert(bich.design.source_size != bich.design.design_size)
	assert(bich.ground.blank_chunk_policy == "transparent_until_painted")
	assert(not bich.ground.blank_generated and str(bich.ground.blank_fill_asset_id).is_empty())
	assert(bich.ground.mask_storage == "chunked_l8")
	assert(MapEditorTypes.validate_document(bich).is_empty())
	var mengzhong := MapEditorTypes.new_map_from_catalog("mengzhong_province")
	assert(mengzhong.design.design_size == [88, 88])
	var blank_templates := MapDesignCatalogService.blank_templates()
	assert(blank_templates.size() == 21)
	var bich_blank := MapEditorTypes.new_map_from_blank_template("blank.bich_province")
	assert(bich_blank.design.design_size == [80, 80])
	assert(bich_blank.editor_meta.blank_template_id == "blank.bich_province")
	var mengzhong_blank := MapEditorTypes.new_map_from_blank_template("blank.mengzhong_province")
	assert(mengzhong_blank.design.design_size == [88, 88])
	assert(mengzhong_blank.editor_meta.blank_template_id == "blank.mengzhong_province")
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		assert((mengzhong_blank.layers[layer_name] as Array).is_empty())
	var unknown := MapEditorTypes.new_map_from_catalog("sandbox_64", "quest_room", 990001, "64格沙盒")
	assert(unknown.design.design_size == [64, 64])
	assert(unknown.runtime_map_id == 990001)
	var custom := MapEditorTypes.new_custom_map("custom_5x3", 990099, "自定义地图", "outdoor_field", Vector2i(5, 3))
	assert(custom.design.design_size == [80, 48])
	assert(custom.editor_meta.authoring_chunk_grid == [5, 3])
	assert(custom.editor_meta.authoring_chunk_size_tiles == [16, 16])
	var custom_10x10 := MapEditorTypes.new_custom_map("custom_10x10", 990100, "10×10 模板", "dungeon_floor", Vector2i(10, 10))
	assert(custom_10x10.design.design_size == [160, 160])
	var orc_tomb_blank := MapEditorTypes.new_map_from_blank_template("blank.orc_tomb_1")
	assert(orc_tomb_blank.design.design_size == [38, 38])
	assert(orc_tomb_blank.ground.blank_chunk_policy == "transparent_until_painted")
	assert(str(orc_tomb_blank.ground.blank_fill_asset_id).is_empty())
	assert(MapEditorSaveService.default_path("sandbox_64") == "res://map_editor_workspace/sandbox_64/sandbox_64.editor.json")
	var catalog_errors := MapAssetCatalogService.validate_catalog()
	assert(catalog_errors.is_empty(), str(catalog_errors))
	var palette := MapAssetCatalogService.palette_assets()
	assert(not palette.is_empty())
	assert(palette.all(func(asset: Dictionary) -> bool: return bool(asset.get("placeable", false))))
	var tile := Vector2(73, 81)
	var px := MapEditorCoordinate.tile_to_ground_px(tile, Vector2i(256, 256))
	assert(MapEditorCoordinate.ground_px_to_tile(px, Vector2i(256, 256)).is_equal_approx(tile))
	var counter := [0]
	var stack := MapEditorCommandStack.new()
	assert(stack.execute({"do": func(): counter[0] += 1, "undo": func(): counter[0] -= 1}))
	assert(counter[0] == 1 and stack.undo() and counter[0] == 0 and stack.redo() and counter[0] == 1)
	var path := "user://map_editor_stage0_test.editor.json"
	var saved := MapEditorSaveService.save_document(unknown, path)
	assert(saved.ok, str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(path)
	assert(loaded.ok and loaded.document.map_id == "sandbox_64")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var editor_scene := load("res://scenes/tools/mafa_scene_editor.tscn") as PackedScene
	var editor := editor_scene.instantiate() as MapEditorApp
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	assert(editor._startup_document_path() == MapEditorSaveService.default_path("bich_province"))
	editor._create_map("sandbox_64", "quest_room", 990001, "64格沙盒")
	assert(editor.current_document.map_id == "sandbox_64")
	assert(editor.current_document_path == MapEditorSaveService.default_path("sandbox_64"))
	var editor_size: Array = editor.current_document.design.design_size
	assert(Vector2i(int(editor_size[0]), int(editor_size[1])) == Vector2i(64, 64))
	assert(editor.asset_tree != null)
	var first_asset_item := editor._first_asset_tree_item()
	assert(first_asset_item != null and first_asset_item.get_icon(0) != null)
	var unloaded_asset_item := first_asset_item.get_next_in_tree()
	while unloaded_asset_item != null and not (unloaded_asset_item.get_metadata(0) is Dictionary and not str(unloaded_asset_item.get_metadata(0).get("asset_id", "")).is_empty()):
		unloaded_asset_item = unloaded_asset_item.get_next_in_tree()
	assert(unloaded_asset_item != null and unloaded_asset_item.get_icon(0) == null)
	editor._ensure_asset_tree_item_icon(unloaded_asset_item)
	assert(unloaded_asset_item.get_icon(0) != null)
	assert(editor.map_template_option.item_count == 21)
	assert(editor.save_map_button.text == "保存地图")
	assert(editor.collision_shape_option.item_count == 4)
	assert(str(editor.collision_shape_option.get_item_metadata(0)) == "cell")
	assert(editor.collision_erase_toggle.text.begins_with("单格擦除碰撞"))
	assert(editor.collision_erase_whole_toggle.text.begins_with("整块擦除碰撞"))
	assert(editor.open_template_button.text == "打开地图模板")
	assert(editor.create_map_button.text == "创建地图模板")
	assert(editor.create_map_dialog.title == "创建地图模板")
	assert(editor.create_dialog_submit_button.text == "创建地图模板")
	var sidebar_button_texts: Array[String] = []
	for candidate: Node in editor.find_children("*", "Button", true, false):
		sidebar_button_texts.append((candidate as Button).text)
	assert("保存素材校准覆盖（不保存地图）" in sidebar_button_texts)
	assert("打开比奇地图" not in sidebar_button_texts)
	assert("从所选模板创建地图" not in sidebar_button_texts)
	assert("sandbox_64.editor.json" in editor.path_label.text)
	assert(str(editor.map_template_option.get_item_metadata(0)) == "blank.bich_province")
	editor._on_map_template_selected(0)
	assert("80×80" in editor.template_info_label.text)
	var template_test_root := "user://mse_template_open_test"
	var template_test_document := template_test_root.path_join("orc_tomb_1.editor.json")
	var template_test_workspace := template_test_root.path_join("ground_workspace")
	_cleanup_template_test_files(template_test_root, template_test_document, template_test_workspace)
	editor.preview.set_walkability_preview({"blocked_tiles": {"1,1": true, "2,2": true}}, true)
	editor.preview.selected_selectable_id = "old_bich_selection"
	editor.preview.hovered_selectable_id = "old_bich_hover"
	editor.preview._view_pan = Vector2(50, 25)
	var old_command_counter := [0]
	assert(editor.command_stack.execute({"do": func(): old_command_counter[0] += 1, "undo": func(): old_command_counter[0] -= 1}))
	assert(editor._open_template_by_id("blank.orc_tomb_1", template_test_document, template_test_workspace))
	assert(editor.current_document.map_id == "orc_tomb_1")
	assert(editor.current_document.design.design_size == [38, 38])
	assert(not editor.current_document.ground.blank_generated)
	assert(str(editor.current_document.ground.blank_fill_asset_id).is_empty())
	assert(editor.preview.document.map_id == "orc_tomb_1")
	assert(editor.preview._blocked_tiles.is_empty())
	assert(editor.preview.selected_selectable_id.is_empty() and editor.preview.hovered_selectable_id.is_empty())
	assert(editor.preview._view_pan == Vector2.ZERO and is_equal_approx(editor.preview._zoom_multiplier, 1.0))
	assert(not editor.command_stack.can_undo() and editor.active_tool_mode == "select")
	assert(FileAccess.file_exists(template_test_document))
	assert(MapEditorCollisionService.add_manual_shape(editor.current_document, "rect", {"rect": [4, 5, 1, 1]}).ok)
	assert(editor._save_current_document().ok)
	var saved_template := MapEditorLoadService.load_document(ProjectSettings.globalize_path(template_test_document), false)
	assert(saved_template.ok and saved_template.document.map_id == "orc_tomb_1")
	assert(saved_template.document.layers.collision.size() == 1)
	assert(editor._open_template_by_id("blank.orc_tomb_1", template_test_document, template_test_workspace))
	assert("地图打开成功" in editor.status_label.text)
	_cleanup_template_test_files(template_test_root, template_test_document, template_test_workspace)
	var wooma_test_root := "user://mse_wooma_template_open_test"
	var wooma_test_document := wooma_test_root.path_join("wooma_forest.editor.json")
	var wooma_test_workspace := wooma_test_root.path_join("ground_workspace")
	_cleanup_template_test_files(wooma_test_root, wooma_test_document, wooma_test_workspace)
	var wooma_open_started := Time.get_ticks_msec()
	assert(editor._open_template_by_id("blank.wooma_forest", wooma_test_document, wooma_test_workspace))
	await get_tree().process_frame
	assert(Time.get_ticks_msec() - wooma_open_started < 3000, "沃玛森林模板打开超过3秒")
	assert(editor.current_document.map_id == "wooma_forest")
	assert(str(editor.map_template_option.get_item_metadata(editor.map_template_option.selected)) == "blank.wooma_forest")
	assert(MapEditorCanvasPreview.VIRTUAL_TILE_DRAW_LIMIT < 56 * 56)
	_cleanup_template_test_files(wooma_test_root, wooma_test_document, wooma_test_workspace)
	editor._create_map("bich_province", "outdoor_province", 4, "比奇省")
	assert(editor.current_document.design.design_size == [80, 80])
	assert(str(editor.map_template_option.get_item_metadata(editor.map_template_option.selected)) == "blank.bich_province")
	editor.queue_free()
	print("MAP_EDITOR_STAGE0_PASS")
	get_tree().quit(0)


func _cleanup_template_test_files(root: String, document_path: String, workspace: String) -> void:
	for path: String in [
		document_path + ".tmp",
		document_path + ".bak",
		document_path,
		workspace.path_join("ground").path_join("ground_manifest.json"),
		workspace.path_join("ground").path_join("ground_state.json"),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for directory: String in [workspace.path_join("ground"), workspace, root]:
		var absolute := ProjectSettings.globalize_path(directory)
		if DirAccess.dir_exists_absolute(absolute):
			DirAccess.remove_absolute(absolute)
