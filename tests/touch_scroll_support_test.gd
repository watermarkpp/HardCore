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
	var hud_root := hud.get_node("MobileSafeRoot")
	for scroll_name: String in [
		"InventoryScroll",
		"MapListScroll",
		"WorldTreeScroll",
		"UnlockScroll",
		"QuestListScroll",
		"GoodsScroll",
		"SkillListScroll",
		"StashScroll",
		"BagScroll",
	]:
		var found := _find_named(hud_root, scroll_name) as ScrollContainer
		assert(found != null, "玩家UI缺少滚动区域：%s" % scroll_name)
		assert(
			found.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
			"%s没有接入共享触摸拖动滚动" % scroll_name,
		)
	for node: Node in _walk(hud_root):
		if node is RichTextLabel and (node as RichTextLabel).scroll_active:
			assert(
				node.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID,
				"带滚动条的富文本没有接入共享触摸拖动：%s" % node.name,
			)

	var character_select: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(character_select)
	await get_tree().process_frame
	var profile_scroll := _find_named(character_select, "ProfileScroll") as ScrollContainer
	assert(profile_scroll != null)
	assert(profile_scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID)

	print("TOUCH_SCROLL_SUPPORT_PASS: 八类玩家面板与人物列表均支持内容区手指拖动")
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
