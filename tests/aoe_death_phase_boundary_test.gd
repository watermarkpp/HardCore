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
	var primary := _make_enemy(game, origin + _screen_offset_gu(axis_gu))
	var survivor := _make_enemy(
		game,
		origin + _screen_offset_gu(axis_gu.rotated(PI / 4.0))
	)
	primary.current_hp = 1
	primary._refresh_overhead_health()
	var survivor_hp_before := survivor.current_hp
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["武器"] = {
		"name": "木剑",
		"count": 1,
		"instance_id": "aoe-death-boundary-weapon",
		"durability_raw": 10000,
		"max_durability_raw": 10000,
		"durability": 10,
		"max_durability": 10,
	}
	PlayerState.test_transaction_debug_reset()
	var death_events: Array[int] = []
	primary.died.connect(func(_enemy: EnemyActor, _data: Dictionary) -> void:
		death_events.append(1)
	)
	game.locked_target = primary
	game.player.half_moon_enabled = true
	game.player._pending_attack_context = {
		"mode": "half_moon",
		"selected_body_mode": "half_moon",
		"skill_name": "半月弯刀",
		"skill_level": 3,
		"release_geometry": ReleaseGeometry.resolve(
			origin,
			Vector2.DOWN,
			primary.get_instance_id(),
			primary.global_position,
			true,
			true,
			ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
		),
	}

	game._on_player_attack(origin, Vector2.DOWN, 200)
	assert(primary.current_hp == 0, "半月致死主目标没有归零")
	assert(survivor.current_hp < survivor_hp_before, "主目标死亡打断了同次半月的存活目标伤害")
	assert(primary._death_pending and not primary._dying, "死亡清理仍在范围伤害循环内同步执行")
	assert(death_events.is_empty(), "died 信号仍在范围伤害循环内同步发出")
	assert(
		not primary.is_in_group("enemies")
		and primary.collision_layer == 0
		and primary.collision_mask == 0,
		"待处理死亡仍能在同帧阻挡投射物或进入后续范围候选"
	)
	assert(
		PlayerState.test_transaction_debug_snapshot().commit_attempts == 1,
		"同一次半月范围攻击仍按目标重复提交武器耐久存档"
	)

	await get_tree().process_frame
	assert(
		primary._dying and death_events.size() == 1,
		"禁用 physics 的对象没有在当前伤害栈结束后统一提交死亡"
	)

	game.queue_free()
	await get_tree().process_frame
	print("AOE_DEATH_PHASE_BOUNDARY_PASS: all targets resolve before deferred death lifecycle")
	get_tree().quit(0)


func _screen_offset_gu(delta_ground_gu: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(delta_ground_gu)


func _make_enemy(game: Node, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(34), game.player, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy
