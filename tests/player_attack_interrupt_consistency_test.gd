extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	var player := PlayerCharacter.new()
	add_child(player)
	player.attack_min = 7
	player.attack_max = 7
	player.defense_min = 0
	player.defense_max = 0
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	var target_hp := [100]
	var emitted_hits := [0]
	player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, damage: int) -> void:
		target_hp[0] -= damage
		emitted_hits[0] += 1
	)

	# 阈值以下的擦伤既不打断动作，也不撤销其命中事务。
	assert(player.request_attack(), "擦伤场景必须能开始攻击")
	await get_tree().create_timer(0.05).timeout
	player.take_damage(threshold - 1)
	assert(player._struck_lock_remaining <= 0.0, "阈值以下伤害不得产生硬直")
	assert(str(player.visual._action_name) == "attack", "擦伤不得把攻击动画替换为受击")
	await get_tree().create_timer(0.15).timeout
	assert(emitted_hits[0] == 1 and target_hp[0] == 93, "未硬直的攻击应在命中帧正常且仅结算一次")

	# 修改版1.5客户端把受击排在当前动作后；命中帧前受击不得伪装取消攻击。
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_attack(), "命中前取消场景必须能开始攻击")
	await get_tree().create_timer(0.05).timeout
	assert(not bool(player.combat_action_snapshot().committed), "命中帧前事务不应提前提交")
	player.take_damage(threshold)
	assert(player._struck_lock_remaining > 0.0, "达到阈值必须产生硬直")
	assert(str(player.visual._action_name) == "attack", "受击不得在命中帧前伪装取消正在播放的攻击")
	assert(bool(player.combat_action_snapshot().active), "命中帧前受击应保留当前攻击事务")
	assert(bool(player.struck_reaction_snapshot().queued), "受击表现必须排到当前攻击动作之后")
	await get_tree().create_timer(0.15).timeout
	assert(emitted_hits[0] == 2 and target_hp[0] == 86, "未被视觉伪取消的攻击应在命中帧结算一次")
	assert(bool(player.combat_action_snapshot().committed), "伤害发出时事务必须同步提交")
	await get_tree().create_timer(0.32).timeout
	assert(str(player.visual._action_name) == "hit", "攻击动作结束后必须播放排队的受击表现")
	await get_tree().create_timer(0.43).timeout

	# 命中帧后事务已经提交；随后受击同样排队，不能撤销或重复该次伤害。
	player._struck_lock_remaining = 0.0
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_attack(), "命中后受击场景必须能开始攻击")
	await get_tree().create_timer(0.19).timeout
	assert(emitted_hits[0] == 3 and target_hp[0] == 79, "命中帧后的攻击伤害必须已经提交一次")
	assert(bool(player.combat_action_snapshot().committed), "命中信号与事务提交状态必须同步")
	player.take_damage(threshold)
	assert(str(player.visual._action_name) == "attack", "攻击恢复帧内的受击表现仍应排队而非截断")
	await get_tree().create_timer(0.08).timeout
	assert(emitted_hits[0] == 3 and target_hp[0] == 79, "命中后受击不得回滚或重复已提交伤害")

	print("PLAYER_ATTACK_INTERRUPT_CONSISTENCY_PASS: threshold=%d, struck queued, each attack committed once" % threshold)
	get_tree().quit(0)
