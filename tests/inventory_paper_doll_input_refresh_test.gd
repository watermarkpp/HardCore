extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var dress_slot := str(PreviewScript.PAPER_LAYER_SLOTS[0])
	var weapon_slot := str(PreviewScript.PAPER_LAYER_SLOTS[1])
	PlayerState.equipment[dress_slot] = {"item_id": 140, "name": "天魔神甲"}
	PlayerState.equipment[weapon_slot] = {"item_id": 113, "name": "怒斩"}
	PlayerState.equipment[str(PreviewScript.PAPER_LAYER_SLOTS[2])] = {
		"item_id": 240,
		"name": "天尊头盔",
	}
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var inventory_button := hud.find_child("InventoryButton", true, false) as Button
	assert(inventory_button != null, "正式 HUD 缺少背包入口")
	assert(hud.inventory_panel == null, "正式 HUD 背包必须保持首开惰性")
	inventory_button.pressed.emit()
	await get_tree().process_frame
	var panel: InventoryPanel = hud.inventory_panel
	assert(panel.visible, "正式 HUD 背包按钮没有打开 InventoryPanel")

	var equipment_panel: Control = panel.get_node("EquipmentPanel")
	var preview: EquipmentCharacterPreview = panel.character_preview
	assert(_preview_count(equipment_panel) == 1, "Inventory has more than one paper-doll preview")
	assert(preview.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(preview.presentation_mode == "classic_avatar")
	assert(not preview.uses_world_avatar(), "Inventory uses the low-resolution world avatar")
	assert(not preview.uses_original_client_stage(), "Inventory drew the full Prguse equipment page")
	assert(preview.has_renderable_assets(), "正式 HUD 背包纸娃娃缺少可渲染底图")
	assert(preview.has_renderable_hair(), "正式 HUD 背包纸娃娃缺少男性头发")
	assert(preview._body_texture != null, "正式 HUD 背包纸娃娃缺少衣服层")
	assert(preview._weapon_texture != null, "正式 HUD 背包纸娃娃缺少武器层")
	assert(preview._helmet_texture != null, "正式 HUD 背包纸娃娃缺少用户头盔层")
	assert(preview.get_meta("paper_doll_render_contract", "") == PreviewScript.PRESENTATION_MODES_CONTRACT_ID)
	preview.configure_presentation_mode("legacyFullPanel")
	assert(preview.presentation_mode == "classic_avatar", "Player UI accepted the forbidden legacyFullPanel mode")
	assert(preview.get_meta("input_policy", "") == "visual_only_mouse_filter_ignore")
	var weapon_holder: Control = panel.equipment_buttons[weapon_slot].get_parent()
	assert(preview.get_index() < weapon_holder.get_index(), "Paper doll is above the equipment interaction layer")
	assert(
		Rect2(preview.position, preview.size).intersects(Rect2(weapon_holder.position, weapon_holder.size)),
		"Test does not cover the preview/equipment-slot overlap"
	)

	preview.configure_source_document(_fixture_document())
	var revision_before := preview.render_revision()
	PlayerState.equipment[dress_slot] = {"item_id": "dress.first", "name": "fixture_dress"}
	PlayerState.equipment[weapon_slot] = {}
	PlayerState.equipment[str(PreviewScript.PAPER_LAYER_SLOTS[2])] = {}
	PlayerState.equipment_changed.emit()
	assert(preview.render_revision() > revision_before, "Equipment change did not refresh the paper doll")
	assert(preview.paper_layer_source_index(dress_slot) == 62)
	assert(preview.original_stage_draw_commands().is_empty(), "Player inventory drew a complete Prguse background or slot frame")
	assert(preview._body_texture != null, "Equipment refresh did not retain the dress layer")
	assert(preview._paper_layers.size() == 1, "Paper doll did not retain the transparent base/dress composition")

	(panel.equipment_buttons[dress_slot] as Button).pressed.emit()
	assert(panel.selected_equipment_slot == dress_slot, "Visual preview blocked equipment-slot selection")
	hud.queue_free()

	print("INVENTORY_PAPER_DOLL_INPUT_REFRESH_PASS")
	get_tree().quit(0)


func _preview_count(parent: Node) -> int:
	var result := 0
	for child: Node in parent.get_children():
		if child is EquipmentCharacterPreview:
			result += 1
	return result


func _fixture_document() -> Dictionary:
	var dress_slot := str(PreviewScript.PAPER_LAYER_SLOTS[0])
	return {
		"contractId": "test.paper_doll.avatar_only_fixture.v1",
		"sex": "male",
		"canvasSize": [168, 199],
		"paperDollFootAnchor": [84, 186],
		"base": {
			"sourceIndex": 376,
			"texture": _solid_texture(Vector2i(168, 199), Color("24170f")),
		},
		"hair": {
			"sourceIndex": 442,
			"texture": _solid_texture(Vector2i(16, 14), Color("422918")),
			"drawOffset": [80, 44],
		},
		"runtimeMappings": {
			"dress.first": {
				"slot": dress_slot,
				"sourceIndex": 62,
				"texture": _solid_texture(Vector2i(84, 140), Color("3c6a35")),
				"drawOffset": [42, 42],
			},
		},
	}


func _solid_texture(texture_size: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create(texture_size.x, texture_size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
