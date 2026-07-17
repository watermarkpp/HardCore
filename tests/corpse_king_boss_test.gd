extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var rule: Dictionary = GameData.boss_service_rules.get("runtimeRules", {}).get("尸王", {})
	assert(int(rule.get("serviceRace", 0)) == 81 and rule.get("serviceClass", "") == "TATMonster", "尸王服务端类映射错误")
	assert(not bool(rule.get("specialSkill", {}).get("enabled", true)) and not bool(rule.get("phaseTwo", {}).get("enabled", true)), "尸王仍保留无来源范围技能")

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	# 固定战斗夹具，避免本地存档中的魔法盾/复活装备污染命中断言。
	player.max_hp = 500
	player.current_hp = 500
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = Vector2(58, 0)
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster("尸王"), player, true)
	add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame
	var visual: MonsterVisual = boss.get_node("MonsterVisual")
	var sprite: Sprite2D = visual.get_node("BodySprite")
	assert(visual.uses_final_art() and visual.frame_size == Vector2i(160, 160), "尸王客户端资源未启用")
	assert(sprite.position == Vector2(-80, -138) and visual.position.y == 6.0, "尸王脚底锚点与阴影不共面")
	assert(boss.name_label.position.y == -116.0, "尸王名称压住大型造型")
	assert(boss.max_hp == 500 and boss.attack_min == 18 and boss.attack_max == 36, "尸王2003候选属性未采用")
	assert(is_equal_approx(boss._attack_interval, 2.8) and is_equal_approx(boss._attack_animation_duration, 0.72) and is_equal_approx(boss._attack_hit_delay, 0.36), "尸王速度或命中帧错误")

	var hp_before := player.current_hp
	boss._physics_process(0.01)
	assert(boss._pending_attack_time > 0.0 and player.current_hp == hp_before, "尸王伤害没有等待命中帧")
	player.global_position = Vector2(0, 58)
	boss._physics_process(0.12)
	assert(boss.facing.dot(Vector2.DOWN) > 0.99 and boss.velocity == Vector2.ZERO, "尸王追击/攻击时没有持续面对玩家")
	boss._physics_process(0.25)
	assert(player.current_hp < hp_before, "尸王客户端命中帧没有结算伤害")
	var speed_before := boss.move_speed
	boss.take_damage(251)
	assert(not boss._boss_phase_two and boss.move_speed == speed_before and boss._boss_warning <= 0.0, "尸王仍触发无来源狂暴或震地")
	boss.set_targeted(true)
	assert(boss.is_targeted and visual.position.y == 6.0, "尸王选中状态改变了脚底高度")
	assert(boss.ground_indicator_center().is_equal_approx(visual.position + visual.ground_contact_offset()), "尸王锁定光圈没有与真实脚底接触点共面")
	assert(boss.ground_indicator_center().distance_to(Vector2(0, 27.0 * 0.28)) > 15.0, "尸王锁定光圈仍停留在 Enemy 逻辑原点")
	print("CORPSE_KING_BOSS_PASS：Race81/TATMonster、2.8秒攻击、命中帧、持续朝向、无伪技能与脚底选中正常")
	get_tree().quit(0)
