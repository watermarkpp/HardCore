class_name UILayoutCalibrationOverlay
extends Control

const GothicModalLayoutScript := preload("res://scripts/gothic_modal_layout.gd")
const OUTPUT_PATH := "res://outputs/ui_calibration/manual_layout_overrides.json"

var target: Control
var profile_id := ""
var selectable_nodes: Array[Control] = []
var selected: Control
var node_picker: OptionButton
var x_field: SpinBox
var y_field: SpinBox
var width_field: SpinBox
var height_field: SpinBox
var font_size_field: SpinBox
var text_caption: Label
var text_editor: TextEdit
var relation_label: Label
var status_label: Label
var inspector_panel: PanelContainer
var inspector_column: VBoxContainer
var viewport_display: Control
var device_coordinate_size := Vector2(2664, 1200)
var mouse_exclusions: Array[Control] = []
var _updating_fields := false
var _last_click_position := Vector2(-10000, -10000)
var _last_click_paths: Array[String] = []
var _click_cycle_index := 0
var _undo_history: Array[Dictionary] = []
var _text_edit_session_active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_inspector()
	set_process_input(true)
	set_process_unhandled_key_input(false)


func edit_panel(panel: Control, panel_profile_id: String) -> void:
	target = panel
	profile_id = panel_profile_id
	_undo_history.clear()
	_refresh_selectable_nodes()
	queue_redraw()
	load_profile.call_deferred()


func add_mouse_exclusion(control: Control) -> void:
	if control != null and not mouse_exclusions.has(control):
		mouse_exclusions.append(control)


func set_viewport_display(control: Control) -> void:
	viewport_display = control
	queue_redraw()


func set_device_coordinate_space(physical_size: Vector2) -> void:
	assert(physical_size.x > 0.0 and physical_size.y > 0.0)
	device_coordinate_size = physical_size
	_sync_fields()
	queue_redraw()


func dock_inspector_to(parent: Node) -> void:
	if parent == null or inspector_panel == null:
		return
	inspector_panel.reparent(parent)
	inspector_panel.position = Vector2(12, 12)


