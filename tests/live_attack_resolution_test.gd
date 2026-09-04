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
			(value as EnemyActor).global_position = game.player.global_position + Vector2(3000, 3000)

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
	intended.global_position = game.player.global_position + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		target_axis_gu * 4.0
	)
	decoy.global_position = game.player.global_position + GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		target_axis_gu
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
	intended.global_position = moved_origin + Vector2(-40, 28)
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
	decoy.global_position = moved_origin + Vector2(3000, 3000)
	_verify_caster_projectile_release(game, intended, origin_at_input)
	game.queue_free()
	await get_tree().process_frame

	print("LIVE_ATTACK_RESOLUTION_PASS：近战动作/伤害朝向一致，实时脚点及法术追踪策略正常")
	get_tree().quit(0)


func _make_enemy(game: Node, display_name: String, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
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
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


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
	target.global_position = live_origin + Vector2(-72, 28)
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
