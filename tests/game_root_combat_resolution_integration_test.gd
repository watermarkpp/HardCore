extends Node

const RuntimeCombatSpatialIndex := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)


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
	# The integration fixture is interested in direct resolver calls only. Freeze
	# the unrelated world loop after bootstrap so no map/death maintenance can
	# move or remove the manually-owned target while assertions run.
	game.set_process(false)
	game.set_physics_process(false)

	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			var existing_enemy := value as EnemyActor
			existing_enemy.set_combat_position(
				game.player.global_position + Vector2(2000, 2000),
				&"integration_fixture_relocate",
			)
			existing_enemy.set_process(false)
			existing_enemy.set_physics_process(false)

	var target := EnemyActor.new()
	target.setup(
		{
			"monster_id": 19,
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
	# setup is canonical-ID authoritative; these fields are the test's explicit
	# combat fixture state, not a production data override.
	target.max_hp = 100
	target.current_hp = 100
	target.monster_data["anti_magic_points"] = 10
	target.monster_data["mdefMin"] = 3
	target.monster_data["mdefMax"] = 3
	target.control_time = 60.0
	var target_position: Vector2 = game.player.global_position + Vector2(60, 0)
	_register_enemy_with_runtime_index(game, target, target_position)
	await get_tree().process_frame

	var hp_before := target.current_hp
	var evaded: bool = game._damage_enemies(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		true,
		2.0,
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
		2.0,
		false,
		"wizard.lightning"
	)
	assert(connected and target.current_hp == hp_before - 7, "雷电术未按 AntiMagic→MAC→扣血顺序结算")

	game._spawn_projectile(
		game.player.global_position,
		Vector2.RIGHT,
		10,
		9.0,
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

	assert(is_equal_approx(projectile.max_travel_distance_gu, 9.0))
	assert(projectile.global_position.is_equal_approx(game.player.global_position))

	var combat_runtime: Node = load(
		"res://scripts/layers/runtime/combat_runtime_service.gd"
	).new()
	var player_hp_before: int = game.player.current_hp
	var player_resolution: Dictionary = combat_runtime.apply_player_direct_spell_damage(
		game.player,
		"wizard.fireball",
		10,
		0,
		0
	)
	assert(player_resolution.success and player_resolution.magic_evaded, "共享运行时未转交玩家AntiMagic管线")
	assert(game.player.current_hp == player_hp_before, "玩家AntiMagic成功后仍被重复扣血")

	game.queue_free()
	await get_tree().process_frame
	print("GAME_ROOT_COMBAT_RESOLUTION_INTEGRATION_PASS：稳定技能ID、AntiMagic、MAC与扣血顺序已接入")
	get_tree().quit(0)


func _register_enemy_with_runtime_index(
	game: Node,
	enemy: EnemyActor,
	position_px: Vector2,
) -> void:
	var runtime_map_id := int(game.get("current_map_id"))
	var spatial_index: RuntimeCombatSpatialIndex = game.get("_combat_spatial_index")
	var spawn_serial := int(game.get("_runtime_spawn_serial")) + 1
	game.set("_runtime_spawn_serial", spawn_serial)
	enemy.configure_runtime_map_projection(
		runtime_map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.configure_spatial_index(spatial_index, spawn_serial)
	enemy.set_meta("spawn_serial", spawn_serial)
	enemy.set_combat_position(position_px, &"integration_fixture_spawn")
	spatial_index.register(
		spawn_serial,
		runtime_map_id,
		game._canonical_screen_px_to_ground_gu(position_px),
		enemy.combat_radius_gu,
		spawn_serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	game.add_child(enemy)
	# Enemy._ready() may perform its one-time overlap repair. Restore the
	# fixture's intended footpoint through the same authoritative position API.
	enemy.set_combat_position(position_px, &"integration_fixture_position")
	enemy.set_process(false)
	enemy.set_physics_process(false)
