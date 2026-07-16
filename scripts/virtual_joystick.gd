class_name TouchJoystick
extends Control

signal vector_changed(value: Vector2)

var radius := 72.0
var knob_radius := 30.0
var _pointer_id := -1
var _value := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _pointer_id == -1:
			_pointer_id = event.index
			_update_value(event.position)
		elif not event.pressed and event.index == _pointer_id:
			_pointer_id = -1
			_value = Vector2.ZERO
			vector_changed.emit(_value)
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_update_value(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_id = -2
				_update_value(event.position)
			elif _pointer_id == -2:
				_pointer_id = -1
				_value = Vector2.ZERO
				vector_changed.emit(_value)
				queue_redraw()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		_update_value(event.position)


func _update_value(local_position: Vector2) -> void:
	var center := size * 0.5
	_value = ((local_position - center) / radius).limit_length(1.0)
	vector_changed.emit(_value)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.08, 0.06, 0.05, 0.46))
	draw_circle(center, radius - 4.0, Color(0.55, 0.45, 0.32, 0.18), false, 3.0)
	draw_circle(center + _value * radius * 0.72, knob_radius, Color(0.72, 0.57, 0.34, 0.65))
