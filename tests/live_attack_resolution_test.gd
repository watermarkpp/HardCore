extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			_move_enemy(
				value as EnemyActor,
				game.player.global_position + Vector2(3000, 3000)
			)

	var origin_at_input: Vector2 = game.player.global_position
	var target_axis_gu := Vector2(1.0, 0.35).normalized()
	var intended := _make_enemy(
		game,
		"原锁定目标",
		origin_at_input + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			target_axis_gu
		)
	)
	var decoy := _make_enemy(
		game,
		"禁止偷换目标",
		origin_at_input + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			target_axis_gu.rotated(PI / 2.0)
		)
	)
	_assert_live_fixture(intended, "原锁定目标")
	_assert_live_fixture(decoy, "禁止偷换目标")
	game.locked_target = intended

	# Body animation remains eight-way, while the release geometry uses the
	# exact live axis to the still-valid locked target.
	game.player._pending_attack_context = {
		"mode": "normal",
		"skill_name": "attack",
		"release_geometry": ReleaseGeometry.resolve(
			game.player.global_position,
			Vector2.RIGHT,
			intended.get_instance_id(),
			intended.global_position,
			true,
			true,
			ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
	}
	var intended_hp := intended.current_hp
	var decoy_hp := decoy.current_hp
	game._on_player_attack(origin_at_input, Vector2.RIGHT, 20)
	assert(intended.current_hp < intended_hp, "合法锁定目标未被连续轴命中")
	assert(decoy.current_hp == decoy_hp, "连续轴攻击错误扫描了未锁定诱饵")

	# An out-of-range lock fails closed. It must not fall back to a nearer target.
	intended.current_hp = intended.max_hp
	_move_enemy(
		intended,
		game.player.global_position + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			target_axis_gu * 4.0
		)
	)
	_move_enemy(
		decoy,
		game.player.global_position + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			target_axis_gu
		)
	)
	game.player._pending_attack_context = {
		"mode": "normal",
		"skill_name": "attack",
		"release_geometry": ReleaseGeometry.resolve(
			game.player.global_position,
			Vector2.RIGHT,
			intended.get_instance_id(),
			intended.global_position,
			true,
			true,
			ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
	}
	intended_hp = intended.current_hp
	decoy_hp = decoy.current_hp
	game._on_player_attack(origin_at_input, Vector2.RIGHT, 20)
	assert(intended.current_hp == intended_hp, "真正超距的原锁定目标被错误命中")
	assert(decoy.current_hp == decoy_hp, "超距锁定错误回退到近处目标")

	# The same resolver is shared by all professions' accepted active skills.
	# It must update both caster origin and target direction at release time.
	var moved_origin := origin_at_input + Vector2(18, -11)
	game.player.global_position = moved_origin
	_move_enemy(intended, moved_origin + Vector2(-40, 28))
	var live_geometry: Dictionary = ReleaseGeometry.resolve(
		game.player.global_position,
		Vector2.RIGHT,
		intended.get_instance_id(),
		intended.global_position,
		true,
		true
	)
	assert((live_geometry.origin_screen_px as Vector2).is_equal_approx(moved_origin), "职业技能发射帧仍使用旧施法者脚点")
	assert(
		(live_geometry.direction_screen_px as Vector2).is_equal_approx(
			moved_origin.direction_to(intended.global_position)
		),
		"职业技能发射帧仍使用旧目标方向"
	)
	_move_enemy(decoy, moved_origin + Vector2(3000, 3000))
	_verify_caster_projectile_release(game, intended, origin_at_input)
	game.queue_free()
	await get_tree().process_frame

	print("LIVE_ATTACK_RESOLUTION_PASS：近战动作/伤害朝向一致，实时脚点及法术追踪策略正常")
	get_tree().quit(0)


func _make_enemy(game: Node, display_name: String, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"monster_id": 38,
			"name": display_name,
			"hp": 100,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
			"agility": 0,
			"defMin": 0,
			"defMax": 0,
		},
		game.player,
		false
	)
	enemy.display_name = display_name
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.control_time = 60.0
	game._runtime_spawn_serial += 1
	var spawn_serial := int(game._runtime_spawn_serial)
	enemy.configure_runtime_map_projection(
		game.current_map_id,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.configure_spatial_index(game._combat_spatial_index, spawn_serial)
	enemy.set_meta("spawn_serial", spawn_serial)
	enemy.set_meta("zone_generation", int(game._zone_generation))
	enemy.set_combat_position(position, &"live_attack_fixture_spawn")
	game._combat_spatial_index.register(
		spawn_serial,
		game.current_map_id,
		game._canonical_screen_px_to_ground_gu(position),
		enemy.combat_radius_gu,
		spawn_serial,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)
	game.add_child(enemy)
	return enemy


func _move_enemy(enemy: EnemyActor, position: Vector2) -> void:
	enemy.set_combat_position(position, &"live_attack_fixture_move")


func _assert_live_fixture(enemy: EnemyActor, label: String) -> void:
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.monster_id == 38
		and str(enemy.monster_data.get("canonical_name", "")) == "半兽勇士"
		and str(enemy.monster_data.get("classification", "")) == "elite"
		and not enemy.is_boss,
		"%s夹具未保持canonical elite ID38身份" % label
	)
	assert(enemy.can_receive_damage(), "%s夹具未保持可受击状态" % label)


func _verify_caster_projectile_release(
	game: Node,
	target: EnemyActor,
	origin_at_input: Vector2
) -> void:
	var profession := "法师"
	var skill_name := "火球术"
	var stable_skill_id := "wizard.fireball"
	PlayerState.reset_progress()
	PlayerState.select_profession(profession)
	PlayerState.level = 50
	PlayerState.learned_skills = {skill_name: 0}
	PlayerState.recalculate_stats()
	game.player.current_mp = 999
	var live_origin := origin_at_input + Vector2(12, -7)
	game.player.global_position = live_origin
	_move_enemy(target, live_origin + Vector2(-72, 28))
	var release_geometry: Dictionary = ReleaseGeometry.resolve(
		live_origin,
		Vector2.RIGHT,
		target.get_instance_id(),
		target.global_position,
		true,
		true
	)
	game.player._pending_skill_context = {"release_geometry": release_geometry}
	game._on_player_skill(skill_name, origin_at_input, Vector2.RIGHT, 0)
	var projectile: SkillProjectile
	for child: Node in game.get_children():
		if child is SkillProjectile and (child as SkillProjectile).resolution_skill_id == stable_skill_id:
			projectile = child as SkillProjectile
			break
	assert(projectile != null, "%s没有在释放帧创建正式投射物" % profession)
	assert(
		projectile.global_position.is_equal_approx(live_origin),
		"%s投射物仍从旧脚点生成" % profession
	)
	assert(
		projectile.visual_muzzle_offset_px.is_equal_approx(
			(release_geometry.direction_screen_px as Vector2).normalized() * 24.0
		),
		"%s projectile muzzle offset escaped PX presentation space" % profession
	)
	assert(
		projectile.direction_screen_px.is_equal_approx(live_origin.direction_to(target.global_position)),
		"%s投射物仍瞄准旧方向" % profession
	)
