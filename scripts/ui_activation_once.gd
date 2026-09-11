class_name UIActivationOnce
extends Node

## A scoped guard for item-selection buttons. NOT a global input interceptor.
## One native DOWN/UP sequence -> at most one semantic pressed callback.
## No time debounce: two quick real taps remain two taps. Native Button keeps
## keyboard/focus/touch semantics. gui_input is observed before native pressed.
const DRAG_LIMIT := 12.0
var button: BaseButton
var action: Callable
var _serial := 0
var _consumed := -1
var _release_serial := -1
var _active := false
var _kind := ""
var _pointer := -1
var _origin := Vector2.ZERO
var _cancelled := false
var _last_authoritative_pressed := false
var _suppress_serial := -1
var accepted_count := 0
var duplicate_count := 0

static func attach(target: BaseButton, callback: Callable) -> UIActivationOnce:
	var old := target.get_node_or_null("HCActivationOnce") as UIActivationOnce
	if old != null:
		assert(old.action == callback, "HC_UI6: different action attached twice")
		return old
	var guard := UIActivationOnce.new()
	guard.name = "HCActivationOnce"
	guard.button = target
	guard.action = callback
	# The original direct connection must be removed by the guarded installer.
	assert(not target.pressed.is_connected(callback), "HC_UI6: bypass pressed connection remains")
	target.add_child(guard)
	target.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	target.gui_input.connect(guard._observe)
	target.pressed.connect(guard._commit)
	target.visibility_changed.connect(guard._visibility_changed)
	target.focus_exited.connect(guard.cancel)
	guard.set_process(false)
	guard.set_physics_process(false)
	return guard

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		cancel()

func cancel() -> void:
	_active = false
	_release_serial = -1
	_cancelled = true
	_kind = ""
	_pointer = -1

func _visibility_changed() -> void:
	if not is_instance_valid(button) or not button.is_visible_in_tree():
		cancel()

func _begin(kind: String, pointer: int, point: Vector2) -> void:
	# At most one candidate exists. A new DOWN from the SAME owner replaces
	# its unfinished candidate (including a UP consumed by content scrolling).
	# DOWN never dispatches an action, so duplicate DOWNs cannot add click debt.
	# A different contact cannot steal the active owner's release permission.
	if _active and (kind != _kind or pointer != _pointer):
		return
	_last_authoritative_pressed = button.button_pressed
	_serial += 1
	_active = true
	_kind = kind
	_pointer = pointer
	_origin = point
	_cancelled = false
	_release_serial = -1

func _end(kind: String, pointer: int, point: Vector2, cancelled: bool = false) -> void:
	if not _active or kind != _kind or pointer != _pointer:
		return
	_active = false
	var inside := Rect2(Vector2.ZERO, button.size).has_point(point)
	if _origin.distance_to(point) > DRAG_LIMIT:
		_cancelled = true
	_release_serial = _serial if inside and not _cancelled and not cancelled else -1

func _observe(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin("touch", touch.index, touch.position)
		else:
			_end("touch", touch.index, touch.position, touch.canceled)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _active and _kind == "touch" and drag.index == _pointer:
			if _origin.distance_to(drag.position) > DRAG_LIMIT:
				_cancelled = true
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_begin("mouse", mouse.device, mouse.position)
		else:
			_end("mouse", mouse.device, mouse.position, mouse.canceled)
	elif event is InputEventMouseMotion:
		if _active and _kind == "mouse" and _origin.distance_to(event.position) > DRAG_LIMIT:
			_cancelled = true
	elif event.is_action("ui_accept") and not event.is_echo():
		if event.is_pressed():
			_begin("key", event.device, button.size * 0.5)
		elif _active and _kind == "key":
			_end("key", event.device, button.size * 0.5)

func suppress_current_gesture() -> void:
	# The bag's genuine double-tap path already selected/used the item on DOWN.
	# Suppression follows the gesture serial, not a deferred one-frame flag.
	if _active:
		_suppress_serial = _serial

static func suppress_for(target: BaseButton) -> void:
	var guard := target.get_node_or_null("HCActivationOnce") as UIActivationOnce
	if guard != null:
		guard.suppress_current_gesture()

func _restore_selection_visual() -> void:
	if button.toggle_mode:
		button.set_pressed_no_signal(bool(button.get_meta("ui_selection_authoritative_pressed", _last_authoritative_pressed)))

func _commit() -> void:
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		return
	if _release_serial < 0 or _release_serial == _consumed or _release_serial == _suppress_serial:
		duplicate_count += 1
		# A redundant native pressed must not leave toggle visuals flipped.
		_restore_selection_visual()
		return
	_consumed = _release_serial # reserve before callbacks that can rebuild UI
	accepted_count += 1
	if action.is_valid():
		action.call()
	if is_instance_valid(button):
		_last_authoritative_pressed = button.button_pressed
