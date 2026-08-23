extends Node

var _assignment_change_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"基本剑术": 3,
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"烈火剑法": 3,
		"野蛮冲撞": 3,
	}
	PlayerState.attack_skill_slots = [""]
	PlayerState.attack_ring_slots = [
		"刺杀剑术",
		"半月弯刀",
		"烈火剑法",
		"野蛮冲撞",
		"",
		"",
	]
	PlayerState._sync_legacy_quick_slots_from_ring()
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	PlayerState.quick_slots_changed.connect(_on_assignment_changed)
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack_ring",
		"slot_index": 1,
		"slot_id": "hud.attack_ring_skill.2",
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.attack_ring_slots[1] == "野蛮冲撞", "六环槽未保存主动技能")
	assert(PlayerState.attack_ring_slots[0] == "刺杀剑术", "修改单一六环槽污染了其他槽")
	assert(PlayerState.attack_skill_slots == [""], "修改六环槽污染了攻击主键")
	assert(_assignment_change_count == 1, "六环置换没有发出唯一状态信号")
	assert(
		str(game.hud.attack_ring_skill_icons[1].get_meta("skill_name", "")) == "野蛮冲撞",
		"六环置换后HUD没有立即刷新"
	)

	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.attack_skill_slots == ["野蛮冲撞"], "主动技能不能绑定攻击主键")
	assert(game.hud.attack_button.get_meta("bound_skill_name", "") == "野蛮冲撞")
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button.assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"clear": true,
	})
	assert(PlayerState.attack_skill_slots == ["野蛮冲撞"], "错误合同不应清空攻击主键")
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack",
		"slot_index": 0,
		"slot_id": "hud.attack.primary",
		"clear": true,
	})
	assert(PlayerState.attack_skill_slots == [""], "清空攻击主键没有恢复普通攻击")

	var before_passive := PlayerState.skill_button_assignments_snapshot()
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v3",
		"slot_group": "attack_ring",
		"slot_index": 5,
		"slot_id": "hud.attack_ring_skill.6",
		"skill_id": "warrior.slaying_swordsmanship",
	})
	assert(
		PlayerState.skill_button_assignments_snapshot() == before_passive,
		"攻杀被动错误进入主动技能槽"
	)

	var player: PlayerCharacter = game.player
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.set_test_combat_time_ms(1000)
	player.restore_warrior_runtime_state(PlayerState.warrior_runtime_state_for_restore())
	player.current_mp = 40
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = player.global_position + Vector2(2000, 2000)
	player.facing = Vector2.RIGHT
	var input_deadline_ms := Time.get_ticks_msec() + 5000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < input_deadline_ms:
		await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "世界启动未在战士攻击测试时限内开放输入")
	# This case verifies the warrior release/resource pipeline, not Bich safe-zone
	# projection. Keep the formal mapped projection, but isolate the fixture from
	# the independent safe-zone relocation policy during the attack wind-up.
	game._active_safe_zones.clear()
	# World bootstrap may finish while this test waits for the input gate. Reset
	# both frozen footpoints after that transition so the release samples the
	# intended in-range lock instead of a pre-transition fixture coordinate.
	player.global_position = Vector2.ZERO
	var target := _make_enemy(game, player, player.global_position + Vector2(16, 0))
	# A dynamically added CharacterBody may finish its ready-time overlap
	# correction on the next frame. Pin the fixture after that lifecycle step.
	await get_tree().process_frame
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.global_position = player.global_position + Vector2(16, 0)
	target.velocity = Vector2.ZERO
	target.apply_control(60.0)
	game._set_locked_target(target, true)

	assert(player.request_skill("烈火剑法"), "烈火开关无法开启")
	assert(player.fire_sword_enabled, "烈火开关状态没有保留")
	assert(player.current_mp == 40, "开启烈火开关不应立即扣MP")
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火开关后攻击输入未被接受")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(
		player.current_mp == 33,
		"烈火必须在同一次攻击唯一扣除7点MP（actual=%d target=%s hp=%d）" % [
			player.current_mp,
			target.global_position,
			target.current_hp,
		]
	)
	assert(player.skill_cooldown_remaining_ms("warrior.fire_sword") > 0, "烈火独立冷却未建立")
	assert(game._canonical_fire_charge_expires_ms == 0, "烈火直释错误建立旧式二段充能")
	assert(player.fire_sword_enabled, "烈火释放后不应自动关闭开关")
	assert(player.skill_cooldown_remaining_ms("warrior.wild_rush") == 0, "烈火冷却串到其他技能")

	player._physics_process(player._attack_timer + 0.01)
	var mana_before_fallback := player.current_mp
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火冷却时必须接受低优先级攻击")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(player.current_mp == mana_before_fallback, "烈火冷却降级攻击不得再次扣除烈火MP")

	player._physics_process(
		float(player.skill_cooldown_remaining_ms("warrior.fire_sword")) / 1000.0 + 0.01
	)
	assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()), "烈火冷却结束后攻击输入未恢复")
	await get_tree().create_timer(player.attack_hit_windup + 0.08).timeout
	assert(player.current_mp == mana_before_fallback - 7, "烈火冷却结束后没有恢复最高优先级")

	PlayerState.quick_slots_changed.disconnect(_on_assignment_changed)
	print("SKILL_RUNTIME_INTEGRATION_PASS：烈火冷却回退及冷却结束优先级恢复正常")
	get_tree().quit(0)


func _on_assignment_changed(_change: Dictionary) -> void:
	_assignment_change_count += 1


func _make_enemy(game: Node, player: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{"name": "烈火目标", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1},
		player,
		false
	)
	# This fixture validates player release/resource semantics, not monster
	# spawn separation. Prevent the enemy ready hook from relocating it away
	# from the exact melee footpoint before the wind-up resolves.
	enemy.primary_target = null
	enemy.global_position = position
	game.add_child(enemy)
	# EnemyActor._ready() initializes its runtime control state. Freeze the
	# fixture after it enters the tree so the target cannot leave melee range
	# during the player's wind-up.
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.global_position = position
	enemy.velocity = Vector2.ZERO
	enemy.apply_control(60.0)
	return enemy
