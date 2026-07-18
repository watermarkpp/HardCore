extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/system_menu_audio_contract_v1.json"
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert(contract is Dictionary, "系统菜单音频契约无法解析")
	assert(contract.get("menuContractId", "") == "ui.system_menu.action.v1", "系统菜单契约 ID 不稳定")
	assert(contract.get("audioContractId", "") == "ui.audio.setting.v1", "音频设置契约 ID 不稳定")
	var menu: Control = SystemMenuPanelScript.new()
	add_child(menu)
	await get_tree().process_frame

	assert(menu.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "暂停菜单不能在游戏暂停时工作")
	assert(menu.modal.theme_type_variation == "GothicModalFrame", "暂停菜单没有使用公共哥特外框")
	assert(menu.current_page == "main" and menu.main_page.visible and not menu.settings_page.visible, "暂停菜单默认页面错误")
	assert(menu.continue_button.size.y >= 56, "继续游戏按钮触控区不足")
	assert(menu.character_select_button.size.y >= 56, "返回人物选择按钮触控区不足")
	assert(menu.save_exit_button.size.y >= 56, "保存并退出按钮触控区不足")
	assert(menu.settings_button.size.y >= 56, "游戏设置按钮触控区不足")
	assert(menu.settings_button.text == "游戏设置", "主菜单没有用游戏设置替代安全回城说明")
	assert(not _tree_contains_text(menu, "安全回城"), "暂停菜单仍显示已删除的安全回城说明")

	menu.show_settings_page()
	assert(menu.current_page == "settings" and menu.settings_page.visible and not menu.main_page.visible, "游戏设置页面没有打开")
	assert(menu.music_toggle.get_meta("setting_id", "") == "audio.music.enabled", "游戏音乐稳定设置 ID 错误")
	assert(menu.sfx_toggle.get_meta("setting_id", "") == "audio.sfx.enabled", "游戏音效稳定设置 ID 错误")
	menu.set_audio_settings(true, true)
	assert(menu.music_status_label.text == "已开启" and menu.sfx_status_label.text == "已开启", "音频开关初始状态没有同步")
	var requests: Array[Dictionary] = []
	menu.audio_setting_changed.connect(func(request: Dictionary) -> void: requests.append(request.duplicate(true)))
	menu.music_toggle.set_pressed(false)
	menu.sfx_toggle.set_pressed(false)
	assert(requests.size() == 2, "音乐和音效开关没有分别发出请求")
	assert(requests[0].contract_id == "ui.audio.setting.v1" and requests[0].setting_id == "audio.music.enabled", "音乐设置请求错误")
	assert(requests[1].setting_id == "audio.sfx.enabled" and not requests[1].enabled, "音效设置请求错误")
	assert(menu.music_status_label.text == "已关闭" and menu.sfx_status_label.text == "已关闭", "关闭音频后状态文字没有更新")
	menu.settings_back_button.pressed.emit()
	assert(menu.current_page == "main", "设置返回按钮没有回到游戏菜单")

	var action_counts := {"continue": 0, "character": 0, "exit": 0}
	menu.continue_requested.connect(func() -> void: action_counts["continue"] += 1)
	menu.return_to_character_select_requested.connect(func() -> void: action_counts["character"] += 1)
	menu.save_and_exit_requested.connect(func() -> void: action_counts["exit"] += 1)
	menu.continue_button.pressed.emit()
	menu.character_select_button.pressed.emit()
	menu.save_exit_button.pressed.emit()
	assert(action_counts == {"continue": 1, "character": 1, "exit": 1}, "暂停菜单动作信号不完整")
	print("SYSTEM_MENU_GOTHIC_UI_PASS：哥特暂停菜单、游戏设置和音乐/音效双开关均正常")
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
