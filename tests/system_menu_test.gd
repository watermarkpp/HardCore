extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false, "Android返回键仍会被引擎直接退出")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	assert(game.get("_system_menu_panel") != null, "游戏内系统菜单未创建")
	game.call("_show_system_menu")
	assert(get_tree().paused and game.get("_system_menu_panel").visible, "系统菜单没有暂停游戏")
	game.call("_hide_system_menu")
	assert(not get_tree().paused and not game.get("_system_menu_panel").visible, "继续游戏没有关闭菜单")
	game.queue_free()
	PlayerState.test_mode = false
	print("SYSTEM_MENU_PASS：返回键菜单、暂停与继续入口正常")
	get_tree().quit(0)
