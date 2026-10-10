extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const ScrollSupport := preload("res://scripts/touch_scroll_support.gd")
var proof := Proof.new()
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok:
		failures.append(label)

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at + Vector2(0, -40)
	event.relative = Vector2(0, -40)
	get_viewport().push_input(event, true)

func _run() -> void:
	var host := Control.new()
	host.process_mode = Node.PROCESS_MODE_PAUSABLE
	host.size = Vector2(500, 350)
	add_child(host)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(220, 160)
	host.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(200, 900)
	scroll.add_child(content)
	var button := Button.new()
	button.position = Vector2(320, 40)
	button.size = Vector2(100, 60)
	host.add_child(button)
	var clicks: Array[int] = [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)
	var support: Node = ScrollSupport.attach_tree(host)
	await get_tree().process_frame
	var point := scroll.get_global_rect().get_center()
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "real scroll overflow")
	_touch(7, point, true)
	_drag(7, point)
	_check(support.get("_dragging") and support.get("_active_touch_index") == 7, "A owns real drag before pause")
	_touch(8, button.get_global_rect().get_center(), false)
	_check(support.get("_active_touch_index") == 7, "unrelated UP does not cancel A")
	# Use the actual SceneTree pause notification; intentionally no A UP.
	get_tree().paused = true
	await get_tree().process_frame
	_check(support.get("_active_touch_index") == -1 and not support.get("_dragging"), "tree pause retires owner without UP")
	_check(not ScrollSupport.is_drag_active(get_tree()), "pause clears selection suppression")
	get_tree().paused = false
	await get_tree().process_frame
	var button_point := button.get_global_rect().get_center()
	_touch(9, button_point, true)
	_touch(9, button_point, false)
	await get_tree().process_frame
	_check(clicks[0] == 1, "first different-index tap works after resume")
	_touch(7, point, true)
	_drag(7, point)
	_check(support.get("_active_touch_index") == 7, "same index can start fresh drag after resume")
	support.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(support.get("_active_touch_index") == -1 and not ScrollSupport.is_drag_active(get_tree()), "app focus interruption retires only scroll owner")
	_touch(11, point, true)
	_drag(11, point)
	support.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(support.get("_active_touch_index") == -1, "app pause retires fresh owner")
	_touch(12, point, true)
	_drag(12, point)
	_touch(12, point, false)
	_check(ScrollSupport.is_drag_active(get_tree()), "ordinary matching release retains160ms anti-click guard")
	_check(support.get("_active_touch_index") == -1, "normal matching UP retires owner")
	host.queue_free()
	await get_tree().process_frame
	var ok := proof.write_receipt("touch_scroll_pause_boundary_20261010_test", proof.records.size(), failures.size())
	print("TOUCH_SCROLL_PAUSE_BOUNDARY_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
