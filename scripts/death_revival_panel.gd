class_name DeathRevivalPanel
extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const GAME_ICON := preload("res://assets/branding/game_icon.png")

signal revival_requested(request: Dictionary)

const CONTRACT_ID := "ui.death.revival.v1"
const PANEL_RECT := Rect2(350, 80, 580, 560)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const TOWN_SLOT := "town"
const SPECIAL_SLOT := "special"

var modal: Panel
var title_label: Label
var death_icon: TextureRect
var message_label: Label
var loss_label: Label
var town_button: Button
var town_status_label: Label
var special_button: Button
var special_status_label: Label
var result_label: Label
var death_context: Dictionary = {}
var revival_options: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	_build_background()
	_build_modal()
	hide()


func _build_background() -> void:
	var shade := ColorRect.new()
	shade.name = "DeathShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.004, 0.004, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var blood_tint := ColorRect.new()
	blood_tint.name = "BloodTint"
	blood_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blood_tint.color = Color(0.24, 0.015, 0.012, 0.10)
	blood_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blood_tint)


func _build_modal() -> void:
	modal = Panel.new()
	modal.name = "DeathRevivalModal"
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.offset_left = -PANEL_RECT.size.x * 0.5
	modal.offset_top = -PANEL_RECT.size.y * 0.5
	modal.offset_right = PANEL_RECT.size.x * 0.5
	modal.offset_bottom = PANEL_RECT.size.y * 0.5
	modal.theme_type_variation = "GothicModalFrame"
	add_child(modal)
	GothicFrameFactoryScript.add_modal_fill(modal, PANEL_RECT.size)

	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(62, 18)
	title_frame.size = Vector2(456, 76)
	title_frame.theme_type_variation = "GothicTitleBar"
	modal.add_child(title_frame)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "角色已死亡"
	title_label.position = Vector2(36, 11)
	title_label.size = Vector2(384, 36)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color("d89a78"))
	title_frame.add_child(title_label)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "请选择复活方式"
	subtitle.position = Vector2(36, 46)
	subtitle.size = Vector2(384, 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = "GothicMutedLabel"
	subtitle.add_theme_font_size_override("font_size", 12)
	title_frame.add_child(subtitle)

	death_icon = TextureRect.new()
	death_icon.name = "GameIcon"
	death_icon.position = Vector2(234, 98)
	death_icon.size = Vector2(112, 112)
	death_icon.texture = GAME_ICON
	death_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	death_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	death_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	death_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_icon.set_meta("stable_id", "ui.death.game_icon")
	modal.add_child(death_icon)

	message_label = Label.new()
	message_label.name = "DeathMessage"
	message_label.text = "你的灵魂正在等待归来"
	message_label.position = Vector2(70, 210)
	message_label.size = Vector2(440, 30)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	modal.add_child(message_label)
	loss_label = Label.new()
	loss_label.name = "LossLabel"
	loss_label.text = ""
	loss_label.position = Vector2(70, 238)
	loss_label.size = Vector2(440, 24)
	loss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loss_label.theme_type_variation = "GothicMutedLabel"
	loss_label.add_theme_font_size_override("font_size", 13)
	modal.add_child(loss_label)

	town_button = _revival_button("TownRevivalButton", "最近城镇复活", 270, "death.revival.town")
	town_button.theme_type_variation = "GothicComponentSelectedButton"
	town_button.pressed.connect(_request_revival.bind(TOWN_SLOT))
	town_status_label = _status_label("TownStatus", 336)
	special_button = _revival_button("SpecialRevivalButton", "特殊复活", 370, "death.revival.special")
	special_button.pressed.connect(_request_revival.bind(SPECIAL_SLOT))
	special_status_label = _status_label("SpecialStatus", 436)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.position = Vector2(70, 470)
	result_label.size = Vector2(440, 30)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.theme_type_variation = "GothicMutedLabel"
	result_label.add_theme_font_size_override("font_size", 13)
	modal.add_child(result_label)
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "复活规则与可用状态由游戏系统提供"
	footer.position = Vector2(70, 514)
	footer.size = Vector2(440, 22)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.theme_type_variation = "GothicMutedLabel"
	footer.add_theme_font_size_override("font_size", 11)
	modal.add_child(footer)
	GothicFrameFactoryScript.seal_modal_rings(modal)


func _revival_button(node_name: String, text_value: String, y: float, stable_id: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = Vector2(70, y)
	button.size = Vector2(440, 64)
	button.theme_type_variation = "GothicComponentButton"
	button.add_theme_font_size_override("font_size", 18)
	button.set_meta("stable_id", stable_id)
	modal.add_child(button)
	return button


func _status_label(node_name: String, y: float) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = Vector2(70, y)
	label.size = Vector2(440, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicMutedLabel"
	label.add_theme_font_size_override("font_size", 12)
	modal.add_child(label)
	return label


func open_death_screen(context := {}) -> void:
	death_context = context.duplicate(true) if context is Dictionary else {}
	message_label.text = str(death_context.get("message", "你的灵魂正在等待归来"))
	loss_label.text = str(death_context.get("loss_text", ""))
	result_label.text = ""
	set_revival_options(death_context.get("revival_options", []))
	show()


func close_death_screen() -> void:
	hide()


func set_revival_options(options: Array) -> void:
	revival_options.clear()
	for value: Variant in options:
		if not value is Dictionary:
			continue
		var option: Dictionary = value.duplicate(true)
		var slot := str(option.get("option_slot", ""))
		if slot in [TOWN_SLOT, SPECIAL_SLOT]:
			revival_options[slot] = option
	_refresh_option(TOWN_SLOT, town_button, town_status_label, "最近城镇复活")
	_refresh_option(SPECIAL_SLOT, special_button, special_status_label, "特殊复活")


func update_revival_option(option_slot: String, state: Dictionary) -> void:
	if option_slot not in [TOWN_SLOT, SPECIAL_SLOT]:
		return
	var option: Dictionary = revival_options.get(option_slot, {}).duplicate(true)
	option.merge(state, true)
	option["option_slot"] = option_slot
	revival_options[option_slot] = option
	if option_slot == TOWN_SLOT:
		_refresh_option(TOWN_SLOT, town_button, town_status_label, "最近城镇复活")
	else:
		_refresh_option(SPECIAL_SLOT, special_button, special_status_label, "特殊复活")


func apply_revival_result(result: Dictionary) -> void:
	var success := bool(result.get("success", false))
	result_label.text = str(result.get("message", "复活成功" if success else "当前无法复活"))
	result_label.add_theme_color_override("font_color", Color("a9c28e") if success else Color("d47868"))
	if result.get("revival_options", null) is Array:
		set_revival_options(result.get("revival_options", []))
	if success:
		close_death_screen()


func _refresh_option(slot: String, button: Button, status: Label, fallback_label: String) -> void:
	var option: Dictionary = revival_options.get(slot, {})
	var configured := not option.is_empty()
	var enabled := configured and bool(option.get("enabled", false))
	var countdown := maxi(0, int(option.get("countdown_seconds", 0)))
	button.text = str(option.get("label", fallback_label))
	button.disabled = not enabled or countdown > 0
	button.set_meta("method_id", str(option.get("method_id", "")))
	if not configured:
		status.text = "等待复活规则"
	elif countdown > 0:
		status.text = "%d 秒后可用" % countdown
	elif enabled:
		status.text = str(option.get("hint", "可以使用"))
	else:
		status.text = str(option.get("reason", "当前不可用"))
	status.add_theme_color_override(
		"font_color",
		Color("a9c28e") if enabled and countdown <= 0 else Color("9f7869")
	)


func _request_revival(option_slot: String) -> void:
	var option: Dictionary = revival_options.get(option_slot, {})
	if option.is_empty() or not bool(option.get("enabled", false)) or int(option.get("countdown_seconds", 0)) > 0:
		return
	var method_id := str(option.get("method_id", ""))
	if method_id.is_empty():
		return
	revival_requested.emit({
		"contract_id": CONTRACT_ID,
		"death_id": str(death_context.get("death_id", "")),
		"option_slot": option_slot,
		"method_id": method_id,
	})
