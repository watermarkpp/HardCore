extends Node
const Guard := preload("res://scripts/ui_activation_once.gd")
var failures: Array[String] = []
var count := 0
var button: Button
func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func touch(index: int, pressed: bool, point: Vector2, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	# push_input expects WINDOW coordinates; the engine converts them with the
	# final transform's inverse. Headless windows report a 0x0 client size, so
	# the transform is a heavy downscale and raw canvas points miss the button.
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	get_viewport().push_input(event)
func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_final_transform() * point
	get_viewport().push_input(event)
func selected() -> void:
	count += 1
	button.set_meta("ui_selection_authoritative_pressed", count % 2 == 1)
	button.set_pressed_no_signal(count % 2 == 1)
func _run() -> void:
	button = Button.new()
	button.position = Vector2(100, 100)
	button.size = Vector2(100, 80)
	button.toggle_mode = true
	add_child(button)
	var guard := Guard.attach(button, selected)
	await get_tree().process_frame
	var point := button.get_global_transform_with_canvas() * Vector2(40, 40)
	touch(0, true, point)
	touch(0, false, point)
	expect(count == 1, "real viewport touch route activates once")
	button.pressed.emit() # a duplicate callback from the SAME completed gesture
	expect(count == 1 and button.button_pressed, "duplicate callback is idempotent")
	for i in range(2):
		touch(0, true, point)
		touch(0, false, point)
	expect(count == 3, "two immediate real taps are not debounce-filtered")
	touch(0, true, point)
	touch(1, true, point)
	touch(1, false, point)
	expect(count == 3, "second finger UP cannot commit first owner")
	touch(0, false, point)
	expect(count == 4, "first owner may commit once")
	touch(0, true, point)
	drag(0, point + Vector2(0, 30))
	touch(0, false, point + Vector2(0, 30))
	expect(count == 4, "drag inside button is not a tap")
	touch(0, true, point)
	touch(0, false, point, true)
	expect(count == 4, "native canceled touch never activates")
	touch(0, true, point)
	Guard.suppress_for(button) # the genuine double-tap path already used the item
	await get_tree().process_frame
	await get_tree().process_frame
	touch(0, false, point)
	expect(count == 4, "double activation suppression survives deferred frames")
	touch(0, true, point)
	guard.cancel()
	touch(0, false, point)
	expect(count == 4, "focus/lifecycle cancellation rejects late UP")
	touch(0, true, point)
	touch(0, false, point)
	expect(count == 5, "new gesture works after cancellation")
	# Native DOWN may be duplicated; there must still be only one release action.
	touch(0, true, point)
	touch(0, true, point)
	expect(count == 5, "duplicate DOWN never dispatches or accumulates debt")
	touch(0, false, point)
	expect(count == 6, "duplicate DOWNs then one UP commit once")
	# Simulate an observer candidate left by a globally consumed old release.
	# The next real same-owner gesture must replace it, without a timeout.
	guard._begin("touch", 0, Vector2(40, 40))
	touch(0, true, point)
	touch(0, false, point)
	expect(count == 7, "new DOWN replaces stale same-owner candidate")
	button.queue_free()
	await get_tree().process_frame
	for message: String in failures:
		push_error("R6_ACTIVATION " + message)
	print("R6_1_ACTIVATION_ROUTE_%s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
