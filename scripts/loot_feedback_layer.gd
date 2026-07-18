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
	toast_container.position = Vector2(460, 108)
	toast_container.size = Vector2(360, 150)
	toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_container)


func _build_rare_banner() -> void:
	rare_banner = Panel.new()
	rare_banner.name = "RareDropBanner"
	rare_banner.position = Vector2(370, 104)
	rare_banner.size = Vector2(540, 82)
	rare_banner.theme_type_variation = "GothicLootRareBanner"
	rare_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rare_banner.visible = false
	rare_banner.set_meta("stable_id", "loot.feedback.rare_drop")
	add_child(rare_banner)
	rare_title = Label.new()
	rare_title.name = "RareTitle"
	rare_title.position = Vector2(44, 10)
	rare_title.size = Vector2(452, 32)
	rare_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rare_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rare_title.add_theme_font_size_override("font_size", 20)
	rare_title.add_theme_color_override("font_color", Color("ffd27c"))
	rare_banner.add_child(rare_title)
	rare_detail = Label.new()
	rare_detail.name = "RareDetail"
	rare_detail.position = Vector2(44, 42)
	rare_detail.size = Vector2(452, 22)
	rare_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rare_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rare_detail.theme_type_variation = "GothicMutedLabel"
	rare_detail.add_theme_font_size_override("font_size", 12)
	rare_banner.add_child(rare_detail)


func _build_failure_notice() -> void:
	failure_panel = Panel.new()
	failure_panel.name = "PickupFailure"
	failure_panel.position = Vector2(28, 122)
	failure_panel.size = Vector2(360, 58)
	failure_panel.theme_type_variation = "GothicLootErrorPanel"
	failure_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	failure_panel.visible = false
	failure_panel.set_meta("stable_id", "loot.feedback.inventory_full")
	add_child(failure_panel)
	failure_label = Label.new()
	failure_label.name = "FailureLabel"
	failure_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	failure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	failure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	failure_label.add_theme_font_size_override("font_size", 15)
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


func clear_feedback() -> void:
	toast_entries.clear()
	_rebuild_toasts()
	rare_remaining = 0.0
	failure_remaining = 0.0
	rare_banner.hide()
	failure_panel.hide()


func _show_pickup_success(event: Dictionary) -> void:
	var entry := event.duplicate(true)
	entry["remaining"] = maxf(0.5, float(event.get("duration", DEFAULT_DURATION)))
	toast_entries.push_front(entry)
	if toast_entries.size() > MAX_TOASTS:
		toast_entries.resize(MAX_TOASTS)
	_rebuild_toasts()


func _show_rare_drop(event: Dictionary) -> void:
	var item_name := str(event.get("item_name", "珍稀物品"))
	var source_name := str(event.get("source_name", ""))
	var title_prefix := "Boss 掉落" if bool(event.get("source_is_boss", false)) else "珍稀掉落"
	rare_title.text = "%s · %s" % [title_prefix, item_name]
	rare_detail.text = str(event.get("message", "来自 %s" % source_name if not source_name.is_empty() else "高价值物品已经出现"))
	rare_remaining = maxf(1.0, float(event.get("duration", 4.0)))
	rare_banner.show()


func _show_pickup_failure(event: Dictionary) -> void:
	var item_name := str(event.get("item_name", "物品"))
	var reason := str(event.get("reason", "当前无法拾取"))
	failure_label.text = "%s · %s" % [reason, item_name]
	failure_remaining = maxf(1.0, float(event.get("duration", 3.0)))
	failure_panel.show()


func _rebuild_toasts() -> void:
	for child: Node in toast_container.get_children():
		toast_container.remove_child(child)
		child.queue_free()
	for index in range(toast_entries.size()):
		var entry: Dictionary = toast_entries[index]
		var panel := Panel.new()
		panel.name = "PickupToast%d" % (index + 1)
		panel.position = Vector2(0, index * 48)
		panel.size = Vector2(360, 42)
		panel.theme_type_variation = "GothicLootToastPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_meta("stable_id", "loot.feedback.normal")
		toast_container.add_child(panel)
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		var item_name := str(entry.get("item_name", "物品"))
		var count := maxi(1, int(entry.get("count", 1)))
		label.text = "获得　%s%s" % [item_name, " ×%d" % count if count > 1 else ""]
		label.add_theme_color_override("font_color", KIND_COLORS.get(str(entry.get("item_kind", "material")), Color("dfccb0")))
		panel.add_child(label)
