extends Node

const TargetingSystem := preload("res://scripts/targeting_system.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")


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

	var player_tile: Vector2i = game._attack_lock_tile(game.player.global_position)
	game.player.global_position = game._canonical_tile_to_world(player_tile)
	game.player.velocity = Vector2.ZERO
	game.player.facing = Vector2.RIGHT
	_place_at_tile_offset(game, first, player_tile, Vector2i(2, 0))
	_place_at_tile_offset(game, second, player_tile, Vector2i(-3, 0))
	_place_at_tile_offset(game, side, player_tile, Vector2i(0, 4))
	_place_at_tile_offset(game, behind, player_tile, Vector2i(-5, -5))
	game._request_mobile_attack()
	assert(game.locked_target == first and first.is_targeted, "无攻击锁定时没有从周围10格选择最近怪物")

	_place_at_tile_offset(game, first, player_tile, Vector2i(5, 0))
	_place_at_tile_offset(game, second, player_tile, Vector2i(1, 0))
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(game.locked_target == first, "已有攻击锁定时因更近怪物出现而擅自换敌")
	game.player.movement_performed.emit(game.player.global_position, game.player.facing)
	assert(game.locked_target == first, "人物移动后丢失了仍在10格内的攻击锁定")

	_place_at_tile_offset(game, first, player_tile, Vector2i(-4, -2))
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(
		game.locked_target == first
		and ArtSpec.direction_index(game.player.facing) == ArtSpec.direction_index(
			_expected_melee_facing(game.player, first)
		),
		"点击或按住攻击时没有强制转向已有攻击锁定"
	)
	game.player.visual._process(0.01)
	assert(
		game.player.visual.current_direction == ArtSpec.mir2_client_direction_row(
			_expected_melee_facing(game.player, first)
		),
		"攻击动作画面没有同步转向攻击锁定"
	)

	_place_at_tile_offset(game, first, player_tile, Vector2i(3, 3))
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._mobile_attack_held = true
	game._process(0.0)
	assert(
		game.locked_target == first
		and ArtSpec.direction_index(game.player.facing) == ArtSpec.direction_index(
			_expected_melee_facing(game.player, first)
		),
		"按住攻击的重复输入没有保持锁定并持续转向目标"
	)
	game._on_mobile_attack_released()

	game._on_mobile_attack_pressed()
	game._on_mobile_attack_released()
	game._on_mobile_attack_pressed()
	game._on_mobile_attack_released()
	assert(game._queued_mobile_attacks == 2, "快速点击发生在攻击动作中时没有逐次登记")
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._process(0.0)
	assert(
		game._queued_mobile_attacks == 1 and game.player._attack_action_timer > 0.0,
		"第一笔快速点击没有在人物可攻击时完成一次攻击"
	)
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._process(0.0)
	assert(
		game._queued_mobile_attacks == 0 and game.player._attack_action_timer > 0.0,
		"第二笔快速点击没有独立完成一次攻击"
	)
	var repeated_press_token := 9001
	game._on_mobile_attack_input_started(repeated_press_token, 17, &"touch")
	game._on_mobile_attack_input_started(repeated_press_token, 17, &"touch")
	assert(
		game._queued_mobile_attacks == 1,
		"repeated DOWN for one physical touch created more than one attack ticket"
	)
	game._on_mobile_attack_input_cancelled(
		repeated_press_token,
		17,
		&"touch",
		&"test_cancel"
	)
	assert(
		game._queued_mobile_attacks == 0 and not game._mobile_attack_held,
		"touch cancel left a ghost attack ticket or held-repeat state"
	)
	var movement_position_before: Vector2 = game.player.global_position
	game.player.set_touch_vector(Vector2.RIGHT)
	game.player._physics_process(game.player._attack_action_timer + 0.01)
	assert(
		game.player.movement_input_active
		and ArtSpec.direction_index(game.player.facing) == ArtSpec.direction_index(Vector2.RIGHT)
		and game.player.global_position.x > movement_position_before.x,
		"松开攻击后没有在动作完成时恢复摇杆方向并继续移动"
	)
	game.player.set_touch_vector(Vector2.ZERO)
	player_tile = game._attack_lock_tile(game.player.global_position)

	_place_at_tile_offset(game, first, player_tile, Vector2i(11, 0))
	game._validate_locked_target()
	assert(game.locked_target == null and not first.is_targeted, "怪物离开角色周围10格后没有取消攻击锁定")
	_place_at_tile_offset(game, first, player_tile, Vector2i(11, 0))
	_place_at_tile_offset(game, second, player_tile, Vector2i(-2, 0))
	_place_at_tile_offset(game, side, player_tile, Vector2i(0, 3))
	_place_at_tile_offset(game, behind, player_tile, Vector2i(4, 4))
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game._request_mobile_attack()
	assert(game.locked_target == second, "攻击重新选敌时选中了10格外怪物或未选择最近怪物")

	game._cancel_target()
	game._cycle_target()
	assert(game.locked_target == second, "无目标时换敌没有从周围最近怪物开始")
	game._cycle_target()
	assert(game.locked_target == side, "换敌没有按周围10格内的距离切到下一只怪物")
	game._cycle_target()
	assert(game.locked_target == behind, "换敌没有覆盖人物四周的合法怪物")
	game._cycle_target()
	assert(
		game.locked_target == second and game.locked_target != first,
		"换敌没有循环或切到了10格外怪物"
	)

	game._skill_cast_target = side
	game.player.facing = game.player.global_position.direction_to(side.global_position)
	assert(
		game._ensure_skill_cast_target(second, 180.0) == side,
		"技能临时目标没有保持自己的独立目标"
	)
	assert(game.locked_target == second, "技能临时选敌覆盖了独立的攻击锁定")
	game._skill_cast_target = null

	await _assert_player_cannot_push_enemy(game, first, second, side, behind)
	await _assert_boss_faces_player(game, enemies)

	for index in range(enemies.size()):
		(enemies[index] as EnemyActor).global_position = Vector2(3000 + index * 80, 3000)
	player_tile = game._attack_lock_tile(game.player.global_position)
	_place_at_tile_offset(game, second, player_tile, Vector2i(-2, -2))
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
	_assert_attack_ticket_contract_for_all_professions(game)
	print("MOBILE_TARGETING_PASS：攻击锁定10格、持续锁定、强制转向、全方向换敌及技能目标隔离正常")
	get_tree().quit(0)


