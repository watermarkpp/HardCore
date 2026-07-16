extends Node


func _ready() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	var player := PlayerCharacter.new()
	add_child(player)
	player.current_hp = player.max_hp
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.set_touch_vector(Vector2.RIGHT)

	assert(is_equal_approx(player.SERVER_STRUCK_TIME_SECONDS, 0.100), "服务端 StruckTime=100 必须映射为 100ms")
	assert(player.SERVER_STRUCK_DAMAGE_THRESHOLD == 0, "RM_STRUCK 的触发条件必须保持为最终伤害 nPower > 0")

	player.take_damage(1)
	assert(player._struck_lock_remaining > 0.0, "正伤害必须启动硬直锁")
	assert(not player.can_start_attack(), "硬直期间必须拒绝攻击动作")
	var struck_position := player.global_position
	player._physics_process(0.05)
	assert(player.global_position.is_equal_approx(struck_position), "硬直前 50ms 不得移动")
	assert(player.velocity.is_zero_approx(), "硬直前 50ms 速度必须归零")
	player._physics_process(0.05)
	assert(player.global_position.is_equal_approx(struck_position), "完整 100ms 硬直窗口内不得移动")
	assert(player.velocity.is_zero_approx(), "完整 100ms 窗口内速度必须保持为零")
	player._physics_process(0.01)
	assert(player.velocity.x > 0.0, "100ms 硬直结束后，持续输入应恢复移动速度")

	player._struck_lock_remaining = 0.0
	player.take_damage(1, false)
	assert(player._struck_lock_remaining <= 0.0, "非 RM_STRUCK 的持续伤害不得制造移动硬直")

	print("PLAYER_STRUCK_LOCK_PASS: nPower>0, StruckTime=100ms, walk/run lock verified")
	get_tree().quit()
