extends Node
const Menu := preload("res://scripts/system_menu_panel.gd")
const Overrides := preload("res://scripts/ui_runtime_layout_overrides.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var stamp := str(Time.get_ticks_usec())
	AudioPreferences.storage_path = "user://v81_audio_" + stamp + ".cfg"
	LootPreferences.storage_path = "user://v81_filter_" + stamp + ".cfg"
	var menu := Menu.new()
	menu.audio_setting_changed.connect(func(request:Dictionary)->void:
		assert(AudioPreferences.set_level(str(request.channel), float(request.value))))
	add_child(menu)
	menu.open_menu()
	menu.show_settings_page()
	for i in range(3): await get_tree().process_frame
	var initial := _geometry(menu)
	assert(menu.settings_title.text == "游戏设置" and menu.settings_title.visible)
	assert(menu.settings_title.get_parent().position.y == 66)
	assert(menu.settings_back_button.get_rect() == Rect2(72,430,356,60))
	for slider: HSlider in [menu.music_slider, menu.sfx_slider]:
		for value in [0,37,100]:
			slider.value = value
			var current: float = AudioPreferences.music_volume if slider == menu.music_slider else AudioPreferences.sfx_volume
			assert(is_equal_approx(current,float(value)/100.0))
	for value in [1,2,0]:
		menu.loot_filter_slider.value = value
		assert(LootPreferences.filter_level == value)
	menu.show_main_page()
	menu.show_settings_page()
	Overrides.apply_profile(menu,"system_menu")
	await get_tree().process_frame
	assert(_geometry(menu) == initial, "tab changes or profile replay must not reset accepted geometry")
	assert(not menu.audio_save_note.visible)
	menu.close_menu()
	assert(not AudioPreferences.dirty and not LootPreferences.dirty)
	menu.queue_free()
	await get_tree().process_frame
	print("SETTINGS_FUNCTION_V81_PASS accepted_geometry, gain_endpoints, filter_three_states, reopen, replay, persistence")
	get_tree().quit()

func _geometry(menu: Control) -> Array:
	var result: Array = []
	for path in ["SystemMenuModal/SettingsPage/SettingsPageTitleFrame", "SystemMenuModal/SettingsPage/SettingsPageTitleFrame/Title", "SystemMenuModal/SettingsPage/MusicVolume", "SystemMenuModal/SettingsPage/SFXVolume", "SystemMenuModal/SettingsPage/LootFilter", "SystemMenuModal/SettingsPage/SettingsBackButton"]:
		result.append(menu.get_node(path).get_rect())
	return result
