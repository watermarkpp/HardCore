extends Control

const DeathRevivalPanelScript := preload("res://scripts/death_revival_panel.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	size = Vector2(1598, 720)
	var panel: Control = DeathRevivalPanelScript.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.open_death_screen({
		"death_id": "death:touch:001",
		"revival_options": [{
			"option_slot": "town",
			"method_id": "revive.nearest_town",
			"label": "最近城镇复活",
			"enabled": true,
			"countdown_seconds": 0,
		}],
	})
	assert(panel.process_mode == Node.PROCESS_MODE_ALWAYS, "死亡界面必须在未暂停时保持触摸输入处理")
	var requests: Array[Dictionary] = []
	panel.revival_requested.connect(func(request: Dictionary) -> void: requests.append(request.duplicate(true)))
	await get_tree().process_frame
	var rect: Rect2 = panel.town_button.get_global_rect()
	var center: Vector2 = rect.get_center()
	var window_scale: Vector2 = Vector2(get_window().size) / get_viewport().get_visible_rect().size
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = center * window_scale
	down.pressed = true
	get_viewport().push_input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = center * window_scale
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame
	assert(requests.size() == 1, "真实触摸事件没有触发最近城镇复活请求")
	assert(panel.town_button.get_meta("gothic_feedback_state", "") == "transition", "城镇复活没有保持过渡反馈直到 Loading 接管")
	assert(panel.town_button.disabled and panel.special_button.disabled, "复活请求处理中没有锁定重复操作")
	assert(requests[0].get("contract_id", "") == "ui.death.revival.v1", "触摸请求缺少死亡复活契约")
	assert(requests[0].get("death_id", "") == "death:touch:001", "触摸请求缺少死亡事件 ID")
	assert(requests[0].get("method_id", "") == "revive.nearest_town", "触摸请求方法错误")
	print("DEATH_REVIVAL_TOUCH_INPUT_PASS: real screen-touch button activation")
	get_tree().quit(0)
