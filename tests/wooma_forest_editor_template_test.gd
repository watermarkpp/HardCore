extends Node


func _ready() -> void:
	# MAP-SAFETY-R1: blank.wooma_forest now resolves to the formal identity
	# key world_wooma_forest (runtime 910004). The legacy map_editor_workspace/
	# wooma_forest/ directory is no longer consumed by this test.
	var template := MapDesignCatalogService.find_blank_template(
		"blank.wooma_forest"
	)
	assert(not template.is_empty())
	assert(str(template.map_id) == "world_wooma_forest")
	assert(template.design_size == [56.0, 56.0])
	var blank := MapEditorTypes.new_map_from_blank_template(
		"blank.wooma_forest"
	)
	assert(not blank.is_empty())
	for layer_name: String in MapEditorTypes.LAYER_NAMES:
		assert(
			(blank.layers[layer_name] as Array).is_empty(),
			"沃玛森林模板原型必须保持空白：%s" % layer_name
		)

	var loaded := MapEditorLoadService.load_document(
		"res://map_editor_workspace/world_wooma_forest/world_wooma_forest.editor.json"
	)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(str(document.map_id) == "world_wooma_forest")
	assert(int(document.runtime_map_id) == 910004)
	assert(document.design.design_size == [56.0, 56.0])
	assert(
		str(document.editor_meta.collision_authority)
		== "hc_polygon_v1"
	)
	assert(
		str(document.ground.coordinate_contract_id)
		== MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	)
	# Structure contract: user-editable content counts are not frozen here;
	# the document must validate and carry real content.
	assert(MapEditorTypes.validate_document(document).is_empty())
	assert(not (document.layers.object_base as Array).is_empty())
	assert(not (document.layers.monster_spawn as Array).is_empty())
	assert(not (document.layers.map_exit_points as Array).is_empty())
	for instance: Dictionary in MapEditorInstanceService.all_instances(
		document
	):
		var asset_id := str(instance.get("asset_id", ""))
		var asset := MapAssetCatalogService.find_asset(asset_id)
		assert(not asset.is_empty(), asset_id)
		assert(
			FileAccess.file_exists(
				"res://" + str(asset.get("image", ""))
			),
			asset_id
		)

	var initialized := MapEditorGroundService.initialize(document)
	assert(initialized.ok, str(initialized.get("errors", [])))
	assert(
		str(initialized.manifest.blank_chunk_policy)
		== "transparent_until_painted"
	)
	assert((initialized.state.dirty_chunks as Array).is_empty())
	var has_materialized_ground := false
	for chunk: Dictionary in initialized.manifest.chunks:
		if bool(chunk.get("materialized", false)):
			has_materialized_ground = true
			break
	assert(has_materialized_ground)

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
	assert("沃玛森林" in menu_text)
	assert("56×56" in menu_text)
	var started := Time.get_ticks_msec()
	assert(editor._open_template_by_id("blank.wooma_forest"))
	await get_tree().process_frame
	assert(
		Time.get_ticks_msec() - started < 3000,
		"沃玛森林模板打开超过3秒"
	)
	assert(str(editor.current_document.map_id) == "world_wooma_forest")
	assert(editor.current_document.design.design_size == [56.0, 56.0])
	assert(str(editor.current_document.ground.blank_fill_asset_id).is_empty())
	assert(not (editor.current_document.layers.object_base as Array).is_empty())
	editor.queue_free()
	print(
		"WOOMA_FOREST_EDITOR_TEMPLATE_PASS "
		+ "template=blank.wooma_forest current=world_wooma_forest size=56x56 runtime=910004"
	)
	get_tree().quit(0)
