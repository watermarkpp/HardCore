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
	var identity: RichTextLabel = panel.character_identity_label
	var identity_help: Node = panel.character_identity_help
	assert(identity.get_parsed_text() == "角色[测试]\n\n战士    等级：35")
	assert(identity.text.contains("[font_size=19]") and identity.text.contains("[font_size=17]"))
	assert(identity.text.begins_with("[center]") and not text.text.contains("[center]"))
	assert(is_equal_approx((76.0 - identity.position.y) * (1200.0 / 720.0), 50.0))
	assert(is_equal_approx((172.0 - text.position.y) * (1200.0 / 720.0), 50.0))
	assert(not text.scroll_active and not text.get_v_scroll_bar().is_visible_in_tree())
	assert(not identity.scroll_active and not identity.get_v_scroll_bar().is_visible_in_tree())
	assert(text.get_content_height() <= text.size.y, "all character content fits: %s/%s" % [text.get_content_height(), text.size.y])
	var title := panel.get_node("AttributePanel/AttributeTitle") as Label
	var frame := panel.get_node("AttributePanel/AttributePanelDecoration/AttributePanelFrame") as Control
	assert(title.visible and title.text == "人物属性")
	for block: Control in [identity, text, title]:
		assert(absf(block.get_global_rect().get_center().x - frame.get_global_rect().get_center().x) < 0.1, "block centers on visible level-2 frame")
	assert(text.get_global_rect().end.y < frame.get_global_rect().end.y)
	assert(text.text.contains("[url=attribute:魔法值]"))
	# Tap the middle of the numeric suffix, not the label “等级”. This fails if
	# only the label is linked, even when its BBCode contains the right URL.
	var font := identity.get_theme_font("normal_font")
	var style := identity.get_theme_stylebox("normal")
	var content_width := identity.size.x - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT)
	var line_width := font.get_string_size("战士    等级：35", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var number_x := style.get_margin(SIDE_LEFT) + (content_width - line_width) * 0.5 + font.get_string_size("战士    等级：", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + font.get_string_size("35", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x * 0.5
	var found := false
	var level_point := Vector2.ZERO
	for y in range(35, 86, 3):
		level_point = identity.get_global_transform_with_canvas() * Vector2(number_x,y)
		_touch(level_point)
		if identity_help.active_attribute == "等级":
			found = true
			break
	assert(found, "native touch on level number opens experience")
	assert(identity_help._copy.text == "等级\n123/%d" % PlayerState.experience_to_next_level())
	_touch(level_point)
	assert(not identity_help._bubble.visible, "repeat tap on number dismisses experience")
	PlayerState.experience = 456
	identity.meta_clicked.emit("attribute:等级")
	assert(identity_help._copy.text.contains("456/"), "experience is live, not cached")
	panel._close()
	assert(not identity_help._bubble.visible, "UI close dismisses experience")
	panel.show()
	identity.meta_clicked.emit("attribute:等级")
	text.meta_clicked.emit("attribute:攻击")
	assert(not identity_help._bubble.visible, "switching attribute blocks closes previous explanation")
	panel._refresh_character_stats()
	assert(not help._bubble.visible, "refresh dismisses stale help")
	text.meta_clicked.emit("attribute:速度")
	var identity_rect := identity.get_global_rect()
	var title_rect := title.get_global_rect()
	var stat_keys := ["max_hp", "max_mp", "attack_min", "attack_max", "magic_min", "magic_max", "tao_min", "tao_max", "defense_min", "defense_max", "magic_defense_min", "magic_defense_max", "accuracy", "agility", "luck", "magic_evasion_percent", "attack_speed_tier", "wear_weight", "max_wear_weight"]
	var zero_width := 0.0
	for digits: int in [0, 9, 99, 999, 0]:
		var values := {}
		for key: String in stat_keys: values[key] = digits
		text.text = panel._character_stats_text(values)
		panel._layout_character_attributes()
		await get_tree().process_frame
		var body_rect := text.get_global_rect()
		if digits == 0: zero_width = body_rect.size.x
		else: assert(body_rect.size.x >= zero_width, "longer values grow the centered block")
		assert(absf(body_rect.get_center().x - frame.get_global_rect().get_center().x) < 0.1)
		assert(body_rect.position.x >= frame.global_position.x + 15.0 and body_rect.end.x <= frame.get_global_rect().end.x - 15.0, "both frame margins remain clear")
		assert(text.get_line_count() == 10, "numeric values must not split/reorder attribute rows")
		assert(text.get_theme_font_size("normal_font_size") == 16, "up to three digits keep the reviewed font size")
		assert(identity.get_global_rect().is_equal_approx(identity_rect) and title.get_global_rect().is_equal_approx(title_rect))
		assert(text.get_content_height() <= text.size.y, "long values must remain visible: %d height=%d region=%s" % [digits,text.get_content_height(),text.size])
		# Replay the old production calibration while the new values are visible.
		# No deferred pass may restore the old body width/height or move the rows.
		preload("res://scripts/ui_runtime_layout_overrides.gd").apply_profile(panel, "inventory")
		for i in range(6):
			await get_tree().process_frame
			assert(text.get_global_rect().is_equal_approx(body_rect), "stale calibration overwrote content geometry")
	var bubble: WeakRef = weakref(help._bubble)
	panel.queue_free()
	await get_tree().process_frame
	assert(bubble.get_ref() == null)
	print("CHARACTER_STATS_MILESTONE_PASS")
	get_tree().quit()


func _touch(point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_final_transform() * point
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
