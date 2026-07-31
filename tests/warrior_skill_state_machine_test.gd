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
	assert(player.request_skill("半月弯刀") and player.half_moon_enabled, "半月开关没有开启")
	var mp_before_half := player.current_mp
	var half_context := player._build_warrior_attack_context(true)
	assert(half_context.mode == "half_moon" and player.current_mp == mp_before_half, "半月开关不应在Router执行前预扣MP")
	assert(player.request_skill("半月弯刀") and not player.half_moon_enabled, "半月开关没有关闭")

	var mp_before_fire := player.current_mp
	player._attack_timer = 0.0
	assert(player.request_skill("烈火剑法") and player.fire_sword_enabled, "烈火开关无法开启")
	assert(player.current_mp == mp_before_fire and is_zero_approx(player._attack_timer), "开启烈火开关不得预扣MP或占用动作")
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
	assert(ordinary_context.passive_proc_layers.size() == 1)
	assert(ordinary_context.passive_proc_layers[0].rolls_per_melee_action == 1)

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
	var half_a := _make_enemy(game, player, "半月左前", Vector2(52, -52), 1)
	var half_b := _make_enemy(game, player, "半月右前", Vector2(52, 52), 1)
	var half_c := _make_enemy(game, player, "半月右侧", Vector2(0, 74), 1)
	player._pending_attack_context = {"mode": "half_moon", "skill_level": 3}
	game._on_player_attack(Vector2.ZERO, Vector2.RIGHT, 130)
	for secondary: EnemyActor in [half_a, half_b, half_c]:
		assert(secondary.current_hp == secondary.max_hp - 50, "半月三个源码方向没有按5/13伤害结算")

	for enemy: EnemyActor in [primary, second, unrelated, half_a, half_b, half_c]:
		enemy.global_position = Vector2(3000, 3000) + Vector2(enemy.get_instance_id() % 200, 0)
	player.global_position = _find_open_rush_origin(game)
	var player_rush_origin := player.global_position
	var rush_target := _make_enemy(game, player, "低级冲撞目标", player.global_position + Vector2(50, 0), 1)
	var rush_origin := rush_target.global_position
	assert(game._execute_wild_rush(Vector2.RIGHT, 3), "三级野蛮在开阔地没有移动")
	assert(player.global_position.x > player_rush_origin.x and rush_target.global_position.x > rush_origin.x, "野蛮没有同时推进玩家和低级目标")

	print("WARRIOR_SKILL_STATE_MACHINE_PASS：攻杀Router、三技能开关、烈火单次攻击直释与野蛮点击释放正常")
	get_tree().quit(0)


func _make_enemy(game: Node, player: PlayerCharacter, display_name: String, position: Vector2, enemy_level: int) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({"name": display_name, "hp": 9999, "attackMin": 1, "attackMax": 1, "level": enemy_level}, player, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


func _find_open_rush_origin(game: Node) -> Vector2:
	for y in range(-1200, 1201, 100):
		for x in range(-1200, 1201, 100):
			var origin := Vector2(x, y)
			var clear := true
			for offset in [Vector2.ZERO, Vector2(50, 0), Vector2(100, 0), Vector2(150, 0), Vector2(200, 0)]:
				if game.background.is_environment_point_blocked(origin + offset):
					clear = false
					break
			if clear:
				return origin
	assert(false, "测试地图中找不到野蛮冲撞开阔夹具")
	return Vector2.ZERO
