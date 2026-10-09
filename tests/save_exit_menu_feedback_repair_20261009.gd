extends Node

const MenuScript := preload("res://scripts/system_menu_panel.gd")

var _signal_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu: SystemMenuPanel = MenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	menu.show()
	menu.get_tree().paused = true
	menu.save_and_exit_requested.connect(_on_save_exit_requested)

	menu.call("_request_save_exit")
	assert(_signal_count == 1, "真实保存退出请求必须发出 save_and_exit_requested")
	assert(menu.save_exit_failure_label != null, "暂停菜单必须有保存退出失败提示控件")
	assert(not menu.save_exit_failure_label.visible, "请求发出前失败提示必须隐藏")
	assert(menu.menu_footer.visible, "正常菜单必须显示 Android 返回提示")

	menu.show_save_exit_failure("安全退出失败，请稍后重试。")
	assert(menu.save_exit_failure_label.visible, "保存失败提示必须在暂停菜单层可见")
	assert(menu.save_exit_failure_label.text == "安全退出失败，请稍后重试。", "失败提示文案必须保留")
	assert(not menu.menu_footer.visible, "失败提示显示时不得与 Footer 重叠")
	assert(menu.main_page.visible and not menu.settings_page.visible, "失败提示必须返回菜单主页面")

	menu.call("_request_continue")
	assert(not menu.save_exit_failure_label.visible, "继续游戏必须清除保存失败提示")
	assert(menu.menu_footer.visible, "继续游戏后必须恢复 Footer")
	get_tree().paused = false
	menu.queue_free()
	print("SAVE_EXIT_MENU_FEEDBACK_REPAIR_PASS")
	get_tree().quit(0)


func _on_save_exit_requested() -> void:
	_signal_count += 1
