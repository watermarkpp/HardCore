extends Node

const MobileLayoutRules := preload("res://scripts/mobile_layout.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(int(ProjectSettings.get_setting("display/window/handheld/orientation", -1)) == 4, "Android方向不是Sensor Landscape")
	assert(str(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items", "Android未使用CanvasItems缩放")
	assert(str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep", "Android未固定1598×720比例并使用黑边补齐")
	assert(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1598, "Android逻辑画布宽度不是1598")
	assert(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 720, "Android逻辑画布高度不是720")
	_assert_resolution_matrix()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: GameHUD = game.hud
	var root := hud.get_node("MobileSafeRoot") as Control
	assert(not root.get_node("TopInfoPanel").visible, "左上角地图人物信息面板必须移除")
	assert(root != null, "HUD缺少安全区根节点")
	var joystick := root.get_node("TouchJoystick") as Control
	var attack := root.get_node("AttackButton") as Button
	var interact := root.get_node("InteractButton") as Button
	var switch_target := root.get_node("SwitchTargetButton") as Button
	var auto_target := root.get_node("AutoTargetButton") as Button
	_assert_touch_target(joystick, Vector2(150, 150), "虚拟摇杆")
	_assert_touch_target(attack, Vector2(120, 120), "攻击按钮")
	_assert_touch_target(interact, Vector2(110, 76), "交互按钮")
	_assert_touch_target(switch_target, Vector2(110, 76), "换敌按钮")
	_assert_touch_target(auto_target, Vector2(120, 48), "自动选怪开关")
	assert(attack.position + attack.size * 0.5 == root.size + GameHUD.HUD_ATTACK_CENTER, "攻击键没有按统一圆心向屏幕内部移动")
	assert(joystick.position == Vector2(70, root.size.y - 210), "摇杆没有按统一矩形向屏幕内部移动")
	assert(bool(attack.call("_has_point", attack.size * 0.5)) and not bool(attack.call("_has_point", Vector2.ZERO)), "攻击键触控仍为方形")
	var previous_ring_center := Vector2.ZERO
	for index in range(6):
		var ring := root.get_node("AttackRingSkill%d" % (index + 1)) as Button
		_assert_touch_target(ring, Vector2(72, 72), "环形技能按钮%d" % (index + 1))
		assert(root.get_node_or_null("SkillButton%d" % (index + 1)) == null, "旧中央技能按钮仍在Android HUD")
		var ring_center := ring.position + ring.size * 0.5
		assert(is_equal_approx(ring_center.distance_to(attack.position + attack.size * 0.5), GameHUD.HUD_ATTACK_RING_RADIUS), "六技能环半径不统一")
		assert(bool(ring.call("_has_point", ring.size * 0.5)) and not bool(ring.call("_has_point", Vector2.ZERO)), "六技能环仍使用方形触控")
		if index > 0:
			assert(ring_center.distance_to(previous_ring_center) > ring.size.x, "相邻六技能环圆形触控区重叠")
		previous_ring_center = ring_center

	var received := {
		"movement": Vector2.ZERO,
		"attack": 0,
		"attack_release": 0,
		"interact": 0,
		"switch": 0,
		"auto": true,
		"skill_group": "",
		"skill_index": -1,
	}
	hud.movement_changed.connect(func(value: Vector2) -> void: received.movement = value)
	hud.attack_pressed.connect(func() -> void: received.attack = int(received.attack) + 1)
	hud.attack_released.connect(func() -> void: received.attack_release = int(received.attack_release) + 1)
	hud.interact_pressed.connect(func() -> void: received.interact = int(received.interact) + 1)
	hud.target_switch_pressed.connect(func() -> void: received.switch = int(received.switch) + 1)
	hud.auto_target_changed.connect(func(enabled: bool) -> void: received.auto = enabled)
	hud.skill_input_started.connect(
		func(slot_group: String, slot_index: int, _token: int, _touch_id: int, _source: StringName) -> void:
			received.skill_group = slot_group
			received.skill_index = slot_index
	)
	(joystick as TouchJoystick).vector_changed.emit(Vector2(0.75, -0.25))
	var attack_touch := InputEventScreenTouch.new()
	attack_touch.index = 0
	attack_touch.position = attack.size * 0.5
	attack_touch.pressed = true
	attack.call("_gui_input", attack_touch)
	attack_touch.pressed = false
	attack.call("_gui_input", attack_touch)
	interact.button_down.emit()
	switch_target.pressed.emit()
	auto_target.toggled.emit(false)
	var ring_touch := InputEventScreenTouch.new()
	ring_touch.index = 6
	ring_touch.position = Vector2(36, 36)
	ring_touch.pressed = true
	(root.get_node("AttackRingSkill6") as Button).call("_gui_input", ring_touch)
	ring_touch.pressed = false
	(root.get_node("AttackRingSkill6") as Button).call("_gui_input", ring_touch)
	assert((received.movement as Vector2).is_equal_approx(Vector2(0.75, -0.25)), "摇杆信号没有接入角色移动")
	assert(int(received.attack) == 1 and int(received.attack_release) == 1 and int(received.interact) == 1, "攻击按下、松开或交互触控接线失败")
	assert(int(received.switch) == 1 and not bool(received.auto), "换敌或自动选怪开关接线失败")
	assert(
		str(received.skill_group) == "attack_ring" and int(received.skill_index) == 5,
		"技能触控槽位分组接线失败"
	)

	PlayerState._notification(NOTIFICATION_APPLICATION_PAUSED)
	PlayerState._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	print("ANDROID_LAYOUT_PASS：Sensor Landscape、16:9/20:9/挖孔安全区、10个触控目标与后台存档通知正常")
	get_tree().quit(0)


func _assert_resolution_matrix() -> void:
	var cases := [
		{"window": Vector2(1920, 1080), "safe": Rect2(0, 0, 1920, 1080), "logical": Vector2(1280, 720), "expected": Vector4.ZERO},
		{"window": Vector2(2400, 1080), "safe": Rect2(80, 0, 2240, 1080), "logical": Vector2(1600, 720), "expected": Vector4(53.333, 0, 53.333, 0)},
		{"window": Vector2(2400, 1080), "safe": Rect2(120, 0, 2280, 1080), "logical": Vector2(1600, 720), "expected": Vector4(80, 0, 0, 0)},
		{"window": Vector2(2340, 1080), "safe": Rect2(90, 30, 2160, 1020), "logical": Vector2(1560, 720), "expected": Vector4(60, 20, 60, 20)},
	]
	for entry: Dictionary in cases:
		var actual: Vector4 = MobileLayoutRules.safe_margins(entry.window, entry.safe, entry.logical)
		var expected: Vector4 = entry.expected
		assert(actual.is_equal_approx(expected), "安全区换算错误：%s != %s" % [actual, expected])


func _assert_touch_target(control: Control, minimum: Vector2, label: String) -> void:
	assert(control != null, "%s不存在" % label)
	assert(control.size.x + 0.01 >= minimum.x and control.size.y + 0.01 >= minimum.y, "%s触控面积不足：%s" % [label, control.size])