func _assert_attack_ticket_contract_for_all_professions(game: Node) -> void:
	var original_profession: String = PlayerState.profession
	var original_attack_slots: Array[String] = PlayerState.attack_skill_slots.duplicate()
	var token_seed := 12000
	for profession_name: String in ["战士", "法师", "道士"]:
		PlayerState.select_profession(profession_name)
		PlayerState.attack_skill_slots = [""]
		game._cancel_all_mobile_attack_inputs(true)
		game.player._attack_timer = 1.0
		game.player._attack_action_timer = 1.0
		var first_token := token_seed
		var second_token := token_seed + 1
		token_seed += 10
		game._on_mobile_attack_input_started(first_token, 1, &"touch")
		game._on_mobile_attack_input_started(first_token, 1, &"touch")
		game._on_mobile_attack_input_started(second_token, 2, &"touch")
		assert(
			game._queued_mobile_attacks == 2,
			"%s attack input did not keep one ticket per unique physical touch" % profession_name
		)
		game._on_mobile_attack_input_ended(first_token, 1, &"touch")
		game._on_mobile_attack_input_ended(second_token, 2, &"touch")
		assert(
			not game._mobile_attack_held and game._queued_mobile_attacks == 2,
			"%s release did not stop held repeat or lost legitimate buffered taps" % profession_name
		)
		game._cancel_all_mobile_attack_inputs(true)
	PlayerState.select_profession(original_profession)
	PlayerState.attack_skill_slots = original_attack_slots


func _place_at_tile_offset(
	game: Node,
	enemy: EnemyActor,
	origin_tile: Vector2i,
	offset: Vector2i
) -> void:
	enemy.global_position = game._canonical_tile_to_world(origin_tile + offset)


func _expected_melee_facing(actor: Node2D, target: Node2D) -> Vector2:
	var direction_index := DirectionSpace.direction_index_for_world_delta(
		target.global_position - actor.global_position
	)
	return DirectionSpace.projected_world_direction(direction_index)


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


func _assert_boss_faces_player(game: Node, _enemies: Array) -> void:
	# 使用隔离 Boss，避免默认地图中已有 Boss 的仇恨表影响朝向断言。
	var boss := EnemyActor.new()
	boss.setup(
		{"name": "测试Boss", "hp": 9999, "attackMin": 1, "attackMax": 1},
		game.player,
		true
	)
	game.add_child(boss)
	await get_tree().process_frame
	boss.control_time = 0.0
	boss.global_position = game.player.global_position + Vector2(-180, -40)
	boss.velocity = Vector2.ZERO
	boss.target = game.player
	for _frame in range(5):
		await get_tree().physics_frame
	var expected := boss.global_position.direction_to(game.player.global_position)
	assert(boss.facing.dot(expected) > 0.995, "Boss追击时没有持续面对玩家")
	boss.queue_free()
