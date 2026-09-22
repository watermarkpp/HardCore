extends Node

## Real SceneTree input-routing regression for UISelectionDismissGuard (Fix C
## verification). Unlike ui_r5_core_test, which drives the guard's private
## gesture helpers directly, every stimulus here is a routed engine event via
## Input.parse_input_event through the formal UISelectionDismissGuard.attach
## entry, so the observed SceneTree dispatch order is part of the contract.
##
## Covered boundary: the guard is a persistent root singleton. A world
## re-entry must keep the observer as the LAST root child (reverse-DFS _input
## order observes first), including when a later root child consumes touch
## release events; stale scopes must be pruned; real drags, multi-finger and
## modal windows must not regress.

const Guard := preload("res://scripts/ui_selection_dismiss_guard.gd")
const ScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")

var failures: Array[String] = []
var checks := 0


class TestScope:
	extends Panel
	var dismiss_count := 0
	var revision := 0
	func _ui_selection_token() -> Array:
		return [revision]
	func _ui_dismiss_selection() -> void:
		dismiss_count += 1
		revision += 1


class UpReleaseConsumer:
	extends Node
	var consumed_up := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			consumed_up += 1
			get_viewport().set_input_as_handled()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _ready() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


## Input.parse_input_event expects WINDOW coordinates (what a real device
## reports); the engine maps them into the viewport through the final
## transform. Stimulus points are authored in canvas coordinates, so bridge
## them exactly the way the engine will invert them.
func _to_window(point: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * point


func _touch(index: int, pressed: bool, point: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = _to_window(point)
	return event


func _routed_tap(point: Vector2, index: int) -> void:
	Input.parse_input_event(_touch(index, true, point))
	await _frames(2)
	Input.parse_input_event(_touch(index, false, point))
	await _frames(3)


func _routed_drag(start: Vector2, delta: Vector2, steps: int, index: int) -> void:
	Input.parse_input_event(_touch(index, true, start))
	await _frames(2)
	for step in range(steps):
		var drag := InputEventScreenDrag.new()
		drag.index = index
		drag.position = _to_window(start + delta * (float(step + 1) / float(steps)))
		drag.relative = (
			_to_window(start + delta * (float(step + 1) / float(steps)))
			- _to_window(start + delta * (float(step) / float(steps)))
		)
		Input.parse_input_event(drag)
		await _frames(1)
	Input.parse_input_event(_touch(index, false, start + delta))
	await _frames(3)


func _observer() -> Node:
	return get_tree().root.get_node_or_null("UISelectionDismissGuard")


func _make_scope(at: Vector2, extent: Vector2) -> TestScope:
	var scope := TestScope.new()
	scope.position = at
	scope.size = extent
	add_child(scope)
	return scope


func _run() -> void:
	await _scenario_world_reentry_order_with_late_up_consumer()
	await _scenario_real_scroll_support_routing()
	await _scenario_routed_two_finger()
	await _scenario_modal_window_routing()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("UI_R5_GUARD_INPUT_ORDER: " + failure)
	print(
		"UI_R5_GUARD_INPUT_ORDER_%s checks=%d failures=%d"
		% ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


## World A registers the observer and dies; world B re-attaches through the
## formal entry; a later root child consumes touch release. The observer must
## re-order itself to stay ahead of that consumer (reverse-DFS) so a blank tap
## still dismisses exactly once and no release candidate lingers.
func _scenario_world_reentry_order_with_late_up_consumer() -> void:
	var scope_a := _make_scope(Vector2(80, 80), Vector2(300, 240))
	Guard.attach(scope_a)
	await _frames(3)
	var observer := _observer()
	expect(observer != null, "正式 attach 必须创建 root 级观察器")
	scope_a.queue_free()
	await _frames(2)

	var scope_b := _make_scope(Vector2(80, 80), Vector2(300, 240))
	Guard.attach(scope_b)
	await _frames(3)
	expect(_observer() == observer, "世界重入必须复用同一观察器实例")

	var consumer := UpReleaseConsumer.new()
	get_tree().root.add_child(consumer)
	await _frames(3)
	expect(
		observer.get_index() > consumer.get_index(),
		"后插入的 root 消费者之后，观察器必须重新排到最后（逆序派发最先观察）",
	)

	var tap_point: Vector2 = scope_b.get_global_transform_with_canvas() * Vector2(150, 120)
	await _routed_tap(tap_point, 5)
	expect(consumer.consumed_up >= 1, "受控消费者必须真实收到并消费 UP（刺激有效性）")
	expect(scope_b.dismiss_count == 1, "重登后一次空白点击必须恰好取消一次（UP 被消费也不能吞掉观察）")
	expect(observer._pointers.is_empty(), "松手候选不得残留")

	get_tree().root.remove_child(consumer)
	consumer.free()
	scope_b.queue_free()
	await _frames(2)


## Real TouchScrollSupport singleton + real ScrollContainer, routed drag: the
## content must scroll, the release must stay a scroll (no dismiss, no
## selection change, no lingering candidate) and the release guard must arm.
func _scenario_real_scroll_support_routing() -> void:
	var scroll_scope := _make_scope(Vector2(400, 40), Vector2(320, 400))
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_scope.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(300, 900)
	scroll.add_child(content)
	ScrollSupportScript.attach_tree(scroll_scope)
	Guard.attach(scroll_scope)
	await _frames(3)
	var bar := scroll.get_v_scroll_bar()
	expect(bar.max_value > bar.page, "夹具滚动内容必须可滚动")
	expect(
		scroll.get_meta("touch_scroll_policy", "") == ScrollSupportScript.STABLE_ID,
		"真实滚动辅助器必须注册夹具滚动容器",
	)

	var start: Vector2 = scroll.get_global_transform_with_canvas() * Vector2(160, 200)
	await _routed_drag(start, Vector2(0, -120), 6, 11)
	expect(bar.value > 50.0, "真实路由拖动必须推进滚动位置")
	expect(scroll_scope.dismiss_count == 0, "真实拖动释放不得误取消选择")
	expect(scroll_scope.revision == 0, "真实拖动不得误改选择")
	expect(_observer()._pointers.is_empty(), "拖动结束后观察器不得残留候选")
	expect(ScrollSupportScript.is_drag_active(get_tree()), "真实拖动释放保护必须立即生效")

	# The 160ms release guard must suppress immediate re-dismissal candidates,
	# then expire so normal blank taps work again.
	await get_tree().create_timer(0.3).timeout
	var before := scroll_scope.dismiss_count
	await _routed_tap(scroll_scope.get_global_transform_with_canvas() * Vector2(60, 60), 12)
	expect(scroll_scope.dismiss_count == before + 1, "释放保护窗口后的空白点击必须恰好取消一次")
	expect(_observer()._pointers.is_empty(), "普通点击结束后候选不得残留")
	scroll_scope.queue_free()
	await _frames(2)


## Routed two-finger sequence over a fresh guarded scope: releasing one finger
## must not end or dismiss for the other, and neither release may clear.
func _scenario_routed_two_finger() -> void:
	var scope := _make_scope(Vector2(80, 80), Vector2(300, 240))
	Guard.attach(scope)
	await _frames(3)
	var pivot: Vector2 = scope.get_global_transform_with_canvas() * Vector2(150, 120)
	Input.parse_input_event(_touch(1, true, pivot))
	await _frames(2)
	Input.parse_input_event(_touch(2, true, pivot + Vector2(24, 0)))
	await _frames(2)
	Input.parse_input_event(_touch(1, false, pivot))
	await _frames(3)
	expect(scope.dismiss_count == 0, "双指场景下释放另一根手指不得产生取消")
	Input.parse_input_event(_touch(2, false, pivot + Vector2(24, 0)))
	await _frames(3)
	expect(scope.dismiss_count == 0, "双指序列不得产生空白取消")
	expect(_observer()._pointers.is_empty(), "双指全部释放后不得残留候选")
	scope.queue_free()
	await _frames(2)


## Real Window modal classification over routed taps: visible popup blocks the
## dismiss; closing the popup restores it.
func _scenario_modal_window_routing() -> void:
	var scope := _make_scope(Vector2(80, 80), Vector2(300, 240))
	Guard.attach(scope)
	await _frames(3)
	var tap_point: Vector2 = scope.get_global_transform_with_canvas() * Vector2(150, 120)

	var popup := Window.new()
	popup.size = Vector2(200, 160)
	popup.visible = true
	get_tree().root.add_child(popup)
	await _frames(3)
	await _routed_tap(tap_point, 7)
	expect(scope.dismiss_count == 0, "可见弹窗期间空白点击不得取消")
	popup.visible = false
	await _frames(2)
	popup.queue_free()
	await _frames(2)

	await _routed_tap(tap_point, 8)
	expect(scope.dismiss_count == 1, "弹窗关闭后空白点击恢复正常取消一次")
	expect(_observer()._pointers.is_empty(), "弹窗用例结束后候选不得残留")
	scope.queue_free()
	await _frames(2)
