class_name GothicConfirmationPanel
extends Control

signal confirmed(request: Dictionary)
signal cancelled(request: Dictionary)

const CONTRACT_ID := "ui.confirmation.dialog.v1"
const STABLE_ID := "ui.confirmation.dialog"
const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")

var modal_frame: Panel
var inner_fill: Control
var title_label: Label
var message_label: Label
var cancel_button: Button
var confirm_button: Button
var current_request: Dictionary = {}


func _ready() -> void:
	name = "GothicConfirmationPanel"
	set_meta("stable_id", STABLE_ID)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	_build_interface()
	UIRuntimeLayoutOverridesScript.apply_profile(self, "confirmation_dialog")
	hide()


func _build_interface() -> void:
	var blocker := ColorRect.new()
	blocker.name = "Blocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(0.012, 0.011, 0.012, 0.78)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	modal_frame = Panel.new()
	modal_frame.name = "ModalFrame"
	modal_frame.set_anchors_preset(Control.PRESET_CENTER)
	modal_frame.position = Vector2(-280, -152)
	modal_frame.size = Vector2(560, 304)
	modal_frame.theme_type_variation = "GothicInsetFrame"
	modal_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_frame.clip_contents = true
	add_child(modal_frame)

	inner_fill = GothicFrameFactoryScript.add_inset_fill(modal_frame)

	var title_bar := Panel.new()
	title_bar.name = "TitleBar"
	title_bar.position = Vector2(70, 20)
	title_bar.size = Vector2(420, 58)
	title_bar.theme_type_variation = "GothicTitleBar"
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_frame.add_child(title_bar)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.position = Vector2(92, 29)
	title_label.size = Vector2(376, 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", GothicUIThemeScript.BRONZE_BRIGHT)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_frame.add_child(title_label)

	message_label = Label.new()
	message_label.name = "Message"
	message_label.position = Vector2(62, 101)
	message_label.size = Vector2(436, 78)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color("d8c8ae"))
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_frame.add_child(message_label)

	cancel_button = Button.new()
	cancel_button.name = "Cancel"
	cancel_button.position = Vector2(58, 207)
	cancel_button.size = Vector2(202, 58)
	cancel_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_button.theme_type_variation = "GothicConfirmationGemButton"
	cancel_button.add_theme_font_size_override("font_size", 17)
	cancel_button.set_meta("stable_id", "confirmation.cancel")
	cancel_button.pressed.connect(_cancel)
	modal_frame.add_child(cancel_button)

	confirm_button = Button.new()
	confirm_button.name = "Confirm"
	confirm_button.position = Vector2(300, 207)
	confirm_button.size = Vector2(202, 58)
	# Confirmation is an action, not a persistent selection.  The owner drives
	# the transaction/transition feedback explicitly after this dialog emits.
	confirm_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_button.theme_type_variation = "GothicConfirmationGemButton"
	confirm_button.add_theme_font_size_override("font_size", 17)
	confirm_button.set_meta("stable_id", "confirmation.confirm")
	confirm_button.pressed.connect(_confirm)
	modal_frame.add_child(confirm_button)


func open_confirmation(config: Dictionary) -> void:
	GothicUIThemeScript.clear_button_feedback(confirm_button)
	var tone := str(config.get("tone", "normal"))
	if tone != "danger":
		tone = "normal"
	current_request = {
		"contract_id": CONTRACT_ID,
		"action_id": str(config.get("action_id", "")),
		"tone": tone,
		"context": config.get("context", {}).duplicate(true) if config.get("context", {}) is Dictionary else {},
	}
	title_label.text = str(config.get("title", "确认操作"))
	message_label.text = str(config.get("message", "是否继续当前操作？"))
	cancel_button.text = str(config.get("cancel_label", "取消"))
	confirm_button.text = str(config.get("confirm_label", "确认"))
	_apply_tone(tone)
	show()
	move_to_front()
	confirm_button.grab_focus()


func close_confirmation() -> void:
	if not visible:
		return
	current_request = {}
	hide()


func _apply_tone(tone: String) -> void:
	var danger := tone == "danger"
	title_label.add_theme_color_override(
		"font_color",
		Color("e6a293") if danger else GothicUIThemeScript.BRONZE_BRIGHT
	)
	confirm_button.add_theme_color_override(
		"font_color",
		Color("ffd1c5") if danger else GothicUIThemeScript.PARCHMENT
	)


func _confirm() -> void:
	if not visible:
		return
	GothicUIThemeScript.set_button_feedback(
		confirm_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_BUSY,
		"confirmation",
	)
	var request := current_request.duplicate(true)
	close_confirmation()
	confirmed.emit(request)


func _cancel() -> void:
	if not visible:
		return
	GothicUIThemeScript.clear_button_feedback(confirm_button)
	var request := current_request.duplicate(true)
	close_confirmation()
	cancelled.emit(request)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
