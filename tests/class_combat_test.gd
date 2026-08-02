extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 35
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	# 正式启动点已是服务端HomeMap=0；职业技能综合测试显式进入带Boss的旧演示场。
	game.change_zone("比奇郊外")
	await get_tree().process_frame
	await get_tree().process_frame
	var enemy: EnemyActor
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			enemy = node
			break
	assert(enemy != null, "职业战斗测试缺少确定性目标")
	enemy.max_hp = 9999
	enemy.current_hp = 9999
	enemy.control_time = 60.0

	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 3, "魔法盾": 3, "火墙": 3}
	game.player.current_mp = 200
	enemy.global_position = game.player.global_position + Vector2(75, 0)
	enemy.apply_control(10.0)
	var hp_before_fireball := enemy.current_hp
	game._on_player_skill("火球术", game.player.global_position, Vector2.RIGHT, 12)
	for frame in range(12):
		await get_tree().physics_frame
	assert(enemy.current_hp < hp_before_fireball, "法师投射物未命中")
	game._on_player_skill("魔法盾", game.player.global_position, Vector2.RIGHT, 10)
	assert(game.player.shield_time > 0.0 and game.player.damage_reduction > 0.0, "魔法盾未生效")
	enemy.global_position = game.player.global_position + Vector2(175, 0)
	enemy.apply_control(10.0)
	# Fire Wall is target-centred in the mobile spell-lock contract. This direct
	# production-entry test bypasses the HUD input path, so install the same
	# explicit lock/selected target that the real input path supplies.
	game._set_magic_locked_target(enemy, true)
	game._skill_cast_target = enemy
	assert(
		game._canonical_screen_px_to_grid_cell(enemy.global_position)
		== Vector2i(round(game._canonical_screen_px_to_ground_gu(enemy.global_position))),
		"旧区域整数技能格与怪物浮点脚点格使用了不同坐标系"
	)
	var hp_before_firewall := enemy.current_hp
	game._on_player_skill("火墙", game.player.global_position, Vector2.RIGHT, 10)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(enemy.current_hp < hp_before_firewall, "火墙持续区域未造成伤害")

	PlayerState.select_profession("道士")
	PlayerState.learned_skills = {
		"施毒术": 3,
		"治愈术": 3,
		"困魔咒": 3,
		"隐身术": 3,
		"召唤骷髅": 3,
	}
	PlayerState.inventory = [
		{"name": "灰色药粉", "count": 10},
		{"name": "护身符", "count": 20},
	]
	game.player.current_mp = 200
	enemy.global_position = game.player.global_position + Vector2(75, 0)
	enemy.apply_control(10.0)
	game._on_player_skill("施毒术", game.player.global_position, Vector2.RIGHT, 12)
	for frame in range(12):
		await get_tree().physics_frame
	assert(enemy.poison_time > 0.0 and enemy.poison_damage > 0, "施毒术状态未生效")
	game.player.take_damage(20)
	var hp_before_heal: int = game.player.current_hp
	game._on_player_skill("治愈术", game.player.global_position, Vector2.RIGHT, 12)
	assert(game.player.current_hp > hp_before_heal, "治愈术未恢复生命")
	enemy.global_position = game.player.global_position + Vector2(120, 0)
	enemy.apply_control(10.0)
	game._on_player_skill("困魔咒", game.player.global_position, Vector2.RIGHT, 1)
	assert(enemy.control_time > 0.0, "困魔咒未定身")
	game._on_player_skill("隐身术", game.player.global_position, Vector2.RIGHT, 1)
	assert(game.player.is_stealthed(), "隐身术未生效")
	game._on_player_skill("召唤骷髅", game.player.global_position, Vector2.RIGHT, 12)
	await get_tree().process_frame
	var summons := get_tree().get_nodes_in_group("summons")
	assert(summons.size() == 1 and summons[0] is SummonActor, "召唤骷髅未生成")
	var summon: SummonActor = summons[0]
	summon.global_position = enemy.global_position + Vector2(10, 0)
	enemy._threat_table.clear()
	enemy.target = null
	enemy._retarget()
	assert(enemy.target == summon, "怪物未将附近召唤物纳入仇恨目标")

	print("CLASS_COMBAT_PASS：法师投射物/火墙/魔法盾与道士治疗/毒/控制/隐身/召唤正常")
	get_tree().quit(0)
