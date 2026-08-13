extends Node

const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Control.new()
	host.position = Vector2(20, 20)
	host.size = Vector2(240, 180)
	add_child(host)
	var scroll := ScrollContainer.new()
	scroll.name = "TestScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(220, 900)
	scroll.add_child(content)
	var support := TouchScrollSupportScript.attach_tree(host)
	await get_tree().process_frame
	var bar := scroll.get_v_scroll_bar()
	assert(bar.max_value > bar.page)
	assert(scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID)
	assert(bar.value == 0.0)
	support.call("_begin_drag_candidate", scroll.get_global_rect().get_center(), 3)
	support.call("_continue_drag", scroll.get_global_rect().get_center() + Vector2(0, -90), Vector2(0, -90))
	assert(bar.value >= 89.0, "按住内容向上拖动没有推进滚动位置")
	assert(bar.visible, "滚动条应保留为当前位置指示")
	assert(
		bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and bar.focus_mode == Control.FOCUS_NONE
			and bool(bar.get_meta("position_indicator_only", false)),
		"滚动条仍会抢占触摸输入，不是纯位置指示器"
	)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var hud_root := hud.get_node("MobileSafeRoot") as Control
	assert(hud.get_node_or_null("SkillPanel") == null, "技能面板应为懒加载")
	hud._ensure_skill_panel()
	(hud.get("skill_panel") as SkillPanel).open_for("技能导师")
	await get_tree().process_frame
	var skill_scroll := _find_named(hud, "SkillListScroll") as ScrollContainer
	assert(skill_scroll != null, "懒加载技能面板缺少 SkillListScroll")
	assert(
		skill_scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
		"懒加载技能面板滚动区没有接入共享触摸拖动",
	)
	for node: Node in _walk(hud.get("skill_panel")):
		if node is RichTextLabel and (node as RichTextLabel).scroll_active:
			assert(
				node.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
				"懒加载技能面板富文本没有接入共享触摸拖动：%s" % node.name,
			)
	var late_scroll := ScrollContainer.new()
	late_scroll.name = "LateScroll"
	late_scroll.size = Vector2(200, 120)
	var late_content := Control.new()
	late_content.custom_minimum_size = Vector2(180, 600)
	late_scroll.add_child(late_content)
	hud_root.add_child(late_scroll)
	await get_tree().process_frame
	assert(
		late_scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
		"attach 后动态加入的滚动容器没有自动注册",
	)

	# Lazy panel coverage: every real _ensure_* panel must register its scrolls.
	PlayerState.profession = "战士"
	hud._ensure_inventory_panel()
	hud._ensure_shop_panel()
	hud._ensure_skill_panel()
	hud._ensure_quest_panel()
	hud._ensure_map_panel()
	hud._ensure_warehouse_panel()
	(hud.get("skill_panel") as SkillPanel).open_for("技能导师")
	await get_tree().process_frame
	for scroll_name: String in [
		"InventoryScroll",
		"MapListScroll",
		"WorldTreeScroll",
		"QuestListScroll",
		"GoodsScroll",
		"SkillListScroll",
		"StashScroll",
		"BagScroll",
	]:
		var found := _find_named(hud, scroll_name) as ScrollContainer
		assert(found != null, "玩家UI缺少滚动区域：%s" % scroll_name)
		assert(
			found.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
			"%s没有接入共享触摸拖动滚动" % scroll_name,
		)
	for node: Node in _walk(hud):
		if node is RichTextLabel and (node as RichTextLabel).scroll_active:
			assert(
				node.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
				"带滚动条的富文本没有接入共享触摸拖动：%s" % node.name,
			)

	# Real SkillListScroll drag: content must overflow, scroll must advance,
	# and the skill card must not emit pressed after the drag.
	get_tree().root.size = Vector2i(1400, 900)
	await get_tree().process_frame
	var drag_skill_scroll := _find_named(hud, "SkillListScroll") as ScrollContainer
	var skill_bar := drag_skill_scroll.get_v_scroll_bar()
	assert(skill_bar.max_value > skill_bar.page, "技能列表没有真实溢出，无法验证拖动")
	var skill_cards := drag_skill_scroll.get_node("SkillCards")
	var skill_card := skill_cards.get_child(0) as Button
	var card_presses: Array[int] = [0]
	skill_card.pressed.connect(func() -> void: card_presses[0] += 1)

	# 先验证非拖动 tap：release 不被共享服务消费，普通点击仍触发 pressed。
	drag_skill_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var tap_center := skill_card.get_global_rect().get_center()
	var tap_down := InputEventScreenTouch.new()
	tap_down.index = 10
	tap_down.pressed = true
	tap_down.position = tap_center
	get_viewport().push_input(tap_down)
	assert(skill_card.button_pressed, "普通点击按下未到达技能卡按钮")
	var tap_up := InputEventScreenTouch.new()
	tap_up.index = 10
	tap_up.pressed = false
	tap_up.position = tap_center
	assert(not bool(support.get("_dragging")), "普通点击被错误标记为滚动拖动")
	get_viewport().push_input(tap_up)
	assert(int(support.get("_active_touch_index")) == -1, "普通点击 release 后触摸候选未复位")

	# 再验证真实拖动：滚动推进、拖动后 pressed 不再增加、共享状态复位。
	card_presses[0] = 0
	var card_global_center := skill_card.get_global_rect().get_center()
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 9
	touch_down.pressed = true
	touch_down.position = card_global_center
	get_viewport().push_input(touch_down)
	support.call("_input", touch_down)
	assert(skill_card.button_pressed, "触摸按下未到达技能卡按钮")
	var drag_position := card_global_center + Vector2(0, -180)
	var drag_event := InputEventScreenDrag.new()
	drag_event.index = 9
	drag_event.position = drag_position
	drag_event.relative = Vector2(0, -180)
	get_viewport().push_input(drag_event)
	support.call("_input", drag_event)
	assert(skill_bar.value >= skill_bar.max_value - skill_bar.page - 1.0, "技能卡片拖动没有推进列表滚动")
	assert(TouchScrollSupportScript.is_drag_active(get_tree()), "技能列表拖动期间共享状态未发布")
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 9
	touch_up.pressed = false
	touch_up.position = drag_position
	get_viewport().push_input(touch_up)
	support.call("_input", touch_up)
	assert(card_presses[0] == 0, "技能列表拖动越过阈值后仍触发了卡片点击")
	assert(not TouchScrollSupportScript.is_drag_active(get_tree()), "技能列表拖动结束后共享状态未复位")

	var character_select: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(character_select)
	await get_tree().process_frame
	var profile_scroll := _find_named(character_select, "ProfileScroll") as ScrollContainer
	assert(profile_scroll != null)
	assert(profile_scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID)

	print("TOUCH_SCROLL_SUPPORT_PASS: 动态后代注册与懒加载技能面板均通过")
	get_tree().quit(0)


func _find_named(root: Node, node_name: String) -> Node:
	for node: Node in _walk(root):
		if node.name == node_name:
			return node
	return null


func _walk(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child: Node in root.get_children():
		result.append_array(_walk(child))
	return result
