extends Node


const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const RuntimeCombatSpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = false
	PlayerState.active_profile_id = ""
	PlayerState.reset_progress(false)
	PlayerState.select_profession("战士")
	# Level 40 keeps the fixture on the V4 unified 240ms reaction window the
	# lock-separation steps below (0.10s + 0.14s + 0.01s) were written against.
	PlayerState.level = 40
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.visual.set_process(false)
	player.max_hp = 500
	player.current_hp = 500
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = Vector2(58, 0)
	player.set_touch_vector(Vector2.RIGHT)
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	assert(threshold == 15, "500 最大生命的 3% 硬直阈值必须保持 15")
	assert(ProfessionRules.player_struck_damage_threshold(120) == 4, "120 最大生命按 3% 缩放应为 4 点阈值")

	var enemy := EnemyActor.new()
	# Name-only GameData.get_monster() is retired fail-closed; the canonical
	# runtime entry must be fetched by monster id. Monster 64 is an ordinary
	# physical melee attacker. The former monster-76 fixture is a mixed magic
	# delivery and cannot prove the player's physical struck chain.
	enemy.setup(GameData.get_monster_by_id(64), player, false)
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnitSpace.screen_delta_px_to_ground_delta_gu)
	add_child(enemy)
	# HC standard-melee access requires the world-owned combat spatial index.
	# A bare fixture injects its own empty index so the real attack-start gate
	# (and only the AI acquisition cadence, which monster-AI suites own) can run.
	var combat_index := RuntimeCombatSpatialIndexScript.new()
	enemy.configure_spatial_index(combat_index, 1)
	combat_index.register(
		1,
		1,
		enemy.spatial_index_position(),
		enemy.combat_radius_gu,
		1,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	enemy.set_physics_process(false)
	enemy.attack_min = threshold
	enemy.attack_max = threshold
	# Keep the real accuracy rule active while making this damage-chain fixture
	# deterministic: every legal roll must hit the player's current agility.
	enemy.accuracy = enemy._target_agility_for_monster_hit(player)
	enemy._attack_timer = 0.0
	assert(
		is_zero_approx(enemy._attack_hit_delay)
		and str(enemy.attack_delivery_rule.get("kind", "")).is_empty(),
		"端到端测试必须使用真实普通物理近战"
	)

	var hp_before := player.current_hp
	assert(enemy._hc_try_start(player), "真实标准近战攻击必须能够启动")
	assert(
		player.current_hp == hp_before - threshold,
		"Enemy._deal_melee_hit 没有向 Player 提交精确最终伤害"
	)
	assert(
		player._struck_lock_remaining > 0.0
		and player._struck_reaction_lock_remaining > 0.0
		and not player.can_start_attack(),
		"达到 3% 阈值后没有建立服务器动作锁和受击表现锁"
	)

	var reaction_seconds := ProfessionRules.player_struck_reaction_seconds(PlayerState.level)
	var observed_frames: Array[int] = []
	# The hit action advances its three frames proportionally to the reaction
	# duration (progress = elapsed / duration). Sample once per frame band while
	# staying inside the action window.
	for fraction: float in [0.05, 0.4, 0.4]:
		player.visual._process(reaction_seconds * fraction)
		observed_frames.append(player.visual.current_frame)
	assert(player.visual.current_animation_name() == "hit", "Enemy 命中没有触发 Player hit 动作")
	assert(player.visual._frame_count_for_action("hit") == 3, "Player hit 动作必须恰好三帧")
	assert(observed_frames == [0, 1, 2], "三帧 hit 动作时序错误：%s" % [observed_frames])

	var struck_position := player.global_position
	player._physics_process(0.10)
	assert(
		player.global_position.is_equal_approx(struck_position)
		and player.velocity.is_zero_approx()
		and player._struck_lock_remaining <= 0.0
		and player._struck_reaction_lock_remaining > 0.0,
		"100ms 服务器动作锁与 240ms 表现锁没有独立计时"
	)
	player._physics_process(0.14)
	assert(
		player.global_position.is_equal_approx(struck_position),
		"三帧受击表现结束前人物发生位移"
	)
	player._physics_process(0.01)
	assert(player.velocity.x > 0.0, "240ms 受击表现结束后输入没有恢复")

	PlayerState.test_mode = true
	print("PLAYER_ENEMY_STRUCK_CHAIN_E2E_PASS: Enemy physical hit -> damage -> 3 hit frames -> 100/240ms locks")
	get_tree().quit(0)
