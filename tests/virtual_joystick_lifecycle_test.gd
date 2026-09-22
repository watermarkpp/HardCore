extends Node


func _ready() -> void:
	var joystick := TouchJoystick.new()
	joystick.size = Vector2(144.0, 144.0)
	add_child(joystick)

	var touch := InputEventScreenTouch.new()
	touch.index = 11
	touch.pressed = true
	touch.position = Vector2(120.0, 72.0)
	joystick._gui_input(touch)
	assert(joystick.input_state_snapshot().pointer_id == 11)

	var emulated_mouse := InputEventMouseButton.new()
	emulated_mouse.device = InputEvent.DEVICE_ID_EMULATION
	emulated_mouse.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse.pressed = true
	emulated_mouse.position = Vector2(72.0, 120.0)
	joystick._gui_input(emulated_mouse)
	assert(joystick.input_state_snapshot().pointer_id == 11,
		"emulated mouse must not replace the real touch owner")

	var unrelated_up := InputEventScreenTouch.new()
	unrelated_up.index = 12
	unrelated_up.pressed = false
	joystick._input(unrelated_up)
	assert(joystick.input_state_snapshot().pointer_id == 11,
		"another finger UP must not cancel the joystick owner")

	var outside_up := InputEventScreenTouch.new()
	outside_up.index = 11
	outside_up.pressed = false
	joystick._input(outside_up)
	assert(joystick.input_state_snapshot().pointer_id == -1)
	assert(joystick.input_state_snapshot().value == Vector2.ZERO)

	var idle_cancel := InputEventScreenTouch.new()
	idle_cancel.index = 14
	idle_cancel.pressed = true
	idle_cancel.canceled = true
	joystick._gui_input(idle_cancel)
	assert(joystick.input_state_snapshot().pointer_id == -1,
		"a cancelled DOWN must not establish a new owner")

	var real_mouse := InputEventMouseButton.new()
	real_mouse.button_index = MOUSE_BUTTON_LEFT
	real_mouse.pressed = true
	real_mouse.position = Vector2(100.0, 72.0)
	joystick._gui_input(real_mouse)
	joystick._gui_input(real_mouse)
	assert(joystick.input_state_snapshot().pointer_id == -2,
		"a repeated mouse DOWN must not cancel its existing owner")
	real_mouse.pressed = false
	joystick._gui_input(real_mouse)
	assert(joystick.input_state_snapshot().pointer_id == -1)

	touch.pressed = true
	joystick._gui_input(touch)
	touch.canceled = true
	joystick._input(touch)
	assert(joystick.input_state_snapshot().pointer_id == -1)

	print("VIRTUAL_JOYSTICK_LIFECYCLE_TEST_PASS")
	get_tree().quit(0)
