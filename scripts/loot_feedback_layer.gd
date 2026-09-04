class_name LootFeedbackLayer
extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

const CONTRACT_ID := "ui.loot.feedback.v1"
const MAX_TOASTS := 3
const DEFAULT_DURATION := 2.4
const KIND_COLORS := {
	"currency": Color("f3cb62"),
	"quest_item": Color("e99752"),
	"equipment": Color("91c7ef"),
	"skill_book": Color("c197ef"),
	"consumable": Color("8bcf8c"),
	"material": Color("d8b884"),
}

var toast_container: Control
var rare_banner: Panel
var rare_title: Label
var rare_detail: Label
var failure_panel: Panel
var failure_label: Label
var toast_entries: Array[Dictionary] = []
var toast_panels: Array[Panel] = []
var toast_labels: Array[Label] = []
var rare_remaining := 0.0
var failure_remaining := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = GothicUIThemeScript.build()
	_build_toasts()
	_build_rare_banner()
	_build_failure_notice()


func _process(delta: float) -> void:
	var changed := false
	for index in range(toast_entries.size() - 1, -1, -1):
		toast_entries[index]["remaining"] = maxf(0.0, float(toast_entries[index].get("remaining", 0.0)) - delta)
		if float(toast_entries[index].get("remaining", 0.0)) <= 0.0:
			toast_entries.remove_at(index)
			changed = true
	if changed:
		_rebuild_toasts()
	rare_remaining = maxf(0.0, rare_remaining - delta)
	failure_remaining = maxf(0.0, failure_remaining - delta)
	rare_banner.visible = rare_remaining > 0.0
	failure_panel.visible = failure_remaining > 0.0


func _build_toasts() -> void:
	toast_container = Control.new()
	toast_container.name = "PickupToastStack"
	toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_container)
	_layout_centered_control(toast_container, 280.0, 108.0, 102.0)
	for index in range(MAX_TOASTS):
		var panel := Panel.new()
		panel.name = "PickupToast%d" % (index + 1)
		panel.position.y = index * 34
		panel.size.y = 30
		panel.theme_type_variation = "GothicLootToastPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_meta("stable_id", "loot.feedback.normal")
		panel.hide()
		toast_container.add_child(panel)
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		panel.add_child(label)
		toast_panels.append(panel)
		toast_labels.append(label)


func _build_rare_banner() -> void:
	rare_banner = Panel.new()
	rare_banner.name = "RareDropBanner"
	rare_banner.theme_type_variation = "GothicLootRareBanner"
	rare_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rare_banner.visible = false
	rare_banner.set_meta("stable_id", "loot.feedback.rare_drop")
	add_child(rare_banner)
	_layout_centered_control(rare_banner, 360.0, 104.0, 56.0)
	rare_title = Label.new()
	rare_title.name = "RareTitle"
	rare_title.position = Vector2(12, 4)
	rare_title.size = Vector2(336, 26)
	rare_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rare_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rare_title.add_theme_font_size_override("font_size", 17)
	rare_title.add_theme_color_override("font_color", Color("ffd27c"))
	rare_banner.add_child(rare_title)
	rare_detail = Label.new()
	rare_detail.name = "RareDetail"
	rare_detail.position = Vector2(12, 30)
	rare_detail.size = Vector2(336, 18)
	rare_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rare_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rare_detail.theme_type_variation = "GothicMutedLabel"
	rare_detail.add_theme_font_size_override("font_size", 11)
	rare_banner.add_child(rare_detail)


func _build_failure_notice() -> void:
	failure_panel = Panel.new()
	failure_panel.name = "PickupFailure"
	failure_panel.theme_type_variation = "GothicLootErrorPanel"
	failure_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	failure_panel.visible = false
	failure_panel.set_meta("stable_id", "loot.feedback.inventory_full")
	add_child(failure_panel)
	_layout_centered_control(failure_panel, 220.0, 122.0, 36.0)
	failure_label = Label.new()
	failure_label.name = "FailureLabel"
	failure_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	failure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	failure_label.add_theme_font_size_override("font_size", 13)
	failure_label.add_theme_color_override("font_color", Color("efaa86"))
	failure_panel.add_child(failure_label)


