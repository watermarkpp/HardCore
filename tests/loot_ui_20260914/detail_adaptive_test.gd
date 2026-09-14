extends Node
const PanelScript := preload("res://scripts/inventory_panel.gd")
const Rules := preload("res://scripts/item_drop_instance_rules.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var panel := PanelScript.new()
	add_child(panel)
	for i in range(3): await get_tree().process_frame
	var view = panel.item_detail_presenter
	var pearl := GameData.get_item_record("珍珠戒指")
	view.show_item(pearl)
	await get_tree().process_frame
	assert(view.debug_layout_valid())
	assert(view.detail_label.size.y - view.detail_label.get_content_height() <= 5.0, "short item must not have artificial empty height")
	view.show_text("测试装备", "防御 0-1")
	await get_tree().process_frame
	var small_height: float = view.size.y
	view.show_text("测试装备", "防御 0-1\n幸运 +1")
	await get_tree().process_frame
	assert(view.size.y > small_height, "new visible attribute must grow the card")
	var marked := 0
	for id in [128,129,130,131,132,133,228,229,230,231,244,245,246,247,248,249]:
		var item := GameData.get_item_rules_record({"item_id":id})
		var instance: Dictionary = {}
		for index in range(100):
			instance = Rules.create_instance(item, "v81-title:%d:%d" % [id,index])
			if Rules.is_affixed_instance(instance,item): break
		assert(Rules.is_affixed_instance(instance,item))
		for context in [{}, {"presentation_zone":"equipment"}]:
			view.show_item(item,instance,context)
			await get_tree().process_frame
			assert(view.debug_layout_valid(), str(id) + str(view.debug_layout_snapshot()))
			assert(view.title_label.text == str(item.name) and view.affix_marker.visible)
			assert(view.title_label.get_minimum_size().x <= view.title_label.size.x)
			assert(is_equal_approx(view.title_label.position.x + view.title_label.size.x / 2.0, view.size.x / 2.0))
			assert(view.affix_marker.position.x >= 0 and view.affix_marker.get_rect().end.x < view.size.x / 2.0)
			assert(not view.detail_label.get_v_scroll_bar().visible)
			assert(is_equal_approx(view.detail_label.position.x + float(view.detail_label.get_content_width()) / 2.0, view.size.x / 2.0), "longest body line must be centered")
		marked += 1
	for value in ["0", "22", "999"]:
		view.show_text("战神盔甲(男)", "类别：盔甲　重量 " + value + "\n耐久：" + value + "/" + value + "\n防御 " + value + "-" + value + "　魔防 1-6\n穿戴要求：攻击46")
		await get_tree().process_frame
		assert(view.debug_layout_valid())
		var body = view.detail_label
		var left: float = body.position.x
		var right: float = view.size.x - left - float(body.get_content_width())
		assert(is_equal_approx(left,right), "final longest-line margins drifted with number width")
	view.hide_detail()
	assert(not view.visible and not view.affix_marker.visible)
	panel.queue_free()
	await get_tree().process_frame
	print("DETAIL_ADAPTIVE_V81_PASS short_height, extra_property, centered_plain_name, centered_body, single_line_jp=%d" % marked)
	get_tree().quit()
