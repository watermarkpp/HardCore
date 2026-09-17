extends Node

## HardCore player hit reaction V4 policy test.
##
## A: 3% max-HP threshold on the real growth formulas (boundary itself staggers)
## B: levels 1-23 reaction durations unchanged (414/360/300/300ms)
## C: level 24+ unified 80ms frames -> 240ms reaction
## D: RUN + struck keeps RUN state, zero displacement, direct RUN resume
## E: 0.6GU walk run-up + struck keeps 0.6GU and finishes the remaining run-up
## F: releasing direction input during the reaction still resets the run-up
## G: a committed attack is never cancelled by an ordinary hit; it settles once
##    and the queued reaction plays after the action completes
## H: five threshold hits during one action stay a single pending bool, one 240ms
##    reaction, no strike-debt accumulation
## I: below-threshold damage only deducts HP and never touches locomotion
## J: causes_struck=false (DOT/poison style) never triggers the ordinary struck

const CharacterBaseGrowth := preload("res://scripts/generated/character_base_growth_v1.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	# ---- A: 3% threshold on the authoritative base growth ----
	assert(
		str(ProfessionRules.COMBAT_REACTION_POLICY.policy_id) == "hardcore_player_hit_reaction_v4",
		"硬直策略必须升级为 v4"
	)
	assert(
		is_equal_approx(float(ProfessionRules.COMBAT_REACTION_POLICY.max_hp_ratio), 0.03),
		"普通硬直阈值比例必须是 3%"
	)
	assert(
		str(ProfessionRules.COMBAT_REACTION_POLICY.comparison) == "actual_damage_gte_threshold",
		"比较必须保持 final_damage >= threshold，边界值本身触发"
	)
	var threshold_cases := [
		["战士", 35, 539, 17], ["法师", 35, 159, 5], ["道士", 35, 306, 10],
		["战士", 40, 674, 21], ["法师", 40, 193, 6], ["道士", 40, 381, 12],
	]
	for case: Array in threshold_cases:
		var stats := CharacterBaseGrowth.stats_for_level(str(case[0]), int(case[1]))
		var max_hp := int(stats["max_hp"])
		assert(max_hp == int(case[2]), "%s %d级成长MaxHP必须为%d" % [case[0], case[1], case[2]])
		assert(
			ProfessionRules.player_struck_damage_threshold(max_hp) == int(case[3]),
			"%s %d级(MaxHP=%d)硬直阈值必须为%d" % [case[0], case[1], max_hp, case[3]]
		)
		assert(
			not ProfessionRules.should_player_stagger(int(case[3]) - 1, max_hp),
			"%s %d级阈值前一点不得硬直" % [case[0], case[1]]
		)
		assert(
			ProfessionRules.should_player_stagger(int(case[3]), max_hp),
			"%s %d级阈值本身必须硬直" % [case[0], case[1]]
		)
	assert(ProfessionRules.player_struck_damage_threshold(100) == 3, "最低3点实际伤害下限必须保留")

	# ---- B/C: reaction duration curve ----
	var duration_cases := [
		[1, 414], [10, 360], [20, 300], [23, 300],
		[24, 240], [25, 240], [35, 240], [40, 240], [50, 240],
	]
	for case: Array in duration_cases:
		assert(
			is_equal_approx(
				ProfessionRules.player_struck_reaction_seconds(int(case[0])),
				float(case[1]) / 1000.0
			),
			"%d级受击表现必须为%dms" % [case[0], case[1]]
		)
	assert(ProfessionRules.player_struck_reaction_frame_milliseconds(23) == 100, "23级单帧必须仍为100ms")
	assert(ProfessionRules.player_struck_reaction_frame_milliseconds(24) == 80, "24级起单帧统一80ms")

	# ---- shared player fixture ----
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
	player.attack_min = 1
	player.attack_max = 1
	player._movement_visual_lock_timer = 0.0
	var threshold := ProfessionRules.player_struck_damage_threshold(player.max_hp)
	assert(threshold == 15, "500 MaxHP 的 3% 阈值必须为 15")
	PlayerState.level = 40

	# ---- D: RUN struck -> zero displacement -> direct RUN resume ----
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	player.set_touch_vector(Vector2.RIGHT)
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	player.take_damage(threshold)
	assert(
		player._struck_lock_remaining > 0.0 and player._struck_reaction_lock_remaining > 0.0,
		"达到阈值必须建立动作锁与受击表现锁"
	)
	assert(
		is_equal_approx(player._struck_reaction_lock_remaining, 0.24),
		"40级受击表现必须是240ms"
	)
	var run_position := player.global_position
	player._physics_process(0.10)
	assert(player.global_position.is_equal_approx(run_position), "受击服务端动作锁内不得位移")
	assert(
		player.locomotion_state == "run" and player.locomotion_distance_gu >= 1.2,
		"RUN受击期间必须保持RUN状态且助跑距离不得清零"
	)
	player._physics_process(0.16)
	assert(player.global_position.is_equal_approx(run_position), "240ms受击表现期内不得位移")
	assert(player.locomotion_state == "run", "受击表现期内RUN状态必须保持")
	player._physics_process(0.01)
	assert(player.velocity.x > 0.0, "受击结束且方向输入保持时必须立即恢复移动")
	assert(player.locomotion_state == "run", "受击后必须直接恢复RUN，禁止回退WALK重新助跑")

	# ---- E: 0.6GU run-up struck -> preserved -> finishes to RUN ----
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player.locomotion_state = "walk"
	player.locomotion_distance_gu = 0.6
	player.take_damage(threshold)
	assert(
		is_equal_approx(player.locomotion_distance_gu, 0.6),
		"起跑0.6GU受击必须立即保留助跑距离"
	)
	assert(player.locomotion_state == "walk", "起跑受击必须保持WALK状态")
	var walk_position := player.global_position
	player._physics_process(0.10)
	player._physics_process(0.16)
	assert(player.global_position.is_equal_approx(walk_position), "起跑受击表现期内不得位移")
	assert(
		is_equal_approx(player.locomotion_distance_gu, 0.6),
		"受击表现期内0.6GU助跑必须原样保留"
	)
	var guard := 0
	while player.locomotion_state != "run" and guard < 120:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player.locomotion_state == "run", "受击结束后从0.6GU继续走必须进入RUN")
	assert(player.locomotion_distance_gu >= 1.0, "进入RUN前必须完成1GU累计")
	assert(
		player.locomotion_distance_gu < 1.2,
		"从0.6GU续走只需约0.4GU即可RUN，禁止清零后重新走满1GU"
	)

	# ---- F: releasing input during the reaction resets the run-up ----
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player.locomotion_state = "walk"
	player.locomotion_distance_gu = 0.6
	player.take_damage(threshold)
	assert(is_equal_approx(player.locomotion_distance_gu, 0.6), "松手场景同样必须先保留0.6GU")
	player.set_touch_vector(Vector2.ZERO)
	player._physics_process(1.0 / 60.0)
	assert(
		player.locomotion_state == "walk" and is_zero_approx(player.locomotion_distance_gu),
		"受击期间玩家主动松手必须清空助跑进度"
	)
	player.set_touch_vector(Vector2.RIGHT)
	guard = 0
	while player.locomotion_state != "run" and guard < 200:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player.locomotion_state == "run", "松手后重新输入必须能再次进入RUN")
	assert(
		player.locomotion_distance_gu >= 1.0,
		"松手清空后必须重新完成完整1GU助跑"
	)

	# ---- G: committed attack is never cancelled by an ordinary hit ----
	var emitted := [0]
	player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
		emitted[0] += 1
	)
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_attack(), "攻击预检必须通过")
	await get_tree().create_timer(0.05).timeout
	player.take_damage(threshold)
	assert(bool(player.struck_reaction_snapshot().queued), "攻击期间达到阈值必须只排队pending硬直")
	assert(str(player.visual.current_animation_name()) == "attack", "普通受击不得取消已提交的攻击动画")
	assert(bool(player.combat_action_snapshot().active), "攻击事务必须保持active")
	assert(not bool(player.combat_action_snapshot().committed), "命中帧前事务不得提前提交")
	assert(emitted[0] == 0, "命中帧前不得提前结算")
	await get_tree().create_timer(0.35).timeout
	assert(emitted[0] == 1, "被硬直排队的攻击必须正常结算恰好一次")
	assert(bool(player.combat_action_snapshot().committed), "伤害结算时事务必须已提交")
	player._attack_action_timer = 0.0
	player._physics_process(1.0 / 60.0)
	assert(not bool(player.struck_reaction_snapshot().queued), "攻击完成后pending必须被消费且只消费一次")
	assert(str(player.visual.current_animation_name()) == "hit", "攻击完成后必须播放排队的受击表现")
	assert(player._struck_reaction_lock_remaining > 0.0, "消费后的受击表现必须真实生效")

	# ---- H: five threshold hits during one action -> one pending reaction ----
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player._queued_struck_reaction = false
	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	assert(player.request_attack(), "第二笔攻击预检必须通过")
	await get_tree().create_timer(0.40).timeout
	assert(emitted[0] == 2, "第二笔攻击也必须恰好结算一次")
	assert(bool(player.combat_action_snapshot().committed), "第二笔攻击事务必须已提交")
	for _hit: int in 5:
		player.take_damage(threshold)
	assert(bool(player.struck_reaction_snapshot().queued), "5次阈值命中后pending必须仍为单个bool")
	assert(player._struck_reaction_lock_remaining <= 0.0, "排队期间不得提前播放受击")
	assert(str(player.visual.current_animation_name()) == "attack", "多次受击不得打断当前攻击动作")
	player._attack_action_timer = 0.0
	player._physics_process(1.0 / 60.0)
	assert(not bool(player.struck_reaction_snapshot().queued), "攻击完成后只允许消费一次pending")
	assert(
		player._struck_reaction_lock_remaining > 0.2 and player._struck_reaction_lock_remaining <= 0.24,
		"多次受击只允许欠一次240ms硬直，禁止硬直债务累积"
	)
	assert(str(player.visual.current_animation_name()) == "hit", "合并后的受击表现必须播放")

	# ---- I: below-threshold damage ----
	player._struck_lock_remaining = 0.0
	player._struck_reaction_lock_remaining = 0.0
	player._queued_struck_reaction = false
	player.locomotion_state = "run"
	player.locomotion_distance_gu = 1.2
	var hp_before := player.current_hp
	player.take_damage(threshold - 1)
	assert(player.current_hp == hp_before - (threshold - 1), "阈值以下伤害必须正常扣血")
	assert(
		player._struck_lock_remaining <= 0.0 and player._struck_reaction_lock_remaining <= 0.0,
		"阈值以下不得产生任何硬直锁"
	)
	assert(
		player.locomotion_state == "run" and is_equal_approx(player.locomotion_distance_gu, 1.2),
		"阈值以下不得影响locomotion状态与助跑距离"
	)

	# ---- J: causes_struck=false never staggers ----
	hp_before = player.current_hp
	player.take_damage(threshold * 3, false)
	assert(player.current_hp == hp_before - threshold * 3, "DOT类伤害必须正常扣血")
	assert(
		player._struck_lock_remaining <= 0.0 and player._struck_reaction_lock_remaining <= 0.0,
		"causes_struck=false 的伤害永远不得触发普通硬直"
	)

	print(
		"PLAYER_HIT_REACTION_POLICY_PASS: v4 ratio=0.03, L1-23 414/360/300ms, L24+ 240ms, locomotion preserved, queued-once, DOT clean"
	)
	get_tree().quit(0)
