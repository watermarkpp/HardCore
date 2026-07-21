extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map(
		"material_layer_order_test",
		991022,
		"Material Layer Order Test",
		Vector2i(64, 64)
	)
	var choices: Array[Dictionary] = []
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if (
			bool(asset.get("placeable", false))
			and str(asset.get("category", "")) == "decoration"
			and str(asset.get("asset_type", "")) != "ground_brush"
		):
			choices.append(asset)
			if choices.size() == 2:
				break
	assert(choices.size() == 2)
	var first := MapEditorInstanceService.create_instance(
		document,
		str(choices[0].asset_id),
		"decoration",
		Vector2i(12, 12),
		"object_base"
	)
	var second := MapEditorInstanceService.create_instance(
		document,
		str(choices[1].asset_id),
		"decoration",
		Vector2i(12, 12),
		"object_base"
	)
	assert(first.get("ok", false), str(first.get("errors", [])))
	assert(second.get("ok", false), str(second.get("errors", [])))
	var first_id := str(first.instance.instance_id)
	var second_id := str(second.instance.instance_id)

	var raised := MapEditorInstanceService.adjust_material_layer_order(
		document,
		first_id,
		1
	)
	assert(raised.get("ok", false))
	assert(int(raised.get("material_layer_order", 0)) == 1)
	_assert_topmost_in_editor(document, first_id)
	_assert_topmost_at_runtime(document, first_id)

	var lowered := MapEditorInstanceService.adjust_material_layer_order(
		document,
		first_id,
		-2
	)
	assert(lowered.get("ok", false))
	assert(int(lowered.get("material_layer_order", 0)) == -1)
	_assert_topmost_in_editor(document, second_id)
	_assert_topmost_at_runtime(document, second_id)

	var clamped := MapEditorInstanceService.adjust_material_layer_order(
		document,
		first_id,
		1000
	)
	assert(
		int(clamped.get("material_layer_order", 0))
		== MapEditorInstanceService.MATERIAL_LAYER_ORDER_MAX
	)
	var duplicated := MapEditorInstanceService.duplicate_instance(
		document,
		first_id,
		Vector2i(24, 24)
	)
	assert(duplicated.get("ok", false))
	assert(
		MapEditorInstanceService.material_layer_order(duplicated.instance)
		== MapEditorInstanceService.MATERIAL_LAYER_ORDER_MAX
	)

	var environment := Node2D.new()
	environment.z_index = -20
	add_child(environment)
	var runtime_sprite := Sprite2D.new()
	environment.add_child(runtime_sprite)
	MapEditorInstanceService.configure_runtime_material_canvas_item(
		runtime_sprite,
		clamped.instance
	)
	assert(runtime_sprite.z_as_relative)
	assert(
		runtime_sprite.z_index
		== MapEditorInstanceService.STATIC_MATERIAL_CHILD_Z_INDEX
	)
	assert(environment.z_index + runtime_sprite.z_index < 0)

	var editor := MapEditorApp.new()
	editor.load_default_workspace_on_ready = false
	add_child(editor)
	await get_tree().process_frame
	assert(editor.instance_size_menu.get_item_index(3) >= 0)
	assert(editor.instance_size_menu.get_item_index(4) >= 0)
	assert("仅素材间" in editor.instance_size_menu.get_item_text(
		editor.instance_size_menu.get_item_index(3)
	))
	print(
		"MSE_MATERIAL_LAYER_ORDER_PASS "
		+ "editor=true runtime=true actors_isolated=true range=-128..128"
	)
	get_tree().quit(0)


func _assert_topmost_in_editor(document: Dictionary, expected_id: String) -> void:
	var commands: Array[Dictionary] = []
	var sequence := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var asset := MapAssetCatalogService.find_asset(str(instance.asset_id))
		commands.append_array(
			MapEditorCanvasPreview.instance_draw_commands(
				instance,
				asset,
				2,
				sequence
			)
		)
		sequence += 1
	commands.sort_custom(MapEditorCanvasPreview._draw_command_less)
	assert(not commands.is_empty())
	assert(str(commands[-1].instance.instance_id) == expected_id)


func _assert_topmost_at_runtime(document: Dictionary, expected_id: String) -> void:
	var sorted := MapEditorInstanceService.sorted_for_material_render(
		MapEditorInstanceService.all_instances(document)
	)
	assert(not sorted.is_empty())
	assert(str(sorted[-1].instance_id) == expected_id)
