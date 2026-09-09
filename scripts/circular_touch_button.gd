class_name CircularTouchButton
extends Button


signal input_started(press_token: int, touch_id: int, source: StringName)
signal input_ended(press_token: int, touch_id: int, source: StringName)
signal input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
)

const INPUT_LIFECYCLE_CONTRACT_ID := "ui.input.circular_touch.lifecycle.v1"
const MOUSE_TOUCH_ID := -1
const UI_ACCEPT_TOUCH_ID := -2
const SOURCE_TOUCH := &"touch"
const SOURCE_MOUSE := &"mouse"
const SOURCE_UI_ACCEPT := &"ui_accept"

@export var lifecycle_enabled := false

var _next_press_token := 1
var _active_inputs: Dictionary = {}
var _pointer_diagnostic_events: Array[Dictionary] = []


func _ready() -> void:
	var window := get_window()
	if window != null and not window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.connect(_on_window_focus_exited)


func _exit_tree() -> void:
	cancel_all_inputs(&"exit_tree")


func _notification(what: int) -> void:
	if not lifecycle_enabled:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_all_inputs(&"application_focus_out")
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_all_inputs(&"hidden")


func _gui_input(event: InputEvent) -> void:
	if not lifecycle_enabled:
		return
	_record_pointer_diagnostic(&"gui", event)
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	_handle_ui_accept(event)


func _input(event: InputEvent) -> void:
	if not lifecycle_enabled:
		return
	_record_pointer_diagnostic(&"global", event)
	if _active_inputs.is_empty():
		return
	# Global input is a release-only safety net. Starts remain owned by GUI hit
	# testing, while an active pointer is allowed to finish outside this Control.
	# When an inside release reaches _gui_input afterwards, the token is already
	# absent and therefore cannot emit a second end/cancel signal.
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not _active_inputs.has(touch_event.index):
			return
		if touch_event.canceled:
			_cancel_input(touch_event.index, SOURCE_TOUCH, &"touch_cancelled")
		elif not touch_event.pressed:
			_end_input(touch_event.index, SOURCE_TOUCH)
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.device != InputEvent.DEVICE_ID_EMULATION
			and not mouse_event.pressed
			and _active_inputs.has(MOUSE_TOUCH_ID)
		):
			_end_input(MOUSE_TOUCH_ID, SOURCE_MOUSE)
		return
	if (
		_active_inputs.has(UI_ACCEPT_TOUCH_ID)
		and event.is_action_released(&"ui_accept")
	):
		_end_input(UI_ACCEPT_TOUCH_ID, SOURCE_UI_ACCEPT)


func cancel_all_inputs(reason: StringName = &"manual") -> void:
	if _active_inputs.is_empty():
		return
	var active_snapshot: Array = _active_inputs.values().duplicate(true)
	_active_inputs.clear()
	for raw_entry: Variant in active_snapshot:
		var entry: Dictionary = raw_entry
		input_cancelled.emit(
			int(entry.get("press_token", 0)),
			int(entry.get("touch_id", 0)),
			StringName(entry.get("source", &"")),
			reason
		)


func active_input_count() -> int:
	return _active_inputs.size()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var touch_id := event.index
	if event.canceled:
		_cancel_input(touch_id, SOURCE_TOUCH, &"touch_cancelled")
		accept_event()
		return
	if event.pressed:
		if _has_point(event.position):
			_start_input(touch_id, SOURCE_TOUCH)
			accept_event()
		return
	_end_input(touch_id, SOURCE_TOUCH)
	accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# A physical screen touch can also generate a mouse event. Godot marks that
	# synthetic event with DEVICE_ID_EMULATION; consuming it here would create a
	# second press token for the same finger.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event.pressed:
		if _has_point(event.position):
			_start_input(MOUSE_TOUCH_ID, SOURCE_MOUSE)
			accept_event()
		return
	_end_input(MOUSE_TOUCH_ID, SOURCE_MOUSE)
	accept_event()