func show_feedback(event: Dictionary) -> void:
	var event_type := str(event.get("event_type", "pickup_success"))
	match event_type:
		"rare_drop":
			_show_rare_drop(event)
		"pickup_failed":
			_show_pickup_failure(event)
		_:
			_show_pickup_success(event)


func show_feedback_batch(events: Array) -> void:
	var pickup_changed := false
	for raw_event: Variant in events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		if str(event.get("event_type", "pickup_success")) == "pickup_success":
			_show_pickup_success(event, false)
			pickup_changed = true
		else:
			show_feedback(event)
	if pickup_changed:
		_rebuild_toasts()


func clear_feedback() -> void:
	toast_entries.clear()
	_rebuild_toasts()
	rare_remaining = 0.0
	failure_remaining = 0.0
	rare_banner.hide()
	failure_panel.hide()


func _show_pickup_success(event: Dictionary, rebuild := true) -> void:
	var entry := event.duplicate(true)
	entry["remaining"] = maxf(0.5, float(event.get("duration", DEFAULT_DURATION)))
	toast_entries.push_front(entry)
	if toast_entries.size() > MAX_TOASTS:
		toast_entries.resize(MAX_TOASTS)
	if rebuild:
		_rebuild_toasts()


func _show_rare_drop(event: Dictionary) -> void:
	var item_name := str(event.get("item_name", "珍稀物品"))
	var source_name := str(event.get("source_name", ""))
	var title_prefix := "Boss 掉落" if bool(event.get("source_is_boss", false)) else "珍稀掉落"
	rare_title.text = "%s · %s" % [title_prefix, item_name]
	rare_detail.text = str(event.get("message", "来自 %s" % source_name if not source_name.is_empty() else "高价值物品已经出现"))
	var banner_width := clampi(
		maxi(rare_title.text.length() * 17 + 30, rare_detail.text.length() * 12 + 30),
		240,
		420
	)
	_set_centered_width(rare_banner, banner_width)
	rare_title.size.x = banner_width - 24
	rare_detail.size.x = banner_width - 24
	rare_remaining = maxf(1.0, float(event.get("duration", 4.0)))
	rare_banner.show()


func _show_pickup_failure(event: Dictionary) -> void:
	var item_name := str(event.get("item_name", "物品"))
	var reason := str(event.get("reason", "当前无法拾取"))
	failure_label.text = "%s · %s" % [reason, item_name]
	_set_centered_width(failure_panel, clampi(failure_label.text.length() * 15 + 28, 150, 320))
	failure_remaining = maxf(1.0, float(event.get("duration", 3.0)))
	failure_panel.show()


func _layout_centered_control(control: Control, width: float, top: float, height: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	_set_centered_width(control, width)
	control.offset_top = top
	control.offset_bottom = top + height


func _set_centered_width(control: Control, width: float) -> void:
	var half_width := maxf(1.0, width) * 0.5
	control.offset_left = -half_width
	control.offset_right = half_width


func _rebuild_toasts() -> void:
	for index in range(MAX_TOASTS):
		var panel: Panel = toast_panels[index]
		if index >= toast_entries.size():
			panel.hide()
			continue
		var entry: Dictionary = toast_entries[index]
		var label: Label = toast_labels[index]
		var item_name := str(entry.get("item_name", "物品"))
		var count := maxi(1, int(entry.get("count", 1)))
		var display_text := "获得　%s%s" % [item_name, " ×%d" % count if count > 1 else ""]
		var toast_width := clampi(display_text.length() * 15 + 22, 120, 280)
		panel.position.x = (toast_container.size.x - toast_width) * 0.5
		panel.size.x = toast_width
		label.text = display_text
		label.add_theme_color_override("font_color", KIND_COLORS.get(str(entry.get("item_kind", "material")), Color("dfccb0")))
		panel.show()
