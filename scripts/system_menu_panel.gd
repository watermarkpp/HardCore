class_name SystemMenuPanel
extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")

signal continue_requested
signal return_to_character_select_requested
signal save_and_exit_requested
signal audio_setting_changed(request: Dictionary)

const ACTION_CONTRACT_ID := "ui.system_menu.action.v1"
const AUDIO_CONTRACT_ID := "ui.audio.setting.v1"
const PANEL_RECT := Rect2(390, 56, 500, 608)

var modal: Panel
var main_page: Control
var settings_page: Control
var main_title: Label
var settings_title: Label
var continue_button: Button
var character_select_button: Button
var settings_button: Button
var save_exit_button: Button
var music_toggle: CheckButton
var sfx_toggle: CheckButton
var music_status_label: Label
var sfx_status_label: Label
var settings_back_button: Button
var current_page := "main"
var music_enabled := true
var sfx_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	_build_background()
	_build_modal()
	show_main_page()
	UIRuntimeLayoutOverridesScript.apply_profile(self, "system_menu")


func _build_background() -> void:
	var shade := ColorRect.new()
	shade.name = "PauseShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.006, 0.005, 0.76)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var vignette := ColorRect.new()
	vignette.name = "PauseVignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.08, 0.01, 0.006, 0.08)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_modal() -> void:
	modal = Panel.new()
	modal.name = "SystemMenuModal"
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.position = -PANEL_RECT.size * 0.5
	modal.size = PANEL_RECT.size
	modal.theme_type_variation = "GothicModalFrame"
	add_child(modal)
	GothicFrameFactoryScript.add_modal_fill(modal, PANEL_RECT.size)
	_build_main_page()
	_build_settings_page()
	GothicFrameFactoryScript.seal_modal_rings(modal)


func _build_main_page() -> void:
	main_page = Control.new()
	main_page.name = "MainPage"
	main_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(main_page)
	main_title = _title_bar(main_page, "游戏菜单", "游戏已经暂停")
	var status := Panel.new()
	status.name = "PauseStatus"
	status.position = Vector2(72, 122)
	status.size = Vector2(356, 52)
	status.theme_type_variation = "GothicInfoPanel"
	main_page.add_child(status)
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "当前游戏进程已暂停"
	status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("b9c9a8"))
	status.add_child(status_label)
	continue_button = _menu_button(main_page, "ContinueButton", "继续游戏", 198, "system_menu.continue")
	continue_button.theme_type_variation = "GothicComponentButton"
	continue_button.pressed.connect(_request_continue)
	settings_button = _menu_button(main_page, "SettingsButton", "游戏设置", 270, "system_menu.settings")
	settings_button.pressed.connect(show_settings_page)
	character_select_button = _menu_button(main_page, "CharacterSelectButton", "返回人物选择", 342, "system_menu.return_to_character_select")
	character_select_button.pressed.connect(_request_character_select)
	save_exit_button = _menu_button(main_page, "SaveExitButton", "保存并退出", 414, "system_menu.save_and_exit")
	save_exit_button.pressed.connect(_request_save_exit)
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "ESC / Android 返回键：继续游戏"
	footer.position = Vector2(60, 510)
	footer.size = Vector2(380, 28)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.theme_type_variation = "GothicMutedLabel"
	footer.add_theme_font_size_override("font_size", 12)
	main_page.add_child(footer)


func _build_settings_page() -> void:
	settings_page = Control.new()
	settings_page.name = "SettingsPage"
	settings_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(settings_page)
	settings_title = _title_bar(settings_page, "游戏设置", "声音")
	music_toggle = _audio_toggle(settings_page, "MusicToggle", "游戏音乐", 158, "audio.music.enabled")
	music_toggle.toggled.connect(_on_music_toggled)
	music_status_label = _toggle_status(settings_page, "MusicStatus", 158)
	sfx_toggle = _audio_toggle(settings_page, "SFXToggle", "游戏音效", 250, "audio.sfx.enabled")
	sfx_toggle.toggled.connect(_on_sfx_toggled)
	sfx_status_label = _toggle_status(settings_page, "SFXStatus", 250)
	var note := Label.new()
	note.name = "SettingsNote"
	note.text = "更多游戏设置将在后续版本加入"
	note.position = Vector2(72, 352)
	note.size = Vector2(356, 32)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.theme_type_variation = "GothicMutedLabel"
	settings_page.add_child(note)
	settings_back_button = _menu_button(settings_page, "SettingsBackButton", "返回游戏菜单", 430, "system_menu.settings.back")
	settings_back_button.theme_type_variation = "GothicComponentButton"
	settings_back_button.pressed.connect(show_main_page)
	var footer := Label.new()
	footer.name = "SettingsFooter"
	footer.text = "开关状态由游戏音频服务保存并应用"
	footer.position = Vector2(60, 510)
	footer.size = Vector2(380, 28)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.theme_type_variation = "GothicMutedLabel"
	footer.add_theme_font_size_override("font_size", 12)
	settings_page.add_child(footer)


