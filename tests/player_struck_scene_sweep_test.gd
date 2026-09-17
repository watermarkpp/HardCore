extends Node

## Reviewer close-out item 2: engine-run sweep of the three highlight scenes.
## Scene 1: RUN struck -> stays RUN, distance preserved, immediate resume.
## Scene 2: a 0.5GU walk run-up struck -> run-up kept, WALK->RUN completes.
## Scene 3: warrior half-moon attack with 12 canonical monsters countering ->
##          all threshold hits merge into ONE pending, ONE 240ms reaction.

const ProfessionRules := preload("res://scripts/profession_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _new_warrior() -> PlayerCharacter:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.level = 40
	var player := PlayerCharacter.new()
	add_child(player)
	player.max_hp = 500
	player.current_hp = 500
	player.defense_min = 0
	player.defense_max = 0
	return player


func _run() -> void:
	var threshold := ProfessionRules.player_struck_damage_threshold(500)
	assert(threshold == 15, "500 最大生命的 3% 硬直阈值必须保持 15")

	# ---- Scene 1: RUN struck ----
	var player := _new_warrior()
	player.set_physics_process(false)
	player.set_touch_vector(Vector2.RIGHT)
	var guard := 0
	while player.locomotion_state != "run" and guard < 600:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player.locomotion_state == "run", "场景1必须先真实进入RUN")
	var run_distance := float(player.locomotion_distance_gu)
	assert(run_distance >= 1.0, "RUN状态必须已完成1GU助跑")
	player.take_damage(threshold)
	assert(player._struck_reaction_lock_remaining > 0.0, "场景1阈值命中必须触发硬直")
	player._physics_process(0.05)
	assert(player.velocity.is_zero_approx(), "场景1受击期间位移必须停止")
	assert(player.locomotion_state == "run", "场景1受击不得把RUN降级")
	assert(
		is_equal_approx(player.locomotion_distance_gu, run_distance),
		"场景1受击不得清零RUN助跑距离"
	)
	guard = 0
	while player._struck_reaction_lock_remaining > 0.0 and guard < 600:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player._struck_reaction_lock_remaining <= 0.0, "场景1硬直窗口必须结束")
	player._physics_process(1.0 / 60.0)
	assert(player.velocity.x > 0.0, "场景1松锁后必须立即恢复位移")
	assert(player.locomotion_state == "run", "场景1硬直后必须直接恢复RUN")
	player.free()

	# ---- Scene 2: 0.5GU walk run-up struck ----
	player = _new_warrior()
	player.set_physics_process(false)
	player.set_touch_vector(Vector2.RIGHT)
	guard = 0
	while player.locomotion_distance_gu < 0.5 and guard < 300:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player.locomotion_state == "walk", "场景2起跑半程必须仍是WALK")
	var runup_distance := float(player.locomotion_distance_gu)
	assert(
		runup_distance >= 0.45 and runup_distance < 1.0,
		"场景2必须停在起跑半程（<1GU）：%f" % runup_distance
	)
	player.take_damage(threshold)
	assert(player._struck_reaction_lock_remaining > 0.0, "场景2阈值命中必须触发硬直")
	guard = 0
	while player._struck_reaction_lock_remaining > 0.0 and guard < 600:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(
		is_equal_approx(player.locomotion_distance_gu, runup_distance),
		"场景2硬直不得清零0.5GU起跑进度"
	)
	assert(player.locomotion_state == "walk", "场景2硬直期间必须保持WALK")
	guard = 0
	while player.locomotion_state != "run" and guard < 300:
		player._physics_process(1.0 / 60.0)
		guard += 1
	assert(player.locomotion_state == "run", "场景2保留的助跑必须能继续走到RUN")
	player.free()

	# ---- Scene 3: warrior half-moon attack vs 12 countering monsters ----
	player = _new_warrior()
	player.current_mp = 100
	PlayerState.learned_skills = {"半月弯刀": 3}
	for _i: int in 12:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(56), player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
	player.half_moon_enabled = true
	assert(player.request_attack(), "半月开启后战士攻击预检必须通过")
	assert(
		str(player.combat_action_snapshot().kind) == "attack",
		"半月攻击必须进入真实combat action事务"
	)
	# 12 simultaneous counter-releases land inside the single attack action
	# window (back-to-back same-frame hits model a real multi-monster AOE).
	for _hit: int in 12:
		player.take_damage(threshold)
	assert(bool(player.combat_action_snapshot().active), "12次同时命中必须落在动作窗口内")
	assert(
		bool(player.struck_reaction_snapshot().queued),
		"12次阈值命中必须合并为单个pending"
	)
	assert(player._struck_reaction_lock_remaining <= 0.0, "排队期间不得提前播放受击")
	assert(
		str(player.visual._action_name) != "hit",
		"多怪命中不得打断半月攻击动作（实测动作：%s）" % player.visual._action_name
	)
	guard = 0
	while (
		(bool(player.combat_action_snapshot().active) or bool(player.struck_reaction_snapshot().queued))
		and guard < 600
	):
		await get_tree().process_frame
		guard += 1
	assert(not bool(player.struck_reaction_snapshot().queued), "动作结束后单次pending必须被消费")
	assert(str(player.visual._action_name) == "hit", "12次命中合并后必须播放一次受击")
	var reaction := float(player.struck_reaction_snapshot().reaction_lock_remaining)
	assert(
		reaction > 0.2 and reaction <= 0.24,
		"12次阈值命中只允许欠一次240ms硬直，禁止债务累积：%f" % reaction
	)
	await get_tree().create_timer(reaction + 0.05).timeout
	assert(player._struck_reaction_lock_remaining <= 0.0, "场景3硬直窗口必须结束")
	assert(not bool(player.struck_reaction_snapshot().queued), "场景3结束后不得残留新债务")

	print("PLAYER_STRUCK_SCENE_SWEEP_PASS: run-struck, 0.5GU run-up struck, 12-monster half-moon merge all verified")
	get_tree().quit(0)
