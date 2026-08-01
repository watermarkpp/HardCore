extends Node

const CircularTouchButtonScript := preload("res://scripts/circular_touch_button.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _test_button_lifecycle()
	await _test_hud_bridge_and_visual_freeze()
	print("CIRCULAR_TOUCH_BUTTON_LIFECYCLE_PASS: touch tokens, cancellation, compatibility, and HUD geometry")
	get_tree().quit(0)


func _test_button_lifecycle() -> void:
	var button = CircularTouchButtonScript.new()
	button.lifecycle_enabled = true
	button.position = Vector2(40, 30)
	button.size = Vector2(120, 120)
	add_child(button)
	await get_tree().process_frame

	assert(
		CircularTouchButtonScript.INPUT_LIFECYCLE_CONTRACT_ID
		== "ui.input.circular_touch.lifecycle.v1"
	)
	var started: Array[Dictionary] = []
	var ended: Array[Dictionary] = []
	var cancelled: Array[Dictionary] = []
	button.input_started.connect(
		func(token: int, touch_id: int, source: StringName) -> void:
			started.append({"token": token, "touch_id": touch_id, "source": source})
	)
	button.input_ended.connect(
		func(token: int, touch_id: int, source: StringName) -> void:
			ended.append({"token": token, "touch_id": touch_id, "source": source})
	)
	button.input_cancelled.connect(
		func(token: int, touch_id: int, source: StringName, reason: StringName) -> void:
			cancelled.append({
				"token": token,
				"touch_id": touch_id,
				"source": source,
				"reason": reason,
			})
	)

	button._gui_input(_touch(7, true))
	assert(started.size() == 1 and button.active_input_count() == 1)
	var first_token := int(started[0].token)
	assert(first_token > 0 and int(started[0].touch_id) == 7)
	assert(StringName(started[0].source) == &"touch")
	button._gui_input(_touch(7, true))
	assert(started.size() == 1, "repeated DOWN for one touch_id created another token")
	button._gui_input(_touch(7, false))
	assert(
		ended.size() == 1
		and int(ended[0].token) == first_token
		and button.active_input_count() == 0
	)
	var outside_touch_down := _touch(15, true)
	outside_touch_down.position = Vector2(500, 500)
	button._input(outside_touch_down)
	assert(started.size() == 1, "global input incorrectly started an outside touch")
	button._gui_input(_touch(15, true))
	var outside_touch_up := _touch(15, false)
	outside_touch_up.position = Vector2(500, 500)
	var ended_before_outside := ended.size()
	button._input(outside_touch_up)
	button._gui_input(outside_touch_up)
	assert(
		ended.size() == ended_before_outside + 1
		and int(ended[-1].touch_id) == 15
		and button.active_input_count() == 0,
		"outside touch release did not end exactly one token",
	)

	button._gui_input(_touch(8, true))
	var cancelled_token := int(started[-1].token)
	var touch_cancel := _touch(8, false, true)
	var cancelled_before_global := cancelled.size()
	button._input(touch_cancel)
	button._gui_input(touch_cancel)
	assert(
		cancelled.size() == cancelled_before_global + 1
		and int(cancelled[-1].token) == cancelled_token
		and StringName(cancelled[-1].reason) == &"touch_cancelled"
	)

	button._gui_input(_touch(9, true))
	button._gui_input(_touch(10, true))
	assert(button.active_input_count() == 2)
	assert(int(started[-1].token) != int(started[-2].token))
	button._gui_input(_touch(9, false))
	assert(button.active_input_count() == 1 and int(ended[-1].touch_id) == 9)
	button.cancel_all_inputs(&"test_manual")
	assert(
		button.active_input_count() == 0
		and int(cancelled[-1].touch_id) == 10
		and StringName(cancelled[-1].reason) == &"test_manual"
	)

	var starts_before_mouse := started.size()
	button._gui_input(_mouse(true, InputEvent.DEVICE_ID_EMULATION))
	button._gui_input(_mouse(false, InputEvent.DEVICE_ID_EMULATION))
	assert(started.size() == starts_before_mouse, "emulated mouse duplicated a touch press")
	button._gui_input(_mouse(true, InputEvent.DEVICE_ID_MOUSE))
	assert(
		int(started[-1].touch_id) == CircularTouchButtonScript.MOUSE_TOUCH_ID
		and StringName(started[-1].source) == &"mouse"
	)
	var outside_mouse_up := _mouse(false, InputEvent.DEVICE_ID_MOUSE)
	outside_mouse_up.position = Vector2(500, 500)
	var ended_before_mouse := ended.size()
	button._input(outside_mouse_up)
	button._gui_input(outside_mouse_up)
	assert(ended.size() == ended_before_mouse + 1)
	assert(int(ended[-1].touch_id) == CircularTouchButtonScript.MOUSE_TOUCH_ID)

	button._gui_input(_ui_accept(true))
	assert(
		int(started[-1].touch_id) == CircularTouchButtonScript.UI_ACCEPT_TOUCH_ID
		and StringName(started[-1].source) == &"ui_accept"
	)
	button._gui_input(_ui_accept(true))
	assert(button.active_input_count() == 1, "ui_accept echo/repeat created another token")
	var ui_accept_up := _ui_accept(false)
	var ended_before_accept := ended.size()
	button._input(ui_accept_up)
	button._gui_input(ui_accept_up)
	assert(ended.size() == ended_before_accept + 1)
	assert(int(ended[-1].touch_id) == CircularTouchButtonScript.UI_ACCEPT_TOUCH_ID)

	button._gui_input(_touch(11, true))
	button.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(
		button.active_input_count() == 0
		and StringName(cancelled[-1].reason) == &"application_focus_out"
	)
	button._gui_input(_touch(12, true))
	button._on_window_focus_exited()
	assert(StringName(cancelled[-1].reason) == &"window_focus_out")
	button._gui_input(_touch(13, true))
	button.hide()
	assert(StringName(cancelled[-1].reason) == &"hidden")
	button.show()
	button._gui_input(_touch(14, true))
	remove_child(button)
	assert(StringName(cancelled[-1].reason) == &"exit_tree")
	button.queue_free()


func _test_hud_bridge_and_visual_freeze() -> void:
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var root := hud.get_node("MobileSafeRoot") as Control
	var attack := root.get_node("AttackButton") as Button

	assert(GameHUD.HUD_ATTACK_CENTER == Vector2(-185, -110))
	assert(GameHUD.HUD_ATTACK_FILL_SIZE == Vector2(90, 90))
	assert(GameHUD.HUD_ATTACK_ICON_SIZE == Vector2(90, 90))
	assert(GameHUD.HUD_ATTACK_RING_COUNT == 6)
	assert(is_equal_approx(GameHUD.HUD_ATTACK_RING_RADIUS, 125.0))
	assert(GameHUD.HUD_ATTACK_RING_BUTTON_SIZE == Vector2(72, 72))
	assert(attack.size == Vector2(120, 120))
	assert(attack.position + attack.size * 0.5 == root.size + GameHUD.HUD_ATTACK_CENTER)
	assert(attack.theme_type_variation == &"GothicTransparentButton")
	assert(str(attack.get_meta("stable_id", "")) == "hud.attack.primary")
	assert(
		str(attack.get_meta("input_lifecycle_contract", ""))
		== CircularTouchButtonScript.INPUT_LIFECYCLE_CONTRACT_ID
	)
	assert(str(attack.get_meta("assignment_contract", "")) == "ui.skill.button_assignment.v3")
	assert(is_equal_approx(float(attack.get_meta("touch_radius", 0.0)), 60.0))

	var counts := {
		"lifecycle_started": 0,
		"lifecycle_ended": 0,
		"lifecycle_cancelled": 0,
		"legacy_pressed": 0,
		"legacy_released": 0,
	}
	hud.attack_input_started.connect(
		func(_token: int, _touch_id: int, _source: StringName) -> void:
			counts.lifecycle_started = int(counts.lifecycle_started) + 1
	)
	hud.attack_input_ended.connect(
		func(_token: int, _touch_id: int, _source: StringName) -> void:
			counts.lifecycle_ended = int(counts.lifecycle_ended) + 1
	)
	hud.attack_input_cancelled.connect(
		func(_token: int, _touch_id: int, _source: StringName, _reason: StringName) -> void:
			counts.lifecycle_cancelled = int(counts.lifecycle_cancelled) + 1
	)
	hud.attack_pressed.connect(
		func() -> void: counts.legacy_pressed = int(counts.legacy_pressed) + 1
	)
	hud.attack_released.connect(
		func() -> void: counts.legacy_released = int(counts.legacy_released) + 1
	)

	# The native BaseButton signals are deliberately not bridged as a second path.
	attack.button_down.emit()
	attack.button_up.emit()
	assert(int(counts.legacy_pressed) == 0 and int(counts.legacy_released) == 0)
	attack.call("_gui_input", _touch(21, true))
	attack.call("_gui_input", _touch(21, true))
	assert(int(counts.lifecycle_started) == 1 and int(counts.legacy_pressed) == 1)
	attack.call("_gui_input", _touch(21, false))
	assert(int(counts.lifecycle_ended) == 1 and int(counts.legacy_released) == 1)
	attack.call("_gui_input", _touch(22, true))
	hud.cancel_attack_inputs(&"hud_test_cancel")
	assert(
		int(counts.lifecycle_started) == 2
		and int(counts.legacy_pressed) == 2
		and int(counts.lifecycle_cancelled) == 1
		and int(counts.legacy_released) == 2
	)

	hud.queue_free()
	await get_tree().process_frame


func _touch(touch_id: int, pressed: bool, cancelled := false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = touch_id
	event.position = Vector2(60, 60)
	event.pressed = pressed
	event.canceled = cancelled
	return event


func _mouse(pressed: bool, device_id: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(60, 60)
	event.pressed = pressed
	event.device = device_id
	return event


func _ui_accept(pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = pressed
	return event
