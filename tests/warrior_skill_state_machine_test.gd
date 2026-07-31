extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"基本剑术": 3, "刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3, "野蛮冲撞": 3,
	}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	player.set_combat_seed(176)
	player.current_mp = 40
	assert(
		game._canonical_basic_sword_bonus(
			player.global_position,
			player.facing.normalized(),
			true
		) == 9,
		"三级基本剑术没有持续提供主源+9近战准确"
	)

	assert(player.request_skill("刺杀剑术") and player.thrusting_enabled, "刺杀开关没有开启")
	var thrust_context := player._build_warrior_attack_context(true)
	assert(thrust_context.mode == "thrust", "刺杀开启后普通攻击没有进入第二格模式")
	var thrust_edge_context := player._build_warrior_attack_context(false)
	assert(
		thrust_edge_context.mode == "thrust"
		and thrust_edge_context.skill_name == "刺杀剑术",
		"刺杀主体动作被瞬时无目标检测降级"
	)
	assert(player.request_skill("半月弯刀") and player.half_moon_enabled, "半月开关没有开启")
	var mp_before_half := player.current_mp
	var half_context := player._build_warrior_attack_context(true)
	assert(half_context.mode == "half_moon" and player.current_mp == mp_before_half, "半月开关不应在Router执行前预扣MP")
	var half_edge_context := player._build_warrior_attack_context(false)
	assert(
		half_edge_context.mode == "half_moon"
		and half_edge_context.skill_name == "半月弯刀",
		"半月主体动作被瞬时无目标检测降级"
	)
	for existing: Node in get_tree().get_nodes_in_group("enemies"):
		if existing is EnemyActor:
			existing.global_position = Vector2(3000, 3000) + Vector2(
				existing.get_instance_id() % 200,
				0
			)
	var no_target_half_mp := player.current_mp
	for _attack_index in range(6):
		player._attack_timer = 0.0
		player._attack_action_timer = 0.0
		assert(player.request_attack(false))
		assert(player.visual._action_name == "半月弯刀")
		await get_tree().create_timer(0.2).timeout
	assert(
		player.current_mp == no_target_half_mp,
		"半月空挥被错误提交MP"
	)
	assert(player.request_skill("半月弯刀") and not player.half_moon_enabled, "半月开关没有关闭")
	for _attack_index in range(6):
		player._attack_timer = 0.0
		player._attack_action_timer = 0.0
		assert(player.request_attack(false))
		assert(player.visual._action_name == "刺杀剑术")
		await get_tree().create_timer(0.2).timeout

	var mp_before_fire := player.current_mp
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_skill("烈火剑法") and player.fire_sword_enabled, "烈火开关无法开启")
	assert(player.current_mp == mp_before_fire and is_zero_approx(player._attack_timer), "开启烈火开关不得预扣MP或占用动作")
	var queued_before_fire_fallback: int = game._queued_mobile_attacks
	game._on_mobile_attack_pressed()
	game._on_mobile_attack_released()
	assert(game._queued_mobile_attacks == queued_before_fire_fallback)
	assert(player._attack_timer > 0.0 and player._attack_action_timer > 0.0)
	assert(player.visual._action_name == "刺杀剑术", "烈火无合法目标时没有回退到刺杀")
	assert(player.skill_cooldown_remaining_ms("warrior.fire_sword") == 0)
	assert(player.current_mp == mp_before_fire)
	await get_tree().create_timer(player.attack_hit_windup + 0.04).timeout
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	var direct_fire_context := player._build_warrior_attack_context(true)
	assert(direct_fire_context.mode == "fire" and direct_fire_context.direct_toggle_release, "烈火没有在同一次攻击输入直接进入攻击模式")
	assert(player.request_attack(true), "烈火开关开启后攻击键未接受")
	assert(player.skill_cooldown_remaining_ms("warrior.fire_sword") == 8000, "烈火独立8秒冷却未建立")
	assert(player.current_mp == mp_before_fire, "MP必须由GameRoot canonical结果唯一提交，Player不得预扣")
	var saved_runtime := player.warrior_runtime_state_for_save()
	assert(saved_runtime.contract_id == "gameplay.warrior.skill_runtime.v2", "战士技能运行时存档契约不稳定")
	assert(saved_runtime.toggles["warrior.fire_sword.auto_enabled"], "烈火开关没有复用既有v2字段")
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	player._skill_cooldown_remaining.clear()
	assert(player.request_skill("烈火剑法") and not player.fire_sword_enabled, "烈火开关无法关闭")
	game._set_canonical_fire_charge_expires_at(0)

	PlayerState.learned_skills = {"攻杀剑术": 3}
	var ordinary_context := player._build_warrior_attack_context(true)
	assert(ordinary_context.mode == "normal", "Player仍在Router之前用旧攻杀周期门控普通攻击")
	assert(ordinary_context.skill_name == "attack", "攻杀错误替换了普通主体动作")
	assert(ordinary_context.passive_proc_layers.size() == 1)
	assert(ordinary_context.passive_proc_layers[0].rolls_per_melee_action == 1)
	player.visual.play_action(ordinary_context.skill_name, 0.51)
	assert(player.visual._action_name == "attack", "攻杀错误进入独立人物动作")

	PlayerState.learned_skills = {"刺杀剑术": 3, "半月弯刀": 3, "野蛮冲撞": 3}
	player.thrusting_enabled = true
	player.half_moon_enabled = false
	player.global_position = Vector2.ZERO
	player.facing = Vector2.RIGHT
	for existing: Node in get_tree().get_nodes_in_group("enemies"):
		if existing is EnemyActor:
			existing.global_position = Vector2(3000, 3000) + Vector2(existing.get_instance_id() % 200, 0)
	var primary := _make_enemy(game, player, "主目标", Vector2(80, 0), 1)
	var second := _make_enemy(game, player, "第二格目标", Vector2(155, 5), 1)
	var unrelated := _make_enemy(game, player, "侧后目标", Vector2(-70, 0), 1)
	game.locked_target = primary
	var second_hp := second.current_hp
	var unrelated_hp := unrelated.current_hp
	player._pending_attack_context = {"mode": "thrust", "skill_level": 3}
	game._on_player_attack(Vector2.ZERO, Vector2.RIGHT, 100)
	assert(second.current_hp == second_hp - 100, "三级刺杀没有对第二格造成100%伤害")
	assert(unrelated.current_hp == unrelated_hp, "刺杀错误命中背后目标")

	primary.current_hp = primary.max_hp
	# Facing screen-E maps to canonical tile step (1,-1). The three classic
	# secondary sectors are NE, SE and S, each exactly one logical tile away.
	var half_a := _make_enemy(game, player, "半月左前", Vector2(32, -16), 1)
	var half_b := _make_enemy(game, player, "半月右前", Vector2(32, 16), 1)
	var half_c := _make_enemy(game, player, "半月右侧", Vector2(0, 32), 1)
	player.half_moon_enabled = true
	player._pending_attack_context = {"mode": "half_moon", "skill_level": 3}
	game._on_player_attack(Vector2.ZERO, Vector2.RIGHT, 130)
	for secondary: EnemyActor in [half_a, half_b, half_c]:
		assert(secondary.current_hp == secondary.max_hp - 50, "半月三个源码方向没有按5/13伤害结算")

	for enemy: EnemyActor in [primary, second, unrelated, half_a, half_b, half_c]:
		enemy.global_position = Vector2(3000, 3000) + Vector2(enemy.get_instance_id() % 200, 0)
	var rush_step := Vector2i(1, -1)
	player.global_position = _find_open_rush_origin(game, rush_step)
	var player_rush_tile: Vector2 = game._canonical_world_to_fractional_tile(player.global_position)
	var player_rush_origin := player.global_position
	var rush_target := _make_enemy(
		game,
		player,
		"低级冲撞目标",
		game._canonical_fractional_tile_to_world(player_rush_tile + Vector2(rush_step)),
		1
	)
	var rush_origin := rush_target.global_position
	var rush_hp := rush_target.current_hp
	game.locked_target = rush_target
	assert(game._execute_wild_rush(Vector2.LEFT, 0), "野蛮在开阔地没有移动")
	assert(
		game._canonical_world_to_fractional_tile(player.global_position).is_equal_approx(
			player_rush_tile + Vector2(rush_step) * 3.0
		),
		"人物没有沿人物脚点到怪物脚点的八方向连线固定推进三格"
	)
	assert(
		game._canonical_world_to_fractional_tile(rush_target.global_position).is_equal_approx(
			game._canonical_world_to_fractional_tile(rush_origin) + Vector2(rush_step) * 3.0
		),
		"低级普通怪物没有固定推进三格"
	)
	assert(rush_target.current_hp == rush_hp, "野蛮冲撞错误造成伤害")

	# Any second monster inside the complete three-tile corridor cancels the
	# whole coupled displacement; neither actor may move partially.
	player.global_position = player_rush_origin
	rush_target.global_position = rush_origin
	var blocker := _make_enemy(
		game,
		player,
		"冲撞路径阻挡怪物",
		game._canonical_fractional_tile_to_world(
			game._canonical_world_to_fractional_tile(rush_origin) + Vector2(rush_step) * 2.0
		),
		1
	)
	var blocked_player_origin := player.global_position
	var blocked_target_origin := rush_target.global_position
	assert(not game._execute_wild_rush(Vector2.RIGHT, 3), "怪物阻挡时不应产生位移")
	assert(
		player.global_position.is_equal_approx(blocked_player_origin)
		and rush_target.global_position.is_equal_approx(blocked_target_origin),
		"怪物阻挡没有原子取消人物与目标的全部位移"
	)
	blocker.global_position = Vector2(3000, 3000)
	# A live lock remains authoritative: an out-of-reach locked monster must not
	# redirect Wild Rush onto another eligible adjacent monster.
	rush_target.global_position = game._canonical_fractional_tile_to_world(
		player_rush_tile + Vector2(rush_step) * 2.0
	)
	var adjacent_fallback := _make_enemy(
		game,
		player,
		"冲撞不可偷换的邻近目标",
		game._canonical_fractional_tile_to_world(player_rush_tile - Vector2(rush_step)),
		1
	)
	game.locked_target = rush_target
	assert(game._select_wild_rush_target() == null, "野蛮冲撞错误偷换了超距锁定目标")
	adjacent_fallback.global_position = Vector2(3050, 3000)
	rush_target.global_position = Vector2(3100, 3000)
	var equal_level_target := _make_enemy(
		game,
		player,
		"同级免疫目标",
		game._canonical_fractional_tile_to_world(player_rush_tile + Vector2(rush_step)),
		PlayerState.level
	)
	game.locked_target = equal_level_target
	assert(game._select_wild_rush_target() == null, "野蛮错误选择了同级目标")
	equal_level_target.global_position = Vector2(3200, 3000)
	var boss_target := _make_enemy(
		game,
		player,
		"Boss免疫目标",
		game._canonical_fractional_tile_to_world(player_rush_tile + Vector2(rush_step)),
		1,
		true
	)
	game.locked_target = boss_target
	assert(game._select_wild_rush_target() == null, "野蛮错误选择了Boss目标")

	print("WARRIOR_SKILL_STATE_MACHINE_PASS：攻杀Router、三技能开关、烈火单次攻击直释与野蛮原子三格推动正常")
	get_tree().quit(0)


