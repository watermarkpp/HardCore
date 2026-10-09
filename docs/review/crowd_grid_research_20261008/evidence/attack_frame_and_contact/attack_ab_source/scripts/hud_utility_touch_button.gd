extends "res://scripts/circular_touch_button.gd"

signal tap_completed

func _input(event: InputEvent) -> void:
	var pointer := -3
	var released := false
	var inside := false
	if event is InputEventScreenTouch:
		pointer = event.index
		released = not event.pressed and not event.canceled
		inside = _has_point(make_input_local(event).position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pointer = MOUSE_TOUCH_ID
		released = not event.pressed
		inside = _has_point(make_input_local(event).position)
	elif event.is_action_released(&"ui_accept"):
		pointer = UI_ACCEPT_TOUCH_ID
		released = true
		inside = true
	var was_owned := _active_inputs.has(pointer)
	super._input(event)
	if was_owned and released and inside and lifecycle_enabled and not disabled and is_visible_in_tree():
		tap_completed.emit()
