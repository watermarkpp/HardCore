extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("道士")
	PlayerState.level = 35
	PlayerState.learned_skills = {"召唤骷髅": 3, "召唤神兽": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player

	var skeleton := SummonActor.new()
	skeleton.setup(player, "骷髅", 30, 3, "taoist.summon_skeleton", 35)
	skeleton.global_position = player.global_position
	game.add_child(skeleton)
	await get_tree().process_frame
	assert(skeleton.skill_id == "taoist.summon_skeleton" and skeleton.attack_type == "physical", "骷髅稳定ID/攻击类型错误")
	assert(skeleton.state == SummonActor.SummonState.FOLLOW_OWNER, "骷髅初始状态错误")
	var enemy := EnemyActor.new()
	enemy.setup({"name": "召唤测试目标", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1}, player, false)
	enemy.control_time = 60.0
	enemy.global_position = skeleton.global_position + Vector2(skeleton.attack_range + 30.0, 0)
	game.add_child(enemy)
	skeleton._current_target = enemy
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.CHASE_TARGET, "召唤物没有进入追击状态")
	enemy.global_position = skeleton.global_position + Vector2(10.0, 0)
	var enemy_hp := enemy.current_hp
	skeleton._attack_timer = 0.0
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.ATTACK_TARGET and enemy.current_hp < enemy_hp, "召唤物没有进入攻击状态")
	assert(skeleton.last_attack_type == "physical", "召唤物攻击类型没有进入攻击状态机")
	skeleton.global_position = player.global_position + Vector2(skeleton.teleport_range + 20.0, 0)
	skeleton._physics_process(0.016)
	assert(skeleton.global_position.distance_to(player.global_position) < 100.0, "召唤物超距没有回到主人身边")
	assert(skeleton.state == SummonActor.SummonState.RETURN_TO_OWNER, "召唤物超距状态错误")
	skeleton.remaining_lifetime = 0.001
	skeleton._physics_process(0.016)
	assert(skeleton.state == SummonActor.SummonState.EXPIRED or skeleton.is_queued_for_deletion(), "召唤物生存期结束后未过期")

	var divine_beast := SummonActor.new()
	divine_beast.setup(player, "神兽", 30, 3, "taoist.summon_divine_beast", 35)
	assert(divine_beast.skill_id == "taoist.summon_divine_beast" and divine_beast.attack_type == "fire", "神兽稳定ID/攻击类型错误")
	assert(divine_beast.max_hp > skeleton.max_hp and divine_beast.attack_range > skeleton.attack_range, "神兽成长或攻击范围未区分")
	divine_beast.free()
	print("SUMMON_ACTOR_STATE_MACHINE_PASS：等级、攻击类型、生存期、超距回归与过期状态正常")
	get_tree().quit(0)