func _handle_ui_accept(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action(&"ui_accept"):
		return
	if event.is_action_pressed(&"ui_accept"):
		_start_input(UI_ACCEPT_TOUCH_ID, SOURCE_UI_ACCEPT)
		accept_event()
	elif event.is_action_released(&"ui_accept"):
		_end_input(UI_ACCEPT_TOUCH_ID, SOURCE_UI_ACCEPT)
		accept_event()


func _start_input(touch_id: int, source: StringName) -> void:
	if not lifecycle_enabled or disabled or not is_visible_in_tree():
		return
	if _active_inputs.has(touch_id):
		return
	var press_token := _next_press_token
	_next_press_token += 1
	_active_inputs[touch_id] = {
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
	}
	input_started.emit(press_token, touch_id, source)


func _end_input(touch_id: int, source: StringName) -> void:
	if not _active_inputs.has(touch_id):
		return
	var entry: Dictionary = _active_inputs[touch_id]
	if StringName(entry.get("source", &"")) != source:
		return
	_active_inputs.erase(touch_id)
	input_ended.emit(int(entry.get("press_token", 0)), touch_id, source)


func _cancel_input(touch_id: int, source: StringName, reason: StringName) -> void:
	if not _active_inputs.has(touch_id):
		return
	var entry: Dictionary = _active_inputs[touch_id]
	if StringName(entry.get("source", &"")) != source:
		return
	_active_inputs.erase(touch_id)
	input_cancelled.emit(int(entry.get("press_token", 0)), touch_id, source, reason)


func _on_window_focus_exited() -> void:
	cancel_all_inputs(&"window_focus_out")


func _has_point(point: Vector2) -> bool:
	var radius := minf(size.x, size.y) * 0.5
	return point.distance_squared_to(size * 0.5) <= radius * radius


func owns_lifecycle_input(
	press_token: int, touch_id: int, source: StringName
) -> bool:
	if not lifecycle_enabled or disabled or not is_visible_in_tree():
		return false
	var raw_entry: Variant = _active_inputs.get(touch_id)
	if not raw_entry is Dictionary:
		return false
	var entry := raw_entry as Dictionary
	return (
		int(entry.get("press_token", 0)) == press_token
		and StringName(entry.get("source", &"")) == source
	)


func input_lifecycle_snapshot() -> Dictionary:
	return {
		"contract_id": INPUT_LIFECYCLE_CONTRACT_ID,
		"lifecycle_enabled": lifecycle_enabled,
		"disabled": disabled,
		"visible_in_tree": is_visible_in_tree(),
		"active_inputs": _active_inputs.duplicate(true),
		"pointer_events": _pointer_diagnostic_events.duplicate(true),
	}


func _record_pointer_diagnostic(stage: StringName, event: InputEvent) -> void:
	# Debug ring only; no per-frame logging, file writes, or synthetic inputs.
	if not OS.is_debug_build():
		return
	# Reject motion/drag before allocating a dictionary (high-frequency path).
	if not (event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey):
		return
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event is InputEventKey and not event.is_action(&"ui_accept"):
		return
	var entry: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"stage": str(stage),
		"device": event.device,
		"active_count": _active_inputs.size(),
	}
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		entry["kind"] = "touch"
		entry["touch_id"] = touch.index
		entry["pressed"] = touch.pressed
		entry["canceled"] = touch.canceled
		entry["position"] = [touch.position.x, touch.position.y]
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		entry["kind"] = "mouse"
		entry["pressed"] = mouse.pressed
		entry["emulated"] = mouse.device == InputEvent.DEVICE_ID_EMULATION
		entry["position"] = [mouse.position.x, mouse.position.y]
	elif event is InputEventKey and event.is_action(&"ui_accept"):
		entry["kind"] = "ui_accept"
		entry["pressed"] = event.is_pressed()
		entry["echo"] = event.is_echo()
	else:
		return
	_pointer_diagnostic_events.append(entry)
	while _pointer_diagnostic_events.size() > 128:
		_pointer_diagnostic_events.pop_front()
