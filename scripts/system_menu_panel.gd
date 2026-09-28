class_name SystemMenuPanel
extends Control

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")

signal continue_requested
signal return_to_character_select_requested
signal save_and_exit_requested
signal audio_setting_changed(request: Dictionary)
signal performance_capture_requested(detail_mode: String)

const ACTION_CONTRACT_ID := "ui.system_menu.action.v1"
const AUDIO_CONTRACT_ID := "ui.audio.setting.v2"
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
var music_slider: HSlider
var sfx_slider: HSlider
var loot_filter_slider: HSlider
var audio_save_note: Label
var music_toggle: CheckButton
var sfx_toggle: CheckButton
var music_status_label: Label
var sfx_status_label: Label
var settings_back_button: Button
var current_page := "main"
var music_enabled := true
var sfx_enabled := true
var _action_feedback_serial := 0
var _layout_initialized := false
var _layout_apply_count := 0


func _ready() -> void:
	set_meta("calibration_retired_paths", ["SystemMenuModal/SettingsPage/MusicToggle", "SystemMenuModal/SettingsPage/SFXToggle", "SystemMenuModal/SettingsPage/MusicFrame", "SystemMenuModal/SettingsPage/SFXFrame", "SystemMenuModal/SettingsPage/MusicTitle", "SystemMenuModal/SettingsPage/SFXTitle", "SystemMenuModal/SettingsPage/MusicStatus", "SystemMenuModal/SettingsPage/SFXStatus", "SystemMenuModal/SettingsPage/SettingsNote", "SystemMenuModal/SettingsPage/SettingsFooter"])
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	_build_background()
	_build_modal()
	show_main_page()
	_ensure_layout_initialized()
	AudioPreferences.levels_changed.connect(set_audio_levels)
	visibility_changed.connect(_ui_audio_visibility_changed)
	set_audio_levels(AudioPreferences.music_volume, AudioPreferences.sfx_volume)


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
	main_title = _title_bar(main_page, "游戏菜单", "")
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
	continue_button.theme_type_variation = "GothicSystemMenuGemButton"
	continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_button.pressed.connect(_request_continue)
	settings_button = _menu_button(main_page, "SettingsButton", "游戏设置", 270, "system_menu.settings")
	settings_button.theme_type_variation = "GothicSystemMenuGemButton"
	settings_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_button.pressed.connect(show_settings_page)
	character_select_button = _menu_button(main_page, "CharacterSelectButton", "返回人物选择", 342, "system_menu.return_to_character_select")
	character_select_button.theme_type_variation = "GothicSystemMenuGemButton"
	character_select_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	character_select_button.pressed.connect(_request_character_select)
	save_exit_button = _menu_button(main_page, "SaveExitButton", "保存并退出", 414, "system_menu.save_and_exit")
	save_exit_button.theme_type_variation = "GothicSystemMenuGemButton"
	save_exit_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_exit_button.pressed.connect(_request_save_exit)
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "ESC / Android 返回键：继续游戏"
	footer.position = Vector2(60, 486)
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
	settings_title = _title_bar(settings_page, "游戏设置", "")
	# Accepted in the production calibrator on 2026-09-14. Keep this header
	# inside the modal opening; the old y=18 placed it beneath the top ornament.
	var title_frame := settings_title.get_parent() as Control
	title_frame.position.y = 66.0
	title_frame.set_meta("calibration_layout_revision", 9)
	settings_title.set_meta("calibration_layout_revision", 9)
	settings_title.size.y = 34.0
	title_frame.get_node("Subtitle").hide()
	title_frame.get_node("Subtitle").set_meta("calibration_layout_revision", 9)
	music_slider = _ui_volume_row("MusicVolume", "游戏音乐", 148.0, "music")
	sfx_slider = _ui_volume_row("SFXVolume", "游戏音效", 230.0, "sfx")
	loot_filter_slider = _ui_volume_row("LootFilter", "物品过滤", 312.0, "loot_filter")
	loot_filter_slider.max_value = 2.0
	loot_filter_slider.tick_count = 3
	loot_filter_slider.ticks_on_borders = true
	loot_filter_slider.set_value_no_signal(LootPreferences.filter_level)
	loot_filter_slider.position = Vector2(70, 36)
	loot_filter_slider.size = Vector2(216, 28)
	loot_filter_slider.set_meta("setting_id", "loot.filter.level")
	var filter_row := loot_filter_slider.get_parent() as Control
	filter_row.size.y = 100.0
	filter_row.get_node("Percent").hide()
	var caption := filter_row.get_node("Caption") as Label
	caption.position = Vector2(20, 12)
	caption.size = Vector2(316, 22)
	var labels := ["关闭", "沃玛以下不显示", "祖玛以下不显示"]
	for index in range(3):
		var label := Label.new()
		label.text = labels[index]
		label.position = Vector2(16 + index * 108, 68)
		label.size = Vector2(108, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		filter_row.add_child(label)
	music_status_label = settings_page.get_node("MusicVolume/Percent") as Label
	sfx_status_label = settings_page.get_node("SFXVolume/Percent") as Label
	audio_save_note = Label.new()
	audio_save_note.name = "VolumeSaveNote"
	audio_save_note.position = Vector2(72, 496)
	audio_save_note.size = Vector2(356, 32)
	audio_save_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_save_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	audio_save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	audio_save_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_save_note.theme_type_variation = "GothicMutedLabel"
	audio_save_note.text = ""
	audio_save_note.hide()
	audio_save_note.set_meta("calibration_layout_revision", 9)
	settings_page.add_child(audio_save_note)
	settings_back_button = _menu_button(settings_page, "SettingsBackButton", "返回游戏菜单", 430, "system_menu.settings.back")
	settings_back_button.set_meta("calibration_layout_revision", 9)
	settings_back_button.theme_type_variation = "GothicSystemSettingsBackGemButton"
	settings_back_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_back_button.pressed.connect(show_main_page)
	if OS.is_debug_build():
		var modes := ["frame_only", "full"]
		var captions := ["记录帧率30秒", "记录CPU30秒"]
		for index in range(2):
			var capture := _menu_button(settings_page, "PerformanceCapture%d" % index,
				captions[index], 510, "system_menu.capture." + modes[index])
			capture.position.x = 72 + index * 182
			capture.size = Vector2(174, 36)
			capture.add_theme_font_size_override("font_size", 13)
			capture.pressed.connect(func() -> void: performance_capture_requested.emit(modes[index]))
		var capture_note := Label.new()
		capture_note.name = "PerformanceCaptureNote"
		capture_note.text = "自动保存到本机；CPU记录会增加测量开销"
		capture_note.position = Vector2(64, 551)
		capture_note.size = Vector2(372, 22)
		capture_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		capture_note.add_theme_font_size_override("font_size", 11)
		settings_page.add_child(capture_note)


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
	frame.theme_type_variation = "GothicSystemSettingsRowGemButton"
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
	set_audio_levels(AudioPreferences.music_volume, AudioPreferences.sfx_volume)
	_clear_action_feedback()
	show()
	show_main_page()


func close_menu() -> void:
	_ui_flush_audio()
	_clear_action_feedback()
	hide()


func show_main_page() -> void:
	if current_page == "settings":
		_ui_flush_audio()
	current_page = "main"
	if main_page != null:
		main_page.show()
	if settings_page != null:
		settings_page.hide()
	_ensure_layout_initialized()


func _ensure_layout_initialized() -> void:
	if _layout_initialized:
		return
	_layout_initialized = true
	_layout_apply_count += 1
	UIRuntimeLayoutOverridesScript.apply_profile(self, "system_menu")


func show_settings_page() -> void:
	set_audio_levels(AudioPreferences.music_volume, AudioPreferences.sfx_volume)
	loot_filter_slider.set_value_no_signal(LootPreferences.filter_level)
	_clear_action_feedback()
	_show_menu_action_result(settings_button, true, "system_menu.settings")
	current_page = "settings"
	main_page.hide()
	settings_page.show()


func set_audio_settings(next_music_enabled: bool, next_sfx_enabled: bool) -> void:
	# Compatibility for legacy callers/tests; the live root uses numeric levels.
	set_audio_levels(1.0 if next_music_enabled else 0.0, 1.0 if next_sfx_enabled else 0.0)


func _refresh_audio_status() -> void:
	if music_status_label == null or sfx_status_label == null:
		return
	music_enabled = music_slider.value > 0.0
	sfx_enabled = sfx_slider.value > 0.0
	music_status_label.text = "%d%%" % roundi(music_slider.value)
	sfx_status_label.text = "%d%%" % roundi(sfx_slider.value)
	if audio_save_note != null:
		var failed := AudioPreferences.last_save_error != OK or LootPreferences.last_save_error != OK
		audio_save_note.text = "设置尚未保存，请关闭菜单后重试" if failed else ""
		audio_save_note.visible = failed


func _on_music_toggled(enabled: bool) -> void:
	music_enabled = enabled
	_refresh_audio_status()
	_emit_audio_setting("audio.music.enabled", enabled)


func _on_sfx_toggled(enabled: bool) -> void:
	sfx_enabled = enabled
	_refresh_audio_status()
	_emit_audio_setting("audio.sfx.enabled", enabled)


func _emit_audio_setting(setting_id: String, enabled: bool) -> void:
	# Legacy test/accessibility adapter. The visible UI only emits numeric gain.
	var channel := "music" if setting_id == "audio.music.enabled" else "sfx"
	_ui_emit_volume_setting(channel, 1.0 if enabled else 0.0)


func _request_continue() -> void:
	_ui_flush_audio()
	_clear_action_feedback()
	GothicUIThemeScript.set_button_feedback(continue_button, GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION, "system_menu.continue")
	continue_requested.emit()


func _request_character_select() -> void:
	_ui_flush_audio()
	_clear_action_feedback()
	GothicUIThemeScript.set_button_feedback(character_select_button, GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION, "system_menu.character_select")
	return_to_character_select_requested.emit()


func _request_save_exit() -> void:
	_ui_flush_audio()
	_clear_action_feedback()
	GothicUIThemeScript.set_button_feedback(save_exit_button, GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION, "system_menu.save_exit")
	save_and_exit_requested.emit()


func _show_menu_action_result(button: Button, success: bool, group: String) -> void:
	_action_feedback_serial += 1
	var serial := _action_feedback_serial
	GothicUIThemeScript.set_button_feedback(
		button,
		GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS if success else GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE,
		group,
	)
	get_tree().create_timer(GothicUIThemeScript.BUTTON_RESULT_SUCCESS_SECONDS if success else GothicUIThemeScript.BUTTON_RESULT_FAILURE_SECONDS).timeout.connect(func() -> void:
		if serial == _action_feedback_serial and is_instance_valid(button) and button.is_inside_tree():
			GothicUIThemeScript.clear_button_feedback(button)
	)


func _clear_action_feedback() -> void:
	_action_feedback_serial += 1
	for button in [continue_button, settings_button, character_select_button, save_exit_button, settings_back_button]:
		GothicUIThemeScript.clear_button_feedback(button)


func _ui_volume_row(node_name: String, caption: String, y: float, channel: String) -> HSlider:
	var row := Control.new()
	row.name = node_name
	row.position = Vector2(72, y)
	row.size = Vector2(356, 76)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("calibration_layout_revision", 7)
	settings_page.add_child(row)
	var frame := Button.new()
	frame.name = "RowFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.theme_type_variation = "GothicSystemSettingsRowGemButton"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.focus_mode = Control.FOCUS_NONE
	frame.set_meta("calibration_layout_revision", 7)
	row.add_child(frame)
	var title := Label.new()
	title.name = "Caption"
	title.text = caption
	title.position = Vector2(20, 10)
	title.size = Vector2(92, 56)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("f2d29b"))
	title.set_meta("calibration_runtime_text", true)
	title.set_meta("calibration_layout_revision", 7)
	row.add_child(title)
	var percent := Label.new()
	percent.name = "Percent"
	percent.position = Vector2(286, 10)
	percent.size = Vector2(50, 56)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	percent.set_meta("calibration_runtime_text", true)
	percent.set_meta("calibration_layout_revision", 7)
	row.add_child(percent)
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.position = Vector2(122, 10)
	slider.size = Vector2(152, 56)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.scrollable = false
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.set_meta("setting_id", "audio." + channel + ".volume")
	slider.set_meta("calibration_layout_revision", 7)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("241c15")
	track.border_color = Color("705438")
	track.set_border_width_all(1)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("b1874f")
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(_ui_slider_changed.bind(channel))
	row.add_child(slider)
	return slider

func set_audio_levels(music: float, sfx: float) -> void:
	if music_slider == null or sfx_slider == null:
		return
	music_slider.set_value_no_signal(clampf(music, 0.0, 1.0) * 100.0)
	sfx_slider.set_value_no_signal(clampf(sfx, 0.0, 1.0) * 100.0)
	_refresh_audio_status()

func _ui_slider_changed(percent: float, channel: String) -> void:
	if channel == "loot_filter":
		LootPreferences.set_filter_level(roundi(percent))
		return
	_ui_emit_volume_setting(channel, clampf(percent / 100.0, 0.0, 1.0))
	_refresh_audio_status()

func _ui_emit_volume_setting(channel: String, value: float) -> void:
	audio_setting_changed.emit({"contract_id": AUDIO_CONTRACT_ID, "channel": channel, "value": value})

func _ui_flush_audio() -> void:
	AudioPreferences.flush()
	LootPreferences.flush()
	_refresh_audio_status()

func _ui_audio_visibility_changed() -> void:
	if not is_visible_in_tree():
		_ui_flush_audio()

func _exit_tree() -> void:
	AudioPreferences.flush()
	LootPreferences.flush()
