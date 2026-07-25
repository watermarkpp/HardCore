extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(2000, 2000)

	var target := EnemyActor.new()
	target.setup(
		{
			"name": "魔法结算目标",
			"hp": 100,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
			"anti_magic_points": 10,
			"mdefMin": 3,
			"mdefMax": 3,
		},
		game.player,
		false
	)
	target.global_position = game.player.global_position + Vector2(60, 0)
	target.control_time = 60.0
	game.add_child(target)
	await get_tree().process_frame

	var hp_before := target.current_hp
	var evaded: bool = game._damage_enemies(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		true,
		120.0,
		false,
		"wizard.lightning"
	)
	assert(not evaded and target.current_hp == hp_before, "雷电术未先执行100% AntiMagic")

	target.monster_data["anti_magic_points"] = 0
	var connected: bool = game._damage_enemies(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		true,
		120.0,
		false,
		"wizard.lightning"
	)
	assert(connected and target.current_hp == hp_before - 7, "雷电术未按 AntiMagic→MAC→扣血顺序结算")

	game._spawn_projectile(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		120.0,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball"
	)
	var projectile: SkillProjectile
	for child: Node in game.get_children():
		if child is SkillProjectile:
			projectile = child
			break
	assert(projectile != null, "GameRoot未创建直接法术投射物")
	assert(projectile.resolution_skill_id == "wizard.fireball", "GameRoot未传递稳定 source_skill_id")
	assert(projectile.source_actor == game.player, "投射物未保留施法者")
	assert(projectile.magic_defense_adapter.is_valid(), "投射物未接入共享MAC适配器")

	print("GAME_ROOT_COMBAT_RESOLUTION_INTEGRATION_PASS：稳定技能ID、AntiMagic、MAC与扣血顺序已接入")
	get_tree().quit(0)
