extends Node
const Inventory := preload("res://scripts/inventory_panel.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.character_name = "角色[测试]"
	PlayerState.profession = "战士"
	PlayerState.level = 35
	PlayerState.experience = 123
	var panel := Inventory.new()
	add_child(panel)
	panel.show()
	for i in range(5): await get_tree().process_frame
	var text: RichTextLabel = panel.equipment_stats_label
	var help: Node = panel.character_attribute_help
	assert(text.get_parsed_text().begins_with("角色[测试]\n\n战士 等级：35\n\n"))
	assert(text.text.contains("[font_size=19]") and text.text.contains("[font_size=17]"))
	assert(not text.scroll_active and not text.get_v_scroll_bar().is_visible_in_tree())
	assert(text.size.y > 500 and text.get_content_height() <= text.size.y, "all character content fits: %s/%s" % [text.get_content_height(), text.size.y])
	assert(not panel.get_node("AttributePanel/AttributeTitle").visible)
	assert(text.text.contains("[url=attribute:等级]") and text.text.contains("[url=attribute:魔法值]"))
	# The real native-touch path must resolve the level link after calibration.
	var found := false
	for y in range(44, 84, 4):
		for x in range(45, 130, 6):
			var point := text.get_global_transform_with_canvas() * Vector2(x,y)
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = get_viewport().get_final_transform() * point
			event.pressed = true
			Input.parse_input_event(event)
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			if help.active_attribute == "等级":
				found = true
				break
		if found: break
	assert(found, "native touch opens level explanation")
	assert(help._copy.text == "等级\n123/%d" % PlayerState.experience_to_next_level())
	text.meta_clicked.emit("attribute:等级")
	assert(not help._bubble.visible)
	PlayerState.experience = 456
	text.meta_clicked.emit("attribute:等级")
	assert(help._copy.text.contains("456/"), "experience is live, not cached")
	panel._close()
	assert(not help._bubble.visible, "UI close dismisses character help")
	panel.show()
	text.meta_clicked.emit("attribute:攻击")
	panel._refresh_character_stats()
	assert(not help._bubble.visible, "refresh dismisses stale help")
	text.meta_clicked.emit("attribute:速度")
	var bubble: WeakRef = weakref(help._bubble)
	panel.queue_free()
	await get_tree().process_frame
	assert(bubble.get_ref() == null)
	print("CHARACTER_STATS_MILESTONE_PASS")
	get_tree().quit()
