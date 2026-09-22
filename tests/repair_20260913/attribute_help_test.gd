extends Node
const Help := preload("res://scripts/item_attribute_help.gd")
const Panels := [preload("res://scripts/inventory_panel.gd"),preload("res://scripts/warehouse_panel.gd"),preload("res://scripts/shop_panel.gd")]

func _ready() -> void:
	_run.call_deferred()

func frames() -> void:
	for i in range(4): await get_tree().process_frame

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func tap(point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_final_transform() * point
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	var copy := "攻击 3-5　魔法 1-4\n强度 +1\n速度 +1"
	for key: String in Help.ENTRIES:
		assert(Help.decorate(key + " +1").contains("[url=attribute:"+key+"]"), key)
	assert(Help.decorate("[color=#ffaa33]攻击上限 +2[/color]").contains("攻击上限[/u]"))
	assert(Help.decorate("description_internal_code")=="description_internal_code")
	for script: GDScript in Panels:
		var ancestor := Control.new()
		ancestor.size = get_viewport().get_visible_rect().size
		add_child(ancestor)
		var owner: Control = script.new()
		ancestor.add_child(owner)
		owner.show()
		await frames()
		var presenter: Control = owner.get("item_detail_presenter")
		var context := {"presentation_zone":"shop" if owner is ShopPanel else "bag"}
		presenter.show_text("属性说明测试", copy, context)
		await frames()
		assert(presenter.debug_layout_valid(),str(owner.name))
		var helper: Node = presenter.attribute_help
		var body: RichTextLabel = presenter.detail_label
		assert(body.get_parsed_text()==copy)
		var geometry := presenter.get_rect()
		# Actual GUI hit-testing of the first underlined attribute.
		var point := body.get_global_transform_with_canvas() * Vector2(8, 10)
		click(point)
		await frames()
		assert(helper.active_attribute=="攻击",str(owner.name)+" actual link click")
		assert(helper._bubble.is_visible_in_tree())
		assert(helper._copy.text.contains("物理攻击"))
		assert(presenter.get_rect()==geometry,"help must not resize the item window")
		assert(get_viewport().get_visible_rect().encloses(helper._bubble.get_rect()),"explanation must stay onscreen: %s viewport %s" % [helper._bubble.get_rect(),get_viewport().get_visible_rect()])
		click(point)
		assert(helper.active_attribute.is_empty() and not helper._bubble.visible,"same link closes")
		tap(point)
		await frames()
		assert(helper.active_attribute=="攻击","native touch opens attribute help")
		tap(point)
		await frames()
		assert(helper.active_attribute.is_empty(),"native touch toggles help off")
		body.meta_clicked.emit("attribute:强度")
		assert(helper.active_attribute=="强度")
		presenter.show_text("换一件物品",copy,context)
		assert(not helper._bubble.visible,"new content closes")
		await frames()
		body.meta_clicked.emit("attribute:速度")
		presenter.hide_detail()
		assert(not helper._bubble.visible,"detail close closes help")
		presenter.show_text("属性说明测试",copy,context)
		await frames()
		body.meta_clicked.emit("attribute:速度")
		ancestor.hide()
		assert(not helper._bubble.visible,"ancestor/UI hide closes independent canvas")
		ancestor.show()
		await frames()
		body.meta_clicked.emit("attribute:速度")
		owner._close()
		assert(not helper._bubble.visible,"actual UI close closes help")
		owner.show()
		await frames()
		presenter.show_text("长属性",copy+"\n"+"攻击 +1\n".repeat(80),context)
		await frames()
		body.meta_clicked.emit("attribute:速度")
		body.get_v_scroll_bar().value = 30
		assert(not helper._bubble.visible,"scroll closes")
		assert(not body.get_v_scroll_bar().is_visible_in_tree())
		body.meta_clicked.emit("attribute:强度")
		var bubble_ref: WeakRef = weakref(helper._bubble)
		ancestor.free()
		assert(bubble_ref.get_ref()==null,"free UI frees explanation canvas")
	print("ATTRIBUTE_HELP_PASS inventory warehouse shop real-click toggle close ancestor switch scroll free")
	get_tree().quit()
