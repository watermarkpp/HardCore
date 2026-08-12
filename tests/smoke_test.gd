extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "主场景无法载入")
	var game := packed.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(GameData.maps.size() == 142, "地图数据数量不符")
	assert(GameData.monsters.size() == 214, "怪物数据数量不符（鸡、鹿已按规划删除）")
	assert(GameData.items.size() == 175, "装备数据数量不符")
	assert(GameData.drops.size() == 3424, "掉落槽数量不符")
	PlayerState.add_item("木剑")
	assert(PlayerState.inventory.size() == 1, "拾取入包失败")
	var equip_result := PlayerState.equip_inventory_index(0)
	assert(equip_result.begins_with("已装备"), "装备穿戴失败")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == 10, "装备属性没有计入角色")
	assert(game.player != null, "玩家未创建")

	# 综合烟测的Boss仍使用旧演示场；正式启动点现在按服务端HomeMap=0进入比奇省。
	game.change_zone("比奇郊外")
	await get_tree().process_frame
	await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(enemies.size() >= 5, "演示怪物未完整生成（鸡、鹿已删除）")
	for actor: Node in enemies:
		if actor is EnemyActor:
			actor.apply_control(5.0)
	var boss: EnemyActor
	for actor: Node in enemies:
		if actor is EnemyActor and actor.is_boss:
			boss = actor
			break
	assert(boss != null, "Boss未生成")
	# Boss阶段机制由双Boss专项测试验证；烟测只验证稳定主链，避免演示Boss规则差异造成误报。
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
	enemy.global_position = game.player.global_position + Vector2(30, 0)
	enemy.apply_control(2.0)
	game._set_locked_target(enemy, true)
	game.player.facing = Vector2.RIGHT
	game.player.attack_min = enemy.current_hp
	game.player.attack_max = enemy.current_hp
	assert(game.player.request_attack(true, enemy.get_instance_id()), "Basic attack rejected: attack=%.3f action=%.3f struck=%.3f control=%.3f dead=%s" % [game.player._attack_timer, game.player._attack_action_timer, game.player._struck_lock_remaining, game.player.control_time, game.player._dead])
	await get_tree().create_timer(0.95).timeout
	assert(not is_instance_valid(enemy), "攻击、死亡链路未完成")

	PlayerState.level = 7
	PlayerState.recalculate_stats()
	PlayerState.add_gold(1000)
	game.change_zone("比奇城")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_zone == "比奇省" and game.current_map_id == 4, "旧比奇城入口没有重定向到客户端0.map")
	var interactables := get_tree().get_nodes_in_group("interactable")
	var npc_count := 0
	for interactable: Node in interactables:
		if interactable is NPCActor:
			npc_count += 1
	assert(npc_count == 7, "比奇省正式运行时NPC数量不符")
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
	game.change_zone("比奇郊外")
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemies").size() >= 5, "返回野外后怪物未生成")

	print("SMOKE_TEST_PASS：数据、区域、商店、药品、技能、任务、战斗与Boss链路正常")
	get_tree().quit(0)
