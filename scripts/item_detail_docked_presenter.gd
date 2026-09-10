class_name ItemDetailDockedPresenter
extends Panel

## Read-only presenter. Formatting remains in the existing, audited formatter.
## Explicit children (not a VBox minimum-size chain) guarantee that long text
## cannot push this panel outside the region or over a transaction button.
const Formatter := preload("res://scripts/item_detail_presenter.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const TITLE_SIZE := 20
const BODY_SIZE := 14
const MARGIN := 14.0
const MAX_WIDTH := 340.0
var title_label: Label
var detail_label: RichTextLabel
var _context: Dictionary = {}
var _layout_key: Array = []
var _message_active := false
var _content_epoch := 0
var _dock_error_reported := false
var _layout_ok := false
var _stripper := RegEx.new()

func _init() -> void:
	name = "ItemDetailPresenter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_meta("calibration_runtime_text", true)
	set_meta("calibration_layout_revision", 5)
	_stripper.compile("\\[[^\\]]+\\]")
	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.clip_text = true
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_color", Color("f2c783"))
	add_child(title_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "Body"
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.scroll_following = false
	detail_label.selection_enabled = false
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_label.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	detail_label.add_theme_color_override("default_color", Color("ddc9a9"))
	detail_label.set_meta("calibration_runtime_text", true)
	add_child(detail_label)
	visible = false

func _ready() -> void:
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.055, 0.039, 0.027, 0.97)
	surface.border_color = Color("8a6336")
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", surface)
	if visible:
		_relayout()

func show_item(item: Dictionary, instance: Dictionary = {}, context: Dictionary = {}) -> void:
	if item.is_empty():
		hide_detail()
		return
	_set_content(str(instance.get("name", item.get("name", "未知物品"))), Formatter.format_item(item, instance, context), context, false)

func show_multi(count: int, context: Dictionary = {}) -> void:
	if count <= 0:
		hide_detail()
		return
	_set_content("已选择 %d 件物品" % count, "多选状态下不可直接穿戴。", context, false)

func show_text(title: String, body: String, context: Dictionary = {}) -> void:
	_set_content(title, body, context, false)

func show_message(message: String, context: Dictionary = {}) -> void:
	if message.is_empty():
		hide_detail()
		return
	_set_content("提示", message, context, true)

func _set_content(title: String, body: String, context: Dictionary, message: bool) -> void:
	_content_epoch += 1
	_message_active = message
	title_label.text = title
	detail_label.text = body
	_context = context.duplicate()
	_layout_key.clear()
	detail_label.scroll_to_line(0)
	visible = not title.is_empty() or not body.is_empty()
	if is_inside_tree() and visible:
		_relayout()

func hide_detail() -> void:
	_content_epoch += 1
	_message_active = false
	_layout_ok = false
	_context.clear()
	_layout_key.clear()
	title_label.text = ""
	detail_label.text = ""
	visible = false

func is_message_active() -> bool:
	return _message_active and visible

func content_epoch() -> int:
	return _content_epoch

func debug_layout_valid() -> bool:
	return _layout_ok

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		# A small geometry key only; no empty-cell enumeration or raster search.
		_relayout()

func _relayout() -> void:
	var owner_control := get_parent() as Control
	if owner_control == null or not owner_control.has_method("_ui_detail_region"):
		return
	var spec: Dictionary = owner_control.call("_ui_detail_region", _context)
	var region: Rect2 = spec.get("region", Rect2())
	var side := str(spec.get("side", "center"))
	var key: Array = [region, side, title_label.text, detail_label.text]
	if key == _layout_key:
		return
	_layout_key = key
	_layout_ok = region.size.x >= 100.0 and region.size.y >= 80.0
	if not _layout_ok:
		modulate.a = 0.0
		detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not _dock_error_reported:
			_dock_error_reported = true
			push_error("UI_R5_DOCK_NO_SPACE: " + str(owner_control.name) + " " + str(region))
		return
	_dock_error_reported = false
	modulate.a = 1.0
	detail_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var title_font := title_label.get_theme_font("font")
	var body_font := detail_label.get_theme_font("normal_font")
	var plain_body := _stripper.sub(detail_label.text, "", true)
	var natural_width := title_font.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TITLE_SIZE).x
	for line: String in plain_body.split("\n"):
		natural_width = maxf(natural_width, body_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_SIZE).x)
	var width := minf(minf(MAX_WIDTH, region.size.x), maxf(160.0, natural_width + MARGIN * 2.0 + 12.0))
	var text_width := maxf(1.0, width - MARGIN * 2.0)
	var title_extent := title_font.get_multiline_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, TITLE_SIZE)
	# A very long name may wrap, but must always leave a usable body viewport.
	var title_height := clampf(title_extent.y, 26.0, minf(70.0, region.size.y * 0.35))
	var body_extent := body_font.get_multiline_string_size(plain_body, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, text_width - 12.0), BODY_SIZE)
	var header := MARGIN * 2.0 + title_height + 8.0
	var height := minf(region.size.y, header + maxf(28.0, body_extent.y + 12.0))
	var fitted := Dock.fit_rect(region, Vector2(width, height), side)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = fitted.position
	size = fitted.size
	title_label.position = Vector2(MARGIN, MARGIN)
	title_label.size = Vector2(text_width, title_height)
	detail_label.position = Vector2(MARGIN, MARGIN + title_height + 8.0)
	detail_label.size = Vector2(text_width, maxf(1.0, height - header))
