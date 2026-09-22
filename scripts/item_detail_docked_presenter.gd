class_name ItemDetailDockedPresenter
extends Panel

## HC-UI6: content is owned by the existing formatter; this class owns layout only.
## No per-frame poll, no scrollbars, no BBCode stripping, no truncated item title.
const NameStyle := preload("res://scripts/ui_item_name_style.gd")
const Formatter := preload("res://scripts/item_detail_presenter.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const TITLE_SIZE := 20
const BODY_SIZE := 14
const MARGIN := 18.0
const MIN_WIDTH := 100.0
const TITLE_GAP := 12.0
const MEASURE_PAD := 4.0
const WIDTH_STEPS := 12
const REVISION := 10
const ShopSpace := preload("res://scripts/ui_shop_detail_space.gd")
const TouchScroll := preload("res://scripts/touch_scroll_support.gd")
const AttributeHelp := preload("res://scripts/item_attribute_help.gd")
var attribute_help: Node

var title_label: Label
var affix_marker: Label
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
var _r2_density := "comfortable"
var _r3_spec: Dictionary = {}
var _r3_session_epoch := -1
# Disabled unless an isolated diagnostic scene opts in; never serialized.
var _r32_capture_candidates := false
var _r32_candidates: Array = []
var _r33_syncing_caption := false
var _r33_exiting := false

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
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.clip_text = false
	title_label.visible_characters = -1
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_color", Color("f2c783"))
	_mark_runtime(title_label)
	add_child(title_label)
	affix_marker = Label.new()
	affix_marker.name = "AffixMarker"
	affix_marker.text = "★"
	affix_marker.add_theme_font_size_override("font_size", TITLE_SIZE)
	affix_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	affix_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_runtime(affix_marker)
	add_child(affix_marker)
	affix_marker.hide()
	detail_label = RichTextLabel.new()
	detail_label.name = "Body"
	detail_label.bbcode_enabled = true
	detail_label.threaded = false
	detail_label.fit_content = false
	detail_label.scroll_active = false
	var scroll_bar := detail_label.get_v_scroll_bar()
	scroll_bar.visibility_changed.connect(func() -> void:
		if scroll_bar.visible:
			scroll_bar.hide()
	)
	scroll_bar.hide()
	detail_label.scroll_following = false
	detail_label.selection_enabled = false
	detail_label.context_menu_enabled = false
	detail_label.visible_characters = -1
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	# Attribute links are functional input, not a blank tap that clears selection.
	detail_label.set_meta("ui_dismiss_protected", true)
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
	attribute_help = AttributeHelp.attach(self, detail_label)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.039, 0.027, 0.97)
	box.border_color = Color("8a6336")
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", box)
	visibility_changed.connect(_invalidate_layout)
	_bind_geometry()
	# Register while short/empty too: overflow is decided later by layout.
	var touch_support := TouchScroll.attach_tree(self)
	if touch_support != null:
		touch_support.register_control(detail_label)
	# Inventory builds the presenter before its EquipmentPanel siblings.
	_bind_geometry.call_deferred()
	_invalidate_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_r33_exiting = false
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
	_r33_exiting = true
	_r33_sync_caption()
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
	NameStyle.apply_label_style(title_label, _name_style)
	NameStyle.apply_label_style(affix_marker, _name_style)

