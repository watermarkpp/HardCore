extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("匕首")
	PlayerState.add_item("布衣(男)")
	PlayerState.add_item("古铜戒指")
	PlayerState.add_item("太阳水", 2)

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert(panel.size == Vector2(1220, 660), "人物物品栏没有使用横屏手机安全尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "人物与背包没有使用公共哥特外框")
	assert(panel.get_node("AttributePanel").theme_type_variation == "GothicInsetFrame", "人物属性栏没有复用公共哥特内框")
	assert(panel.get_node("EquipmentPanel").theme_type_variation == "GothicInsetFrame", "人物装备栏没有复用公共哥特内框")
	assert(panel.get_node("BagPanel").theme_type_variation == "GothicInsetFrame", "综合背包没有复用公共哥特内框")
	assert(panel.get_node("AttributePanel").position.x < panel.get_node("EquipmentPanel").position.x, "人物属性面板必须位于装备栏左侧")
	assert(panel.get_node("EquipmentPanel").position.x < panel.get_node("BagPanel").position.x, "综合背包必须位于装备栏右侧")
	assert(panel.equipment_buttons.size() == 8, "人物装备栏必须显示八个直接装备槽")
	assert(panel.item_grid.get_child_count() == 40, "综合背包必须显示固定40格和空格底色")
	assert(panel.item_grid.get_child(3).has_node("StackCount") and panel.item_grid.get_child(3).get_node("StackCount").text == "2", "可堆叠物品没有在同一格显示数量")
	assert(panel.character_preview != null, "装备面板缺少人物穿戴预览")
	panel.context_menu.clear()
	panel._context_actions.clear()
	panel._add_inventory_context_actions(2)
	assert(panel.context_menu.item_count == 2, "戒指长按菜单必须提供左右两个槽位")
	assert(panel._context_actions[1].get("slot", "") == "左戒指" and panel._context_actions[2].get("slot", "") == "右戒指", "戒指左右槽位菜单顺序错误")

	var attack_before := int(PlayerState.computed_stats.get("attack_max", 0))
	panel._select_inventory_item(0)
	assert("匕首" in panel.detail_label.text, "点击背包物品没有显示物品属性")
	panel.context_menu.clear()
	panel._context_actions.clear()
	panel._add_inventory_context_actions(0)
	assert(panel.context_menu.item_count == 1 and panel._context_actions[1].get("action", "") == "equip", "长按武器没有生成装备菜单")
	panel._on_context_action(1)
	await get_tree().process_frame
	assert(str(PlayerState.equipment["武器"].get("name", "")) == "匕首", "界面穿戴没有进入武器槽")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) > attack_before, "界面穿戴没有即时刷新装备属性")
	assert(panel.character_preview._weapon_texture != null, "武器穿戴后人物预览没有外观")
	var weapon_slot_icon: TextureRect = panel.equipment_buttons["武器"].get_node("CenteredPixelIcon")
	assert("/inventory/" in weapon_slot_icon.texture.resource_path, "装备格错误使用了穿戴人物缩略图")
	assert(weapon_slot_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "装备格图标没有使用清晰像素过滤")
	assert(weapon_slot_icon.position == (panel.equipment_buttons["武器"].size - weapon_slot_icon.size) * 0.5, "装备图标没有处于格子正中")
	assert(weapon_slot_icon.size.x <= panel.equipment_buttons["武器"].size.x - 24.0 and weapon_slot_icon.size.y <= panel.equipment_buttons["武器"].size.y - 26.0, "装备图标侵入哥特插槽边框")

	var armor_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "布衣(男)":
			armor_index = index
	assert(armor_index >= 0, "测试衣服实例丢失")
	panel._select_inventory_item(armor_index)
	panel.context_menu.clear()
	panel._context_actions.clear()
	panel._add_inventory_context_actions(armor_index)
	assert(panel.context_menu.item_count == 1 and panel._context_actions[1].get("slot", "") == "衣服", "长按衣服没有生成正确穿戴菜单")
	panel._on_context_action(1)
	await get_tree().process_frame
	assert(str(PlayerState.equipment["衣服"].get("name", "")) == "布衣(男)", "界面穿戴没有进入衣服槽")
	assert(panel.character_preview._body_texture != null, "衣服穿戴后人物预览没有外观")

	panel._select_equipment_slot("武器")
	assert("匕首" in panel.detail_label.text, "点击已装备物品没有显示物品属性")
	panel._press_context = {"source": "equipment", "slot": "武器"}
	panel._press_button = panel.equipment_buttons["武器"]
	panel._open_long_press_menu()
	assert(panel.context_menu.item_count == 1 and panel._context_actions[1].get("action", "") == "unequip", "长按已装备物品没有显示卸下")
	panel._on_context_action(1)
	assert(PlayerState.equipment["武器"].is_empty(), "界面卸下武器失败")

	print("INVENTORY_EQUIPMENT_UI_PASS：图标网格、八槽穿戴、属性刷新、人物外观和卸下闭环正常")
	get_tree().quit(0)
