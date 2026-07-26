extends Node

var _quick_slot_change_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"烈火剑法": 3,
		"野蛮冲撞": 3,
	}
	PlayerState.quick_slots = ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	PlayerState.quick_slots_changed.connect(_on_quick_slots_changed)
	game.hud.skill_button_assignment_requested.emit({
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "attack_ring",
		"slot_index": 1,
		"slot_id": "hud.attack_ring_skill.2",
		"skill_id": "warrior.wild_rush",
	})
	assert(PlayerState.quick_slots[1] == "野蛮冲撞", "HUD新版请求未将野蛮冲撞置换到快捷槽")
	assert(_quick_slot_change_count == 1, "快捷槽置换没有发出唯一稳定状态信号")
	assert(game.hud.quick_buttons[1].text.contains("野蛮冲撞"), "快捷槽置换后HUD没有立即刷新")
	var slots_after_v2 := PlayerState.quick_slots.duplicate()
	game.hud.skill_quick_slot_assignment_requested.emit({
		"contract_id": "ui.skill.quick_slot_assignment.v1",
		"slot_index": 0,
		"skill_name": "野蛮冲撞",
	})
	assert(PlayerState.quick_slots == slots_after_v2, "GameRoot错误重复接入旧版快捷槽信号")

	var player: PlayerCharacter = game.player
	player.set_test_combat_time_ms(1000)
	player.restore_warrior_runtime_state(PlayerState.warrior_runtime_state_for_restore())
	player.current_mp = 40
	assert(player.request_skill("烈火剑法"), "烈火显式充能无法开始")
	assert(is_equal_approx(player._attack_action_timer, 0.6), "烈火显式充能未使用SOT 600ms身体动作")
	assert(is_equal_approx(player._attack_timer, 8.0), "烈火显式充能冷却未与600ms身体动作隔离")
	await get_tree().create_timer(0.65).timeout
	assert(player.fire_sword_armed, "烈火Router结果未同步显式充能状态")
	assert(game._canonical_fire_charge_expires_ms > Time.get_ticks_msec(), "烈火canonical结果未建立一次性充能")
	var mana_after_charge := player.current_mp
	assert(mana_after_charge == 33, "烈火显式充能未按SOT唯一扣除7点MP")
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = player.global_position + Vector2(2000, 2000)
	var far_enemy := _make_enemy(game, player, player.global_position + Vector2(180, 0))
	game._cancel_target()
	player.facing = Vector2.RIGHT
	var mana_before_empty_attack := player.current_mp
	game._on_player_attack(player.global_position, Vector2.RIGHT, 100)
	assert(player.current_mp == mana_before_empty_attack, "近战范围内无目标时普通攻击错误消耗烈火")
	assert(game._canonical_fire_charge_expires_ms > Time.get_ticks_msec(), "空挥后烈火一次性充能被错误清除")

	far_enemy.global_position = player.global_position + Vector2(80, 0)
	game._on_player_attack(player.global_position, Vector2.RIGHT, 100)
	assert(player.current_mp == mana_after_charge, "烈火命中时错误二次扣除MP")
	assert(game._canonical_fire_charge_expires_ms == 0, "烈火命中后一次性充能未消费")

	PlayerState.quick_slots_changed.disconnect(_on_quick_slots_changed)
	print("SKILL_RUNTIME_INTEGRATION_PASS：v2换槽、单路信号、HUD刷新及烈火SOT显式充能正常")
	get_tree().quit(0)


func _on_quick_slots_changed(_change: Dictionary) -> void:
	_quick_slot_change_count += 1


func _make_enemy(game: Node, player: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({"name": "烈火目标", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1}, player, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy
