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

	assert(player.request_skill("刺杀剑术") and player.thrusting_enabled, "刺杀开关没有开启")
	var thrust_context := player._build_warrior_attack_context()
	assert(thrust_context.mode == "thrust", "刺杀开启后普通攻击没有进入第二格模式")
	assert(player.request_skill("半月弯刀") and player.half_moon_enabled, "半月开关没有开启")
	var mp_before_half := player.current_mp
	var half_context := player._build_warrior_attack_context()
	assert(half_context.mode == "half_moon" and player.current_mp == mp_before_half - 3, "半月没有优先刺杀或没有逐刀消耗3MP")
	assert(player.request_skill("半月弯刀") and not player.half_moon_enabled, "半月开关没有关闭")

	player.set_test_combat_time_ms(-1)
	assert(player.restore_warrior_runtime_state({
		"contract_id": "gameplay.warrior.skill_runtime.v2",
		"toggles": {"warrior.fire_sword.auto_enabled": false},
		"cooldowns": {"warrior.fire_sword.ready_remaining_ms": 0},
	}), "零冷却战士技能快照无法恢复")
	player.set_test_combat_time_ms(1000)
	assert(player.warrior_state_snapshot().fire_ready_remaining_ms == 0, "零剩余冷却跨时钟域恢复后不应进入等待")
	var mp_before_fire := player.current_mp
	assert(player.request_skill("烈火剑法") and player.fire_sword_auto_enabled, "烈火自动释放开关没有开启")
	assert(not player.fire_sword_armed and player.current_mp == mp_before_fire, "开启烈火自动释放时不应蓄力或消耗魔法")
	var no_target_context := player._build_warrior_attack_context(false)
	assert(no_target_context.mode != "fire" and player.current_mp == mp_before_fire, "没有可命中目标时烈火错误消耗")
	var fire_context := player._build_warrior_attack_context(true)
	assert(fire_context.mode == "fire" and player.fire_sword_auto_enabled, "烈火没有在普通攻击循环中自动释放")
	assert(player.current_mp == mp_before_fire - 7, "烈火自动释放没有按次消耗7MP")
	var cooldown_context := player._build_warrior_attack_context(true)
	assert(cooldown_context.mode != "fire", "烈火冷却期间错误重复释放")
	player.set_test_combat_time_ms(11000)
	var second_fire_context := player._build_warrior_attack_context(true)
	assert(second_fire_context.mode == "fire", "烈火冷却结束后没有自动再次释放")
	var saved_runtime := player.warrior_runtime_state_for_save()
	assert(saved_runtime.contract_id == "gameplay.warrior.skill_runtime.v2", "战士技能运行时存档契约不稳定")
	assert(saved_runtime.toggles["warrior.fire_sword.auto_enabled"], "烈火自动开关没有进入兼容存档快照")
	assert(player.request_skill("烈火剑法") and not player.fire_sword_auto_enabled, "再次点击没有关闭烈火自动释放")
	assert(player.restore_warrior_runtime_state(saved_runtime) and player.fire_sword_auto_enabled, "烈火自动开关无法从兼容快照恢复")
	assert(player.warrior_state_snapshot().fire_ready_remaining_ms == 10000, "烈火冷却剩余时间没有稳定恢复")
	player.set_test_combat_time_ms(21000)
	player.current_mp = 6
	var insufficient_mana_context := player._build_warrior_attack_context(true)
	assert(insufficient_mana_context.mode != "fire" and player.fire_sword_auto_enabled, "资源不足时烈火应保持开启并等待后续普通攻击")

	PlayerState.learned_skills = {"攻杀剑术": 3}
	player.set_combat_seed(176)
	var proc_count := 0
	for _attack in range(WarriorCombatMath.slaying_proc_cycle(3)):
		if player._next_slaying_proc():
			proc_count += 1
	assert(proc_count == 1, "三级攻杀每4刀周期必须且只能触发一次")

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

	print("WARRIOR_SKILL_STATE_MACHINE_PASS：攻杀周期、刺杀/半月开关、烈火自动开关与野蛮冲撞状态机正常")
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
