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
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	assert(threshold == 3, "120 最大生命的统一硬直阈值应为3点最终伤害")
	assert(str(ProfessionRules.COMBAT_REACTION_POLICY.policy_id) == "player_struck_threshold_v1", "硬直公式必须暴露稳定策略ID")

	player.take_damage(threshold - 1)
	assert(player._struck_lock_remaining <= 0.0, "低于统一阈值的擦伤不得启动硬直锁")
	player.take_damage(threshold)
	assert(player._struck_lock_remaining > 0.0, "达到统一阈值的最终伤害必须启动硬直锁")
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
	player.take_damage(threshold, false)
	assert(player._struck_lock_remaining <= 0.0, "非 RM_STRUCK 的持续伤害不得制造移动硬直")
	assert(ProfessionRules.player_struck_damage_threshold(1000) == 20, "硬直阈值必须随最大生命按2%缩放")

	print("PLAYER_STRUCK_LOCK_PASS: threshold=%d, StruckTime=100ms, walk/run lock verified" % threshold)
	get_tree().quit()
