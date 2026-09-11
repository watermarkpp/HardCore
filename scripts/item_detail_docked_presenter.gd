class_name ItemDetailDockedPresenter
extends Panel

## HC-UI6: content is owned by the existing formatter; this class owns layout only.
## No per-frame poll, no scrollbars, no BBCode stripping, no truncated item title.
const NameStyle := preload("res://scripts/ui_item_name_style.gd")
const Formatter := preload("res://scripts/item_detail_presenter.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const TITLE_SIZE := 20
const BODY_SIZE := 14
const MARGIN := 14.0
const MAX_WIDTH := 280.0
const PREFERRED_WIDTH := 220.0
const MIN_WIDTH := 140.0
const PORTRAIT_RATIO := 1.12
const TITLE_GAP := 8.0
const MEASURE_PAD := 4.0
# R2: shrink whitespace only, never fonts, text, ratio, or allowed geometry.
const COMPACT_MARGIN := 8.0
const COMPACT_TITLE_GAP := 4.0
const COMPACT_MEASURE_PAD := 2.0
const REVISION := 8

var title_label: Label
var detail_label: RichTextLabel
var _context: Dictionary = {}
var _layout_key: Array = []
var _message_active := false
var _content_epoch := 0
var _dock_error_reported := false
var _layout_ok := false
var _queued := false
var _laying_out := false
var _layout_count := 0
var _layout_error := ""
var _title_source := ""
var _body_source := ""
var _connections: Array = []
var _name_style: Dictionary = {}
var _title_color := NameStyle.DEFAULT_COLOR
var _test_suppress_expected_layout_error := false
var _r2_density := "normal"

func _init() -> void:
	name = "ItemDetailPresenter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	_mark_runtime(self)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.clip_text = false
	title_label.visible_characters = -1
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_color", Color("f2c783"))
	_mark_runtime(title_label)
	add_child(title_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "Body"
	detail_label.bbcode_enabled = true
	detail_label.threaded = false
	detail_label.fit_content = false
	detail_label.scroll_active = false
	detail_label.scroll_following = false
	detail_label.selection_enabled = false
	detail_label.context_menu_enabled = false
	detail_label.visible_characters = -1
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	# Own the content box: inherited style margins must not invalidate measurement.
	detail_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	detail_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	detail_label.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	detail_label.add_theme_color_override("default_color", Color("ddc9a9"))
	_mark_runtime(detail_label)
	add_child(detail_label)
	visible = false

static func _mark_runtime(node: Control) -> void:
	node.set_meta("calibration_runtime_text", true)
	node.set_meta("calibration_layout_revision", REVISION)

func _ready() -> void:
	set_process(false)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.039, 0.027, 0.97)
	box.border_color = Color("8a6336")
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", box)
	visibility_changed.connect(_invalidate_layout)
	_bind_geometry()
	# Inventory builds the presenter before its EquipmentPanel siblings.
	_bind_geometry.call_deferred()
	_invalidate_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_invalidate_layout()

func _watch(node: Object, signal_name: StringName) -> void:
	if not is_instance_valid(node) or not node.has_signal(signal_name):
		return
	var callback := Callable(self, "_invalidate_layout")
	if not node.is_connected(signal_name, callback):
		node.connect(signal_name, callback)
		_connections.append([weakref(node), signal_name])

func _bind_geometry() -> void:
	var owner := get_parent() as Control
	if owner == null:
		return
	_watch(owner, &"item_rect_changed")
	_watch(owner, &"visibility_changed")
	var ancestor := owner.get_parent()
	while ancestor != null:
		if ancestor is Control:
			_watch(ancestor, &"item_rect_changed")
		ancestor = ancestor.get_parent()
	_watch(get_viewport(), &"size_changed")
	_watch(title_label, &"theme_changed")
	_watch(detail_label, &"theme_changed")
	for node: Node in owner.find_children("*", "ScrollContainer", true, false):
		_watch(node, &"item_rect_changed")
	# Watch only authored geometric dependencies, never all 100 inventory cells.
	for path: String in [
		"BagPanel", "BagPanel/InventoryScroll", "EquipmentPanel",
		"StashSection", "StashSection/StashScroll", "BagSection", "BagSection/BagScroll",
		"DetailPanel", "DetailPanel/DetailPanelDecoration", "DetailPanel/DetailTitle",
	]:
		var node := owner.get_node_or_null(NodePath(path)) as Control
		if node != null:
			_watch(node, &"item_rect_changed")
			_watch(node, &"visibility_changed")
	var equipment := owner.get_node_or_null("EquipmentPanel")
	if equipment != null:
		for child: Node in equipment.find_children("*", "Control", true, false):
			if child is BaseButton or str(child.name).begins_with("EquipmentHolder_"):
				_watch(child, &"item_rect_changed")
	# Owners differ; use their existing named action references when present.
	for property: Dictionary in owner.get_property_list():
		if str(property.name) in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
			var node: Variant = owner.get(str(property.name))
			if node is Control:
				_watch(node, &"item_rect_changed")
				_watch(node, &"visibility_changed")

func _exit_tree() -> void:
	for connection: Array in _connections:
		var node: Object = (connection[0] as WeakRef).get_ref()
		var callback := Callable(self, "_invalidate_layout")
		if is_instance_valid(node) and node.is_connected(connection[1], callback):
			node.disconnect(connection[1], callback)
	_connections.clear()
	_queued = false

static func _item_title(item: Dictionary, instance: Dictionary) -> String:
	return NameStyle.display_name(item, instance)

func _set_name_style(item: Dictionary, instance: Dictionary = {}) -> void:
	_name_style = NameStyle.describe(item, instance)
	_title_color = _name_style["color"]
	title_label.add_theme_color_override("font_color", _title_color)

func _reset_name_style(message: bool = false) -> void:
	_name_style.clear()
	_title_color = NameStyle.MESSAGE_COLOR if message else NameStyle.DEFAULT_COLOR
	title_label.add_theme_color_override("font_color", _title_color)


func show_item(item: Dictionary, instance: Dictionary = {}, context: Dictionary = {}) -> void:
	if item.is_empty():
		hide_detail()
		return
	_set_name_style(item, instance)
	_set_content(_item_title(item, instance), Formatter.format_item(item, instance, context), context, false)

func show_multi(count: int, context: Dictionary = {}) -> void:
	if count <= 0:
		hide_detail()
		return
	_reset_name_style()
	_set_content("已选择 %d 件物品" % count, "多选状态下不可直接穿戴。", context, false)

func show_text(title: String, body: String, context: Dictionary = {}) -> void:
	var item: Variant = context.get("rarity_item", {})
	var instance: Variant = context.get("rarity_instance", {})
	if item is Dictionary and not (item as Dictionary).is_empty():
		_set_name_style(item, instance if instance is Dictionary else {})
	else:
		_reset_name_style()
	_set_content(title, body, context, false)

func show_message(message: String, context: Dictionary = {}) -> void:
	if message.is_empty():
		hide_detail()
		return
	_reset_name_style(true)
	_set_content("提示", message, context, true)

func _set_content(title: String, body: String, context: Dictionary, message: bool) -> void:
	_content_epoch += 1
	_message_active = message
	_context = context.duplicate()
	_title_source = title.strip_edges()
	if _title_source.is_empty():
		_title_source = "提示" if message else "未知物品"
	_body_source = body
	title_label.text = _title_source
	detail_label.text = _body_source
	title_label.add_theme_color_override("font_color", _title_color)
	title_label.show()
	detail_label.show()
	title_label.visible_characters = -1
	detail_label.visible_characters = -1
	detail_label.scroll_active = false
	visible = true
	_layout_key.clear()
	# Synchronous shaping is available in the current Godot branch. The deferred
	# coalesced pass also catches the owner's calibration/visibility transaction.
	if is_inside_tree():
		_relayout()
	_invalidate_layout()

func hide_detail() -> void:
	_content_epoch += 1
	_message_active = false
	_layout_ok = false
	_context.clear()
	_reset_name_style()
	_layout_key.clear()
	_title_source = ""
	_body_source = ""
	title_label.text = ""
	detail_label.text = ""
	visible = false

func is_message_active() -> bool:
	return _message_active and visible

func content_epoch() -> int:
	return _content_epoch

func debug_layout_valid() -> bool:
	return _layout_ok

func debug_layout_snapshot() -> Dictionary:
	return {
		"valid": _layout_ok, "error": _layout_error, "layouts": _layout_count, "density": _r2_density,
		"name_style": _name_style.duplicate(), "title_color": title_label.get_theme_color("font_color"),
		"title": title_label.text, "body": detail_label.get_parsed_text(),
		"rect": Rect2(position, size), "title_rect": Rect2(title_label.position, title_label.size),
		"body_rect": Rect2(detail_label.position, detail_label.size),
		"body_content_height": detail_label.get_content_height(),
		"scroll_active": detail_label.scroll_active, "epoch": _content_epoch,
	}

func _invalidate_layout() -> void:
	if _laying_out or _queued or not is_inside_tree():
		return
	_layout_key.clear()
	_queued = true
	_flush_layout.call_deferred()

func _flush_layout() -> void:
	_queued = false
	if is_inside_tree() and is_visible_in_tree():
		_relayout()

func _measure_at(width: float, margin: float = MARGIN, pad: float = MEASURE_PAD) -> Vector2:
	var text_width := floorf(width - margin * 2.0)
	title_label.size = Vector2(text_width, 1.0)
	# Label's own shaped minimum includes CJK fallback metrics and wrapped lines.
	var title_height := ceilf(title_label.get_minimum_size().y) + pad
	detail_label.size = Vector2(text_width, 1.0)
	# Read the actual RichTextLabel (including BBCode, bold and fallback fonts).
	var body_height := ceilf(float(detail_label.get_content_height())) + pad
	return Vector2(maxf(26.0, title_height), maxf(20.0, body_height))

func _relayout() -> void:
	if _laying_out or not visible or not is_inside_tree():
		return
	var owner := get_parent() as Control
	if owner == null or not owner.has_method("_ui_detail_region"):
		return
	var spec: Dictionary = owner.call("_ui_detail_region", _context)
	var region: Rect2 = spec.get("region", Rect2())
	var side := str(spec.get("side", "center"))
	var expanded: Rect2 = spec.get("expanded_region", region)
	var key: Array = [region, expanded, side, _title_source, _body_source]
	if key == _layout_key:
		return
	_layout_key = key
	_layout_count += 1
	_laying_out = true
	_layout_error = ""
	_layout_ok = false
	if region.size.x < 100.0 or region.size.y < 80.0:
		_fail_layout("NO_SPACE")
		return
	var chosen_width := 0.0
	var chosen_height := 0.0
	var measured := Vector2.ZERO
	var chosen_margin := MARGIN
	var chosen_gap := TITLE_GAP
	_r2_density = "normal"
	# All candidates use the owner's existing safe region; do not enlarge frames.
	var regions: Array[Rect2] = [region]
	if expanded.has_area() and expanded != region:
		regions.append(expanded)
	for candidate_region: Rect2 in regions:
		var upper_width := floorf(minf(MAX_WIDTH, minf(candidate_region.size.x, candidate_region.size.y / PORTRAIT_RATIO)))
		# Keep normal spacing where it fits. Compact spacing is a bounded fallback.
		for density in range(2):
			var margin := MARGIN if density == 0 else COMPACT_MARGIN
			var gap := TITLE_GAP if density == 0 else COMPACT_TITLE_GAP
			var pad := MEASURE_PAD if density == 0 else COMPACT_MEASURE_PAD
			var width := minf(PREFERRED_WIDTH, upper_width)
			if width < 100.0:
				continue
			while width <= upper_width:
				var extent := _measure_at(width, margin, pad)
				var height := maxf(ceilf(width * PORTRAIT_RATIO), margin * 2.0 + extent.x + gap + extent.y)
				if height <= floorf(candidate_region.size.y):
					chosen_width = width
					chosen_height = height
					measured = extent
					chosen_margin = margin
					chosen_gap = gap
					_r2_density = "normal" if density == 0 else "compact"
					region = candidate_region
					break
				if width >= upper_width:
					break
				width = minf(upper_width, width + 12.0)
			if chosen_width > 0.0:
				break
		if chosen_width > 0.0:
			break
	if chosen_width <= 0.0:
		# An impossible layout remains an explicit release-blocking error. Never
		# truncate descriptions, restore scrolling or silently shrink typography.
		_fail_layout("CONTENT_OVERFLOW")
		return
	var fitted := Dock.fit_rect(region, Vector2(chosen_width, chosen_height), side)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = fitted.position.round()
	size = fitted.size
	var text_width := chosen_width - chosen_margin * 2.0
	title_label.position = Vector2(chosen_margin, chosen_margin)
	title_label.size = Vector2(text_width, measured.x)
	detail_label.position = Vector2(chosen_margin, chosen_margin + measured.x + chosen_gap)
	detail_label.size = Vector2(text_width, chosen_height - chosen_margin * 2.0 - measured.x - chosen_gap)
	_layout_ok = (
		float(detail_label.get_content_height()) <= detail_label.size.y
		and float(detail_label.get_content_width()) <= detail_label.size.x + 1.0
		and title_label.get_minimum_size().y <= title_label.size.y
		and not title_label.text.strip_edges().is_empty()
		and region.grow(1.0).encloses(Rect2(position, size))
	)
	if not _layout_ok:
		_fail_layout("POST_LAYOUT_OVERFLOW")
		return
	modulate.a = 1.0
	title_label.modulate = Color.WHITE
	title_label.self_modulate = Color.WHITE
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock_error_reported = false
	_laying_out = false

func _fail_layout(reason: String) -> void:
	_layout_error = reason
	_layout_ok = false
	modulate.a = 0.0
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _dock_error_reported and not _test_suppress_expected_layout_error:
		push_error("HC_UI6_DETAIL_%s: %s" % [reason, _title_source])
		_dock_error_reported = true
	_laying_out = false
