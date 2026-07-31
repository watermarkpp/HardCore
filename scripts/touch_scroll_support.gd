class_name TouchScrollSupport
extends Node

const STABLE_ID := "ui.touch_content_scroll.v1"
const DRAG_THRESHOLD := 8.0

var _registered_controls: Array[WeakRef] = []
var _active_control: Control
var _active_touch_index := -1
var _press_position := Vector2.ZERO
var _dragging := false


static func attach_tree(root: Node) -> Node:
	if root == null or root.get_tree() == null:
		return null
	var scene_root := root.get_tree().root
	var support := scene_root.get_node_or_null("TouchScrollSupport")
	if support == null and scene_root.has_meta("_touch_scroll_support_pending"):
		support = scene_root.get_meta("_touch_scroll_support_pending") as Node
	if support == null:
		var support_script := load("res://scripts/touch_scroll_support.gd") as GDScript
		support = support_script.new()
		support.name = "TouchScrollSupport"
		support.set_meta("stable_id", STABLE_ID)
		# HUD and character-select can request this singleton while SceneTree root
		# is still attaching their scene. Register controls immediately, but
		# defer only the singleton's parent insertion so it never fails with
		# "parent node is busy setting up children".
		scene_root.set_meta("_touch_scroll_support_pending", support)
		scene_root.add_child.call_deferred(support)
	support.register_tree(root)
	return support


func register_tree(root: Node) -> void:
	if root is ScrollContainer:
		register_control(root)
	elif root is RichTextLabel and (root as RichTextLabel).scroll_active:
		register_control(root)
	for child: Node in root.get_children():
		register_tree(child)


func register_control(control: Control) -> void:
	if control == null or bool(control.get_meta("touch_content_scroll_registered", false)):
		return
	control.set_meta("touch_content_scroll_registered", true)
	control.set_meta("touch_scroll_policy", STABLE_ID)
	var scroll_bar := _vertical_scroll_bar(control)
	if scroll_bar != null:
		scroll_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll_bar.focus_mode = Control.FOCUS_NONE
		scroll_bar.set_meta("position_indicator_only", true)
	_registered_controls.append(weakref(control))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag_candidate(event.position, event.index)
		elif event.index == _active_touch_index:
			_end_drag()
	elif event is InputEventScreenDrag and event.index == _active_touch_index:
		_continue_drag(event.position, event.relative)


func _begin_drag_candidate(position: Vector2, touch_index: int) -> void:
	_active_control = _control_at(position)
	_active_touch_index = touch_index if _active_control != null else -1
	_press_position = position
	_dragging = false


func _continue_drag(position: Vector2, relative: Vector2) -> void:
	if _active_control == null:
		return
	if not _dragging and position.distance_to(_press_position) < DRAG_THRESHOLD:
		return
	_dragging = true
	var scroll_bar := _vertical_scroll_bar(_active_control)
	if scroll_bar == null or scroll_bar.max_value <= scroll_bar.page:
		return
	scroll_bar.value = clampf(
		scroll_bar.value - relative.y,
		scroll_bar.min_value,
		maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	)
	get_viewport().set_input_as_handled()


func _end_drag() -> void:
	_active_control = null
	_active_touch_index = -1
	_dragging = false


func _control_at(position: Vector2) -> Control:
	for index in range(_registered_controls.size() - 1, -1, -1):
		var control := _registered_controls[index].get_ref() as Control
		if control == null:
			_registered_controls.remove_at(index)
			continue
		if control.is_visible_in_tree() and control.get_global_rect().has_point(position):
			var scroll_bar := _vertical_scroll_bar(control)
			if scroll_bar != null and scroll_bar.max_value > scroll_bar.page:
				return control
	return null


func _vertical_scroll_bar(control: Control) -> VScrollBar:
	if control is ScrollContainer:
		return (control as ScrollContainer).get_v_scroll_bar()
	if control is RichTextLabel:
		return (control as RichTextLabel).get_v_scroll_bar()
	return null
