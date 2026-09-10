class_name UISelectionDismissGuard
extends Node

## A passive tap observer. It NEVER accepts/consumes/injects input and NEVER
## edits combat, joystick, touch-scroll, transaction or inventory authority.
const ScrollSupport := preload("res://scripts/touch_scroll_support.gd")
const NAME := "UISelectionDismissGuard"
const MAX_TAP_MSEC := 450
const MOVE_LIMIT := 8.0
const MODAL_SCRIPTS := [
	"system_menu_panel.gd", "loading_transition_overlay.gd",
	"gothic_confirmation_panel.gd", "death_revival_panel.gd",
	"skill_panel.gd", "map_panel.gd", "quest_panel.gd",
]
const CUSTOM_INPUT_SCRIPTS := ["virtual_joystick.gd", "circular_touch_button.gd"]
var _scopes: Array[WeakRef] = []
var _functional: Array[WeakRef] = []
var _modals: Array[WeakRef] = []
var _pointers: Dictionary = {}
var _generation := 0

static func attach(scope: Control) -> void:
	if scope == null or scope.get_tree() == null:
		return
	var root := scope.get_tree().root
	var observer := root.get_node_or_null(NAME)
	if observer == null and root.has_meta(NAME):
		observer = root.get_meta(NAME) as Node
	if observer == null:
		observer = load("res://scripts/ui_selection_dismiss_guard.gd").new()
		observer.name = NAME
		root.set_meta(NAME, observer)
		root.add_child.call_deferred(observer)
	observer.register_scope(scope)

func register_scope(scope: Control) -> void:
	for reference: WeakRef in _scopes:
		if reference.get_ref() == scope:
			return
	_scopes.append(weakref(scope))

func _ready() -> void:
	# Pausable on purpose: the game menu must own its own sliders/buttons.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_scan_existing(get_tree().root)
	get_tree().node_added.connect(_register_node)
	_move_observer_last.call_deferred()

func _scan_existing(node: Node) -> void:
	_register_node(node)
	for child: Node in node.get_children():
		_scan_existing(child)

func _script_name(node: Node) -> String:
	var script := node.get_script() as Script
	return script.resource_path.get_file() if script != null else ""

func _register_node(node: Node) -> void:
	if node is Window and node != get_tree().root:
		_modals.append(weakref(node))
		return
	if not node is Control:
		return
	var path := _script_name(node)
	if path in MODAL_SCRIPTS:
		_modals.append(weakref(node))
	if node is BaseButton or node is Range or node is LineEdit or node is TextEdit or node is ItemList or node is Tree or node is TabBar or path in CUSTOM_INPUT_SCRIPTS or bool(node.get_meta("ui_dismiss_protected", false)):
		_functional.append(weakref(node))

func _top_scope() -> Control:
	var result: Control = null
	var best_layer := -2147483648
	var best_z := -2147483648
	for reference: WeakRef in _scopes:
		var scope := reference.get_ref() as Control
		if scope == null or not scope.is_visible_in_tree() or not scope.can_process():
			continue
		var layer_node := scope.get_canvas_layer_node()
		var layer := layer_node.layer if layer_node != null else 0
		if result == null or layer > best_layer or (layer == best_layer and scope.z_index >= best_z):
			result = scope
			best_layer = layer
			best_z = scope.z_index
	return result

func _blocked_by_modal() -> bool:
	for index in range(_modals.size() - 1, -1, -1):
		var node := _modals[index].get_ref() as Node
		if node == null:
			_modals.remove_at(index)
		elif node is Window and (node as Window).visible:
			return true
		elif node is Control and (node as Control).is_visible_in_tree() and (node as Control).modulate.a > 0.0:
			return true
	return false

