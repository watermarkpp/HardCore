extends Node
## R2 integrates with the existing editor, rather than a second map editor.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")
const PixelLayout := preload("res://scripts/map_editor/polygon/poly_pixel_layout.gd")
const Reset := preload("res://scripts/map_editor/polygon/poly_reset.gd")
const Overlay := preload("res://scripts/map_editor/polygon/poly_editor_overlay.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const META_KEYS := ["collision_authority", "collision_migration_contract_id", "collision_migration_blocked_count", "collision_backup_path", "collision_reset_contract_id"]
const MODES := ["select", "polygon", "rect", "ellipse", "legacy_cut", "cell"]
var app: Variant
var canvas: Variant
var overlay: Overlay
var active_button: CheckButton
var mode_option: OptionButton
var snap_button: CheckBox
var info: Label
var active := false
var mode := "select"
var selected := -1
var selected_vertex := -1
var draw_owner := ""
var draft := PackedVector2Array()
var drag_original := PackedVector2Array()
var drag_kind := ""
var drag_start := Vector2.ZERO
var hover := Vector2.INF
var document_ref: Dictionary = {}
var cache: Array[Dictionary] = []
var cache_dirty := true
var clear_all_button: Button
var clear_all_dialog: ConfirmationDialog
var _reset_confirmation: Dictionary = {}
var _reset_busy: bool = false
# Test-only redirection; production uses the project outputs directory.
var test_reset_backup_root: String = ""
var left_latched := false
var last_cell := Vector2i(-1, -1)
# T-key toggle: the non-select mode to restore when leaving select mode again.
var select_toggle_memory := ""

## 2026-09-20 user order: highlight overlapping drawn polygons.
var overlap_cache: Dictionary = {}
var overlap_cache_dirty := true
var draft_overlap_notice := false

func setup(editor_app: Node) -> void:
	app = editor_app
	canvas = app.preview
	canvas.set("_hc_polygon_controller", self)
	canvas.focus_mode = Control.FOCUS_ALL
	overlay = Overlay.new()
	overlay.controller = self
	canvas.add_child(overlay)
	canvas.draw.connect(overlay.queue_redraw)
	var panel := VBoxContainer.new()
	app.sidebar.add_child(panel)
	var title := Label.new()
	title.text = "HardCore · 自由多边形 / 像素布置 R2"
	panel.add_child(title)
	_button(panel, "升级当前老地图（先备份，不自动保存）", _migrate)
	clear_all_button = Button.new()
	clear_all_button.text = "清空当前地图全部碰撞，重新绘制"
	clear_all_button.tooltip_text = "清除本地图全部障碍轮廓；保留地图外边界和安全区规则。先备份，可撤销，不自动保存。"
	clear_all_button.pressed.connect(_request_clear_all)
	panel.add_child(clear_all_button)
	clear_all_dialog = ConfirmationDialog.new()
	clear_all_dialog.title = "确认清空当前地图碰撞"
	clear_all_dialog.get_ok_button().text = "备份并清空"
	clear_all_dialog.get_cancel_button().text = "取消"
	clear_all_dialog.confirmed.connect(_confirm_clear_all)
	clear_all_dialog.canceled.connect(_cancel_clear_all)
	add_child(clear_all_dialog)
	active_button = CheckButton.new()
	active_button.text = "启用精细碰撞工具"
	active_button.toggled.connect(_activate)
	panel.add_child(active_button)
	mode_option = OptionButton.new()
	for label: String in ["选择 / 拖顶点 / Alt 拖整块", "自由多边形（任意位置落点）", "连续矩形（两点）", "连续椭圆（两点）", "框选清除旧格碰撞", "单格辅助绘制"]:
		mode_option.add_item(label)
	mode_option.item_selected.connect(_mode_changed)
	panel.add_child(mode_option)
	snap_button = CheckBox.new()
	snap_button.text = "可选 0.25 GU 吸附（默认关闭；Shift 临时吸附）"
	panel.add_child(snap_button)
	_button(panel, "绘制地图级轮廓（不绑定素材）", _draw_map_polygon)
	_button(panel, "记住选中素材，绘制绑定轮廓", _remember_and_draw)
	_button(panel, "把选中轮廓绑定到记住的素材", _bind_selected)
	_button(panel, "选中轮廓解除绑定，固定到地图", _unbind_selected)
	_button(panel, "完成轮廓（Enter 或点击首点）", _finish_polygon)
	_button(panel, "删除选中轮廓（Delete）", _delete_shape)
	_button(panel, "删除选中顶点（Backspace）", _delete_vertex)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "普通方向键：格子移动；Ctrl+方向键：未缩放画面 1 像素。\n自由轮廓不依赖网格交点。Ctrl+点边插点；Alt 拖整块；右键/Esc 取消。\n地图级轮廓固定；素材绑定轮廓随移动、复制、缩放和旋转。旧单格不会自动猜配素材。"
	panel.add_child(info)

func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func invalidate_document() -> void:
	cache_dirty = true
	if is_instance_valid(overlay):
		overlay.queue_redraw()

func _sync_document() -> void:
	if is_same(document_ref, app.current_document):
		return
	document_ref = app.current_document
	selected = -1
	selected_vertex = -1
	draw_owner = ""
	active = false
	active_button.set_pressed_no_signal(false)
	cache_dirty = true
	_cancel_draft()

func _status(message: String) -> void:
	if is_instance_valid(info):
		info.text = message
	if is_instance_valid(app.status_label):
		app.status_label.text = message

func _size_gu() -> Vector2i:
	return Geo.parse_size(app.current_document.get("design", {}).get("design_size", []))

func _screen_to_gu(point: Vector2, snap := false) -> Vector2:
	if canvas._draw_scale <= 0.0:
		return Vector2.INF
	var result := Coord.ground_px_to_tile((point - canvas._draw_offset) / canvas._draw_scale, _size_gu())
	if snap or snap_button.button_pressed:
		result = result.snapped(Vector2.ONE * 0.25)
	return result

func _gu_to_screen(point: Vector2) -> Vector2:
	return canvas._draw_offset + Coord.tile_to_ground_px(point, _size_gu()) * canvas._draw_scale

func _records() -> Array[Dictionary]:
	if not cache_dirty:
		return cache
	cache_dirty = false
	cache.clear()
	var gathered := Binding.gather(app.current_document)
	for row: Dictionary in gathered.records:
		var checked := Geo.validate(Geo.encode(row.points), _size_gu())
		row["valid_geometry"] = bool(checked.ok)
		cache.append(row)
	overlap_cache_dirty = true
	return cache

## True when the given polygon shares area with any record except
## exclude_index (used to skip the record being edited in place).
static func polygon_overlaps_records(points: PackedVector2Array, records: Array, exclude_index: int) -> bool:
	if points.size() < 3:
		return false
	for index: int in records.size():
		if index == exclude_index:
			continue
		var other: PackedVector2Array = records[index].get("points", PackedVector2Array())
		if other.size() < 3:
			continue
		if not Geometry2D.intersect_polygons(points, other).is_empty():
			return true
	return false

func _overlap_map() -> Dictionary:
	if not overlap_cache_dirty:
		return overlap_cache
	overlap_cache_dirty = false
	overlap_cache.clear()
	for i: int in cache.size():
		var points: PackedVector2Array = cache[i].get("points", PackedVector2Array())
		if points.size() < 3:
			continue
		if polygon_overlaps_records(points, cache, i):
			overlap_cache[i] = true
	return overlap_cache

func _selected_record() -> Dictionary:
	var rows := _records()
	return rows[selected] if selected >= 0 and selected < rows.size() else {}

func _selected_points() -> PackedVector2Array:
	return _selected_record().get("points", PackedVector2Array())

func _activate(value: bool) -> void:
	_sync_document()
	if value and not Geo.enabled(app.current_document):
		active = false
		canvas.set_interaction_mode("select")
		active_button.set_pressed_no_signal(false)
		_status("先选择“升级当前老地图”保留旧碰撞，或“清空当前地图全部碰撞，重新绘制”。两者都先备份，不自动保存。")
		return
	active = value
	active_button.set_pressed_no_signal(active)
	_cancel_draft()
	if active:
		canvas.selected_selectable_id = ""
		canvas.set_interaction_mode("polygon_precision")
		canvas.grab_focus()
	elif canvas.interaction_mode == "polygon_precision":
		canvas.set_interaction_mode("select")
	overlay.queue_redraw()

func _mode_changed(index: int) -> void:
	mode = MODES[index]
	_activate(true)

func open_polygon_tool(shape := "polygon") -> void:
	_sync_document()
	mode = shape if shape in MODES else "polygon"
	mode_option.select(MODES.find(mode))
	_activate(true)

func open_legacy_erase() -> void:
	open_polygon_tool("legacy_cut")
	_status("此工具只清除迁移保留的旧格碰撞。新轮廓请切换选择工具后删除或拖顶点。")

func _draw_map_polygon() -> void:
	draw_owner = ""
	open_polygon_tool("polygon")

func _remember_and_draw() -> void:
	_sync_document()
	var id := str(canvas.selected_selectable_id)
	var found := Binding.locate(app.current_document, id)
	if not found.ok:
		_status("先按 E 用素材选择工具选中图片，再点击此按钮。")
		return
	if bool(found.instance.get("selection_locked", false)) or not bool(found.instance.get("runtime_export", true)):
		_status("该素材已锁定或不导出，不能绑定游戏碰撞。")
		return
	draw_owner = id
	open_polygon_tool("polygon")
	_status("新轮廓绑定素材 %s；任意位置逐点绘制。需先清掉该处旧格阻挡，避免双层阻挡。" % id)

func handle_input(event: InputEvent) -> bool:
	_sync_document()
	if PixelLayout.handle(app, event):
		return true
	if not active or not Geo.enabled(app.current_document):
		return false
	if canvas.interaction_mode != "polygon_precision":
		active = false
		active_button.set_pressed_no_signal(false)
		_cancel_draft()
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode in [KEY_Z, KEY_Y]:
			_cancel_draft()
			if event.keycode == KEY_Z:
				app.command_stack.undo()
			else:
				app.command_stack.redo()
			invalidate_document()
			return true
		match event.keycode:
			KEY_ESCAPE:
				_cancel_draft()
				return true
			KEY_ENTER, KEY_KP_ENTER:
				_finish_polygon()
				return true
			KEY_DELETE:
				_delete_shape()
				return true
			KEY_BACKSPACE:
				if mode == "polygon" and not draft.is_empty():
					draft.remove_at(draft.size() - 1)
					overlay.queue_redraw()
				else:
					_delete_vertex()
				return true
			KEY_T:
				_toggle_select_mode()
				return true
		return false
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			left_latched = false
			if not drag_kind.is_empty():
				_cancel_draft()
		# Pan is owned by the original canvas. Recompute hover after its draw.
		if canvas._panning:
			return false
		hover = _screen_to_gu(event.position, event.shift_pressed)
		if not drag_kind.is_empty():
			if drag_kind == "vertex":
				draft[selected_vertex] = hover
			else:
				for i: int in range(draft.size()):
					draft[i] = drag_original[i] + hover - drag_start
			overlay.queue_redraw()
			return true
		if mode == "cell" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_paint_cell(hover)
		overlay.queue_redraw()
		return false
	if not event is InputEventMouseButton:
		return false
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if draft.is_empty():
				_activate(false)
			else:
				_cancel_draft()
		return true
	if not event.pressed:
		left_latched = false
		last_cell = Vector2i(-1, -1)
		if not drag_kind.is_empty():
			var points := draft.duplicate()
			drag_kind = ""
			draft.clear()
			_replace_selected(points, "调整轮廓")
		return true
	# Preserve the existing editor's one-action-per-physical-press contract.
	if event.double_click or left_latched:
		left_latched = true
		return true
	left_latched = true
	canvas.grab_focus()
	var point := _screen_to_gu(event.position, event.shift_pressed)
	if not point.is_finite():
		return true
	hover = point
	if mode == "polygon":
		if draft.size() >= 3 and _gu_to_screen(draft[0]).distance_to(event.position) <= 7.0:
			_finish_polygon()
		elif draft.size() >= Geo.MAX_VERTICES:
			_status("轮廓最多 %d 个顶点；请拆成几个简单轮廓，避免细碎像素描边。" % Geo.MAX_VERTICES)
		else:
			draft.append(point)
	elif mode == "cell":
		_paint_cell(point)
	elif mode in ["rect", "ellipse", "legacy_cut"]:
		if draft.is_empty():
			draft.append(point)
		else:
			var box := Rect2(draft[0], Vector2.ZERO).expand(point)
			if mode == "legacy_cut":
				var candidate: Dictionary = app.current_document.duplicate(true)
				candidate.layers.collision = Author.clear_legacy_region(candidate.layers.collision, box)
				_transact(candidate, "局部清除旧格碰撞")
			else:
				_add_polygon(_shape_points(box), "新增连续形状")
			draft.clear()
	else:
		_select_or_drag(point, event.position, event.ctrl_pressed, event.alt_pressed)
	overlay.queue_redraw()
	return true

func _shape_points(box: Rect2) -> PackedVector2Array:
	if mode != "ellipse":
		return Geo.rectangle_points(box)
	var points := PackedVector2Array()
	for i: int in range(32):
		points.append(box.get_center() + Vector2.from_angle(TAU * float(i) / 32.0) * box.size * 0.5)
	return points

func _paint_cell(point: Vector2) -> void:
	var cell := Vector2i(floori(point.x), floori(point.y))
	if cell == last_cell:
		return
	last_cell = cell
	_add_polygon(Geo.rectangle_points(Rect2(Vector2(cell), Vector2.ONE)), "单格辅助绘制")

func _select_or_drag(point: Vector2, screen_point: Vector2, insert: bool, whole: bool) -> void:
	var p := _selected_points()
	if insert and p.size() >= 3:
		var best := 100.0
		var edge := -1
		var inserted := Vector2.ZERO
		for i: int in range(p.size()):
			var q := Geo.nearest_on_segment(screen_point, _gu_to_screen(p[i]), _gu_to_screen(p[(i + 1) % p.size()]))
			if screen_point.distance_squared_to(q) < best:
				best = screen_point.distance_squared_to(q)
				edge = i
				inserted = _screen_to_gu(q)
		if edge >= 0:
			p.insert(edge + 1, inserted)
			_replace_selected(p, "插入碰撞顶点")
			selected_vertex = edge + 1
			return
	for i: int in range(p.size()):
		if _gu_to_screen(p[i]).distance_to(screen_point) <= 10.0:
			selected_vertex = i
			drag_kind = "vertex"
			draft = p.duplicate()
			drag_original = p.duplicate()
			drag_start = point
			return
	selected = -1
	selected_vertex = -1
	var records := _records()
	for i: int in range(records.size() - 1, -1, -1):
		p = records[i].points
		if p.size() >= 3 and Geometry2D.is_point_in_polygon(point, p):
			selected = i
			if whole:
				drag_kind = "whole"
				draft = p.duplicate()
				drag_original = p.duplicate()
				drag_start = point
			_status("选中 %s；归属：%s" % [str(records[i].collision_id), str(records[i].owner) if not str(records[i].owner).is_empty() else "地图"])
			return

func _add_polygon(points: PackedVector2Array, label: String) -> bool:
	var checked := Geo.validate(Geo.encode(points), _size_gu())
	if not checked.ok:
		_status("拒绝轮廓：%s" % str(checked.errors))
		return false
	var candidate: Dictionary = app.current_document.duplicate(true)
	if draw_owner.is_empty():
		candidate.layers.collision.append(Author.entry(Author.next_id(candidate.layers.collision), checked.points))
	else:
		var saved := Binding.put_local(candidate, draw_owner, checked.points)
		if not saved.ok:
			_status("绑定失败：%s" % str(saved.errors))
			return false
	_transact(candidate, label)
	return true

func _finish_polygon() -> void:
	if not active or mode != "polygon":
		return
	if _add_polygon(draft, "新增自由多边形"):
		draft.clear()
		draft_overlap_notice = false
		overlay.queue_redraw()

func _replace_selected(points: PackedVector2Array, label: String) -> void:
	var record := _selected_record()
	if record.is_empty():
		return
	var checked := Geo.validate(Geo.encode(points), _size_gu())
	if not checked.ok:
		_status("拒绝修改：%s" % str(checked.errors))
		overlay.queue_redraw()
		return
	var candidate: Dictionary = app.current_document.duplicate(true)
	if str(record.owner).is_empty():
		for row: Dictionary in candidate.layers.collision:
			if str(row.get("collision_id", "")) == str(record.collision_id):
				row.data.points = Geo.encode(checked.points)
				row.source = "manual"
	else:
		var saved := Binding.put_local(candidate, record.owner, checked.points, record.local_id)
		if not saved.ok:
			_status("修改失败：%s" % str(saved.errors))
			return
	var selected_before := selected
	_transact(candidate, label)
	selected = selected_before

func _delete_shape() -> void:
	var record := _selected_record()
	if not active or record.is_empty() or not draft.is_empty():
		return
	var candidate: Dictionary = app.current_document.duplicate(true)
	if Binding.remove(candidate, record):
		_transact(candidate, "删除碰撞轮廓")

func _delete_vertex() -> void:
	var points := _selected_points()
	if not active or selected_vertex < 0 or selected_vertex >= points.size():
		return
	points.remove_at(selected_vertex)
	_replace_selected(points, "删除碰撞顶点")
	selected_vertex = -1

func _bind_selected() -> void:
	var record := _selected_record()
	if record.is_empty() or draw_owner.is_empty():
		_status("先选中素材并点击“记住选中素材”，再切回碰撞选择模式选中要绑定的轮廓。")
		return
	var candidate: Dictionary = app.current_document.duplicate(true)
	var saved := Binding.put_local(candidate, draw_owner, record.points)
	if not saved.ok:
		_status("绑定失败：%s" % str(saved.errors))
		return
	if not Binding.remove(candidate, record):
		_status("原轮廓不存在，未修改。")
		return
	_transact(candidate, "把轮廓绑定到素材")

func _unbind_selected() -> void:
	var record := _selected_record()
	if record.is_empty() or str(record.owner).is_empty():
		_status("请选择素材绑定轮廓。")
		return
	var candidate: Dictionary = app.current_document.duplicate(true)
	if not Binding.remove(candidate, record):
		return
	candidate.layers.collision.append(Author.entry(Author.next_id(candidate.layers.collision), record.points))
	_transact(candidate, "解除绑定并保持当前位置")

## T key: flip between the select mode and the last non-select drawing mode.
## Press once to jump to 选择/拖顶点/Alt 整块, press again to restore the
## previous dropdown choice. Only the mode dropdown moves; the tool stays on.
func _toggle_select_mode() -> void:
	if mode == "select":
		var restore := select_toggle_memory
		if restore.is_empty() or not restore in MODES:
			_status("已在选择模式；没有可恢复的绘制模式。")
			return
		select_toggle_memory = ""
		var index := MODES.find(restore)
		mode_option.select(index)
		_mode_changed(index)
		_status("已恢复 %s。" % mode_option.get_item_text(index))
	else:
		select_toggle_memory = mode
		mode_option.select(MODES.find("select"))
		_mode_changed(MODES.find("select"))
		_status("已切换到选择模式；再按 T 恢复 %s。" % mode_option.get_item_text(MODES.find(select_toggle_memory)))


func _cancel_draft() -> void:
	draft.clear()
	drag_original.clear()
	drag_kind = ""
	left_latched = false
	last_cell = Vector2i(-1, -1)
	draft_overlap_notice = false
	if is_instance_valid(overlay):
		overlay.queue_redraw()

func _snapshot(document: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for key: String in META_KEYS:
		if document.get("editor_meta", {}).has(key):
			values[key] = document.editor_meta[key]
	var owners: Dictionary = {}
	for instance: Dictionary in Binding.instances(document):
		if instance.has(Binding.FIELD):
			owners[str(instance.instance_id)] = instance[Binding.FIELD].duplicate(true)
	return {"entries": document.get("layers", {}).get("collision", []).duplicate(true),
		"erase_present": document.get("layers", {}).has("collision_erase"),
		"erased": document.get("layers", {}).get("collision_erase", []).duplicate(true),
		"meta": values, "owners": owners}

func _transact(candidate: Dictionary, label: String) -> void:
	var document: Dictionary = app.current_document
	var before := _snapshot(document)
	var after := _snapshot(candidate)
	var keys: Dictionary = {}
	for id: String in before.owners:
		keys[id] = true
	for id: String in after.owners:
		keys[id] = true
	for id: String in keys:
		if before.owners.get(id) == after.owners.get(id):
			before.owners.erase(id)
			after.owners.erase(id)
		else:
			if not before.owners.has(id):
				before.owners[id] = null
			if not after.owners.has(id):
				after.owners[id] = null
	app.command_stack.execute({"label": label,
		"do": func() -> void: _apply_state(document, after, label),
		"undo": func() -> void: _apply_state(document, before, "撤销：" + label)})

func _apply_state(document: Dictionary, state: Dictionary, label: String) -> void:
	if not is_same(document, app.current_document):
		_status("文档已更换，拒绝跨地图撤销。")
		return
	for id: String in state.owners:
		if not Binding.locate(document, id).ok:
			_status("绑定素材已删除，拒绝不完整恢复；地图未改动。")
			return
	for id: String in state.owners:
		var found := Binding.locate(document, id)
		if state.owners[id] == null:
			found.instance.erase(Binding.FIELD)
		else:
			found.instance[Binding.FIELD] = state.owners[id].duplicate(true)
		document.layers[found.layer][found.index] = found.instance
	document.layers.collision = state.entries.duplicate(true)
	if bool(state.get("erase_present", false)):
		document.layers["collision_erase"] = state.get("erased", []).duplicate(true)
	else:
		document.layers.erase("collision_erase")
	var meta: Dictionary = document.get("editor_meta", {}).duplicate(true)
	for key: String in META_KEYS:
		meta.erase(key)
	for key: String in state.meta:
		meta[key] = state.meta[key]
	meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["runtime_approved"] = false
	document.editor_meta = meta
	app._last_build_candidate = {}
	selected = -1
	selected_vertex = -1
	cache_dirty = true
	var previous_latch := left_latched
	var previous_cell := last_cell
	_cancel_draft()
	left_latched = previous_latch
	last_cell = previous_cell
	canvas.set_document(document)
	if not Geo.enabled(document):
		_activate(false)
	_status("%s；未保存、未发布。" % label)

func _migrate() -> void:
	_sync_document()
	var document: Dictionary = app.current_document
	if document.is_empty() or Geo.enabled(document):
		_status("当前地图为空或已经使用精细碰撞。")
		return
	var effective := MapEditorCollisionService.build_walkability(document)
	var migrated := Author.migrate(document, effective)
	if not migrated.ok:
		_status("迁移失败：%s" % str(migrated.errors))
		return
	var backup := _backup(document, effective)
	if not backup.ok:
		_status("备份失败，地图未改动：%s" % str(backup.errors))
		return
	migrated.document.editor_meta["collision_backup_path"] = backup.path
	_transact(migrated.document, "升级为真实多边形，保留当前有效旧阻挡")
	_activate(true)
	_status("备份：%s。旧阶梯未自动平滑；请局部清除旧阻挡，再画新轮廓。" % backup.path)

func _backup(document: Dictionary, effective: Dictionary) -> Dictionary:
	var text := JSON.stringify({"contract_id": "hc.polygon_migration_backup.v2", "document": document,
		"effective_walkability": effective, "source_path": str(app.current_document_path),
		"base_commit": "6312d0ba69682fb1424739788b18bb8b39db174b"}, "\t", true, true) + "\n"
	var root := "res://outputs/polygon_migration_backups/%s" % str(document.get("map_id", "map")).validate_filename()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	if error != OK:
		return {"ok": false, "errors": ["backup_directory_failed:%d" % error]}
	var path := root.path_join("before_%s.json" % text.sha256_text())
	if FileAccess.file_exists(path):
		return {"ok": FileAccess.get_file_as_string(path) == text, "path": path, "errors": ["backup_existing_content_mismatch"]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["backup_open_failed"]}
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(path) != text:
		return {"ok": false, "errors": ["backup_readback_mismatch"]}
	return {"ok": true, "path": path}

func draw_overlay(surface: Control) -> void:
	_sync_document()
	if app.current_document.is_empty() or not Geo.enabled(app.current_document) or (not active and not canvas.show_walkable_preview):
		return
	var rows := _records()
	var overlap_map := _overlap_map()
	for i: int in range(rows.size()):
		var points: PackedVector2Array = rows[i].points
		if i == selected and not drag_kind.is_empty():
			points = draft
		var screen := PackedVector2Array()
		for point: Vector2 in points:
			screen.append(_gu_to_screen(point))
		if screen.size() < 3 or not Geo.bounds(screen).intersects(Rect2(Vector2.ZERO, canvas.size).grow(12), true):
			continue
		var color := Color(1, 0.65, 0.25) if str(rows[i].get("source", "")) == "legacy_final" else Color(0.15, 0.85, 0.95)
		if not str(rows[i].get("owner", "")).is_empty():
			color = Color(0.75, 0.45, 1)
		var record_overlap := bool(overlap_map.get(i, false))
		if i == selected and not drag_kind.is_empty():
			record_overlap = polygon_overlaps_records(points, rows, i)
		if record_overlap:
			color = Color(1, 0.42, 0.1)
		if i == selected:
			color = Color(0.3, 1, 0.45)
		if bool(rows[i].valid_geometry) and drag_kind.is_empty():
			surface.draw_colored_polygon(screen, Color(color, 0.14))
		screen.append(screen[0])
		surface.draw_polyline(screen, color, 2, true)
		if i == selected:
			for j: int in range(points.size()):
				surface.draw_circle(_gu_to_screen(points[j]), 5 if j == selected_vertex else 3.5, color)
	if draft.is_empty() or not drag_kind.is_empty():
		return
	var shown := draft.duplicate()
	if hover.is_finite():
		if mode in ["rect", "ellipse", "legacy_cut"]:
			shown = _shape_points(Rect2(draft[0], Vector2.ZERO).expand(hover))
			if not shown.is_empty():
				shown.append(shown[0])
		elif mode == "polygon":
			shown.append(hover)
	var draft_overlap := polygon_overlaps_records(shown, rows, -1)
	if draft_overlap != draft_overlap_notice:
		draft_overlap_notice = draft_overlap
		if draft_overlap:
			_status("警告：绘制中的轮廓与现有碰撞重合（构建时会自动并集合并，不影响阻挡结果）")
		else:
			_status("轮廓绘制中")
	var draft_color := Color(1, 0.35, 0.15) if draft_overlap else Color(0.2, 1, 1)
	var screen := PackedVector2Array()
	for point: Vector2 in shown:
		screen.append(_gu_to_screen(point))
	for point: Vector2 in draft:
		surface.draw_circle(_gu_to_screen(point), 4, draft_color)
	if screen.size() >= 2:
		surface.draw_polyline(screen, draft_color, 2, true)


func _cancel_clear_all() -> void:
	_reset_confirmation = {}
	if is_instance_valid(clear_all_dialog):
		clear_all_dialog.hide()

func _request_clear_all() -> void:
	if _reset_busy:
		return
	_sync_document()
	var document: Dictionary = app.current_document
	var counts: Dictionary = Reset.summary(document)
	if not bool(counts.get("ok", false)):
		_status("无法清空：%s" % str(counts.get("errors", [])))
		return
	_cancel_draft()
	_reset_confirmation = {"document": document, "fingerprint": Reset.fingerprint(document)}
	clear_all_dialog.dialog_text = (
		"地图：%s\n地图 ID：%s\n地图级多边形：%d；素材绑定轮廓：%d\n旧碰撞形状：%d；旧擦除记录：%d\n保留但不再参与生成的实例策略：%d\n\n"
		% [counts.map_name, counts.map_id, counts.map_polygons, counts.bound_polygons,
			counts.legacy_shapes, counts.legacy_erase_cells, counts.instance_policy_sources]
		+ "将清空当前地图全部障碍碰撞。素材、NPC、门点、刷怪点、地面和视觉对象不会删除。\n"
		+ "地图外边界和安全区规则保留，防止角色走出地图。\n"
		+ "操作前自动备份，Ctrl+Z 可撤销。本次不会自动保存、构建或发布。")
	clear_all_dialog.popup_centered(Vector2i(620, 360))

func _confirm_clear_all() -> Dictionary:
	if _reset_busy or _reset_confirmation.is_empty():
		return {"ok": false, "errors": ["reset_confirmation_missing_or_busy"]}
	var request: Dictionary = _reset_confirmation
	_cancel_clear_all()
	var document: Dictionary = app.current_document
	if not is_same(document, request.document) or Reset.fingerprint(document) != str(request.fingerprint):
		_status("确认后地图或文档已变化，未执行清空；请重新点击按钮。")
		return {"ok": false, "errors": ["reset_document_changed"]}
	_reset_busy = true
	var prepared: Dictionary = Reset.plan(document, str(app.current_document_path))
	if not bool(prepared.get("ok", false)):
		_reset_busy = false
		_status("清空准备失败，文档未改动：%s" % str(prepared.get("errors", [])))
		return prepared
	var root: String = test_reset_backup_root if not test_reset_backup_root.is_empty() else Reset.BACKUP_ROOT
	var backup: Dictionary = Reset.write_backup(prepared.backup_payload, root)
	if not bool(backup.get("ok", false)):
		_reset_busy = false
		_status("备份失败，取消清空；文档未改动：%s" % str(backup.get("errors", [])))
		return backup
	if not is_same(app.current_document, document) or Reset.fingerprint(document) != str(prepared.before_fingerprint):
		_reset_busy = false
		_status("备份后文档已变化，未执行清空；备份已保留。")
		return {"ok": false, "errors": ["reset_document_changed"]}
	var candidate: Dictionary = prepared.candidate
	candidate.editor_meta["collision_backup_path"] = str(backup.path)
	# The shared transaction owns the sole mutation, revision increment and
	# candidate invalidation. No second UndoRedo stack and no disk map save.
	_transact(candidate, "清空当前地图全部碰撞，重新绘制")
	mode = "polygon"
	mode_option.select(MODES.find(mode))
	draw_owner = ""
	_activate(true)
	_reset_busy = false
	_status("当前地图全部障碍碰撞已清空；已备份；未保存；未构建；未发布。地图外边界与安全区规则保留。备份：%s" % str(backup.path))
	return {"ok": true, "errors": [], "backup_path": str(backup.path), "summary": prepared.summary}
