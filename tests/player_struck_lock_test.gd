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

	assert(is_equal_approx(ProfessionRules.player_struck_action_lock_seconds(), 0.100), "修改版1.5服务端 StruckTime=100 仅作为新动作锁证据")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(1), 0.414), "1级三帧受击表现应为414ms")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(10), 0.360), "10级三帧受击表现应为360ms")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(20), 0.300), "20级三帧受击表现应为300ms")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(24), 0.300), "24级三帧受击表现应为300ms")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(40), 0.300), "40级三帧受击表现应为300ms")
	assert(is_equal_approx(ProfessionRules.player_struck_reaction_seconds(50), 0.300), "50级三帧受击表现应为300ms")
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	assert(threshold == 3, "120 最大生命的统一硬直阈值应为3点最终伤害")
	assert(str(ProfessionRules.COMBAT_REACTION_POLICY.policy_id) == "hardcore_player_hit_reaction_v3", "硬直公式必须明确标识为HardCore策略")
	assert(str(ProfessionRules.COMBAT_REACTION_POLICY.origin) == "hardcore_custom_balance_not_original_176", "自定义阈值不得伪装成1.76原版")
	var evidence: Array = ProfessionRules.COMBAT_REACTION_POLICY.evidence
	assert(evidence.size() >= 3 and str(evidence[0].scope) == "modified_1.5_2002_not_verified_1.76", "证据必须标明本地源码版本边界并保留公开旁证")

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
	assert(player.global_position.is_equal_approx(struck_position), "100ms服务端动作锁内不得移动")
	assert(player.velocity.is_zero_approx(), "100ms动作锁内速度必须保持为零")
	assert(player._struck_lock_remaining <= 0.0 and player._struck_reaction_lock_remaining > 0.0, "100ms动作锁与414ms受击表现必须分开计时")
	player._physics_process(0.30)
	assert(player.global_position.is_equal_approx(struck_position), "三帧受击表现结束前不得滑行")
	player._physics_process(0.02)
	assert(player.global_position.is_equal_approx(struck_position), "414ms边界帧仍应保持原位")
	player._physics_process(0.01)
	assert(player.velocity.x > 0.0, "414ms受击表现结束后，持续输入应恢复移动速度")

	player._struck_lock_remaining = 0.0
	player.take_damage(threshold, false)
	assert(player._struck_lock_remaining <= 0.0, "非 RM_STRUCK 的持续伤害不得制造移动硬直")
	assert(ProfessionRules.player_struck_damage_threshold(1000) == 20, "硬直阈值必须随最大生命按2%缩放")

	print("PLAYER_STRUCK_LOCK_PASS: HardCore threshold=%d, server lock=100ms, visual recovery=300-414ms" % threshold)
	get_tree().quit()