func _reset_name_style(message: bool = false) -> void:
	_name_style.clear()
	_title_color = NameStyle.MESSAGE_COLOR if message else NameStyle.DEFAULT_COLOR
	NameStyle.apply_label_style(title_label, {}, _title_color)
	NameStyle.apply_label_style(affix_marker, {}, _title_color)


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
	if attribute_help != null: attribute_help.dismiss()
	var parent := get_parent() as Control
	var session := parent.get_node_or_null("R3SelectionLifecycle") if parent != null else null
	if session != null:
		if not parent.is_visible_in_tree():
			return # an old result must not repopulate a closed detail panel
		_r3_session_epoch = int(session.get("epoch"))
	_content_epoch += 1
	_message_active = message
	_context = context.duplicate()
	_title_source = title.strip_edges()
	if _title_source.is_empty():
		_title_source = "提示" if message else "未知物品"
	_body_source = body if message else AttributeHelp.decorate(body)
	_sync_title()
	detail_label.text = _body_source
	detail_label.get_v_scroll_bar().value = 0.0
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
	if attribute_help != null: attribute_help.dismiss()
	_content_epoch += 1
	_message_active = false
	_layout_ok = false
	_context.clear()
	_reset_name_style()
	_layout_key.clear()
	_title_source = ""
	_body_source = ""
	title_label.text = ""
	affix_marker.hide()
	detail_label.text = ""
	visible = false
	_r33_sync_caption()

func is_message_active() -> bool:
	return _message_active and visible

func content_epoch() -> int:
	return _content_epoch

func debug_layout_valid() -> bool:
	return _layout_ok

func debug_layout_snapshot() -> Dictionary:
	return {
		"valid": _layout_ok, "error": _layout_error, "layouts": _layout_count, "density": _r2_density,
		"margin": MARGIN, "title_gap": TITLE_GAP, "space_spec": _r3_spec.duplicate(),
		"candidate_trace": _r32_candidates.duplicate(true),
		"source_title": _title_source, "source_body": _body_source,
		"name_style": _name_style.duplicate(), "title_color": title_label.get_theme_color("font_color"),
		"title": title_label.text, "body": detail_label.get_parsed_text(),
		"rect": Rect2(position, size), "title_rect": Rect2(title_label.position, title_label.size),
		"body_rect": Rect2(detail_label.position, detail_label.size),
		"body_content_height": detail_label.get_content_height(),
		"scroll_active": detail_label.scroll_active, "epoch": _content_epoch,
	}

func _r33_sync_caption() -> void:
	if _r33_syncing_caption:
		return
	var owner := get_parent() as Control
	if owner == null:
		return
	_r33_syncing_caption = true
	var active := not _r33_exiting and is_inside_tree() and is_visible_in_tree() and not _title_source.is_empty()
	ShopSpace.sync_section_caption(owner, active)
	_r33_syncing_caption = false

func _invalidate_layout() -> void:
	if _r33_exiting or _r33_syncing_caption:
		return
	_r33_sync_caption()
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

func _sync_title() -> void:
	affix_marker.visible = _title_source.begins_with("★")
	title_label.text = _title_source.trim_prefix("★") if affix_marker.visible else _title_source

func _title_required_width() -> float:
	var marker_width := affix_marker.get_minimum_size().x + 2.0 if affix_marker.visible else 0.0
	return ceilf(title_label.get_minimum_size().x + 2.0 * (MARGIN + marker_width))

func _place_affix_marker() -> void:
	# The plain name stays centered. The marker is separate from its alignment.
	var name_width := title_label.get_minimum_size().x
	var marker_width := affix_marker.get_minimum_size().x
	title_label.position.x = (size.x - name_width) * 0.5
	title_label.size.x = name_width
	affix_marker.position = Vector2((size.x - name_width) * 0.5 - marker_width - 2.0, MARGIN)
	affix_marker.size = Vector2(marker_width, title_label.size.y)

func _center_body_block() -> void:
	# A long title can widen the card beyond its body. Keep each paragraph's
	# original left alignment while centering the entire shaped content block.
	# Round up with one pixel of breathing room to retain the measured wrapping.
	var body_width := minf(detail_label.size.x, ceilf(float(detail_label.get_content_width())) + 1.0)
	detail_label.size.x = maxf(1.0, body_width)
	# Re-read after the final width is applied. Center the longest actual line,
	# excluding the extra wrap-safety pixel of the RichTextLabel content box.
	var longest_line_width := float(detail_label.get_content_width())
	detail_label.position.x = (size.x - longest_line_width) * 0.5

