extends Node

const DEATH_RELEASE_TIMEOUT_SECONDS := 5.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Exercise the production frame-paced bootstrap. The headless test-mode
	# blocking loader can starve dummy-renderer texture finalization.
	PlayerState.test_mode = false
	PlayerState.reset_progress()
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "主场景无法载入")
	var game := packed.instantiate()
	add_child(game)
	var bootstrap_deadline := Time.get_ticks_msec() + 60000
	while (
		(game._world_bootstrap_in_progress or game._map_transition_in_progress)
		and Time.get_ticks_msec() < bootstrap_deadline
	):
		await get_tree().process_frame
	assert(not game._world_bootstrap_in_progress, "综合烟测初始世界加载未完成")
	assert(not game._map_transition_in_progress, "综合烟测初始地图切换未完成")
	PlayerState.test_mode = true

	assert(GameData.maps.size() == 209, "142张来源地图与67张正式地图身份未完整载入")
	var monster_counts := GameData.canonical_monster_counts()
	assert(
		int(monster_counts.get("catalog_identity_count", 0)) == 156,
		"canonical怪物身份目录数量不符"
	)
	assert(
		int(monster_counts.get("runtime_spawnable_count", -1))
		== GameData.monsters.size()
		and GameData.monsters.size() > 0,
		"运行时可生成怪物视图不符"
	)
	assert(GameData.items.size() == 175, "装备数据数量不符")
	assert(GameData.drops.size() == 3424, "掉落槽数量不符")
	PlayerState.add_item("木剑")
	assert(PlayerState.inventory.size() == 1, "拾取入包失败")
	var equip_result := PlayerState.equip_inventory_index(0)
	assert(equip_result.begins_with("已装备"), "装备穿戴失败")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == 10, "装备属性没有计入角色")
	assert(game.player != null, "玩家未创建")

	# 综合烟测直接使用正式比奇运行图；旧郊外演示区不再是生产入口。
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(enemies.size() > 0, "正式比奇运行图没有生成怪物")
	for actor: Node in enemies:
		if actor is EnemyActor:
			actor.apply_control(5.0)
	var boss: EnemyActor
	for actor: Node in enemies:
		if actor is EnemyActor and actor.is_boss:
			boss = actor
			break
	# The retained outskirts sample contains canonical elite ID 56, not a boss.
	# Caller placement must not promote an elite merely to preserve the old demo.
	assert(boss == null, "canonical精英被旧演示调用提升成Boss")
	game.player.take_damage(10)
	var hp_after_skill: int = game.player.current_hp
	PlayerState.add_item("金创药(小量)")
	var potion_index := PlayerState.inventory.size() - 1
	PlayerState.use_inventory_index(potion_index)
	await get_tree().create_timer(0.65).timeout
	assert(game.player.current_hp > hp_after_skill, "生命药品没有生效")
	# Server RM_STRUCK intentionally blocks actions for 100 ms after damage.
	# Wait on the physics-owned state itself; wall-clock timers may resume one
	# frame before the player physics callback consumes the final remainder.
	while game.player._struck_lock_remaining > 0.0:
		await get_tree().physics_frame
	var enemy: EnemyActor = enemies[0]
	game.player.global_position = enemy.global_position - Vector2(30, 0)
	enemy.apply_control(2.0)
	game._set_locked_target(enemy, true)
	game.player.facing = Vector2.RIGHT
	game.player.attack_min = enemy.max_hp * 10
	game.player.attack_max = enemy.max_hp * 10
	var enemy_hp_before_attack := enemy.current_hp
	var death_observation: Dictionary = {
		"lethal_hp_observed": false,
		"death_pending_observed": false,
		"dying_observed": false,
		"died_signal_observed": false,
	}
	enemy.died.connect(func(dead_enemy: EnemyActor, _monster_data: Dictionary) -> void:
		death_observation["died_signal_observed"] = true
		death_observation["lethal_hp_observed"] = dead_enemy.current_hp < enemy_hp_before_attack
		death_observation["dying_observed"] = dead_enemy._dying
	)
	assert(game.player.request_attack(true, enemy.get_instance_id()), "Basic attack rejected: attack=%.3f action=%.3f struck=%.3f control=%.3f dead=%s" % [game.player._attack_timer, game.player._attack_action_timer, game.player._struck_lock_remaining, game.player.control_time, game.player._dead])
	var death_observation_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < death_observation_deadline:
		if not is_instance_valid(enemy):
			break
		death_observation["lethal_hp_observed"] = bool(death_observation.get("lethal_hp_observed", false)) or enemy.current_hp < enemy_hp_before_attack
		death_observation["death_pending_observed"] = bool(death_observation.get("death_pending_observed", false)) or enemy._death_pending
		death_observation["dying_observed"] = bool(death_observation.get("dying_observed", false)) or enemy._dying
		if (
			bool(death_observation.get("lethal_hp_observed", false))
			and (
				bool(death_observation.get("death_pending_observed", false))
				or bool(death_observation.get("dying_observed", false))
				or bool(death_observation.get("died_signal_observed", false))
			)
		):
			break
		await get_tree().process_frame
	assert(bool(death_observation.get("lethal_hp_observed", false)), "攻击释放后目标HP没有下降")
	assert(
		bool(death_observation.get("death_pending_observed", false))
		or bool(death_observation.get("dying_observed", false))
		or bool(death_observation.get("died_signal_observed", false)),
		"致死攻击没有进入death_pending/dying生命周期"
	)
	var death_release_deadline := Time.get_ticks_msec() + int(DEATH_RELEASE_TIMEOUT_SECONDS * 1000.0)
	while is_instance_valid(enemy) and Time.get_ticks_msec() < death_release_deadline:
		await get_tree().process_frame
	assert(not is_instance_valid(enemy), "攻击、死亡链路未完成")

	PlayerState.level = 7
	PlayerState.recalculate_stats()
	PlayerState.add_gold(1000)
	game.change_zone("比奇城")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_zone.begins_with("比奇省") and game.current_map_id == 910001, "旧比奇城入口没有重定向到正式比奇地图")
	var interactables := get_tree().get_nodes_in_group("interactable")
	var npc_count := 0
	var service_identity_ids := {}
	for interactable: Node in interactables:
		if interactable is NPCActor:
			npc_count += 1
			service_identity_ids[(interactable as NPCActor).service_identity_id] = true
	assert(
		npc_count == MapEditorRuntimeBridge.game_content_for_map(910001).npcs.size(),
		"比奇省正式NPC布置没有逐点生成"
	)
	assert(service_identity_ids.size() == 7, "比奇省七种统一NPC功能身份未闭环")
	var bookseller: NPCActor
	var trainer: NPCActor
	var veteran: NPCActor
	for actor: Node in interactables:
		if actor is NPCActor and actor.npc_name == "书店老板":
			bookseller = actor
		elif actor is NPCActor and actor.npc_kind == "trainer":
			trainer = actor
		elif actor is NPCActor and actor.npc_kind == "quest":
			veteran = actor
	assert(bookseller != null and trainer != null and veteran != null, "商店、技能或任务NPC未生成")
	bookseller.interact(game)
	game.hud.shop_panel.item_list.select(0)
	game.hud.shop_panel._buy_selected()
	assert(PlayerState.has_item("基本剑术"), "技能书购买失败")
	trainer.interact(game)
	var basic_book_index := -1
	for inventory_index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[inventory_index].get("name", "")) == "基本剑术":
			basic_book_index = inventory_index
			break
	assert(basic_book_index >= 0, "背包中未找到已购买的技能书")
	PlayerState.use_inventory_index(basic_book_index)
	assert(PlayerState.is_skill_learned("基本剑术"), "技能学习失败")
	assert(
		PlayerState.attack_ring_slots.all(func(value: String) -> bool: return value.is_empty()),
		"被动技能不应进入攻击键或六环主动技能槽"
	)
	veteran.interact(game)
	game.hud.quest_panel._act()
	for count in range(3):
		PlayerState.record_kill("稻草人")
	assert(PlayerState.quest_progress("bich_beginner_gear") == 3, "任务击杀进度失败")
	var gold_before_claim := PlayerState.gold
	game.hud.quest_panel._act()
	assert(PlayerState.gold == gold_before_claim + 100 and PlayerState.has_item("布衣(男)"), "任务奖励领取失败")
	assert(get_tree().get_nodes_in_group("enemies").size() > 0, "正式比奇野外怪物被任务流程清空")

	print("SMOKE_TEST_PASS：数据、区域、商店、药品、技能、任务、战斗与Boss链路正常")
	get_tree().quit(0)
