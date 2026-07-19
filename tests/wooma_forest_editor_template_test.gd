extends Node


func _ready() -> void:
	var template := MapDesignCatalogService.find_blank_template(
		"blank.wooma_forest"
	)
	assert(not template.is_empty())
	assert(str(template.map_id) == "wooma_forest")
	assert(int(template.runtime_map_id) == 268)
	assert(template.design_size == [56.0, 56.0])
	assert(str(template.workspace_status) == "ready")
	assert(str(template.template_version_id) == "wooma_forest_blank_v1")

	var loaded := MapEditorLoadService.load_document(
		"res://map_editor_workspace/wooma_forest/wooma_forest.editor.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(str(document.map_id) == "wooma_forest")
	assert(int(document.runtime_map_id) == 268)
	assert(document.design.design_size == [56.0, 56.0])
	assert(
		str(document.editor_meta.template_version_id)
		== "wooma_forest_blank_v1"
	)
	assert(
		str(document.ground.coordinate_contract_id)
		== MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	)
	assert(str(document.ground.blank_fill_asset_id).is_empty())
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		assert(
			(document.layers[layer_name] as Array).is_empty(),
			"沃玛森林空模板不应预置内容：%s" % layer_name
		)

	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	assert(str(initialized.manifest.default_fill_asset_id).is_empty())
	assert(
		str(initialized.manifest.blank_chunk_policy)
		== "transparent_until_painted"
	)
	assert((initialized.state.dirty_chunks as Array).is_empty())
	for chunk: Dictionary in initialized.manifest.chunks:
		assert(str(chunk.fill_asset_id).is_empty())
		assert(not bool(chunk.materialized))
		assert(str(chunk.state) == "virtual")

	var editor_scene := load(
		"res://scenes/tools/mafa_scene_editor.tscn"
	) as PackedScene
	var editor := editor_scene.instantiate() as MapEditorApp
	editor.load_default_workspace_on_ready = false
	editor.persist_last_document_path = false
	add_child(editor)
	editor._refresh_map_template_options("blank.wooma_forest")
	assert(
		str(
			editor.map_template_option.get_item_metadata(
				editor.map_template_option.selected
			)
		) == "blank.wooma_forest"
	)
	var menu_text := editor.map_template_option.get_item_text(
		editor.map_template_option.selected
	)
	assert("沃玛森林（可编辑空白模板）" in menu_text)
	assert("56×56" in menu_text)
	var started := Time.get_ticks_msec()
	assert(editor._open_template_by_id("blank.wooma_forest"))
	await get_tree().process_frame
	assert(
		Time.get_ticks_msec() - started < 3000,
		"沃玛森林模板打开超过3秒"
	)
	assert(str(editor.current_document.map_id) == "wooma_forest")
	assert(editor.current_document.design.design_size == [56.0, 56.0])
	assert(str(editor.current_document.ground.blank_fill_asset_id).is_empty())
	editor.queue_free()
	print(
		"WOOMA_FOREST_EDITOR_TEMPLATE_PASS "
		+ "template=blank.wooma_forest size=56x56 runtime=268"
	)
	get_tree().quit(0)
