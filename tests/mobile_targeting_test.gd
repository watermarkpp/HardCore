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
	# Targeting is isolated from the Bich safe-zone displacement policy here.
	# Safe-zone GU projection has its own contract tests.
	game._active_safe_zones = []
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
		_move_enemy(
			enemies[index] as EnemyActor,
			Vector2(3000 + index * 80, 3000)
		)

	var player_tile: Vector2i = game._canonical_screen_px_to_grid_cell(game.player.global_position)
	game.player.global_position = game._canonical_grid_cell_to_screen_px(player_tile)
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
	for index in range(enemies.size()):
		_move_enemy(
			enemies[index] as EnemyActor,
			Vector2(3000 + index * 80, 3000)
		)
	game.player.global_position = _find_open_rightward_movement_origin(game)
	game.player.velocity = Vector2.ZERO
	await get_tree().physics_frame
	assert(
		not game.player._dead
		and game.player._attack_action_timer > 0.0
		and game.player._movement_visual_lock_timer <= 0.0
		and game.player._struck_lock_remaining <= 0.0
		and game.player._struck_reaction_lock_remaining <= 0.0
		and game.player.control_time <= 0.0,
		"movement fixture did not isolate the active attack-action lock"
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
	player_tile = game._canonical_screen_px_to_grid_cell(game.player.global_position)
	assert(game.ATTACK_LOCK_CONTRACT == "combat.attack_lock.euclidean_gu.v2")
	assert(is_equal_approx(game.ATTACK_LOCK_RANGE_GU, 10.0))
	_place_at_tile_offset(game, first, player_tile, Vector2i(8, 8))
	game._set_attack_locked_target(first, true)
	assert(
		game.locked_target == null,
		"8×8 ground delta is 11.314 GU and must be outside the 10 GU lock circle"
	)
	_place_at_tile_offset(game, first, player_tile, Vector2i(7, 7))
	game._set_attack_locked_target(first, true)
	assert(
		game.locked_target == first,
		"7×7 ground delta is 9.899 GU and must remain inside the 10 GU lock circle"
	)
	game._cancel_target()

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
		game._ensure_skill_cast_target(second) == side,
		"技能临时目标没有保持自己的独立目标"
	)
	assert(game.locked_target == second, "技能临时选敌覆盖了独立的攻击锁定")
	game._skill_cast_target = null

	await _assert_player_cannot_push_enemy(game, first, second, side, behind)
	await _assert_boss_faces_player(game, enemies)

	for index in range(enemies.size()):
		_move_enemy(
			enemies[index] as EnemyActor,
			Vector2(3000 + index * 80, 3000)
		)
	player_tile = game._canonical_screen_px_to_grid_cell(game.player.global_position)
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
	var cave_bat: Dictionary = GameData.get_monster_by_id(43)
	assert(
		int(cave_bat.get("monster_id", -1)) == 43
		and str(cave_bat.get("canonical_name", "")) == "山洞蝙蝠",
		"飞行怪夹具未取得canonical ID43"
	)
	flying.setup(cave_bat, game.player, false)
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
	_move_enemy(
		enemy,
		game._canonical_grid_cell_to_screen_px(origin_tile + offset)
	)


func _move_enemy(enemy: EnemyActor, position: Vector2) -> void:
	enemy.set_combat_position(position, &"mobile_targeting_fixture_move")


func _find_open_rightward_movement_origin(game: Node) -> Vector2:
	const CLEAR_DISTANCE_PX := 64
	const SAMPLE_STEP_PX := 4
	var center_tile: Vector2i = game._canonical_screen_px_to_grid_cell(
		game.player.global_position
	)
	for y in range(-24, 25):
		for x in range(-24, 25):
			var candidate: Vector2 = game._canonical_grid_cell_to_screen_px(
				center_tile + Vector2i(x, y)
			)
			var clear: bool = true
			for distance_px: int in range(
				0, CLEAR_DISTANCE_PX + SAMPLE_STEP_PX, SAMPLE_STEP_PX
			):
				if WorldSpatialRules.environment_blocks_actor_screen_px(
					game.background,
					candidate + Vector2.RIGHT * float(distance_px),
					ArtSpec.PLAYER_COLLISION_RADIUS_PX
				):
					clear = false
					break
			if clear:
				return candidate
	assert(false, "找不到向右移动开放夹具")
	return Vector2.ZERO


func _expected_melee_facing(actor: Node2D, target: Node2D) -> Vector2:
	var direction_index := DirectionSpace.direction_index_for_screen_delta_px(
		target.global_position - actor.global_position
	)
	return DirectionSpace.projected_screen_direction_px(direction_index)


