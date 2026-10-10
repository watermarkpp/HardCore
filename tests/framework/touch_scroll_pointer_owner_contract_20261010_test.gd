extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")

var proof := Proof.new()
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _touch(index: int, position: Vector2, pressed: bool, canceled := false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	return event

func _drag(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	return event

func _run() -> void:
	var host := Control.new()
	host.name = "TouchOwnerContractRoot"
	host.position = Vector2(0, 0)
	host.size = Vector2(520, 360)
	add_child(host)
	var scroll := ScrollContainer.new()
	scroll.name = "OwnerScroll"
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(240, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(220, 900)
	scroll.add_child(content)
	var button := Button.new()
	button.name = "IndependentButton"
	button.position = Vector2(320, 40)
	button.size = Vector2(150, 70)
	button.text = "Independent"
	host.add_child(button)
	var button_presses: Array[int] = [0]
	button.pressed.connect(func() -> void: button_presses[0] += 1)
	var support: Node = TouchScrollSupportScript.attach_tree(host)
	await get_tree().process_frame
	var bar := scroll.get_v_scroll_bar()
	_check(bar != null and bar.max_value > bar.page, "real ScrollContainer has vertical overflow")
	_check(scroll.get_meta("touch_scroll_policy", "") == TouchScrollSupportScript.STABLE_ID, "real ScrollContainer is registered")
	if bar == null or bar.max_value <= bar.page:
		_finish()
		return

	var a_position := scroll.get_global_rect().get_center()
	var a_drag_position := a_position + Vector2(0, -100)
	_push_input(_touch(7, a_position, true))
	_push_input(_drag(7, a_drag_position, Vector2(0, -100)))
	var value_after_a := bar.value
	var owner_before_b: Node = support.get("_active_control")
	_check(int(support.get("_active_touch_index")) == 7, "A owns the scroll stream after drag")
	_check(bool(support.get("_dragging")) and value_after_a > 0.0, "A drag advances the real ScrollContainer")

	# B is an independent button input. Its DOWN must not replace A's owner.
	var b_position := button.get_global_rect().get_center()
	var b_down := _touch(8, b_position, true)
	_push_input(b_down)
	await get_tree().process_frame
	_check(int(support.get("_active_touch_index")) == 7, "B DOWN cannot preempt A scroll owner")
	_check(support.get("_active_control") == owner_before_b, "B DOWN preserves A control identity")
	var b_up := _touch(8, b_position, false)
	_push_input(b_up)
	await get_tree().process_frame
	_check(button_presses[0] == 1, "B independent button still receives its own tap")
	# A remains live after B's complete tap and can continue scrolling.
	_push_input(_drag(7, a_drag_position + Vector2(0, -60), Vector2(0, -60)))
	_check(bar.value > value_after_a, "A continues scrolling after B independent tap")

	var a_up := _touch(7, a_drag_position + Vector2(0, -60), false)
	_push_input(a_up)
	_check(int(support.get("_active_touch_index")) == -1 and not bool(support.get("_dragging")), "A release revokes owner")
	_check(TouchScrollSupportScript.is_drag_active(get_tree()), "A drag release keeps the existing anti-click guard")

	# A hidden owner is revoked before C can be considered.
	_push_input(_touch(11, a_position, true))
	_push_input(_drag(11, a_position + Vector2(0, -80), Vector2(0, -80)))
	scroll.hide()
	_push_input(_touch(12, b_position, true))
	_check(int(support.get("_active_touch_index")) == -1, "hidden scroll owner is revoked before a new pointer")
	_check(support.get("_active_control") == null, "hidden scroll control no longer owns input")
	_push_input(_touch(12, b_position, false))
	scroll.show()

	# CANCEL follows the same owner end boundary and never leaves A active.
	_push_input(_touch(13, a_position, true))
	_push_input(_drag(13, a_position + Vector2(0, -80), Vector2(0, -80)))
	_push_input(_touch(13, a_position + Vector2(0, -80), false, true))
	_check(int(support.get("_active_touch_index")) == -1, "A CANCEL revokes owner")
	_check(not bool(support.get("_dragging")), "A CANCEL clears drag state")

	# A plain single-pointer tap remains a non-drag candidate and is released.
	_push_input(_touch(14, a_position, true))
	_push_input(_touch(14, a_position, false))
	_check(int(support.get("_active_touch_index")) == -1, "single-pointer tap releases without drag ownership")

	host.queue_free()
	await get_tree().process_frame
	_finish()

func _push_input(event: InputEvent) -> void:
	# The fixture positions are viewport-local. Passing true keeps the same
	# coordinate contract used by the existing multitouch tests.
	get_viewport().push_input(event, true)

func _finish() -> void:
	var ok := proof.write_receipt("touch_scroll_pointer_owner_contract_20261010_test", proof.records.size(), failures.size())
	print("TOUCH_SCROLL_POINTER_OWNER_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