func _build_inspector() -> void:
	inspector_panel = PanelContainer.new()
	inspector_panel.name = "CalibrationInspector"
	inspector_panel.position = Vector2(12, 12)
	inspector_panel.size = Vector2(388, 900)
	inspector_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inspector_panel)

	inspector_column = VBoxContainer.new()
	inspector_column.add_theme_constant_override("separation", 8)
	inspector_panel.add_child(inspector_column)

	var title := Label.new()
	title.text = "UI 数字校准台 · 2664×1200"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	inspector_column.add_child(title)

	var help := Label.new()
	help.text = "直接点击画面选择控件\n方向键移动 1px · Shift 10px · Ctrl+方向键改尺寸 · Ctrl+S 保存"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 12)
	inspector_column.add_child(help)

	node_picker = OptionButton.new()
	node_picker.custom_minimum_size = Vector2(300, 42)
	node_picker.item_selected.connect(_select_index)
	inspector_column.add_child(node_picker)

	x_field = _number_field(inspector_column, "X", _field_changed.bind("x"))
	y_field = _number_field(inspector_column, "Y", _field_changed.bind("y"))
	width_field = _number_field(inspector_column, "宽", _field_changed.bind("width"))
	height_field = _number_field(inspector_column, "高", _field_changed.bind("height"))
	font_size_field = _number_field(inspector_column, "字号", _field_changed.bind("font_size"))
	font_size_field.min_value = 1
	font_size_field.max_value = 240

	text_caption = Label.new()
	text_caption.text = "文字内容"
	text_caption.add_theme_font_size_override("font_size", 13)
	inspector_column.add_child(text_caption)
	text_editor = TextEdit.new()
	text_editor.custom_minimum_size = Vector2(360, 92)
	text_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_editor.placeholder_text = "选中文字层后可直接修改"
	text_editor.focus_entered.connect(_begin_text_edit)
	text_editor.focus_exited.connect(func() -> void: _text_edit_session_active = false)
	text_editor.text_changed.connect(_text_editor_changed)
	inspector_column.add_child(text_editor)

	relation_label = Label.new()
	relation_label.custom_minimum_size = Vector2(360, 86)
	relation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	relation_label.add_theme_font_size_override("font_size", 12)
	inspector_column.add_child(relation_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	inspector_column.add_child(actions)
	var reload_button := Button.new()
	reload_button.text = "载入已保存"
	reload_button.custom_minimum_size = Vector2(142, 46)
	reload_button.pressed.connect(load_profile)
	actions.add_child(reload_button)
	var save_button := Button.new()
	save_button.text = "保存当前界面"
	save_button.custom_minimum_size = Vector2(142, 46)
	save_button.pressed.connect(save_profile)
	actions.add_child(save_button)

	var edit_actions := HBoxContainer.new()
	edit_actions.add_theme_constant_override("separation", 8)
	inspector_column.add_child(edit_actions)
	var delete_button := Button.new()
	delete_button.text = "删除选中层"
	delete_button.custom_minimum_size = Vector2(142, 46)
	delete_button.pressed.connect(delete_selected)
	edit_actions.add_child(delete_button)
	var undo_button := Button.new()
	undo_button.text = "撤销 Ctrl+Z"
	undo_button.custom_minimum_size = Vector2(142, 46)
	undo_button.pressed.connect(undo_last_change)
	edit_actions.add_child(undo_button)

	var center_actions := HBoxContainer.new()
	center_actions.add_theme_constant_override("separation", 8)
	inspector_column.add_child(center_actions)
	var center_horizontal_button := Button.new()
	center_horizontal_button.text = "左右居中"
	center_horizontal_button.custom_minimum_size = Vector2(176, 46)
	center_horizontal_button.pressed.connect(center_selected_horizontal)
	center_actions.add_child(center_horizontal_button)
	var center_vertical_button := Button.new()
	center_vertical_button.text = "上下居中"
	center_vertical_button.custom_minimum_size = Vector2(176, 46)
	center_vertical_button.pressed.connect(center_selected_vertical)
	center_actions.add_child(center_vertical_button)

	var hierarchy_actions := HBoxContainer.new()
	hierarchy_actions.add_theme_constant_override("separation", 8)
	inspector_column.add_child(hierarchy_actions)
	var select_scroll_button := Button.new()
	select_scroll_button.text = "选中滑动区"
	select_scroll_button.custom_minimum_size = Vector2(176, 42)
	select_scroll_button.pressed.connect(select_enclosing_scroll)
	hierarchy_actions.add_child(select_scroll_button)
	var select_parent_button := Button.new()
	select_parent_button.text = "选中父层"
	select_parent_button.custom_minimum_size = Vector2(176, 42)
	select_parent_button.pressed.connect(select_nearest_parent_layer)
	hierarchy_actions.add_child(select_parent_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	inspector_column.add_child(status_label)


func dock_panel_selector(selector: Control) -> void:
	if selector == null or inspector_column == null:
		return
	selector.reparent(inspector_column)
	selector.position = Vector2.ZERO
	selector.custom_minimum_size = Vector2(300, 42)
	inspector_column.move_child(selector, 2)


func _number_field(parent: VBoxContainer, caption: String, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(54, 38)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = -4096
	field.max_value = 8192
	field.step = 1
	field.custom_minimum_size = Vector2(232, 38)
	field.value_changed.connect(callback)
	row.add_child(field)
	return field


func _refresh_selectable_nodes() -> void:
	selectable_nodes.clear()
	node_picker.clear()
	if target == null:
		return
	_collect_controls(target)
	selectable_nodes.sort_custom(func(left: Control, right: Control) -> bool: return str(target.get_path_to(left)) < str(target.get_path_to(right)))
	for control in selectable_nodes:
		node_picker.add_item("%s  [%s]" % [str(target.get_path_to(control)), control.get_class()])
	if not selectable_nodes.is_empty():
		_select_index(0)


func _collect_controls(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			var control := child as Control
			if _is_calibratable(control):
				selectable_nodes.append(control)
		_collect_controls(child)


func _is_calibratable(control: Control) -> bool:
	if control.name == "ModalFrameOverlay" or not control.visible:
		return false
	if bool(control.get_meta("calibration_internal_visual", false)):
		return false
	if control.has_meta("calibration_layer"):
		return true
	var variation := str(control.theme_type_variation)
	return (
		control.get_parent() == target
		or control is Label
		or control is RichTextLabel
		or control is Button
		or control is LineEdit
		or control is TextEdit
		or control is ScrollContainer
		or control is CheckButton
		or control is TextureRect
		or variation.begins_with("GothicComponent")
		or variation in ["GothicInsetFrame", "GothicTabFrame", "GothicContentToggle", "GothicSearchField"]
	)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if _handle_calibration_key(key):
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	if (
		inspector_panel != null
		and inspector_panel.get_viewport() == get_viewport()
		and inspector_panel.get_global_rect().has_point(click.position)
	):
		return
	for excluded in mouse_exclusions:
		if is_instance_valid(excluded) and excluded.visible and excluded.get_global_rect().has_point(click.position):
			return
	var candidates: Array[Control] = []
	for control in selectable_nodes:
		if control.is_visible_in_tree() and _control_overlay_rect(control).has_point(click.position):
			candidates.append(control)
	if candidates.is_empty():
		status_label.text = "此处没有可校准控件"
		return
	candidates.sort_custom(func(left: Control, right: Control) -> bool:
		var left_area := left.size.x * left.size.y
		var right_area := right.size.x * right.size.y
		if not is_equal_approx(left_area, right_area):
			return left_area < right_area
		return _node_depth(left) > _node_depth(right)
	)
	var candidate_paths: Array[String] = []
	for candidate in candidates:
		candidate_paths.append(str(target.get_path_to(candidate)))
	var structural_index := _preferred_scroll_candidate(candidates, click.position, click.ctrl_pressed)
	if structural_index >= 0:
		_click_cycle_index = structural_index
	elif click.double_click:
		_click_cycle_index = 0
		for candidate_index in range(candidates.size()):
			if _supports_text(candidates[candidate_index]):
				_click_cycle_index = candidate_index
				break
	elif click.position.distance_to(_last_click_position) <= 4.0 and candidate_paths == _last_click_paths:
		_click_cycle_index = (_click_cycle_index + 1) % candidates.size()
	else:
		_click_cycle_index = 0
	_last_click_position = click.position
	_last_click_paths = candidate_paths
	selected = candidates[_click_cycle_index]
	get_viewport().gui_release_focus()
	var picker_index := selectable_nodes.find(selected)
	if picker_index >= 0:
		node_picker.select(picker_index)
	_sync_fields()
	status_label.text = "已选择：%s · 重叠层 %d/%d（同点再点可切换）" % [
		str(target.get_path_to(selected)), _click_cycle_index + 1, candidates.size()
	]
	if click.double_click and _supports_text(selected):
		status_label.text = "正在编辑文字：%s" % str(target.get_path_to(selected))
		_focus_text_editor.call_deferred()
	queue_redraw()
	get_viewport().set_input_as_handled()


func _node_depth(node: Node) -> int:
	var depth := 0
	var cursor := node
	while cursor != null and cursor != target:
		depth += 1
		cursor = cursor.get_parent()
	return depth


func _select_index(index: int) -> void:
	if index < 0 or index >= selectable_nodes.size():
		return
	selected = selectable_nodes[index]
	_sync_fields()
	queue_redraw()


func select_enclosing_scroll() -> void:
	if selected == null:
		return
	var cursor: Node = selected
	while cursor != null and cursor != target:
		if cursor is ScrollContainer and selectable_nodes.has(cursor as Control):
			_select_control(cursor as Control, "已选中整个滑动区")
			return
		cursor = cursor.get_parent()
	status_label.text = "当前层不在可滑动区域内"


func select_nearest_parent_layer() -> void:
	if selected == null:
		return
	var cursor := selected.get_parent()
	while cursor != null and cursor != target:
		if cursor is Control and selectable_nodes.has(cursor as Control):
			_select_control(cursor as Control, "已选中父层")
			return
		cursor = cursor.get_parent()
	status_label.text = "当前层没有更高的可校准父层"


func _select_control(control: Control, message: String) -> void:
	selected = control
	var picker_index := selectable_nodes.find(selected)
	if picker_index >= 0:
		node_picker.select(picker_index)
	_sync_fields()
	status_label.text = "%s：%s" % [message, str(target.get_path_to(selected))]
	queue_redraw()


func _preferred_scroll_candidate(candidates: Array[Control], click_position: Vector2, force_scroll: bool) -> int:
	for index in range(candidates.size()):
		var candidate := candidates[index]
		if not candidate is ScrollContainer:
			continue
		var rect := _control_overlay_rect(candidate)
		var scrollbar_hit := click_position.x >= rect.end.x - 24.0
		if force_scroll or scrollbar_hit:
			return index
	return -1


func _sync_fields() -> void:
	if selected == null:
		return
	var scale := _device_scale(selected)
	var screen_rect := selected.get_global_rect()
	_updating_fields = true
	x_field.value = screen_rect.position.x * scale.x
	y_field.value = screen_rect.position.y * scale.y
	width_field.value = screen_rect.size.x * scale.x
	height_field.value = screen_rect.size.y * scale.y
	if _supports_text(selected):
		text_editor.editable = true
		text_editor.text = _control_text(selected)
		font_size_field.editable = true
		font_size_field.value = float(_control_font_size(selected)) * scale.y
		text_caption.text = "文字内容（实时修改）"
	else:
		text_editor.editable = false
		text_editor.text = ""
		font_size_field.editable = false
		font_size_field.value = 1
		text_caption.text = "文字内容（当前层无文字）"
	_updating_fields = false
	var parent_control := selected.get_parent() as Control
	var parent_size := parent_control.size if parent_control != null else Vector2.ZERO
	var normalized := _normalized_rect(selected.position, selected.size, parent_size)
	var parent_device_size := parent_size * scale
	relation_label.text = "父级: %s\n父级尺寸: %.0f × %.0f 设备像素\n比例: x %.4f · y %.4f · w %.4f · h %.4f" % [
		str(target.get_path_to(selected.get_parent())), parent_device_size.x, parent_device_size.y,
		normalized[0], normalized[1], normalized[2], normalized[3]
	]


func _field_changed(value: float, field_name: String) -> void:
	if _updating_fields or selected == null:
		return
	_push_undo_state()
	var scale := _device_scale(selected)
	var current_screen_rect := selected.get_global_rect()
	match field_name:
		"x": selected.position.x += value / scale.x - current_screen_rect.position.x
		"y": selected.position.y += value / scale.y - current_screen_rect.position.y
		"width": selected.size.x = maxf(value / scale.x, 1.0 / scale.x)
		"height": selected.size.y = maxf(value / scale.y, 1.0 / scale.y)
		"font_size":
			if _supports_text(selected):
				_set_control_font_size(selected, maxi(1, roundi(value / scale.y)))
	_sync_fields()
	queue_redraw()


func _handle_calibration_key(key: InputEventKey) -> bool:
	if not key.pressed or key.echo:
		return false
	if key.ctrl_pressed and key.keycode == KEY_Z:
		undo_last_change()
		return true
	if key.ctrl_pressed and key.keycode == KEY_S:
		save_profile()
		return true
	if key.keycode == KEY_DELETE:
		delete_selected()
		return true
	if selected == null:
		return false
	var delta := Vector2.ZERO
	match key.keycode:
		KEY_LEFT: delta.x = -1
		KEY_RIGHT: delta.x = 1
		KEY_UP: delta.y = -1
		KEY_DOWN: delta.y = 1
		_: return false
	delta *= 10.0 if key.shift_pressed else 1.0
	var scale := _device_scale(selected)
	var logical_delta := delta / scale
	_push_undo_state()
	if key.ctrl_pressed:
		selected.size = Vector2(
			maxf(1.0 / scale.x, selected.size.x + logical_delta.x),
			maxf(1.0 / scale.y, selected.size.y + logical_delta.y),
		)
	else:
		selected.position += logical_delta
	_sync_fields()
	queue_redraw()
	return true


func delete_selected() -> void:
	if selected == null or selected == target:
		return
	_push_undo_state()
	selected.visible = false
	status_label.text = "已标记删除：%s · Ctrl+Z 可恢复" % str(target.get_path_to(selected))
	queue_redraw()


func center_selected_horizontal() -> void:
	_center_selected_axis(true)


func center_selected_vertical() -> void:
	_center_selected_axis(false)


func _center_selected_axis(horizontal: bool) -> void:
	if selected == null:
		return
	var scale := _device_scale(selected)
	var screen_rect := Rect2(Vector2.ZERO, device_coordinate_size)
	var logical_rect := selected.get_global_rect()
	var current_rect := Rect2(logical_rect.position * scale, logical_rect.size * scale)
	_push_undo_state()
	if horizontal:
		selected.position.x += (screen_rect.get_center().x - current_rect.get_center().x) / scale.x
		status_label.text = "已相对 2664×1200 屏幕左右居中：%s" % str(target.get_path_to(selected))
	else:
		selected.position.y += (screen_rect.get_center().y - current_rect.get_center().y) / scale.y
		status_label.text = "已相对 2664×1200 屏幕上下居中：%s" % str(target.get_path_to(selected))
	_sync_fields()
	queue_redraw()


func undo_last_change() -> void:
	if target == null or _undo_history.is_empty():
		status_label.text = "没有可以撤销的操作"
		return
	var state: Dictionary = _undo_history.pop_back()
	var control := target.get_node_or_null(NodePath(str(state.get("path", "")))) as Control
	if control == null:
		status_label.text = "撤销目标已经不存在"
		return
	var rect: Array = state.get("rect", [])
	if rect.size() == 4:
		control.position = Vector2(float(rect[0]), float(rect[1]))
		control.size = Vector2(float(rect[2]), float(rect[3]))
	control.visible = bool(state.get("visible", true))
	if state.has("text") and _supports_text(control):
		_set_control_text(control, str(state["text"]))
	if state.has("fontSize") and _supports_text(control):
		_set_control_font_size(control, int(state["fontSize"]))
	selected = control
	var picker_index := selectable_nodes.find(selected)
	if picker_index >= 0:
		node_picker.select(picker_index)
	_sync_fields()
	status_label.text = "已撤销：%s" % str(target.get_path_to(selected))
	queue_redraw()


func _push_undo_state() -> void:
	if selected == null or target == null:
		return
	var state := {
		"path": str(target.get_path_to(selected)),
		"rect": [selected.position.x, selected.position.y, selected.size.x, selected.size.y],
		"visible": selected.visible,
	}
	if _supports_text(selected):
		state["text"] = _control_text(selected)
		state["fontSize"] = _control_font_size(selected)
	if not _undo_history.is_empty() and _undo_history.back() == state:
		return
	_undo_history.append(state)
	if _undo_history.size() > 200:
		_undo_history.pop_front()


func save_profile() -> void:
	if target == null or profile_id.is_empty():
		return
	var data := _read_output()
	data["schemaVersion"] = 3
	data["coordinateSpace"] = "device_physical_pixels"
	data["deviceProfile"] = {
		"width": 2664,
		"height": 1200,
		"densityDpi": 520,
		"safeInsets": [121, 0, 129, 0],
	}
	var profiles: Dictionary = data.get("profiles", {})
	var nodes := {}
	for control in selectable_nodes:
		var parent_control := control.get_parent() as Control
		var parent_size := parent_control.size if parent_control != null else Vector2.ZERO
		var scale := _device_scale(control)
		var global_rect := control.get_global_rect()
		var entry := {
			"parent": str(target.get_path_to(control.get_parent())),
			"parentSize": [parent_size.x * scale.x, parent_size.y * scale.y],
			"rect": [global_rect.position.x * scale.x, global_rect.position.y * scale.y, global_rect.size.x * scale.x, global_rect.size.y * scale.y],
			"localRect": [control.position.x * scale.x, control.position.y * scale.y, control.size.x * scale.x, control.size.y * scale.y],
			"logicalRect": [control.position.x, control.position.y, control.size.x, control.size.y],
			"normalized": _normalized_rect(control.position, control.size, parent_size),
			"themeVariation": str(control.theme_type_variation),
			"visible": control.visible,
			"deleted": not control.visible,
			"layoutRevision": int(control.get_meta("calibration_layout_revision", 0)),
			"textRevision": int(control.get_meta("calibration_text_revision", 0)),
		}
		if _supports_text(control):
			entry["text"] = _control_text(control)
			entry["fontSize"] = float(_control_font_size(control)) * scale.y
			entry["logicalFontSize"] = _control_font_size(control)
		nodes[str(target.get_path_to(control))] = entry
	profiles[profile_id] = {
		"designSize": [target.size.x * _device_scale(target).x, target.size.y * _device_scale(target).y],
		"logicalDesignSize": [target.size.x, target.size.y],
		"frameSafeInset": [54 * _device_scale(target).x, 94 * _device_scale(target).y, 54 * _device_scale(target).x, 114 * _device_scale(target).y],
		"nodes": nodes,
	}
	data["profiles"] = profiles
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	status_label.text = "已保存：%s · %d 个控件" % [profile_id, nodes.size()]


func load_profile() -> void:
	if target == null or profile_id.is_empty():
		return
	var data := _read_output()
	var profile: Dictionary = data.get("profiles", {}).get(profile_id, {})
	var entries: Dictionary = profile.get("nodes", {})
	if entries.is_empty():
		status_label.text = "当前界面没有已保存数据"
		return
	var resolved := _resolve_saved_controls(entries)
	var ordered: Array[Dictionary] = resolved.get("matched", [])
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _node_depth(left["control"] as Node) < _node_depth(right["control"] as Node)
	)
	var schema_version := int(data.get("schemaVersion", 1))
	# Apply parent geometry before child geometry, let anchors/containers settle,
	# then repeat once so every saved screen-space rect is exact.
	for pass_index in range(2):
		for item: Dictionary in ordered:
			_apply_saved_geometry(item["control"] as Control, item["entry"] as Dictionary, schema_version)
		await get_tree().process_frame
	for item: Dictionary in ordered:
		var control := item["control"] as Control
		var entry := item["entry"] as Dictionary
		if entry.has("text") and _supports_text(control) and _should_restore_saved_text(control, entry):
			_set_control_text(control, str(entry["text"]))
		if entry.has("fontSize") and _supports_text(control):
			var scale := _device_scale(control)
			_set_control_font_size(control, maxi(1, roundi(float(entry["fontSize"]) / scale.y)))
		control.visible = bool(entry.get("visible", true))
	await get_tree().process_frame
	# Text and font restoration can invalidate Button minimum sizes. Reapply the
	# saved geometry after that invalidation so the persisted device-pixel rect
	# remains authoritative.
	for item: Dictionary in ordered:
		_apply_saved_geometry(item["control"] as Control, item["entry"] as Dictionary, schema_version)
	await get_tree().process_frame
	var verification := _verify_loaded_profile(ordered)
	var missing: Array = resolved.get("missing", [])
	_undo_history.clear()
	_refresh_selectable_nodes_after_load(ordered)
	status_label.text = "整页已载入：%s · %d 层 · 隐藏 %d 层 · 缺失 %d · 偏差 %d" % [
		profile_id,
		ordered.size(),
		int(verification.get("hidden", 0)),
		missing.size(),
		int(verification.get("mismatches", 0)),
	]
	if missing.is_empty() and int(verification.get("mismatches", 0)) == 0:
		print("UI_CALIBRATION_PROFILE_LOAD_PASS profile=%s layers=%d hidden=%d" % [
			profile_id, ordered.size(), int(verification.get("hidden", 0))
		])
	else:
		push_warning("UI_CALIBRATION_PROFILE_LOAD_MISMATCH profile=%s missing=%s mismatches=%d details=%s" % [
			profile_id, missing, int(verification.get("mismatches", 0)), verification.get("details", [])
		])
	_sync_fields()
	queue_redraw()


func _apply_saved_geometry(control: Control, entry: Dictionary, schema_version: int) -> void:
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		return
	if schema_version >= 3:
		var scale := _device_scale(control)
		var desired_size := Vector2(float(rect[2]) / scale.x, float(rect[3]) / scale.y)
		_prepare_control_for_saved_size(control, desired_size)
		control.size = desired_size
		var desired_screen_position := Vector2(float(rect[0]) / scale.x, float(rect[1]) / scale.y)
		control.position += desired_screen_position - control.get_global_rect().position
	elif schema_version == 2:
		var scale := _device_scale(control)
		control.position = Vector2(float(rect[0]) / scale.x, float(rect[1]) / scale.y)
		control.size = Vector2(float(rect[2]) / scale.x, float(rect[3]) / scale.y)
	else:
		control.position = Vector2(float(rect[0]), float(rect[1]))
		control.size = Vector2(float(rect[2]), float(rect[3]))


func _prepare_control_for_saved_size(control: Control, desired_size: Vector2) -> void:
	if not control is Button:
		return
	var button := control as Button
	var minimum_size := button.get_combined_minimum_size()
	var relax_horizontal := desired_size.x + 0.01 < minimum_size.x
	var relax_vertical := desired_size.y + 0.01 < minimum_size.y
	if not relax_horizontal and not relax_vertical:
		return
	# The common gothic button texture carries generous content margins. A user
	# can deliberately calibrate a smaller rect, so duplicate only this button's
	# style resources and relax those minimum-size margins without changing the
	# texture, ring artwork, or centered text rendering.
	button.clip_text = true
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var source := button.get_theme_stylebox(state)
		if source == null:
			continue
		var adjusted := source.duplicate() as StyleBox
		if relax_horizontal:
			adjusted.content_margin_left = 0.0
			adjusted.content_margin_right = 0.0
		if relax_vertical:
			adjusted.content_margin_top = 0.0
			adjusted.content_margin_bottom = 0.0
		button.add_theme_stylebox_override(state, adjusted)
	button.update_minimum_size()


func _resolve_saved_controls(entries: Dictionary) -> Dictionary:
	var matched: Array[Dictionary] = []
	var missing: Array[String] = []
	var used: Dictionary = {}
	var legacy_inventory_cells := _legacy_inventory_cell_mapping(entries)
	var legacy_quest_cards := _legacy_quest_card_mapping(entries)
	for path_value: Variant in entries.keys():
		var saved_path := str(path_value)
		var entry: Dictionary = entries[path_value]
		if _is_retired_saved_path(saved_path):
			continue
		# Dynamic collection members must be excluded before text fallback. A
		# legacy map-card label can share text with a world-tree button (for
		# example, "苍月岛") and would otherwise steal that static control.
		if _is_deferred_dynamic_saved_path(saved_path):
			continue
		# Legacy runtime-generated collection paths can accidentally resolve to a
		# different member after a rebuild because Godot may reuse the same
		# @Button@N name for another card. Resolve these paths by deterministic
		# catalog order before attempting an exact path lookup.
		var control := _resolve_legacy_quest_control(saved_path, legacy_quest_cards)
		if control == null:
			control = target.get_node_or_null(NodePath(saved_path)) as Control
		if control == null:
			control = _resolve_legacy_inventory_control(saved_path, legacy_inventory_cells)
		if control == null:
			control = _fallback_saved_control(entry, used)
		if control == null:
			# A hidden/deleted saved layer may be intentionally retired from the
			# runtime hierarchy after the user confirms its removal. It must not
			# remain a permanent load error or force the old placeholder back.
			if (
				bool(entry.get("deleted", false))
				or not bool(entry.get("visible", true))
				or _is_deferred_dynamic_saved_path(saved_path)
			):
				continue
			missing.append(saved_path)
			continue
		if _saved_geometry_revision_stale(control, entry):
			continue
		if _saved_geometry_retired_by_dependencies(control, entries):
			continue
		used[control.get_instance_id()] = true
		matched.append({"saved_path": saved_path, "control": control, "entry": entry})
	return {"matched": matched, "missing": missing}


func _is_deferred_dynamic_saved_path(saved_path: String) -> bool:
	# Map cards and world-tree entries are runtime collections derived from the
	# selected region and the authoritative map catalog. Saved members from one
	# catalog state are not static layers in another state and must never fall
	# back onto unrelated controls that happen to share their text.
	return (
		saved_path.begins_with("MapListPanel/MapListScroll/MapCards/")
		or saved_path.begins_with("MapPreviewPanel/WorldTreeScroll/WorldTree/")
	)


func _is_retired_saved_path(saved_path: String) -> bool:
	if target == null or not target.has_meta("calibration_retired_paths"):
		return false
	var retired_paths: Array = target.get_meta("calibration_retired_paths", [])
	return saved_path in retired_paths


func _saved_geometry_retired_by_dependencies(control: Control, entries: Dictionary) -> bool:
	if not control.has_meta("calibration_layout_dependencies"):
		return false
	var dependencies: Array = control.get_meta("calibration_layout_dependencies", [])
	for dependency_value: Variant in dependencies:
		var dependency_path := str(dependency_value)
		if not entries.has(dependency_path) or not entries[dependency_path] is Dictionary:
			continue
		var dependency: Dictionary = entries[dependency_path]
		if bool(dependency.get("deleted", false)) or not bool(dependency.get("visible", true)):
			return true
	return false


func _saved_geometry_revision_stale(control: Control, entry: Dictionary) -> bool:
	var current_revision := int(control.get_meta("calibration_layout_revision", 0))
	var saved_revision := int(entry.get("layoutRevision", 0))
	return current_revision > saved_revision


func _saved_text_revision_stale(control: Control, entry: Dictionary) -> bool:
	var current_revision := int(control.get_meta("calibration_text_revision", 0))
	var saved_revision := int(entry.get("textRevision", 0))
	return current_revision > saved_revision


func _legacy_inventory_cell_mapping(entries: Dictionary) -> Dictionary:
	# Older saved inventory profiles inherited Godot's generated @Control@N
	# names for grid cells. Those numbers are process-local, but their numeric
	# order is the deterministic grid creation order. Map that order onto the
	# permanent InventoryCell_000..099 names without rewriting the user's file.
	const GRID_PREFIX := "BagPanel/InventoryScroll/ItemGrid/"
	var legacy_ids: Array[int] = []
	for path_value: Variant in entries.keys():
		var saved_path := str(path_value)
		if not saved_path.begins_with(GRID_PREFIX):
			continue
		var remainder := saved_path.trim_prefix(GRID_PREFIX)
		var slash_index := remainder.find("/")
		var legacy_name := remainder if slash_index < 0 else remainder.left(slash_index)
		if not legacy_name.begins_with("@Control@"):
			continue
		var numeric_part := legacy_name.trim_prefix("@Control@")
		if numeric_part.is_valid_int() and not legacy_ids.has(int(numeric_part)):
			legacy_ids.append(int(numeric_part))
	legacy_ids.sort()
	var grid := target.get_node_or_null(NodePath(GRID_PREFIX.trim_suffix("/")))
	var mapping: Dictionary = {}
	if grid == null:
		return mapping
	for index in range(mini(legacy_ids.size(), grid.get_child_count())):
		mapping["@Control@%d" % legacy_ids[index]] = grid.get_child(index)
	return mapping


func _resolve_legacy_inventory_control(saved_path: String, legacy_cells: Dictionary) -> Control:
	const GRID_PREFIX := "BagPanel/InventoryScroll/ItemGrid/"
	if legacy_cells.is_empty() or not saved_path.begins_with(GRID_PREFIX):
		return null
	var remainder := saved_path.trim_prefix(GRID_PREFIX)
	var slash_index := remainder.find("/")
	var legacy_name := remainder if slash_index < 0 else remainder.left(slash_index)
	var cell := legacy_cells.get(legacy_name) as Control
	if cell == null:
		return null
	if slash_index < 0:
		return cell
	return cell.get_node_or_null(NodePath(remainder.substr(slash_index + 1))) as Control


func _legacy_quest_card_mapping(entries: Dictionary) -> Dictionary:
	# Early quest profiles saved runtime-generated @Button@N names. Their
	# numeric order is the deterministic six-task catalog order, so migrate the
	# entire card subtree onto the current quest buttons without rewriting the
	# user's saved profile.
	const QUEST_PREFIX := "QuestListPanel/QuestListScroll/QuestList/"
	var legacy_ids: Array[int] = []
	for path_value: Variant in entries.keys():
		var saved_path := str(path_value)
		if not saved_path.begins_with(QUEST_PREFIX):
			continue
		var remainder := saved_path.trim_prefix(QUEST_PREFIX)
		var slash_index := remainder.find("/")
		var legacy_name := remainder if slash_index < 0 else remainder.left(slash_index)
		if not legacy_name.begins_with("@Button@"):
			continue
		var numeric_part := legacy_name.trim_prefix("@Button@")
		if numeric_part.is_valid_int() and not legacy_ids.has(int(numeric_part)):
			legacy_ids.append(int(numeric_part))
	legacy_ids.sort()
	var quest_list := target.get_node_or_null(NodePath(QUEST_PREFIX.trim_suffix("/")))
	var mapping: Dictionary = {}
	if quest_list == null:
		return mapping
	var quest_cards: Array[Control] = []
	for child: Node in quest_list.get_children():
		if child is Button:
			quest_cards.append(child as Control)
	for index in range(mini(legacy_ids.size(), quest_cards.size())):
		mapping["@Button@%d" % legacy_ids[index]] = quest_cards[index]
	return mapping


func _resolve_legacy_quest_control(saved_path: String, legacy_cards: Dictionary) -> Control:
	const QUEST_PREFIX := "QuestListPanel/QuestListScroll/QuestList/"
	if legacy_cards.is_empty() or not saved_path.begins_with(QUEST_PREFIX):
		return null
	var remainder := saved_path.trim_prefix(QUEST_PREFIX)
	var slash_index := remainder.find("/")
	var legacy_name := remainder if slash_index < 0 else remainder.left(slash_index)
	var card := legacy_cards.get(legacy_name) as Control
	if card == null:
		return null
	if slash_index < 0:
		return card
	return card.get_node_or_null(NodePath(remainder.substr(slash_index + 1))) as Control


func _fallback_saved_control(entry: Dictionary, used: Dictionary) -> Control:
	if not entry.has("text"):
		return null
	var saved_text := str(entry["text"])
	var saved_variation := str(entry.get("themeVariation", ""))
	var candidates: Array[Control] = []
	for control in selectable_nodes:
		if used.has(control.get_instance_id()) or not _supports_text(control):
			continue
		if _control_text(control) != saved_text:
			continue
		if not saved_variation.is_empty() and str(control.theme_type_variation) != saved_variation:
			continue
		candidates.append(control)
	return candidates[0] if candidates.size() == 1 else null


func _verify_loaded_profile(ordered: Array[Dictionary]) -> Dictionary:
	var mismatches := 0
	var hidden := 0
	var details: Array[String] = []
	for item: Dictionary in ordered:
		var control := item["control"] as Control
		var entry := item["entry"] as Dictionary
		var saved_path := str(item.get("saved_path", target.get_path_to(control)))
		var rect: Array = entry.get("rect", [])
		var scale := _device_scale(control)
		var actual := control.get_global_rect()
		if rect.size() == 4:
			var actual_physical := Rect2(actual.position * scale, actual.size * scale)
			var expected_physical := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
			if not actual_physical.position.is_equal_approx(expected_physical.position) or not actual_physical.size.is_equal_approx(expected_physical.size):
				if actual_physical.position.distance_to(expected_physical.position) > 0.75 or actual_physical.size.distance_to(expected_physical.size) > 0.75:
					mismatches += 1
					details.append("%s geometry expected=%s actual=%s" % [saved_path, expected_physical, actual_physical])
		var expected_visible := bool(entry.get("visible", true))
		if not expected_visible:
			hidden += 1
		if control.visible != expected_visible:
			mismatches += 1
			details.append("%s visible expected=%s actual=%s" % [saved_path, expected_visible, control.visible])
		if entry.has("text") and _supports_text(control) and _should_restore_saved_text(control, entry) and _control_text(control) != str(entry["text"]):
			mismatches += 1
			details.append("%s text" % saved_path)
		if entry.has("fontSize") and _supports_text(control):
			var actual_font_physical := float(_control_font_size(control)) * scale.y
			if absf(actual_font_physical - float(entry["fontSize"])) > 0.75:
				mismatches += 1
				details.append("%s font expected=%.3f actual=%.3f" % [saved_path, float(entry["fontSize"]), actual_font_physical])
	return {"mismatches": mismatches, "hidden": hidden, "details": details}


func _refresh_selectable_nodes_after_load(ordered: Array[Dictionary]) -> void:
	# Keep hidden user-deleted controls in the picker so they can still be
	# restored through Ctrl+Z or a future saved profile load. Also append every
	# currently visible calibratable control that is absent from the saved
	# profile. This is how newly added buttons/slots remain selectable without
	# changing any previously calibrated layer.
	selectable_nodes.clear()
	node_picker.clear()
	var saved_instance_ids: Dictionary = {}
	for item: Dictionary in ordered:
		var control := item["control"] as Control
		selectable_nodes.append(control)
		saved_instance_ids[control.get_instance_id()] = true
	var current_controls: Array[Control] = []
	_collect_calibratable_controls(target, current_controls)
	for control in current_controls:
		if not saved_instance_ids.has(control.get_instance_id()):
			selectable_nodes.append(control)
	selectable_nodes.sort_custom(func(left: Control, right: Control) -> bool:
		return str(target.get_path_to(left)) < str(target.get_path_to(right))
	)
	for control in selectable_nodes:
		var state_marker := "  [已隐藏]" if not control.visible else ("  [新增]" if not saved_instance_ids.has(control.get_instance_id()) else "")
		node_picker.add_item("%s  [%s]%s" % [
			str(target.get_path_to(control)), control.get_class(), state_marker
		])
	if selected == null or not selectable_nodes.has(selected):
		selected = selectable_nodes[0] if not selectable_nodes.is_empty() else null
	if selected != null:
		var picker_index := selectable_nodes.find(selected)
		if picker_index >= 0:
			node_picker.select(picker_index)


func _collect_calibratable_controls(parent: Node, result: Array[Control]) -> void:
	for child in parent.get_children():
		if child is Control and _is_calibratable(child as Control):
			result.append(child as Control)
		_collect_calibratable_controls(child, result)


func _load_selected_override() -> void:
	if selected == null:
		return
	var profile: Dictionary = _read_output().get("profiles", {}).get(profile_id, {})
	var entry: Dictionary = profile.get("nodes", {}).get(str(target.get_path_to(selected)), {})
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		status_label.text = "当前控件没有已保存数据"
		return
	_push_undo_state()
	var data := _read_output()
	if int(data.get("schemaVersion", 1)) >= 3:
		var scale := _device_scale(selected)
		selected.size = Vector2(float(rect[2]) / scale.x, float(rect[3]) / scale.y)
		var desired_screen_position := Vector2(float(rect[0]) / scale.x, float(rect[1]) / scale.y)
		selected.position += desired_screen_position - selected.get_global_rect().position
	elif int(data.get("schemaVersion", 1)) == 2:
		var scale := _device_scale(selected)
		selected.position = Vector2(float(rect[0]) / scale.x, float(rect[1]) / scale.y)
		selected.size = Vector2(float(rect[2]) / scale.x, float(rect[3]) / scale.y)
	else:
		selected.position = Vector2(float(rect[0]), float(rect[1]))
		selected.size = Vector2(float(rect[2]), float(rect[3]))
	selected.visible = bool(entry.get("visible", true))
	if entry.has("text") and _supports_text(selected) and _should_restore_saved_text(selected, entry):
		_set_control_text(selected, str(entry["text"]))
	if entry.has("fontSize") and _supports_text(selected):
		var scale := _device_scale(selected)
		_set_control_font_size(selected, maxi(1, roundi(float(entry["fontSize"]) / scale.y)))
	_sync_fields()
	queue_redraw()
	status_label.text = "已载入当前控件"


func _read_output() -> Dictionary:
	if not FileAccess.file_exists(OUTPUT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT_PATH))
	return parsed if parsed is Dictionary else {}


func _normalized_rect(at: Vector2, control_size: Vector2, parent_size: Vector2) -> Array:
	if parent_size.x <= 0.0 or parent_size.y <= 0.0:
		return [0.0, 0.0, 0.0, 0.0]
	return [at.x / parent_size.x, at.y / parent_size.y, control_size.x / parent_size.x, control_size.y / parent_size.y]


func _device_scale(control: Control) -> Vector2:
	if control == null:
		return Vector2.ONE
	var logical_size := control.get_viewport().get_visible_rect().size
	if logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return Vector2.ONE
	return device_coordinate_size / logical_size


func _supports_text(control: Control) -> bool:
	return control is Label or control is RichTextLabel or control is Button or control is LineEdit or control is TextEdit


func _runtime_owned_text(control: Control) -> bool:
	if bool(control.get_meta("calibration_runtime_text", false)):
		return true
	var path := str(target.get_path_to(control)) if target != null and is_instance_valid(target) else ""
	if path.begins_with("SkillDetailPanel/"):
		return control.name in [&"DescriptionTitle", &"SkillDescription", &"SkillStats", &"SkillName"]
	if path.begins_with("SkillListPanel/SkillListScroll/SkillCards/"):
		return true
	return false

func _should_restore_saved_text(control: Control, entry: Dictionary) -> bool:
	return not _runtime_owned_text(control) and not _saved_text_revision_stale(control, entry)


func _control_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is RichTextLabel:
		return (control as RichTextLabel).text
	if control is Button:
		return (control as Button).text
	if control is LineEdit:
		return (control as LineEdit).text
	if control is TextEdit:
		return (control as TextEdit).text
	return ""


func _set_control_text(control: Control, value: String) -> void:
	if control is Label:
		(control as Label).text = value
	elif control is RichTextLabel:
		(control as RichTextLabel).text = value
	elif control is Button:
		(control as Button).text = value
	elif control is LineEdit:
		(control as LineEdit).text = value
	elif control is TextEdit:
		(control as TextEdit).text = value


func _control_font_size(control: Control) -> int:
	if control is RichTextLabel:
		return control.get_theme_font_size("normal_font_size")
	return control.get_theme_font_size("font_size")


func _set_control_font_size(control: Control, value: int) -> void:
	if control is RichTextLabel:
		control.add_theme_font_size_override("normal_font_size", value)
	else:
		control.add_theme_font_size_override("font_size", value)


func _begin_text_edit() -> void:
	if selected == null or not _supports_text(selected) or _text_edit_session_active:
		return
	_push_undo_state()
	_text_edit_session_active = true


func _text_editor_changed() -> void:
	if _updating_fields or selected == null or not _supports_text(selected):
		return
	if not _text_edit_session_active:
		_begin_text_edit()
	_set_control_text(selected, text_editor.text)
	queue_redraw()


func _focus_text_editor() -> void:
	if text_editor == null or not text_editor.editable:
		return
	text_editor.grab_focus()
	text_editor.select_all()


func _draw() -> void:
	if target == null:
		return
	var panel_overlay_rect := _control_overlay_rect(target)
	draw_rect(panel_overlay_rect, Color(0.18, 0.72, 1.0, 0.92), false, 2.0)
	var safe := GothicModalLayoutScript.safe_rect(target.size)
	var target_transform := target.get_global_transform_with_canvas()
	var safe_top_left: Vector2 = _canvas_point_to_overlay(target, target_transform * safe.position)
	var safe_bottom_right: Vector2 = _canvas_point_to_overlay(target, target_transform * safe.end)
	draw_rect(Rect2(safe_top_left, safe_bottom_right - safe_top_left), Color(0.25, 1.0, 0.38, 0.95), false, 3.0)
	if selected != null:
		var selected_rect := _control_overlay_rect(selected)
		var highlight := Color(1.0, 0.18, 0.72, 1.0)
		draw_rect(selected_rect, Color(1.0, 0.18, 0.72, 0.16), true)
		draw_rect(selected_rect, Color(0.04, 0.01, 0.03, 0.95), false, 9.0)
		draw_rect(selected_rect, highlight, false, 5.0)
		_draw_selection_handles(selected_rect, highlight)
		_draw_selection_tag(selected_rect)


func _control_overlay_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var top_left := _canvas_point_to_overlay(control, transform * Vector2.ZERO)
	var bottom_right := _canvas_point_to_overlay(control, transform * control.size)
	return Rect2(top_left, bottom_right - top_left)


func _canvas_point_to_overlay(control: Control, point: Vector2) -> Vector2:
	if viewport_display != null and control.get_viewport() != get_viewport():
		var source_rect := control.get_viewport().get_visible_rect()
		var display_rect := viewport_display.get_global_rect()
		if source_rect.size.x > 0.0 and source_rect.size.y > 0.0:
			var normalized := (point - source_rect.position) / source_rect.size
			return _global_to_overlay(display_rect.position + normalized * display_rect.size)
	return _global_to_overlay(point)


func _global_to_overlay(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * point


func _draw_selection_handles(rect: Rect2, color: Color) -> void:
	var handle_size := Vector2(12, 12)
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		draw_rect(Rect2(point - handle_size * 0.5, handle_size), Color(0.03, 0.01, 0.02, 1.0), true)
		draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), color, true)


func _draw_selection_tag(rect: Rect2) -> void:
	var scale := _device_scale(selected)
	var global_rect := selected.get_global_rect()
	var path_text := "%s  ·  x %.0f  y %.0f  w %.0f  h %.0f px" % [
		str(target.get_path_to(selected)), global_rect.position.x * scale.x, global_rect.position.y * scale.y,
		global_rect.size.x * scale.x, global_rect.size.y * scale.y
	]
	var tag_size := Vector2(maxf(260.0, path_text.length() * 7.2 + 20.0), 28.0)
	var tag_position := Vector2(rect.position.x, rect.position.y - tag_size.y - 6.0)
	if tag_position.y < 2.0:
		tag_position.y = rect.end.y + 6.0
	draw_rect(Rect2(tag_position, tag_size), Color(0.035, 0.01, 0.025, 0.96), true)
	draw_rect(Rect2(tag_position, tag_size), Color(1.0, 0.18, 0.72, 1.0), false, 2.0)
	draw_string(ThemeDB.fallback_font, tag_position + Vector2(10, 19), path_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