func _assert_direction_priority() -> void:
	var front_near := Node2D.new()
	var front_far := Node2D.new()
	var side := Node2D.new()
	var behind := Node2D.new()
	for node: Node2D in [front_near, front_far, side, behind]:
		add_child(node)
	var candidates: Array[Dictionary] = [
		{"target": behind, "ground_position_gu": Vector2(-1.0, 0.0)},
		{"target": side, "ground_position_gu": Vector2(0.0, 1.0)},
		{"target": front_far, "ground_position_gu": Vector2(4.0, 0.0)},
		{"target": front_near, "ground_position_gu": Vector2(2.0, 0.25)},
	]
	assert(TargetingSystem.CONTRACT_ID == "combat.targeting.euclidean_gu.v2")
	assert(TargetingSystem.select_target_ground_gu(candidates, Vector2.ZERO, Vector2.RIGHT) == front_near, "自动选敌没有优先最近正面目标")
	assert(TargetingSystem.select_target_ground_gu(candidates.slice(0, 2), Vector2.ZERO, Vector2.RIGHT) == side, "正面无怪时没有选择侧面目标")
	assert(TargetingSystem.select_target_ground_gu([candidates[0]], Vector2.ZERO, Vector2.RIGHT) == behind, "仅背面有怪时没有选择背面目标")
	var ordered := TargetingSystem.front_targets_ground_gu([candidates[2], candidates[0], candidates[3]], Vector2.ZERO, Vector2.RIGHT)
	assert(ordered.size() == 2 and ordered[0] == front_near and ordered[1] == front_far, "手动正面目标没有按距离排序")
	for node: Node2D in [front_near, front_far, side, behind]:
		node.queue_free()


func _assert_player_cannot_push_enemy(game: Node, blocker: EnemyActor, second: EnemyActor, side: EnemyActor, behind: EnemyActor) -> void:
	# Keep this collision-only check outside the real nine-tile safe zone; enemies
	# inside that circle are intentionally expelled by GameRoot every frame.
	var arena_origin: Vector2 = game._bich_home_screen_position_px() + Vector2(600, 0)
	for enemy: EnemyActor in [second, side, behind]:
		_move_enemy(
			enemy,
			arena_origin + Vector2(700, 300) + Vector2(enemy.get_instance_id() % 100, 0)
		)
	game.player.global_position = arena_origin
	game.player.velocity = Vector2.ZERO
	game.player.facing = Vector2.RIGHT
	_move_enemy(blocker, arena_origin + Vector2(72, 0))
	blocker.velocity = Vector2.ZERO
	blocker.control_time = 0.0
	blocker.apply_control(30.0)
	var blocker_origin := blocker.global_position
	game.player.set_touch_vector(Vector2.RIGHT)
	for _frame in range(32):
		await get_tree().physics_frame
	game.player.set_touch_vector(Vector2.ZERO)
	assert(blocker.global_position.distance_to(blocker_origin) < 0.5, "人物普通移动推动了怪物：origin=%s end=%s delta=%.3f" % [blocker_origin, blocker.global_position, blocker.global_position.distance_to(blocker_origin)])
	assert(game.player.global_position.distance_to(blocker.global_position) >= ArtSpec.PLAYER_COLLISION_RADIUS_PX + blocker.collision_radius_px - 1.0, "人物移动穿进了怪物碰撞体")


func _assert_boss_faces_player(game: Node, _enemies: Array) -> void:
	# 使用隔离 Boss，避免默认地图中已有 Boss 的仇恨表影响朝向断言。
	var boss := EnemyActor.new()
	boss.setup(
		{"monster_id": 76, "name": "沃玛教主", "hp": 9999, "attackMin": 1, "attackMax": 1},
		game.player,
		false
	)
	# The canonical setup owns identity and stats; this is only the local
	# high-HP movement fixture override used by the facing assertion.
	boss.max_hp = 9999
	boss.current_hp = 9999
	game._runtime_spawn_serial += 1
	var spawn_serial := int(game._runtime_spawn_serial)
	var boss_position: Vector2 = game.player.global_position + Vector2(-180, -40)
	boss.configure_runtime_map_projection(
		game.current_map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	boss.configure_spatial_index(game._combat_spatial_index, spawn_serial)
	boss.set_meta("spawn_serial", spawn_serial)
	boss.set_meta("zone_generation", int(game._zone_generation))
	boss.set_combat_position(boss_position, &"mobile_targeting_fixture_boss_spawn")
	game._combat_spatial_index.register(
		spawn_serial,
		game.current_map_id,
		game._canonical_screen_px_to_ground_gu(boss_position),
		boss.combat_radius_gu,
		spawn_serial,
		boss,
		Callable(boss, "spatial_index_position"),
	)
	game.add_child(boss)
	await get_tree().process_frame
	assert(
		boss.monster_id == 76
		and boss.is_boss
		and str(boss.monster_data.get("classification", "")) == "boss"
		and int(boss.boss_rule.get("monsterId", -1)) == 76
		and bool(boss.get_meta("caller_boss_ignored", false)),
		"隔离Boss夹具必须由canonical ID76派生Boss身份"
	)
	boss.control_time = 0.0
	_move_enemy(boss, boss_position)
	boss.velocity = Vector2.ZERO
	boss.target = game.player
	for _frame in range(5):
		await get_tree().physics_frame
	var expected := boss.global_position.direction_to(game.player.global_position)
	assert(boss.facing.dot(expected) > 0.995, "Boss追击时没有持续面对玩家")
	boss.queue_free()
