class_name PlayerNoticePresenter
extends Control

## Single central player-notice layer (UNIFIED-PLAYER-NOTICE R2).
##
## Owns the only transient global notice visuals: one fixed geometry
## (same as the former error channel), one font size, priority preemption,
## dedupe and a bounded queue. Business layers never build their own notice
## labels; they call HUD show_notice / show_item_notice /
## present_action_result, which normalize through UIPlayerNotice.
##
## Item names inside a notice resolve through UIItemNameStyle so the colors
## and outlines match the rest of the item system exactly.

const NoticeScript := preload("res://scripts/ui_player_notice.gd")
const NameStyleScript := preload("res://scripts/ui_item_name_style.gd")

const NOTICE_TEXT_COLOR := Color("ffd06f")
const NOTICE_FONT_SIZE := 22

var prefix_label: Label
var item_label: Label
var suffix_label: Label

var _active: Dictionary = {}
var _queue: Array = []
var _remaining := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 360
	offset_top = 132
	offset_right = -360
	offset_bottom = 172
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 4096
	visible = false


func _ready() -> void:
	var center := CenterContainer.new()
	center.name = "NoticeCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var row := HBoxContainer.new()
	row.name = "NoticeRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	prefix_label = Label.new()
	prefix_label.name = "ErrorNotice"
	_apply_plain_style(prefix_label)
	row.add_child(prefix_label)

	item_label = Label.new()
	item_label.name = "NoticeItemName"
	_apply_plain_style(item_label)
	item_label.visible = false
	row.add_child(item_label)

	suffix_label = Label.new()
	suffix_label.name = "NoticeSuffix"
	_apply_plain_style(suffix_label)
	suffix_label.visible = false
	row.add_child(suffix_label)


func _apply_plain_style(label: Label) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", NOTICE_FONT_SIZE)
	label.add_theme_color_override("font_color", NOTICE_TEXT_COLOR)
	# The overlay itself carries the absolute z; text children stay relative
	# to it so the whole layer shares one z context.
	label.z_index = 0


## Present one normalized notice. Same dedupe_key refreshes the visible or
## queued notice in place; higher priority preempts the visible notice;
## lower/equal priority joins the bounded queue.
func present(notice: Dictionary) -> void:
	var normalized := NoticeScript.normalize(notice)
	var key := str(normalized["dedupe_key"])

	# Same-key dedupe: refresh content and timer, never queue a duplicate.
	if not _active.is_empty() and str(_active["dedupe_key"]) == key:
		_active = normalized
		_render(normalized)
		_remaining = float(normalized["duration"])
		return
	for index in range(_queue.size()):
		if str(_queue[index]["dedupe_key"]) == key:
			if _active.is_empty() or int(normalized["priority"]) >= int(_active["priority"]):
				_queue.remove_at(index)
				_show(normalized)
				return
			_queue[index] = normalized
			return

	if _active.is_empty():
		_show(normalized)
		return

	if int(normalized["priority"]) >= int(_active["priority"]):
		# Equal or higher priority replaces the visible notice immediately
		# (latest wins on the error lane, R1 semantics); the displaced notice
		# is dropped, not re-shown later.
		_show(normalized)
		return

	_queue.append(normalized)
	while _queue.size() > NoticeScript.MAX_QUEUE:
		_drop_lowest_queued()


func _drop_lowest_queued() -> void:
	var lowest := 0
	for index in range(1, _queue.size()):
		if int(_queue[index]["priority"]) < int(_queue[lowest]["priority"]):
			lowest = index
	_queue.remove_at(lowest)


func _show(notice: Dictionary) -> void:
	_active = notice
	_render(notice)
	_remaining = float(notice["duration"])
	visible = true


func _render(notice: Dictionary) -> void:
	var segments: Array = notice.get("segments", [])
	if segments.is_empty():
		_render_plain(str(notice.get("message", "")))
		return
	# Mixed format: at most one item segment; the notice message (when the
	# caller supplied one, e.g. ActionResult "锻造成功") plus the text
	# segments form the prefix, the item renders in its own style, and any
	# trailing text becomes the suffix so the row reads as one line.
	var prefix := str(notice.get("message", ""))
	var suffix := ""
	var rendered := false
	for segment: Dictionary in segments:
		if str(segment.get("type", "")) == "item" and not rendered:
			_render_item(segment)
			rendered = true
		elif rendered:
			suffix += str(segment.get("text", ""))
		else:
			prefix += str(segment.get("text", ""))
	_set_text(prefix_label, prefix)
	suffix_label.visible = not suffix.is_empty()
	_set_text(suffix_label, suffix)
	if not rendered:
		# Item style data missing: fall back to the notice message.
		_render_item({})


func _render_plain(message: String) -> void:
	item_label.visible = false
	suffix_label.visible = false
	_set_text(prefix_label, message)


func _render_item(segment: Dictionary) -> void:
	var item: Dictionary = segment.get("item", {})
	var instance: Dictionary = segment.get("instance", {})
	if item.is_empty():
		item_label.visible = false
		return
	var style := NameStyleScript.describe(item, instance)
	_set_text(item_label, str(style.get("name", "")))
	NameStyleScript.apply_label_style(item_label, style, NOTICE_TEXT_COLOR)
	item_label.visible = not str(style.get("name", "")).is_empty()


func _set_text(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	if _queue.is_empty():
		_clear()
		return
	# Next notice: highest priority first, oldest among equals.
	var next_index := 0
	for index in range(1, _queue.size()):
		if int(_queue[index]["priority"]) > int(_queue[next_index]["priority"]):
			next_index = index
	var next: Dictionary = _queue[next_index]
	_queue.remove_at(next_index)
	_show(next)


func _clear() -> void:
	_active = {}
	_remaining = 0.0
	visible = false
	if prefix_label != null:
		prefix_label.text = ""
	if item_label != null:
		item_label.text = ""
		item_label.visible = false
	if suffix_label != null:
		suffix_label.text = ""
		suffix_label.visible = false


## Test/inspection helpers.
func full_text() -> String:
	if prefix_label == null:
		return ""
	var text := prefix_label.text
	if item_label != null and item_label.visible:
		text += item_label.text
	if suffix_label != null and suffix_label.visible:
		text += suffix_label.text
	return text


func current_notice() -> Dictionary:
	return _active.duplicate()


func queue_size() -> int:
	return _queue.size()


func queue_dedupe_keys() -> Array:
	var keys: Array = []
	for notice: Dictionary in _queue:
		keys.append(str(notice["dedupe_key"]))
	return keys


func clear_for_test() -> void:
	_queue.clear()
	_clear()
