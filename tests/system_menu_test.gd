extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false, "Android返回键仍会被引擎直接退出")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var ready_deadline := Time.get_ticks_msec() + 10000
	while (
		(not game.gameplay_input_is_enabled() or game._world_bootstrap_in_progress)
		and Time.get_ticks_msec() < ready_deadline
	):
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "system menu input fixture did not reach formal READY")
	assert(game.get("_system_menu_panel") != null, "游戏内系统菜单未创建")
	assert(game.get("_system_menu_panel") is SystemMenuPanel, "主体游戏仍在使用临时系统菜单")
	assert(game.get("_system_menu_panel").settings_button != null, "UI 分支制作的设置入口未接入")
	var menu: Control = game.get("_system_menu_panel")
	# A menu pause is an input lifecycle boundary. Android can suppress the UP
	# that would otherwise clear these owners while the SceneTree is paused.
	var attack_release_count := {"value": 0}
	game.player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
		attack_release_count.value += 1
	)
	var attack_down := InputEventScreenTouch.new()
	attack_down.index = 1
	attack_down.pressed = true
	attack_down.position = game.hud.attack_button.size * 0.5
	game.hud.attack_button._gui_input(attack_down)
	var joystick_touch := InputEventScreenTouch.new()
	joystick_touch.index = 0
	joystick_touch.pressed = true
	joystick_touch.position = Vector2(110.0, 72.0)
	game.hud.movement_joystick._gui_input(joystick_touch)
	assert(game._mobile_attack_held)
	assert(game.hud.attack_button.active_input_count() == 1)
	assert(game.hud.movement_joystick.input_state_snapshot().pointer_id == 0)
	var attack_deadline := Time.get_ticks_msec() + 1500
	while attack_release_count.value == 0 and Time.get_ticks_msec() < attack_deadline:
		await get_tree().process_frame
	assert(attack_release_count.value > 0, "real HUD attack DOWN did not reach player.attack_requested")
	# Ordinary show/hide owns and releases only the pause created by the menu.
	game.call("_show_system_menu")
	assert(get_tree().paused and menu.visible, "系统菜单没有暂停游戏")
	assert(not game._mobile_attack_held and game._active_mobile_attack_tokens.is_empty(),
		"系统菜单暂停前没有撤销攻击触摸所有权")
	assert(game.hud.attack_button.active_input_count() == 0,
		"系统菜单暂停前没有撤销HUD按钮所有权")
	assert(game.hud.movement_joystick.input_state_snapshot().pointer_id == -1,
		"系统菜单暂停前没有撤销摇杆触摸所有权")
	assert(bool(game.get("_system_menu_pause_owned")), "系统菜单没有记录自身暂停所有权")
	game.call("_hide_system_menu")
	assert(not get_tree().paused and not menu.visible, "继续游戏没有关闭菜单")
	assert(not bool(game.get("_system_menu_pause_owned")), "继续游戏没有释放系统菜单暂停所有权")
	assert(menu._layout_apply_count == 1, "系统菜单重复打开重复应用布局")

	# Resume requires one new physical lifecycle. Reusing touch index 0 is valid
	# after the old joystick owner was cancelled and must leave no owner on UP.
	var resumed_down := InputEventScreenTouch.new()
	resumed_down.index = 0
	resumed_down.pressed = true
	resumed_down.position = game.hud.attack_button.size * 0.5
	game.hud.attack_button._gui_input(resumed_down)
	assert(game.hud.attack_button.active_input_count() == 1 and game._mobile_attack_held)
	var resumed_up := InputEventScreenTouch.new()
	resumed_up.index = 0
	resumed_up.pressed = false
	resumed_up.position = resumed_down.position
	game.hud.attack_button._gui_input(resumed_up)
	assert(game.hud.attack_button.active_input_count() == 0 and not game._mobile_attack_held,
		"resume DOWN/UP left a stale attack owner")

	# Android WM back arrives as a notification rather than ui_cancel.  It must
	# toggle in both directions, including the deferred close from a paused tree.
	game.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert(get_tree().paused and menu.visible, "Android返回键没有打开并暂停系统菜单")
	game.call("_notification", Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	assert(not get_tree().paused and not menu.visible, "Android返回键没有关闭菜单并恢复游戏")

	# An external hide must self-heal the pause, without requiring a second
	# input event or releasing an unrelated pause source.
	game.call("_show_system_menu")
	assert(get_tree().paused and menu.visible, "自愈测试前系统菜单未打开")
	menu.hide()
	assert(not get_tree().paused and not bool(game.get("_system_menu_pause_owned")), "菜单意外隐藏后仍持有暂停")

	# Leave the global tree and test-mode singleton in a known state on every
	# successful path; the test runner must not leak a paused tree.
	get_tree().paused = false
	game.queue_free()
	PlayerState.test_mode = false
	print("SYSTEM_MENU_PASS：返回键菜单、暂停与继续入口正常")
	get_tree().quit(0)
