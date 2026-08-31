class_name TouchJoystick
extends Control

signal vector_changed(value: Vector2)

var radius := 72.0
var knob_radius := 30.0
var external_frame := false
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
			cancel_input()
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_update_value(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_id = -2
				_update_value(event.position)
			elif _pointer_id == -2:
				cancel_input()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		_update_value(event.position)


func _update_value(local_position: Vector2) -> void:
	var center := size * 0.5
	_value = ((local_position - center) / radius).limit_length(1.0)
	vector_changed.emit(_value)
	queue_redraw()


func cancel_input() -> void:
	# Idempotent lifecycle boundary: a lost release must never keep ownership or
	# a non-zero vector alive across a map transition.
	_pointer_id = -1
	_value = Vector2.ZERO
	vector_changed.emit(Vector2.ZERO)
	queue_redraw()


func input_state_snapshot() -> Dictionary:
	return {
		"pointer_id": _pointer_id,
		"value": _value,
	}


func _draw() -> void:
	var center := size * 0.5
	if not external_frame:
		draw_circle(center, radius, Color(0.025, 0.018, 0.016, 0.62))
		draw_circle(center, radius - 3.0, Color(0.38, 0.27, 0.17, 0.36), false, 3.0)
		draw_circle(center, radius - 10.0, Color(0.72, 0.54, 0.31, 0.25), false, 2.0)
		for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			var tip: Vector2 = center + direction * (radius - 7.0)
			var side: Vector2 = direction.orthogonal() * 6.0
			draw_colored_polygon(PackedVector2Array([tip, center + direction * (radius - 18.0) + side, center + direction * (radius - 18.0) - side]), Color(0.72, 0.53, 0.30, 0.74))
	var knob_center := center + _value * radius * 0.72
	draw_circle(knob_center, knob_radius + 3.0, Color(0.06, 0.035, 0.025, 0.92))
	draw_circle(knob_center, knob_radius, Color(0.59, 0.40, 0.21, 0.84))
	draw_circle(knob_center, knob_radius - 6.0, Color(0.20, 0.11, 0.065, 0.92))
	draw_arc(knob_center, knob_radius - 2.0, 0.0, TAU, 32, Color(0.88, 0.68, 0.40, 0.72), 2.0, true)
