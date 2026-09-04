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
	PlayerState.learned_skills = {
		"warrior.basic_sword": 3,
		"warrior.slaying": 3,
		"warrior.thrusting": 3,
		"warrior.half_moon": 3,
		"warrior.fire_sword": 3,
	}
	PlayerState.recalculate_stats()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(3000, 3000)

	var origin: Vector2 = game.player.global_position
	var axis_gu := Vector2(1.0, 0.35).normalized()
	var player_position_before: Vector2 = game.player.global_position
	var locked := _make_enemy(game, "固定锁定", origin + _screen_offset_gu(axis_gu * 4.0))
	var near := _make_enemy(game, "禁止回退", origin + _screen_offset_gu(axis_gu))
	var lateral := _make_enemy(
		game,
		"轴外目标",
		origin + _screen_offset_gu(axis_gu.rotated(PI / 2.0))
	)
	game.locked_target = locked

	# An out-of-range locked target fails closed. Normal and fire may not scan a
	# nearer monster or move the player to manufacture a hit.
	var far_release := _release(origin, locked, Vector2.DOWN)
	_set_attack_context(game, "normal", "attack", far_release)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked.current_hp == locked.max_hp, "普通攻击错误命中超距锁定目标")
	assert(near.current_hp == near.max_hp, "普通攻击错误回退到范围内目标")
	assert(game.player.global_position.is_equal_approx(player_position_before), "攻击为追锁自动移动了角色")

	game.player.current_mp = 999
	game.player.fire_sword_enabled = true
	_set_attack_context(game, "fire", "烈火剑法", far_release, true)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked.current_hp == locked.max_hp and near.current_hp == near.max_hp, "烈火对无效锁定发生回退命中")

	# A valid in-range lock owns the continuous axis and single-target priority.
	_move_enemy(locked, origin + _screen_offset_gu(axis_gu))
	_move_enemy(near, locked.global_position)
	game.locked_target = locked
	game.player.fire_sword_enabled = false
	_reset_hp([locked, near, lateral])
	var near_release := _release(origin, locked, Vector2.DOWN)
	_set_attack_context(game, "normal", "attack", near_release)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked.current_hp < locked.max_hp, "普通攻击未命中合法锁定目标")
	assert(near.current_hp == near.max_hp, "普通攻击错误命中同位置未锁定目标")

	# Thrust uses the same continuous axis for its near and far slots.
	_move_enemy(locked, origin + _screen_offset_gu(axis_gu * 2.25))
	_move_enemy(near, origin + _screen_offset_gu(axis_gu))
	_move_enemy(lateral, origin + _screen_offset_gu(axis_gu.rotated(PI / 2.0)))
	game.locked_target = locked
	_reset_hp([locked, near, lateral])
	game.player.thrusting_enabled = true
	game.player.half_moon_enabled = false
	var thrust_release := _release(origin, locked, Vector2.DOWN)
	_set_attack_context(game, "thrust", "刺杀剑术", thrust_release)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(near.current_hp < near.max_hp, "刺杀连续轴近段未命中")
	assert(locked.current_hp < locked.max_hp, "刺杀连续轴远段未命中锁定目标")
	assert(lateral.current_hp == lateral.max_hp, "刺杀错误命中连续轴外目标")

	# Half moon rotates its side sectors around the same locked-target axis.
	_move_enemy(locked, origin + _screen_offset_gu(axis_gu))
	_move_enemy(near, origin + _screen_offset_gu(axis_gu.rotated(-PI / 4.0)))
	_move_enemy(lateral, origin + _screen_offset_gu(axis_gu.rotated(PI / 4.0)))
	var behind := _make_enemy(
		game,
		"半月背后",
		origin + _screen_offset_gu(axis_gu.rotated(PI))
	)
	game.locked_target = locked
	_reset_hp([locked, near, lateral, behind])
	game.player.thrusting_enabled = false
	game.player.half_moon_enabled = true
	var half_release := _release(origin, locked, Vector2.DOWN)
	_set_attack_context(game, "half_moon", "半月弯刀", half_release)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked.current_hp < locked.max_hp, "半月主扇区未命中锁定目标")
	assert(near.current_hp < near.max_hp and lateral.current_hp < lateral.max_hp, "半月连续轴侧扇区遗漏目标")
	assert(behind.current_hp == behind.max_hp, "半月错误命中角色背后目标")

	# Actor and target footpoints are sampled together at release.
	game.player.thrusting_enabled = false
	game.player.half_moon_enabled = false
	var moved_origin := origin + Vector2(18, -11)
	game.player.global_position = moved_origin
	_move_enemy(locked, moved_origin + _screen_offset_gu(axis_gu * 1.25))
	locked.current_hp = locked.max_hp
	game.locked_target = locked
	var moving_release := _release(moved_origin, locked, Vector2.RIGHT)
	_set_attack_context(game, "normal", "attack", moving_release)
	game._on_player_attack(moved_origin, Vector2.RIGHT, 20)
	assert(locked.current_hp < locked.max_hp, "人物与锁定目标同时移动后整刀判空")

	game.queue_free()
	await get_tree().process_frame
	print("MELEE_LOCK_FALLBACK_PASS: invalid locks fail closed; valid locks own continuous normal/thrust/half-moon axes")
	get_tree().quit(0)


func _release(origin: Vector2, target: EnemyActor, body_direction: Vector2) -> Dictionary:
	return ReleaseGeometry.resolve(
		origin,
		body_direction,
		target.get_instance_id(),
		target.global_position,
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)


func _set_attack_context(
	game: Node,
	mode: String,
	skill_name: String,
	release_geometry: Dictionary,
	direct_toggle_release := false
) -> void:
	game.player._pending_attack_context = {
		"mode": mode,
		"selected_body_mode": mode,
		"skill_name": skill_name,
		"skill_level": 3,
		"direct_toggle_release": direct_toggle_release,
		"release_geometry": release_geometry,
	}


func _reset_hp(targets: Array) -> void:
	for target: EnemyActor in targets:
		target.current_hp = target.max_hp


func _screen_offset_gu(delta_ground_gu: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(delta_ground_gu)


func _move_enemy(enemy: EnemyActor, position: Vector2) -> void:
	enemy.set_combat_position(position, &"melee_lock_fixture_move")


func _make_enemy(game: Node, display_name: String, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"monster_id": 38,
			"name": display_name,
			"hp": 200,
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
	enemy.set_combat_position(position, &"melee_lock_fixture_spawn")
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
