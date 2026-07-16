extends Node

const TargetingSystem := preload("res://scripts/targeting_system.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_assert_direction_priority()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(enemies.size() >= 4, "选敌规则测试缺少怪物")
	var first := enemies[0] as EnemyActor
	var second := enemies[1] as EnemyActor
	var side := enemies[2] as EnemyActor
	var behind := enemies[3] as EnemyActor
	for enemy: EnemyActor in [first, second, side, behind]:
		enemy.control_time = 30.0
		enemy.max_hp = 9999
		enemy.current_hp = 9999
	for index in range(4, enemies.size()):
		(enemies[index] as EnemyActor).global_position = Vector2(3000 + index * 80, 3000)

	game.player.global_position = Vector2.ZERO
	game.player.velocity = Vector2.ZERO
	game.player.facing = Vector2.RIGHT
	first.global_position = Vector2(80, 0)
	second.global_position = Vector2(160, 10)
	side.global_position = Vector2(0, 55)
	behind.global_position = Vector2(-45, 0)
	game._request_mobile_attack()
	assert(game.locked_target == first and first.is_targeted, "自动普攻没有选择最近正面目标")

	first.global_position = Vector2(0, 70)
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(game.locked_target == second, "怪物位置改变后普攻没有重新选择正面目标")
	first.global_position = Vector2(70, 0)
	game.player.movement_performed.emit(game.player.global_position, game.player.facing)
	assert(game.locked_target == null, "自动模式在人物移动时仍持续锁定怪物")
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(game.locked_target == first and game.player.facing.dot(game.player.global_position.direction_to(first.global_position)) > 0.999, "攻击时没有重新选怪并强制面向目标")
	game.player.visual._process(0.01)
	assert(game.player.visual.current_direction == ArtSpec.mir2_client_direction_row(game.player.global_position.direction_to(first.global_position)), "攻击动作画面没有同步转向目标")

	game._set_auto_target_enabled(false)
	assert(not game.auto_target_enabled and game.hud.auto_target_button.text.contains("关"), "自动选怪开关没有关闭")
	first.global_position = Vector2(-60, 0)
	second.global_position = Vector2(90, 0)
	side.global_position = Vector2(150, 20)
	behind.global_position = Vector2(-35, 0)
	game.player.movement_performed.emit(game.player.global_position, game.player.facing)
	assert(game.locked_target == first, "手动模式在人物移动后擅自更换了目标")
	game._cycle_target()
	assert(game.locked_target == second, "手动换敌没有从最近的正面目标开始")
	game._cycle_target()
	assert(game.locked_target == side, "手动换敌没有按距离切到更远的正面目标")
	game._cycle_target()
	assert(game.locked_target == second and game.locked_target != behind, "手动换敌切到了人物背后或没有循环")

	await _assert_player_cannot_push_enemy(game, first, second, side, behind)
	await _assert_boss_faces_player(game, enemies)

	for index in range(enemies.size()):
		(enemies[index] as EnemyActor).global_position = Vector2(3000 + index * 80, 3000)
	second.global_position = game.player.global_position + Vector2(90, 0)
	side.global_position = game.player.global_position + Vector2(150, 20)
	game.player.facing = Vector2.RIGHT
	game._set_auto_target_enabled(true)
	assert(game.auto_target_enabled and game.locked_target == null, "开启自动选怪后不应在攻击前持续锁定")
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(game.locked_target == second, "攻击发生时没有选择最近正面目标")
	for index in range(enemies.size()):
		(enemies[index] as EnemyActor).global_position = Vector2(3000 + index * 80, 3000)
	second.global_position = game.player.global_position + Vector2(0, -90)
	game._cancel_target()
	game.player.facing = Vector2.DOWN
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	game.player.visual._process(0.01)
	assert(game.player.facing == Vector2.UP and game.player.visual.current_direction == 0, "向北攻击没有在动作开始帧转向目标")
	assert(game._skill_needs_target("projectile") and game._skill_needs_target("area"), "攻击技能目标规则错误")
	assert(not game._skill_needs_target("heal") and not game._skill_needs_target("summon"), "增益或召唤不应抢夺目标方向")
	var flying := EnemyActor.new()
	flying.setup(GameData.get_monster("山洞蝙蝠"), game.player, false)
	game.add_child(flying)
	await get_tree().process_frame
	assert(flying.collision_layer == 0 and flying.collision_mask == 1, "飞行怪仍阻挡人物移动")
	flying.queue_free()
	print("MOBILE_TARGETING_PASS：仅攻击时自动锁定、攻击转向、正侧背优先、手动换敌与Boss朝向正常")
	get_tree().quit(0)


func _assert_direction_priority() -> void:
	var front_near := Node2D.new()
	front_near.position = Vector2(90, 20)
	var front_far := Node2D.new()
	front_far.position = Vector2(180, 0)
	var side := Node2D.new()
	side.position = Vector2(0, 35)
	var behind := Node2D.new()
	behind.position = Vector2(-25, 0)
	for node: Node2D in [front_near, front_far, side, behind]:
		add_child(node)
	assert(TargetingSystem.select_target([behind, side, front_far, front_near], Vector2.ZERO, Vector2.RIGHT) == front_near, "自动选敌没有优先最近正面目标")
	assert(TargetingSystem.select_target([behind, side], Vector2.ZERO, Vector2.RIGHT) == side, "正面无怪时没有选择侧面目标")
	assert(TargetingSystem.select_target([behind], Vector2.ZERO, Vector2.RIGHT) == behind, "仅背面有怪时没有选择背面目标")
	var ordered := TargetingSystem.front_targets([front_far, behind, front_near], Vector2.ZERO, Vector2.RIGHT)
	assert(ordered.size() == 2 and ordered[0] == front_near and ordered[1] == front_far, "手动正面目标没有按距离排序")
	for node: Node2D in [front_near, front_far, side, behind]:
		node.queue_free()


func _assert_player_cannot_push_enemy(game: Node, blocker: EnemyActor, second: EnemyActor, side: EnemyActor, behind: EnemyActor) -> void:
	# Keep this collision-only check outside the real nine-tile safe zone; enemies
	# inside that circle are intentionally expelled by GameRoot every frame.
	var arena_origin: Vector2 = game._bich_home_world_position() + Vector2(600, 0)
	for enemy: EnemyActor in [second, side, behind]:
		enemy.global_position = arena_origin + Vector2(700, 300) + Vector2(enemy.get_instance_id() % 100, 0)
	game.player.global_position = arena_origin
	game.player.velocity = Vector2.ZERO
	game.player.facing = Vector2.RIGHT
	blocker.global_position = arena_origin + Vector2(72, 0)
	blocker.velocity = Vector2.ZERO
	blocker.control_time = 0.0
	blocker.apply_control(30.0)
	var blocker_origin := blocker.global_position
	game.player.set_touch_vector(Vector2.RIGHT)
	for _frame in range(32):
		await get_tree().physics_frame
	game.player.set_touch_vector(Vector2.ZERO)
	assert(blocker.global_position.distance_to(blocker_origin) < 0.5, "人物普通移动推动了怪物：origin=%s end=%s delta=%.3f" % [blocker_origin, blocker.global_position, blocker.global_position.distance_to(blocker_origin)])
	assert(game.player.global_position.distance_to(blocker.global_position) >= ArtSpec.PLAYER_COLLISION_RADIUS + blocker.collision_radius - 1.0, "人物移动穿进了怪物碰撞体")


func _assert_boss_faces_player(game: Node, enemies: Array) -> void:
	var boss: EnemyActor
	for enemy: EnemyActor in enemies:
		if enemy.is_boss:
			boss = enemy
			break
	if boss == null:
		# 测试自行创建固定Boss，不再依赖默认出生地图是否包含Boss。
		boss = EnemyActor.new()
		boss.setup({"name": "测试Boss", "hp": 9999, "attackMin": 1, "attackMax": 1}, game.player, true)
		game.add_child(boss)
		await get_tree().process_frame
	boss.control_time = 0.0
	boss.global_position = game.player.global_position + Vector2(-180, -40)
	boss.velocity = Vector2.ZERO
	for _frame in range(5):
		await get_tree().physics_frame
	var expected := boss.global_position.direction_to(game.player.global_position)
	assert(boss.facing.dot(expected) > 0.995, "Boss追击时没有持续面对玩家")
	if boss.display_name == "测试Boss":
		boss.queue_free()