func _make_enemy(
	game: Node,
	player: PlayerCharacter,
	display_name: String,
	position: Vector2,
	enemy_level: int,
	is_boss := false
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": display_name, "hp": 9999, "attackMin": 1, "attackMax": 1, "level": enemy_level},
		player,
		is_boss
	)
	enemy.global_position = position
	game.add_child(enemy)
	# EnemyActor._ready() initializes its runtime control state. Freeze the
	# fixture after it enters the tree so hit-frame assertions use the intended
	# fixed geometry.
	enemy.control_time = 60.0
	return enemy


func _find_open_rush_origin(game: Node, direction_step: Vector2i) -> Vector2:
	var center_tile: Vector2 = game._canonical_world_to_fractional_tile(game.player.global_position)
	for y in range(-24, 25):
		for x in range(-24, 25):
			var origin_tile := center_tile + Vector2(x, y)
			var clear := true
			for distance in range(5):
				var sample: Vector2 = game._canonical_fractional_tile_to_world(
					origin_tile + Vector2(direction_step) * float(distance)
				)
				if game.background.is_environment_point_blocked(sample):
					clear = false
					break
			if clear:
				return game._canonical_fractional_tile_to_world(origin_tile)
	assert(false, "测试地图中找不到野蛮冲撞开阔夹具")
	return Vector2.ZERO
