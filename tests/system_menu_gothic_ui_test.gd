extends Node

## 2026-09-10 R5 迁移版：声音设置已从 CheckButton 开关改为音量滑条 +
## 百分比 + v2 数值事件 + 关闭菜单自动保存（用户要求）。
## 迁移断言的旧要求/新要求/用户依据见 docs/ui_r5/20260910/IMPLEMENTATION_REPORT.md §5-S5。
## 旧 v1 合同与 v1 兼容处理单独验证；旧开关节点不复活。

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/system_menu_audio_contract_v1.json"
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")
const GameRootScript := preload("res://scripts/game_root.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const AudioPreferencesScript := preload("res://scripts/audio_preferences.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# 旧 v1 合同单独验证（保留）：契约 ID 不变，game_root 仍接受 v1 请求。
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "系统菜单音频契约无法解析")
	assert(contract.get("menuContractId", "") == "ui.system_menu.action.v1", "系统菜单契约 ID 不稳定")
	assert(contract.get("audioContractId", "") == "ui.audio.setting.v1", "音频设置契约 ID 不稳定")

	var menu: Control = SystemMenuPanelScript.new()
	add_child(menu)
	await get_tree().process_frame

	# —— 结构与外观（保留，R5 未改）——
	assert(menu.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "暂停菜单不能在游戏暂停时工作")
	assert(menu.modal.theme_type_variation == "GothicModalFrame", "暂停菜单没有使用公共哥特外框")
	assert(menu.modal.get_node("ModalSurface").get_script() == GothicFrameFillScript, "暂停菜单一级框没有使用代码背景")
	assert(menu.modal.has_node("ModalFrameSafetyOverlay"), "暂停菜单缺少双圈安全覆盖层")
	var layout_contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ui/manual_layout_overrides.json"))
	var modal_saved: Array = layout_contract["profiles"]["system_menu"]["nodes"]["SystemMenuModal"]["logicalRect"] if layout_contract["profiles"]["system_menu"]["nodes"].has("SystemMenuModal") else []
	assert(modal_saved.size() == 4, "系统菜单正式布局合同缺少 Modal")
	var modal_center: Vector2 = menu.modal.get_global_rect().get_center()
	assert(absf(modal_center.x - menu.size.x * 0.5) <= 1.0 and absf(modal_center.y - menu.size.y * 0.5) <= 1.0, "暂停菜单数学上未相对完整屏幕居中")
	assert(menu.current_page == "main" and menu.main_page.visible and not menu.settings_page.visible, "暂停菜单默认页面错误")
	assert(menu.continue_button.size.y >= 56, "继续游戏按钮触控区不足")
	# 旧断言：variation == GothicComponentButton（旧普通按钮体系）。
	# 新断言：当前用户已验收的暂停菜单宝石按钮体系 GothicSystemMenuGemButton，
	# 且非 toggle、未按压——保留“动作不得伪装为持久选择”的原始语义。
	assert(menu.continue_button.theme_type_variation == &"GothicSystemMenuGemButton"
		and not menu.continue_button.toggle_mode and not menu.continue_button.button_pressed,
		"继续游戏动作不应伪装为持久选择")
	assert(menu.character_select_button.size.y >= 56, "返回人物选择按钮触控区不足")
	assert(menu.save_exit_button.size.y >= 56, "保存并退出按钮触控区不足")
	assert(menu.settings_button.size.y >= 56, "游戏设置按钮触控区不足")
	assert(menu.settings_button.text == "游戏设置", "主菜单没有用游戏设置替代安全回城说明")
	assert(not _tree_contains_text(menu, "安全回城"), "暂停菜单仍显示已删除的安全回城说明")

	# —— 设置页：滑条/百分比（迁移自旧 CheckButton 断言）——
	menu.show_settings_page()
	assert(menu.current_page == "settings" and menu.settings_page.visible and not menu.main_page.visible, "游戏设置页面没有打开")
	# 旧断言：music_toggle/sfx_toggle（CheckButton）携带 setting_id=audio.<ch>.enabled。
	# 新断言：音量滑条携带 setting_id=audio.<ch>.volume。
	# 依据：用户要求音乐/音效改为滑条，即时预览、关闭菜单自动保存；开关节点退役。
	var music_slider: HSlider = menu.settings_page.get_node("MusicVolume/Slider")
	var sfx_slider: HSlider = menu.settings_page.get_node("SFXVolume/Slider")
	assert(menu.music_slider == music_slider and menu.sfx_slider == sfx_slider, "音量滑条没有注册到面板")
	assert(music_slider.get_meta("setting_id", "") == "audio.music.volume", "游戏音乐稳定设置 ID 错误")
	assert(sfx_slider.get_meta("setting_id", "") == "audio.sfx.volume", "游戏音效稳定设置 ID 错误")
	assert(music_slider.step == 1.0 and not music_slider.scrollable and not sfx_slider.scrollable, "音量滑条步进/滚轮行为错误")
	# 旧断言：MusicFrame/SFXFrame 大按钮背景 + 标题/状态/开关都收在框内、状态文字对齐。
	# v81 已接受三行设置布局（4f4462ad）：音量行距 82，为物品过滤保留第三行。
	# 滑条行容器 MusicVolume/SFXVolume 同一布局、Caption/Percent/Slider
	# 都收在行内安全区、百分比文字 x 对齐、保存提示存在。
	# 依据：现有 v81 设置布局；本轮只修反馈时序，不改人工布局。
	var music_row: Control = menu.settings_page.get_node("MusicVolume")
	var sfx_row: Control = menu.settings_page.get_node("SFXVolume")
	assert(music_row.size == sfx_row.size and music_row.size == Vector2(356, 76), "两行声音设置没有使用同一布局")
	assert(music_row.position == Vector2(72, 148) and sfx_row.position == Vector2(72, 230), "已接受音量行位置变化")
	assert(menu.settings_page.get_node("LootFilter").position == Vector2(72, 312), "第三行物品过滤位置变化")
	var music_caption: Label = menu.settings_page.get_node("MusicVolume/Caption")
	var sfx_caption: Label = menu.settings_page.get_node("SFXVolume/Caption")
	assert(music_caption.text == "游戏音乐" and sfx_caption.text == "游戏音效", "声音标题错误")
	var music_percent: Label = menu.settings_page.get_node("MusicVolume/Percent")
	var sfx_percent: Label = menu.settings_page.get_node("SFXVolume/Percent")
	assert(music_percent.position.x == sfx_percent.position.x, "声音状态文字没有对齐")
	for volume_row: Control in [music_row, sfx_row]:
		var row_rect := Rect2(Vector2.ZERO, volume_row.size)
		for child_name: String in ["Caption", "Percent", "Slider"]:
			var child := volume_row.get_node(child_name) as Control
			assert(row_rect.encloses(Rect2(child.position, child.size)), "声音设置行内控件越出安全区")
	assert(menu.settings_page.has_node("VolumeSaveNote"), "设置页缺少自动保存提示")
	# 旧断言：set_audio_settings(true,true) → 状态文字“已开启”。
	# 新断言：旧 API 作为兼容适配器仍可用（bool→音量映射），滑条到 100、百分比 "100%"。
	# 依据：百分比显示替代开/关文字；旧调用方不破坏。
	menu.set_audio_settings(true, true)
	assert(music_slider.value == 100.0 and sfx_slider.value == 100.0, "音频音量初始状态没有同步")
	assert(music_percent.text == "100%" and sfx_percent.text == "100%", "音频百分比文字没有同步")

	# —— v2 数值事件（迁移自旧 v1 开关请求断言）——
	# 旧断言：toggle set_pressed(false) 分别发出 v1 {setting_id, enabled} 请求。
	# 新断言：滑条值变化分别发出 v2 {contract_id, channel, value} 请求，百分比即时更新。
	# 依据：v2 音量合同 ui.audio.setting.v2。
	var requests: Array[Dictionary] = []
	menu.audio_setting_changed.connect(func(request: Dictionary) -> void: requests.append(request.duplicate(true)))
	music_slider.value = 31.0
	sfx_slider.value = 42.0
	assert(requests.size() == 2, "音乐和音效滑条没有分别发出请求")
	assert(str(requests[0].get("contract_id", "")) == "ui.audio.setting.v2" and str(requests[0].get("channel", "")) == "music", "音乐设置请求错误")
	assert(is_equal_approx(float(requests[0].get("value", -1.0)), 0.31), "音乐音量值错误")
	assert(str(requests[1].get("channel", "")) == "sfx" and is_equal_approx(float(requests[1].get("value", -1.0)), 0.42), "音效设置请求错误")
	assert(music_percent.text == "31%" and sfx_percent.text == "42%", "滑条变化后百分比文字没有更新")

	# —— 旧 v1 兼容单独验证：真实 game_root 处理器（不复活开关节点）——
	# 旧路径：开关节点直发 v1 请求。新路径：game_root._on_system_menu_audio_setting_changed
	# 仍接受 v1 {setting_id, enabled} 并映射为音量（关闭=0）。用未入树的脚本实例调用真实处理器。
	var root_handler := Node2D.new()
	root_handler.set_script(GameRootScript)
	var sfx_volume_before_v1 := AudioPreferences.sfx_volume
	root_handler._on_system_menu_audio_setting_changed({"contract_id": "ui.audio.setting.v1", "setting_id": "audio.music.enabled", "enabled": false})
	assert(is_zero_approx(AudioPreferences.music_volume), "v1 音乐关闭请求没有映射为 0 音量")
	assert(is_equal_approx(AudioPreferences.sfx_volume, sfx_volume_before_v1), "v1 处理器不应改动音效音量")
	root_handler._on_system_menu_audio_setting_changed({"contract_id": "ui.audio.setting.v1", "setting_id": "audio.sfx.enabled", "enabled": false})
	assert(is_zero_approx(AudioPreferences.sfx_volume), "v1 音效关闭请求没有映射为 0 音量")

	# —— 真实关闭保存接线（新增；不直接调用 flush）——
	# 旧测试无保存验证。新断言：滑条→v2 请求→真实 game_root 处理器→AudioPreferences
	# （即时预览、不落盘）→真实 close_menu()（_ui_flush_audio）→落盘→重开恢复。
	# 依据：用户要求“拖动即时生效，关闭菜单时自动保存”。
	var save_dir := "user://system_menu_gothic_ui_test_" + str(Time.get_ticks_usec())
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir)) == OK, "隔离保存目录创建失败")
	var original_storage := AudioPreferences.storage_path
	AudioPreferences.storage_path = save_dir + "/preferences.cfg"
	menu.audio_setting_changed.connect(Callable(root_handler, "_on_system_menu_audio_setting_changed"))
	music_slider.value = 55.0
	sfx_slider.value = 66.0
	assert(is_equal_approx(AudioPreferences.music_volume, 0.55) and is_equal_approx(AudioPreferences.sfx_volume, 0.66), "关闭菜单前音量没有即时预览到 AudioPreferences")
	assert(AudioPreferences.dirty, "关闭菜单前应处于未保存状态")
	assert(not FileAccess.file_exists(AudioPreferences.storage_path), "拖动阶段不应写盘")
	menu.close_menu()
	assert(not AudioPreferences.dirty, "关闭菜单后没有保存")
	assert(FileAccess.file_exists(AudioPreferences.storage_path), "关闭菜单没有触发音频保存")
	var saved_cfg := ConfigFile.new()
	assert(saved_cfg.load(AudioPreferences.storage_path) == OK, "保存的音频配置可解析")
	assert(int(saved_cfg.get_value("meta", "version", -1)) == 2, "保存配置缺少 v2 版本标记")
	assert(is_equal_approx(float(saved_cfg.get_value("audio", "music_volume", -1.0)), 0.55), "音乐音量没有按拖动值保存")
	assert(is_equal_approx(float(saved_cfg.get_value("audio", "sfx_volume", -1.0)), 0.66), "音效音量没有按拖动值保存")
	# 重启等价：全新 AudioPreferences 实例从盘恢复（用户要求重启后数值保留）。
	var reloaded := AudioPreferencesScript.new()
	reloaded.storage_path = AudioPreferences.storage_path
	add_child(reloaded)
	assert(is_equal_approx(reloaded.music_volume, 0.55) and is_equal_approx(reloaded.sfx_volume, 0.66), "重启后音量没有从盘恢复")
	reloaded.queue_free()
	menu.open_menu()
	assert(is_equal_approx(menu.music_slider.value, 55.0) and is_equal_approx(menu.sfx_slider.value, 66.0), "重新打开菜单滑条没有恢复已存音量")
	AudioPreferences.storage_path = original_storage
	root_handler.free()

	menu.settings_back_button.pressed.emit()
	assert(menu.current_page == "main", "设置返回按钮没有回到游戏菜单")
	# 旧断言：back == GothicComponentButton。新断言：当前设置返回宝石按钮体系，且非 toggle。
	# 依据：与继续游戏相同的用户已验收暂停菜单按钮体系；语义“动作不伪装持久选择”保留。
	assert(menu.settings_back_button.theme_type_variation == &"GothicSystemSettingsBackGemButton"
		and not menu.settings_back_button.toggle_mode, "设置返回动作不应伪装为持久选择")

	var action_counts := {"continue": 0, "character": 0, "exit": 0}
	menu.continue_requested.connect(func() -> void: action_counts["continue"] += 1)
	menu.return_to_character_select_requested.connect(func() -> void: action_counts["character"] += 1)
	menu.save_and_exit_requested.connect(func() -> void: action_counts["exit"] += 1)
	menu.continue_button.pressed.emit()
	menu.character_select_button.pressed.emit()
	menu.save_exit_button.pressed.emit()
	assert(action_counts == {"continue": 1, "character": 1, "exit": 1}, "暂停菜单动作信号不完整")
	print("SYSTEM_MENU_GOTHIC_UI_PASS：哥特暂停菜单、游戏设置音量滑条与关闭自动保存均正常")
	get_tree().quit(0)


func _tree_contains_text(root: Node, value: String) -> bool:
	if root is Label and value in root.text:
		return true
	if root is Button and value in root.text:
		return true
	for child in root.get_children():
		if _tree_contains_text(child, value):
			return true
	return false
