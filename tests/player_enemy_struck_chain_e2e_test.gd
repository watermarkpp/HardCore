extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = false
	PlayerState.active_profile_id = ""
	PlayerState.reset_progress(false)
	PlayerState.select_profession("战士")
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.visual.set_process(false)
	player.max_hp = 500
	player.current_hp = 500
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = Vector2(58, 0)
	player.set_touch_vector(Vector2.RIGHT)
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	assert(threshold == 10, "500 最大生命的 2% 硬直阈值必须保持 10")
	assert(ProfessionRules.player_struck_damage_threshold(120) == 3, "最低 3 点硬直阈值被改写")

	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster("骷髅精灵"), player, true)
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.attack_min = threshold
	enemy.attack_max = threshold
	enemy._attack_timer = 0.0
	assert(
		is_equal_approx(enemy._attack_hit_delay, 0.3),
		"端到端测试必须使用真实骷髅精灵命中帧时序"
	)

	var hp_before := player.current_hp
	enemy._physics_process(0.01)
	assert(
		enemy._pending_attack_time > 0.0 and player.current_hp == hp_before,
		"Enemy 真实攻击没有先进入客户端命中帧等待"
	)
	enemy._physics_process(0.28)
	assert(player.current_hp == hp_before, "Enemy 伤害在真实命中帧之前提前结算")
	enemy._physics_process(0.03)
	assert(
		player.current_hp == hp_before - threshold,
		"Enemy._deal_melee_hit 没有向 Player 提交精确最终伤害"
	)
	assert(
		player._struck_lock_remaining > 0.0
		and player._struck_reaction_lock_remaining > 0.0
		and not player.can_start_attack(),
		"达到 2% 阈值后没有建立服务器动作锁和受击表现锁"
	)

	var observed_frames: Array[int] = []
	for delta: float in [0.001, 0.08, 0.08]:
		player.visual._process(delta)
		observed_frames.append(player.visual.current_frame)
	assert(player.visual.current_animation_name() == "hit", "Enemy 命中没有触发 Player hit 动作")
	assert(player.visual._frame_count_for_action("hit") == 3, "Player hit 动作必须恰好三帧")
	assert(observed_frames == [0, 1, 2], "三帧 hit 动作时序错误：%s" % [observed_frames])

	var struck_position := player.global_position
	player._physics_process(0.10)
	assert(
		player.global_position.is_equal_approx(struck_position)
		and player.velocity.is_zero_approx()
		and player._struck_lock_remaining <= 0.0
		and player._struck_reaction_lock_remaining > 0.0,
		"100ms 服务器动作锁与 240ms 表现锁没有独立计时"
	)
	player._physics_process(0.14)
	assert(
		player.global_position.is_equal_approx(struck_position),
		"三帧受击表现结束前人物发生位移"
	)
	player._physics_process(0.01)
	assert(player.velocity.x > 0.0, "240ms 受击表现结束后输入没有恢复")

	PlayerState.test_mode = true
	print("PLAYER_ENEMY_STRUCK_CHAIN_E2E_PASS: Enemy hit frame -> damage -> 3 hit frames -> 100/240ms locks")
	get_tree().quit(0)