func _title_bar(parent: Control, title_text: String, subtitle_text: String) -> Label:
	var title_frame := Panel.new()
	title_frame.name = "%sTitleFrame" % parent.name
	title_frame.position = Vector2(56, 18)
	title_frame.size = Vector2(388, 70)
	title_frame.theme_type_variation = "GothicTitleBar"
	parent.add_child(title_frame)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.position = Vector2(30, 10)
	title.size = Vector2(328, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f0c77f"))
	title_frame.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = subtitle_text
	subtitle.position = Vector2(30, 40)
	subtitle.size = Vector2(328, 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = "GothicMutedLabel"
	subtitle.add_theme_font_size_override("font_size", 12)
	title_frame.add_child(subtitle)
	return title


func _menu_button(parent: Control, node_name: String, text_value: String, y: float, stable_id: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = Vector2(72, y)
	button.size = Vector2(356, 60)
	button.theme_type_variation = "GothicComponentButton"
	button.add_theme_font_size_override("font_size", 18)
	button.set_meta("stable_id", stable_id)
	parent.add_child(button)
	return button


func _audio_toggle(parent: Control, node_name: String, label_text: String, y: float, setting_id: String) -> CheckButton:
	var frame := Button.new()
	frame.name = node_name.trim_suffix("Toggle") + "Frame"
	frame.position = Vector2(72, y)
	frame.size = Vector2(356, 68)
	frame.theme_type_variation = "GothicComponentButton"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.focus_mode = Control.FOCUS_NONE
	frame.set_meta("calibration_layout_revision", 3)
	parent.add_child(frame)
	var title := Label.new()
	title.name = node_name.trim_suffix("Toggle") + "Title"
	title.text = label_text
	title.position = Vector2(104, y + 18)
	title.size = Vector2(118, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("f2d29b"))
	title.set_meta("calibration_layout_revision", 3)
	parent.add_child(title)
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.text = ""
	toggle.position = Vector2(332, y + 16)
	toggle.size = Vector2(52, 36)
	toggle.theme_type_variation = "GothicSettingsSwitch"
	toggle.set_meta("setting_id", setting_id)
	toggle.set_meta("calibration_layout_revision", 3)
	parent.add_child(toggle)
	return toggle


func _toggle_status(parent: Control, node_name: String, y: float) -> Label:
	var status := Label.new()
	status.name = node_name
	status.position = Vector2(230, y + 18)
	status.size = Vector2(88, 32)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.set_meta("calibration_layout_revision", 3)
	parent.add_child(status)
	return status


func open_menu() -> void:
	show()
	show_main_page()


func close_menu() -> void:
	hide()


func show_main_page() -> void:
	current_page = "main"
	if main_page != null:
		main_page.show()
	if settings_page != null:
		settings_page.hide()
	UIRuntimeLayoutOverridesScript.apply_profile(self, "system_menu")


func show_settings_page() -> void:
	current_page = "settings"
	main_page.hide()
	settings_page.show()


func set_audio_settings(next_music_enabled: bool, next_sfx_enabled: bool) -> void:
	music_enabled = next_music_enabled
	sfx_enabled = next_sfx_enabled
	music_toggle.set_pressed_no_signal(music_enabled)
	sfx_toggle.set_pressed_no_signal(sfx_enabled)
	_refresh_audio_status()


func _refresh_audio_status() -> void:
	music_status_label.text = "已开启" if music_enabled else "已关闭"
	music_status_label.add_theme_color_override("font_color", Color("a9c28e") if music_enabled else Color("9a7b6e"))
	sfx_status_label.text = "已开启" if sfx_enabled else "已关闭"
	sfx_status_label.add_theme_color_override("font_color", Color("a9c28e") if sfx_enabled else Color("9a7b6e"))


func _on_music_toggled(enabled: bool) -> void:
	music_enabled = enabled
	_refresh_audio_status()
	_emit_audio_setting("audio.music.enabled", enabled)


func _on_sfx_toggled(enabled: bool) -> void:
	sfx_enabled = enabled
	_refresh_audio_status()
	_emit_audio_setting("audio.sfx.enabled", enabled)


func _emit_audio_setting(setting_id: String, enabled: bool) -> void:
	audio_setting_changed.emit({
		"contract_id": AUDIO_CONTRACT_ID,
		"setting_id": setting_id,
		"enabled": enabled,
	})


func _request_continue() -> void:
	continue_requested.emit()


func _request_character_select() -> void:
	return_to_character_select_requested.emit()


func _request_save_exit() -> void:
	save_and_exit_requested.emit()