func _relayout() -> void:
	if _laying_out or not visible or not is_inside_tree():
		return
	var owner := get_parent() as Control
	if owner == null or not owner.has_method("_ui_detail_region"):
		return
	var session := owner.get_node_or_null("R3SelectionLifecycle")
	if session != null and not bool(session.call("allows_presentation", _r3_session_epoch)):
		hide_detail()
		return
	# Reflowing the shop action band emits geometry signals. Ignore those while
	# solving, then key the final geometry. No perpetual deferred-layout loop.
	_laying_out = true
	_r33_sync_caption()
	var spec: Dictionary = owner.call("_ui_detail_region", _context)
	var region: Rect2 = spec.get("region", Rect2())
	var expanded: Rect2 = spec.get("expanded_region", region)
	var shop := str(spec.get("kind", "")) == "shop"
	var side := str(spec.get("side", "center"))
	var key: Array = [region, expanded, side, shop, spec.get("screen_scale", Vector2.ONE), _title_source, _body_source]
	if key == _layout_key:
		_laying_out = false
		return
	_layout_key = key
	_r3_spec = spec.duplicate()
	_layout_count += 1
	_layout_error = ""
	_layout_ok = false
	_r2_density = "comfortable"
	_r32_candidates.clear()
	var regions: Array[Rect2] = [region]
	if expanded.has_area() and expanded != region:
		regions.append(expanded)
	_sync_title()
	detail_label.text = _body_source
	var title_width := _title_required_width()
	var chosen: Dictionary = {}
	for candidate: Rect2 in regions:
		var upper := floorf(candidate.size.x)
		if upper < maxf(MIN_WIDTH, title_width) or candidate.size.y < 80.0:
			continue
		var lower := minf(maxf(160.0, title_width), upper)
		var best_cost := INF
		# Fit the actual shaped content. Short items no longer inherit an
		# artificial portrait-height floor; extra properties grow the card.
		for n in range(WIDTH_STEPS + 1):
			var trial_width := floorf(lerpf(lower, upper, float(n) / float(WIDTH_STEPS)))
			var trial_extent := _measure_at(trial_width)
			var natural := MARGIN * 2.0 + trial_extent.x + TITLE_GAP + trial_extent.y
			var trial_height := ceilf(natural)
			if _r32_capture_candidates:
				_r32_candidates.append({
					"region": candidate, "width": trial_width,
					"height": trial_height, "available_height": floorf(candidate.size.y),
					"title_measured_h": trial_extent.x, "body_measured_h": trial_extent.y,
					"natural_height": natural, "requested_text_width": floorf(trial_width - MARGIN * 2.0),
					"actual_title_width": title_label.size.x,
					"actual_body_width": detail_label.size.x,
					"body_content_width": detail_label.get_content_width(),
					"body_line_count": detail_label.get_line_count(),
					"fits_height": trial_height <= floorf(candidate.size.y),
				})
			if trial_height > floorf(candidate.size.y):
				continue
			var cost := trial_width * trial_height
			if cost < best_cost:
				best_cost = cost
				chosen = {"width": trial_width, "height": trial_height, "region": candidate}
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		# Ninth-section scroll contract: after exhausting every legal layout
		# candidate, a body whose natural height still exceeds the dock falls
		# back to presenter-managed, BODY-ONLY vertical scrolling instead of
		# failing the whole detail. The title stays fixed at the top, the full
		# body text stays reachable by scrolling, scroll_active reports the
		# measured state honestly, and the region clearance still holds.
		var fallback: Rect2 = region
		if expanded.has_area() and expanded.get_area() > fallback.get_area():
			fallback = expanded
		var max_height := floorf(fallback.size.y)
		var max_width := floorf(fallback.size.x)
		var scroll_width := max_width
		if max_height < 80.0 or max_width < maxf(MIN_WIDTH, title_width):
			_fail_layout("SPACE_PLAN_REQUIRED")
			return
		var scroll_extent := _measure_at(scroll_width)
		var scroll_height := minf(ceilf(MARGIN * 2.0 + scroll_extent.x + TITLE_GAP + scroll_extent.y), max_height)
		scroll_height = minf(scroll_height, max_height)
		var fitted := Dock.fit_rect(fallback, Vector2(scroll_width, scroll_height), side)
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = fitted.position
		size = fitted.size
		region = fallback
		var text_width := scroll_width - 2.0 * MARGIN
		title_label.position = Vector2(MARGIN, MARGIN)
		title_label.size = Vector2(text_width, scroll_extent.x)
		_place_affix_marker()
		detail_label.position = Vector2(MARGIN, MARGIN + scroll_extent.x + TITLE_GAP)
		detail_label.size = Vector2(text_width, scroll_height - MARGIN * 2.0 - scroll_extent.x - TITLE_GAP)
		_center_body_block()
		detail_label.scroll_active = float(detail_label.get_content_height()) > detail_label.size.y + 0.5
		_layout_ok = (
			float(detail_label.get_content_width()) <= detail_label.size.x + 0.5
			and title_label.get_minimum_size().y <= title_label.size.y
			and not title_label.text.strip_edges().is_empty()
			and region.grow(0.05).encloses(Rect2(position, size))
			and detail_label.text == _body_source
		)
		for r: Rect2 in spec.get("protected", []):
			if Rect2(position, size).intersects(r):
				_layout_ok = false
		if not _layout_ok:
			_fail_layout("POST_LAYOUT_OVERFLOW")
			return
		modulate.a = 1.0
		title_label.modulate = Color.WHITE
		title_label.self_modulate = Color.WHITE
		detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_dock_error_reported = false
		_laying_out = false
		return
	var width: float = chosen.width
	var height: float = chosen.height
	region = chosen.region
	# Candidate measurements mutate the controls. Re-shape the actual winner.
	var extent := _measure_at(width)
	var fitted := Dock.fit_rect(region, Vector2(width, height), side)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = fitted.position
	size = fitted.size
	var text_width := width - 2.0 * MARGIN
	title_label.position = Vector2(MARGIN, MARGIN)
	title_label.size = Vector2(text_width, extent.x)
	_place_affix_marker()
	detail_label.position = Vector2(MARGIN, MARGIN + extent.x + TITLE_GAP)
	detail_label.size = Vector2(text_width, height - MARGIN * 2.0 - extent.x - TITLE_GAP)
	_center_body_block()
	_layout_ok = (
		float(detail_label.get_content_height()) <= detail_label.size.y
		and float(detail_label.get_content_width()) <= detail_label.size.x + 0.5
		and title_label.get_minimum_size().y <= title_label.size.y
		and not title_label.text.strip_edges().is_empty()
		and region.grow(0.05).encloses(Rect2(position, size))
	)
	for r: Rect2 in spec.get("protected", []):
		if Rect2(position, size).intersects(r):
			_layout_ok = false
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
	var available: Rect2 = _r3_spec.get("region", Rect2())
	if available.size.x >= 100.0 and available.size.y >= 80.0:
		position = available.position
		size = available.size
		title_label.position = Vector2(MARGIN, MARGIN)
		title_label.size = Vector2(maxf(1.0, size.x - MARGIN * 2.0), 30.0)
		detail_label.position = Vector2(MARGIN, MARGIN + 34.0)
		detail_label.size = Vector2(maxf(1.0, size.x - MARGIN * 2.0), maxf(1.0, size.y - MARGIN * 2.0 - 34.0))
		detail_label.text = "说明区空间不足。"
		modulate.a = 1.0
	else:
		modulate.a = 0.0
	# This error surface is NOT a successful item detail. All normal catalog
	# cases must pass original body equality + geometry gates before release.
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _dock_error_reported and not _test_suppress_expected_layout_error:
		push_error("HC_UI6_DETAIL_%s: %s" % [reason, _title_source])
		_dock_error_reported = true
	_laying_out = false

