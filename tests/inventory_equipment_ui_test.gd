extends Node

const PreviewScript := preload("res://scripts/equipment_character_preview.gd")


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
	assert(panel.theme.get_stylebox("normal", "GothicComponentSlotButton") is StyleBoxFlat, "人物与背包插槽没有使用简洁原生方格")
	assert(panel.get_node("AttributePanel").position.x < panel.get_node("EquipmentPanel").position.x, "人物属性面板必须位于装备栏左侧")
	assert(panel.get_node("EquipmentPanel").position.x < panel.get_node("BagPanel").position.x, "综合背包必须位于装备栏右侧")
	assert(panel.bag_summary_label.position.y >= 18.0 and panel.bag_summary_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "背包金币与占用格数仍然贴近装饰框上沿")
	assert(panel.equipment_buttons.size() == 8, "人物装备栏必须显示八个直接装备槽")
	assert(panel.item_grid.columns == 8 and panel.item_grid.get_child_count() == 100, "综合背包必须使用8列并提供固定100格")
	var bag_scroll := panel.get_node("BagPanel/InventoryScroll") as ScrollContainer
	var fortieth_cell := panel.item_grid.get_child(39) as Control
	var forty_first_cell := panel.item_grid.get_child(40) as Control
	assert(fortieth_cell.position.y + fortieth_cell.size.y <= bag_scroll.size.y, "背包首屏没有完整显示前40格")
	assert(forty_first_cell.position.y >= bag_scroll.size.y, "第41格错误进入背包首屏")
	assert(bag_scroll.get_v_scroll_bar().visible, "背包后60格没有提供右侧滚动查看")
	assert(panel.item_grid.get_child(3).has_node("StackCount") and panel.item_grid.get_child(3).get_node("StackCount").text == "2", "可堆叠物品没有在同一格显示数量")
	assert(panel.character_preview != null, "装备面板缺少人物穿戴预览")
	assert(not panel.character_preview.center_on_opaque_bounds, "背包装备纸娃娃不应再由合成alpha边界移动")
	assert(
		panel.character_preview.get_meta("horizontal_alignment_contract", "") == PreviewScript.FOOT_STAGE_ANCHOR_CONTRACT_ID,
		"背包装备纸娃娃脚部锚点稳定契约丢失"
	)
	assert(PreviewScript.FOOT_STAGE_RADII.x > PreviewScript.FOOT_STAGE_RADII.y * 3.0, "人物脚下舞台没有使用正确的透视椭圆")
	assert(PreviewScript.FOOT_STAGE_CENTER.y >= 185.0, "人物脚下舞台仍与双脚外沿重合")
	assert(panel.equipment_stats_label is RichTextLabel and panel.equipment_stats_label.scroll_active, "人物属性超长时没有右侧滑块")
	assert(panel.detail_label.scroll_active, "物品属性超长时没有右侧滑块")
	assert(panel.equipment_stats_label.size == panel.detail_label.size, "人物属性与物品属性占位尺寸不一致")
	var equipment_panel := panel.get_node("EquipmentPanel") as Control
	var necklace_button := panel.equipment_buttons["项链"] as Button
	var armor_button := panel.equipment_buttons["衣服"] as Button
	var necklace_rect := Rect2(necklace_button.get_parent().position + necklace_button.position, necklace_button.size)
	var armor_rect := Rect2(armor_button.get_parent().position + armor_button.position, armor_button.size)
	assert(not necklace_rect.intersects(armor_rect), "项链与衣服装备格发生连接或重叠")
	assert(panel.theme.get_stylebox("normal", "GothicEquipmentSlotButton") is StyleBoxFlat, "装备格没有使用简洁正方形公共样式")
	assert((panel.equipment_buttons["武器"] as Button).size.x == (panel.equipment_buttons["武器"] as Button).size.y, "装备格不是严格正方形")
	var weapon_caption := panel.equipment_buttons["武器"].get_parent().get_node("SlotCaptionPlate") as Control
	var weapon_button := panel.equipment_buttons["武器"] as Button
	assert(weapon_caption.position.y < weapon_button.position.y + weapon_button.size.y and weapon_caption.position.y + weapon_caption.size.y > weapon_button.position.y + weapon_button.size.y, "装备名称铭牌没有压住对应装备格底边")
	var future_row := equipment_panel.get_node("FutureEquipmentRow") as Control
	var current_slots_bottom := 0.0
	for button_value: Variant in panel.equipment_buttons.values():
		var equipment_button := button_value as Button
		current_slots_bottom = maxf(current_slots_bottom, equipment_button.get_parent().position.y + equipment_button.get_parent().size.y)
	assert(current_slots_bottom <= future_row.position.y, "现有装备格没有为勋章、腰带和鞋子预留底部扩展行")
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
	assert(weapon_slot_icon.size.x <= panel.equipment_buttons["武器"].size.x - 4.0 and weapon_slot_icon.size.y <= panel.equipment_buttons["武器"].size.y - 4.0, "装备图标侵入简洁插槽边框")
	assert(weapon_slot_icon.size == weapon_slot_icon.texture.get_size(), "原游戏物品图被缩放，未保持1:1原始清晰度")

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

	# --- Direct activation contract: single click selects, double click uses ---
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("太阳水", 2)
	PlayerState.add_item("匕首")
	PlayerState.add_item("布衣(女)")
	panel.refresh()
	await get_tree().process_frame

	var sun_index := _inventory_index_of("太阳水")
	var dagger_index := _inventory_index_of("匕首")
	assert(sun_index >= 0 and dagger_index >= 0, "双击测试物品缺失")
	panel._select_inventory_item(sun_index)
	assert(PlayerState.item_count("太阳水") == 2, "单击不应使用物品")
	assert(panel.selected_inventory_index == sun_index, "单击应只选择并显示详情")
	assert("太阳水" in panel.detail_label.text, "单击未显示物品详情")
	panel._select_inventory_item(dagger_index)
	assert(PlayerState.equipment.get("武器", {}).is_empty(), "单击装备不应直接装备")
	await get_tree().process_frame

	var sun_button := panel.item_grid.get_child(sun_index).get_node("ItemButton") as Button
	assert(sun_button.gui_input.is_connected(Callable(panel, "_inventory_input").bind(sun_index)), "物品按钮未连接背包输入处理器")
	var double_click := InputEventMouseButton.new()
	double_click.button_index = MOUSE_BUTTON_LEFT
	double_click.pressed = true
	double_click.double_click = true
	double_click.position = sun_button.size * 0.5
	panel._inventory_input(double_click, sun_index, sun_button)
	await get_tree().process_frame
	assert(PlayerState.item_count("太阳水") == 1, "双击消耗品应使用一次")
	assert("使用：太阳水" in panel.detail_label.text, "双击使用结果未显示")

	sun_index = _inventory_index_of("太阳水")
	dagger_index = _inventory_index_of("匕首")
	var dagger_button := panel.item_grid.get_child(dagger_index).get_node("ItemButton") as Button
	# preferred_slot intentionally stays empty: PlayerState is the authoritative
	# equipment-slot resolver, so the UI does not hardcode a side slot here.
	var equip_click := InputEventMouseButton.new()
	equip_click.button_index = MOUSE_BUTTON_LEFT
	equip_click.pressed = true
	equip_click.double_click = true
	equip_click.position = dagger_button.size * 0.5
	panel._inventory_input(equip_click, dagger_index, dagger_button)
	await get_tree().process_frame
	assert(str(PlayerState.equipment.get("武器", {}).get("name", "")) == "匕首", "双击装备应直接穿戴")
	assert(not PlayerState.has_item("匕首"), "双击装备后物品应移出背包")

	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("太阳水", 2)
	panel.refresh()
	await get_tree().process_frame
	sun_index = _inventory_index_of("太阳水")
	sun_button = panel.item_grid.get_child(sun_index).get_node("ItemButton") as Button
	var touch_tap := InputEventScreenTouch.new()
	touch_tap.index = 5
	touch_tap.pressed = true
	touch_tap.double_tap = true
	touch_tap.position = sun_button.size * 0.5
	panel._inventory_input(touch_tap, sun_index, sun_button)
	await get_tree().process_frame
	assert(PlayerState.item_count("太阳水") == 1, "触摸双击应使用一次")

	# --- Production long-press suppressed, menu builder retained ---
	sun_button = panel.item_grid.get_child(sun_index).get_node("ItemButton") as Button
	panel.context_menu.clear()
	panel.context_menu.hide()
	panel._context_actions.clear()
	panel._press_context = {"source": "inventory", "index": sun_index}
	panel._press_button = sun_button
	panel.call("_on_long_press_timer_timeout")
	assert(not panel.context_menu.visible, "生产长按不应弹出上下文菜单")
	assert(panel.context_menu.item_count == 0, "生产长按不应构建菜单")
	panel._add_inventory_context_actions(sun_index)
	assert(panel.context_menu.item_count == 1 and panel._context_actions[1].get("action", "") == "use", "长按菜单动作构建逻辑应保留")

	# --- Drag beyond threshold cancels long-press and activation ---
	var press_down := InputEventScreenTouch.new()
	press_down.index = 6
	press_down.pressed = true
	press_down.position = sun_button.size * 0.5
	panel._inventory_input(press_down, sun_index, sun_button)
	var drag_event := InputEventScreenDrag.new()
	drag_event.index = 6
	drag_event.position = press_down.position + Vector2(0, 16)
	panel._inventory_input(drag_event, sun_index, sun_button)
	assert(panel._press_timer.is_stopped(), "拖动越过阈值应取消长按")
	var press_up := InputEventScreenTouch.new()
	press_up.index = 6
	press_up.pressed = false
	press_up.position = drag_event.position
	panel._inventory_input(press_up, sun_index, sun_button)
	await get_tree().process_frame
	assert(PlayerState.item_count("太阳水") == 1, "拖动释放不应使用或装备物品")
	assert(not panel.context_menu.visible, "拖动后不应弹出菜单")
	print("INVENTORY_EQUIPMENT_UI_PASS：双击激活、单击选择、长按策略与拖动取消均通过")
	get_tree().quit(0)


func _inventory_index_of(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1
