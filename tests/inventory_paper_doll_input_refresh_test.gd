extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame

	var equipment_panel: Control = panel.get_node("EquipmentPanel")
	var preview: EquipmentCharacterPreview = panel.character_preview
	assert(_preview_count(equipment_panel) == 1, "装备界同时挂载了多套纸娃娃")
	assert(preview.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(
		preview.get_meta("input_policy", "")
		== "visual_only_mouse_filter_ignore"
	)
	var weapon_holder: Control = panel.equipment_buttons["武器"].get_parent()
	assert(preview.get_index() < weapon_holder.get_index(), "纸娃娃错误绘制在装备槽交互层之上")
	assert(
		Rect2(preview.position, preview.size).intersects(
			Rect2(weapon_holder.position, weapon_holder.size)
		),
		"测试没有覆盖纸娃娃与装备槽重叠区域"
	)

	preview.configure_source_document(_fixture_document())
	var revision_before := preview.render_revision()
	PlayerState.equipment["衣服"] = {"item_id": "dress.first", "name": "夹具衣服"}
	PlayerState.equipment_changed.emit()
	assert(preview.render_revision() > revision_before, "装备变化没有同步刷新纸娃娃")
	assert(preview.paper_layer_source_index("衣服") == 62)
	var commands := preview.original_stage_draw_commands()
	assert(commands.size() == 3, "装备界纸娃娃没有保持单一 base/hair/dress 合成")
	assert(commands[0].stagePosition == PreviewScript.ORIGINAL_CLIENT_BASE_SCREEN_ORIGIN)
	assert(
		commands[0].targetRect.intersects(commands[2].targetRect),
		"裸体基底与衣服层仍被错误拆成上下两个人物"
	)

	(panel.equipment_buttons["衣服"] as Button).pressed.emit()
	assert(panel.selected_equipment_slot == "衣服", "视觉预览层阻断了装备槽选择")

	print("INVENTORY_PAPER_DOLL_INPUT_REFRESH_PASS")
	get_tree().quit(0)


func _preview_count(parent: Node) -> int:
	var result := 0
	for child: Node in parent.get_children():
		if child is EquipmentCharacterPreview:
			result += 1
	return result


func _fixture_document() -> Dictionary:
	return {
		"contractId": PreviewScript.ORIGINAL_CLIENT_STAGE_CONTRACT_ID,
		"sex": "male",
		"canvasSize": [232, 325],
		"viewportOrigin": [0, 0],
		"stage": {
			"sourceIndex": 376,
			"texture": _solid_texture(Vector2i(168, 199), Color("24170f")),
			"hotX": 7,
			"hotY": -44,
			"stagePosition": [38, 52],
		},
		"hair": {
			"sourceIndex": 442,
			"texture": _solid_texture(Vector2i(16, 14), Color("422918")),
			"hotX": 87,
			"hotY": 0,
		},
		"composition": {
			"canvasSize": [232, 325],
			"viewportOrigin": [0, 0],
			"equipmentScreenAnchor": [31, 96],
		},
		"itemMappings": {
			"dress.first": {
				"slot": "衣服",
				"sourceIndex": 62,
				"texture": _solid_texture(Vector2i(84, 140), Color("3c6a35")),
				"hotX": 47,
				"hotY": 14,
			},
		},
	}


func _solid_texture(texture_size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
