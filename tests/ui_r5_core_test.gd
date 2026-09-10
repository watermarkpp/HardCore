extends Node

const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const Presenter := preload("res://scripts/item_detail_docked_presenter.gd")
const Guard := preload("res://scripts/ui_selection_dismiss_guard.gd")
const Visual := preload("res://scripts/ui_item_selection_visual.gd")
var failures: Array[String] = []
var checks := 0

class TestScope:
	extends Panel
	var dismiss_count := 0
	var revision := 0
	var presentation := "right"
	var scroll: Control
	var buy_button: Button
	var repair_button: Button
	var sell_quantity_row: Control
	var sell_quantity_button: Button
	func _ui_selection_token() -> Array:
		return [revision]
	func _ui_dismiss_selection() -> void:
		dismiss_count += 1
		revision += 1
	func _ui_detail_region(_context: Dictionary) -> Dictionary:
		if presentation == "shop":
			return Dock.shop_region(self)
		return Dock.side_region(self, scroll, presentation)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var scope := TestScope.new()
	scope.position = Vector2(200, 40)
	scope.size = Vector2(1080, 620)
	add_child(scope)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(640, 90)
	scroll.size = Vector2(357, 340)
	scope.add_child(scroll)
	scope.scroll = scroll
	var view := Presenter.new()
	scope.add_child(view)
	for zoom: float in [0.75, 1.0, 1.2]:
		scope.scale = Vector2.ONE * zoom
		scope.presentation = "right"
		view.show_text("长属性测试", "追加属性：攻击 +5\n".repeat(80))
		await get_tree().process_frame
		var region: Rect2 = scope._ui_detail_region({})["region"]
		var actual := Rect2(view.position, view.size)
		expect(view.debug_layout_valid(), "right dock has usable space at scale " + str(zoom))
		expect(region.grow(0.5).encloses(actual), "right detail remains bounded")
		expect(not actual.intersects(Dock.rect_in(scope, scroll)), "right detail never covers grid")
		expect(view.detail_label.scroll_active, "long body can scroll")
		expect(view.detail_label.text.count("追加属性") == 80, "long body is not truncated")
		scroll.position.x = 64
		scope.presentation = "left"
		view.show_message("无法使用：不满足条件。")
		await get_tree().process_frame
		region = scope._ui_detail_region({})["region"]
		actual = Rect2(view.position, view.size)
		expect(region.grow(0.5).encloses(actual), "left detail remains bounded")
		expect(actual.end.x <= Dock.rect_in(scope, scroll).position.x, "left detail stays left")
		scroll.position.x = 640
	scope.scale = Vector2.ONE
	view.hide_detail()
	expect(view.detail_label.text.is_empty() and view.title_label.text.is_empty(), "hide clears both text sinks")
	# Real transform round-trip (not origin + unscaled size).
	var expected := Dock.transformed_rect(scope.get_global_transform_with_canvas().affine_inverse() * scroll.get_global_transform_with_canvas(), Rect2(Vector2.ZERO, scroll.size))
	expect(Dock.rect_in(scope, scroll).is_equal_approx(expected), "coordinate transform uses all corners")

	var button := Button.new()
	button.position = Vector2(40, 40)
	button.size = Vector2(90, 60)
	button.toggle_mode = true
	var theme_resource := Theme.new()
	var plain := StyleBoxFlat.new()
	var chosen := StyleBoxFlat.new()
	theme_resource.set_stylebox("normal", "R5Plain", plain)
	theme_resource.set_stylebox("normal", "R5Chosen", chosen)
	# Godot 4.7 resolves a custom type variation through the theme chain only
	# when it is registered against the base type, as every production Gothic
	# variation in gothic_ui_theme.gd does before use.
	theme_resource.set_type_variation("R5Plain", "Button")
	theme_resource.set_type_variation("R5Chosen", "Button")
	button.theme = theme_resource
	scope.add_child(button)
	Visual.apply(button, true, &"R5Plain", &"R5Chosen")
	expect(button.button_pressed, "semantic selection presses toggle")
	Visual.apply(button, false, &"R5Plain", &"R5Chosen")
	expect(not button.button_pressed, "deselection clears pressed state")
	expect(button.get_theme_stylebox("hover") == plain, "hover cannot resurrect selected frame")
	expect(button.get_theme_stylebox("pressed") == plain, "press frame equals unselected normal")
	expect(button.get_theme_stylebox("focus") is StyleBoxEmpty, "no ghost focus frame")

	var guard := Guard.new()
	guard.register_scope(scope)
	add_child(guard)
	await get_tree().process_frame
	var blank := scope.get_global_transform_with_canvas() * Vector2(500, 560)
	var occupied := button.get_global_transform_with_canvas() * Vector2(30, 30)
	guard._begin(0, blank)
	guard._end(0, blank, false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "one blank tap clears once")
	guard._begin(0, occupied)
	guard._end(0, occupied, false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "functional button is protected")
	guard._begin(0, blank)
	guard._move(0, blank + Vector2(0, 30))
	guard._end(0, blank + Vector2(0, 30), false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "drag is not a blank tap")
	guard._begin(0, blank)
	guard._pointers[0]["time"] = Time.get_ticks_msec() - 600
	guard._begin(1, blank)
	guard._end(1, blank, false)
	guard._end(0, blank, false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "second finger after long hold cannot clear")
	guard._begin(0, blank)
	guard._end(0, blank, true)
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "native cancellation is ignored")
	guard._begin(0, blank)
	guard._end(0, blank, false)
	scope.revision += 1
	await get_tree().process_frame
	expect(scope.dismiss_count == 1, "deferred clear cannot erase a newer selection")
	var fake_mouse := InputEventMouseButton.new()
	fake_mouse.device = InputEvent.DEVICE_ID_EMULATION
	fake_mouse.button_index = MOUSE_BUTTON_LEFT
	fake_mouse.pressed = true
	fake_mouse.position = blank
	guard._input(fake_mouse)
	expect(guard._pointers.is_empty(), "emulated mouse does not duplicate native gesture")
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guard._begin(0, occupied)
	guard._end(0, occupied, false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 2, "passive empty cell clears")
	button.disabled = false
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	guard._begin(0, occupied)
	guard._end(0, occupied, false)
	await get_tree().process_frame
	expect(scope.dismiss_count == 2, "functional empty unequip target remains protected")
	guard.queue_free()
	scope.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	for failure: String in failures:
		push_error("UI_R5_CORE: " + failure)
	print("UI_R5_CORE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
