extends Node


func _ready() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var player := PlayerCharacter.new()
	add_child(player)
	player.attack_min = 1
	player.attack_max = 1
	assert(is_equal_approx(player.attack_cooldown, 0.9), "零攻速档普通攻击最小间隔必须为900ms")
	assert(is_equal_approx(player.attack_animation_duration, 0.51), "战士普通攻击动作必须约为510ms")
	assert(is_equal_approx(player.attack_hit_windup, 0.17), "客户端第2号表现帧应在170ms触发")
	assert(player.request_attack(), "空闲状态应能开始普通攻击")
	assert(not player.can_start_attack(), "攻击动作期间不得发起下一刀")
	player.touch_vector = Vector2.RIGHT
	var locked_position := player.global_position
	player._physics_process(0.25)
	assert(player.global_position.is_equal_approx(locked_position), "完整攻击动作结束前不得移动")
	player._physics_process(0.27)
	assert(player._attack_action_timer <= 0.0, "510ms后攻击动作锁应结束")
	assert(not player.can_start_attack(), "动作结束后仍应等待900ms攻击间隔")
	player._physics_process(0.39)
	assert(player.can_start_attack(), "900ms攻击间隔结束后应允许下一刀")
	print("WARRIOR_ATTACK_TIMING_PASS：900ms续刀间隔、510ms完整动作锁和独立计时正常")
	get_tree().quit()