static func control_hit(control: Control, viewport_point: Vector2) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	var transform := control.get_global_transform_with_canvas()
	if absf(transform.determinant()) < 0.000001:
		return false
	if not Rect2(Vector2.ZERO, control.size).has_point(transform.affine_inverse() * viewport_point):
		return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			var clip := ancestor as Control
			if not Rect2(Vector2.ZERO, clip.size).has_point(clip.get_global_transform_with_canvas().affine_inverse() * viewport_point):
				return false
		ancestor = ancestor.get_parent()
	return true

func _protected_at(scope: Control, point: Vector2) -> bool:
	var inside_scope := control_hit(scope, point)
	for index in range(_functional.size() - 1, -1, -1):
		var control := _functional[index].get_ref() as Control
		if control == null:
			_functional.remove_at(index)
			continue
		# A modal STOP panel obscures gameplay controls underneath it. Outside
		# the panel, preserve those controls (including custom touch buttons).
		if inside_scope and not scope.is_ancestor_of(control):
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE and not _script_name(control) in CUSTOM_INPUT_SCRIPTS:
			continue
		if control_hit(control, point):
			return true
	return false

func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin(touch.index, touch.position)
		else:
			_end(touch.index, touch.position, touch.canceled)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move(drag.index, drag.position)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_begin(-1, mouse.position)
		else:
			_end(-1, mouse.position, false)
	elif event is InputEventMouseMotion:
		_move(-1, (event as InputEventMouseMotion).position)

func _begin(pointer: int, point: Vector2) -> void:
	var now := Time.get_ticks_msec()
	# Keep other held contacts even after a long hold: a second finger must
	# not become a blank tap just because the first finger exceeded 450 ms.
	# Reuse of the SAME pointer id replaces only this observer's old candidate.
	_pointers.erase(pointer)
	_generation += 1
	var multi := not _pointers.is_empty()
	for key: Variant in _pointers.keys():
		_pointers[key]["cancelled"] = true
	var scope := _top_scope()
	if scope == null:
		return
	_pointers[pointer] = {
		"scope": weakref(scope), "origin": point, "time": now,
		"generation": _generation,
		"token": scope.call("_ui_selection_token"),
		"cancelled": multi or _blocked_by_modal() or _protected_at(scope, point) or ScrollSupport.is_drag_active(get_tree()),
	}

func _move(pointer: int, point: Vector2) -> void:
	if _pointers.has(pointer) and point.distance_to(_pointers[pointer]["origin"]) > MOVE_LIMIT:
		_pointers[pointer]["cancelled"] = true

func _end(pointer: int, point: Vector2, cancelled: bool) -> void:
	if not _pointers.has(pointer):
		return
	_move(pointer, point)
	var candidate: Dictionary = _pointers[pointer].duplicate()
	_pointers.erase(pointer)
	if cancelled or bool(candidate["cancelled"]):
		return
	_commit.call_deferred(candidate, point)

func _commit(candidate: Dictionary, point: Vector2) -> void:
	var scope := (candidate["scope"] as WeakRef).get_ref() as Control
	if scope == null or scope != _top_scope() or _blocked_by_modal():
		return
	if int(candidate["generation"]) != _generation or Time.get_ticks_msec() - int(candidate["time"]) > MAX_TAP_MSEC:
		return
	if ScrollSupport.is_drag_active(get_tree()) or _protected_at(scope, point):
		return
	if candidate["token"] != scope.call("_ui_selection_token"):
		return
	scope.call("_ui_dismiss_selection")

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_PAUSED]:
		_generation += 1
		_pointers.clear()

func _move_observer_last() -> void:
	# SceneTree delivers _input in reverse tree order. Observe before content
	# drag helpers consume their release, without consuming anything ourselves.
	if is_inside_tree() and get_parent() == get_tree().root:
		get_parent().move_child(self, get_parent().get_child_count() - 1)

func _exit_tree() -> void:
	if get_tree() != null and get_tree().root.has_meta(NAME) and get_tree().root.get_meta(NAME) == self:
		get_tree().root.remove_meta(NAME)
