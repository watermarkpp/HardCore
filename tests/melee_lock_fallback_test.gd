extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const WarriorMeleeGeometry := preload("res://scripts/skills/warrior_melee_geometry.gd")


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
	var south_gu := Vector2(1.0, 1.0).normalized()
	var locked_far := _make_enemy(
		game, "超距锁定", origin + _screen_offset_gu(south_gu * 4.0)
	)
	var near_a := _make_enemy(
		game, "近距A", origin + _screen_offset_gu(south_gu * 1.0)
	)
	var near_b := _make_enemy(
		game, "近距B", origin + _screen_offset_gu(south_gu * 1.0)
	)
	var thrust_far_a := _make_enemy(
		game, "刺杀远段A", origin + _screen_offset_gu(south_gu * 2.25)
	)
	var thrust_far_b := _make_enemy(
		game, "刺杀远段B", origin + _screen_offset_gu(south_gu * 2.25)
	)
	var half_side_a := _make_enemy(
		game, "半月侧面A", origin + _screen_offset_gu(Vector2(1.0, 0.0))
	)
	var half_side_b := _make_enemy(
		game, "半月侧面B", origin + _screen_offset_gu(Vector2(0.0, 1.0))
	)
	var half_side_c := _make_enemy(
		game,
		"半月侧面C",
		origin + _screen_offset_gu(Vector2(-1.0, 1.0).normalized())
	)
	game.locked_target = locked_far

	var release_geometry: Dictionary = ReleaseGeometry.resolve(
		origin,
		Vector2.DOWN,
		locked_far.get_instance_id(),
		locked_far.global_position,
		true,
		true
	)

	# Normal and fire remain single-target, but a far lock may no longer block
	# the nearest monster actually covered by the blade.
	_set_attack_context(game, "normal", "attack", release_geometry)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked_far.current_hp == locked_far.max_hp, "普通攻击错误命中超距锁定目标")
	assert(near_a.current_hp == near_a.max_hp - 20, "普通攻击没有回退到范围内最近目标")
	assert(near_b.current_hp == near_b.max_hp, "普通攻击错误变成多目标")

	_reset_hp([near_a, near_b])
	game.player.current_mp = 999
	game.player.fire_sword_enabled = true
	_set_attack_context(game, "fire", "烈火剑法", release_geometry, true)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(locked_far.current_hp == locked_far.max_hp, "烈火错误命中超距锁定目标")
	assert(near_a.current_hp < near_a.max_hp, "烈火没有回退到范围内最近目标")
	assert(near_b.current_hp == near_b.max_hp, "烈火错误变成多目标")

	# Thrust has no target-count cap: every monster in either legal line segment
	# independently enters the hit/damage pipeline.
	_reset_hp([near_a, near_b, thrust_far_a, thrust_far_b])
	game.player.fire_sword_enabled = false
	game.player.thrusting_enabled = true
	game.player.half_moon_enabled = false
	_set_attack_context(game, "thrust", "刺杀剑术", release_geometry)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	for target: EnemyActor in [near_a, near_b, thrust_far_a, thrust_far_b]:
		assert(target.current_hp < target.max_hp, "刺杀遗漏范围内目标：%s" % target.monster_data.get("name", ""))

	# A locked monster near the edge of one 45-degree visual sector must use the
	# exact release-frame footpoint axis. At short range the old canonical axis
	# happened to fit inside the 1-GU strip; at the 2.4-GU far segment its lateral
	# error exceeds the strip and produced the device-only-looking "visual hit,
	# no damage" regression. Keep the body on the S row, but share one continuous
	# damage axis between the locked target and every other monster in the strip.
	for target: EnemyActor in [near_a, near_b, thrust_far_a, thrust_far_b]:
		target.global_position = origin + Vector2(3000, 3000)
	var off_axis_direction_gu := south_gu.rotated(deg_to_rad(22.0))
	var off_axis_locked := _make_enemy(
		game,
		"刺杀远端偏轴锁定",
		origin + _screen_offset_gu(off_axis_direction_gu * 2.4)
	)
	var off_axis_near := _make_enemy(
		game,
		"刺杀同轴近端",
		origin + _screen_offset_gu(off_axis_direction_gu * 1.0)
	)
	var off_axis_release: Dictionary = ReleaseGeometry.resolve(
		origin,
		Vector2.DOWN,
		off_axis_locked.get_instance_id(),
		off_axis_locked.global_position,
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	assert(int(off_axis_release.visual_direction_index) == 0)
	assert(int(off_axis_release.live_locked_target_direction_index) == 0)
	var old_far_slot := WarriorMeleeGeometry.thrust_footprint_slot_gu(
		Vector2.ZERO,
		off_axis_direction_gu * 2.4,
		off_axis_locked.combat_radius_gu,
		0
	)
	assert(old_far_slot == 0, "测试样本没有复现旧八方向中心线的远端漏判")
	_set_attack_context(game, "thrust", "刺杀剑术", off_axis_release)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	assert(off_axis_locked.current_hp < off_axis_locked.max_hp, "连续刺杀轴没有命中2.4 GU偏轴锁定目标")
	assert(off_axis_near.current_hp < off_axis_near.max_hp, "同一次刺杀的近端候选没有复用连续伤害轴")

	# Half moon likewise has no target-count cap inside its approved arc.
	near_a.global_position = origin + _screen_offset_gu(south_gu * 1.0)
	near_b.global_position = origin + _screen_offset_gu(south_gu * 1.0)
	off_axis_locked.global_position = origin + Vector2(3000, 3000)
	off_axis_near.global_position = origin + Vector2(3000, 3000)
	_reset_hp([near_a, near_b, half_side_a, half_side_b, half_side_c])
	game.player.thrusting_enabled = false
	game.player.half_moon_enabled = true
	game.player.current_mp = 999
	_set_attack_context(game, "half_moon", "半月弯刀", release_geometry)
	game._on_player_attack(origin, Vector2.DOWN, 20)
	for target: EnemyActor in [near_a, near_b, half_side_a, half_side_b, half_side_c]:
		assert(target.current_hp < target.max_hp, "半月遗漏范围内目标：%s" % target.monster_data.get("name", ""))

	# Both actor and locked monster may move during windup. The shared release
	# resolver and melee handler must use the same live pair of footpoints.
	for target: EnemyActor in [near_a, near_b, thrust_far_a, thrust_far_b, half_side_a, half_side_b, half_side_c]:
		target.global_position = origin + Vector2(3000, 3000)
	game.player.thrusting_enabled = false
	game.player.half_moon_enabled = false
	game.player.fire_sword_enabled = false
	var moved_origin := origin + Vector2(18, -11)
	game.player.global_position = moved_origin
	locked_far.global_position = moved_origin + (
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			Vector2(1.0, 1.0).normalized() * 1.25
		)
	)
	locked_far.current_hp = locked_far.max_hp
	game.locked_target = locked_far
	var moving_release_geometry: Dictionary = ReleaseGeometry.resolve(
		game.player.global_position,
		Vector2.DOWN,
		locked_far.get_instance_id(),
		locked_far.global_position,
		true,
		true
	)
	_set_attack_context(game, "normal", "attack", moving_release_geometry)
	game._on_player_attack(origin, Vector2.RIGHT, 20)
	assert(locked_far.current_hp < locked_far.max_hp, "人物与锁定怪物同时移动后整刀判空")

	game.queue_free()
	await get_tree().process_frame
	print("MELEE_LOCK_FALLBACK_PASS：锁定仅控制朝向；普通/烈火单体回退；刺杀/半月范围内无数量上限")
	get_tree().quit(0)


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


func _make_enemy(game: Node, display_name: String, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
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
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy
