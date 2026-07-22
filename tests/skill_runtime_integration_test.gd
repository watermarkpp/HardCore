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
	assert(player.request_skill("烈火剑法") and player.fire_sword_auto_enabled, "烈火自动释放开关无法开启")
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = player.global_position + Vector2(2000, 2000)
	var far_enemy := _make_enemy(game, player, player.global_position + Vector2(180, 0))
	game._cancel_target()
	player.facing = Vector2.RIGHT
	var mana_before_empty_attack := player.current_mp
	game._request_mobile_attack()
	assert(player.current_mp == mana_before_empty_attack, "近战范围内无目标时普通攻击错误消耗烈火")
	assert(player.fire_sword_auto_enabled, "空挥后烈火自动开关被错误关闭")

	player._attack_timer = 0.0
	player._attack_action_timer = 0.0
	far_enemy.global_position = player.global_position + Vector2(80, 0)
	game._cancel_target()
	game._request_mobile_attack()
	assert(player.current_mp < mana_before_empty_attack, "近战范围内有目标时烈火没有自动释放")
	assert(player.fire_sword_auto_enabled, "烈火自动释放后开关没有保持开启")

	PlayerState.quick_slots_changed.disconnect(_on_quick_slots_changed)
	print("SKILL_RUNTIME_INTEGRATION_PASS：v2换槽、单路信号、HUD刷新及烈火有目标释放/空挥保留正常")
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
