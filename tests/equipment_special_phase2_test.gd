extends Node


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _reset_level_50() -> void:
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.gold = 1000
	PlayerState.recalculate_stats()


func _equip(item_name: String) -> void:
	PlayerState.add_item(item_name)
	assert(PlayerState.equip_inventory_index(_inventory_index(item_name)).begins_with("已装备"), "%s无法组成通用套装" % item_name)


func _run() -> void:
	PlayerState.test_mode = true
	_reset_level_50()
	var base_hp := int(PlayerState.computed_stats.get("max_hp", 0))
	var base_mp := int(PlayerState.computed_stats.get("max_mp", 0))
	for item_name: String in ["魔血项链", "魔血手镯", "魔血戒指"]:
		_equip(item_name)
	var expected_magic_power := mini(125, maxi(0, base_mp - 1))
	assert(PlayerState.has_special_effect("magic_blood"), "魔血三件套没有形成运行效果")
	assert(int(PlayerState.computed_stats.get("max_hp", 0)) == base_hp + expected_magic_power, "魔血三件套没有按75+50将MP转为HP")
	assert(int(PlayerState.computed_stats.get("max_mp", 0)) == base_mp - expected_magic_power, "魔血套装MP扣减错误")
	var magic_necklace: Dictionary = PlayerState.equipment["项链"]
	PlayerState.damage_equipment_durability("项链", int(magic_necklace.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("max_hp", 0)) == base_hp + 50, "零耐久魔血组件仍计入三件套或没有撤销全套奖励")

	_reset_level_50()
	var base_accuracy := int(PlayerState.computed_stats.get("accuracy", 0))
	for item_name: String in ["虹魔项链", "虹魔手镯", "虹魔戒指"]:
		_equip(item_name)
	assert(int(PlayerState.computed_stats.get("life_steal_percent", 0)) == 9, "虹魔4+3+2吸血候选没有累计")
	assert(int(PlayerState.computed_stats.get("accuracy", 0)) == base_accuracy + 2, "虹魔三件套服务端准确+2没有接入")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(not enemies.is_empty(), "虹魔吸血测试没有怪物")
	game.player.current_hp = game.player.max_hp - 30
	var hp_before: int = int(game.player.current_hp)
	assert(game._apply_physical_hit(enemies[0], 100), "虹魔近战测试攻击失败")
	assert(game.player.current_hp == hp_before + 9, "虹魔近战吸血没有按9%恢复")
	var rainbow_necklace: Dictionary = PlayerState.equipment["项链"]
	PlayerState.damage_equipment_durability("项链", int(rainbow_necklace.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("life_steal_percent", 0)) == 5, "零耐久虹魔项链没有撤销4%吸血")
	assert(int(PlayerState.computed_stats.get("accuracy", 0)) == base_accuracy, "虹魔组件破损后仍保留全套准确奖励")

	_reset_level_50()
	_equip("传送戒指")
	_equip("火焰戒指")
	assert(PlayerState.available_special_actions() == ["teleport", "flame_skill"], "双主动戒指动作顺序错误")
	assert(game.hud.special_action_button.visible, "手机特装按钮没有显示")
	game.player.facing = Vector2.RIGHT
	var position_before: Vector2 = game.player.global_position
	game._on_special_action_pressed("teleport")
	assert(game.player.global_position.x > position_before.x, "传送戒指没有沿朝向移动到安全落点")
	game.player.current_mp = 10
	var children_before := game.get_child_count()
	game._on_special_action_pressed("flame_skill")
	assert(game.player.current_mp == 5 and game.get_child_count() == children_before + 1, "火焰戒指没有消耗5MP并生成火球")

	_reset_level_50()
	_equip("防御戒指")
	game.player.current_hp = game.player.max_hp - 40
	game.player.current_mp = 10
	hp_before = game.player.current_hp
	game._on_special_action_pressed("recovery_skill")
	assert(game.player.current_hp > hp_before and game.player.current_mp == 5, "防御戒指没有消耗5MP并治疗")
	var recovery_ring: Dictionary = PlayerState.equipment["左戒指"]
	PlayerState.damage_equipment_durability("左戒指", int(recovery_ring.get("max_durability", 1)))
	assert(PlayerState.available_special_actions().is_empty() and not game.hud.special_action_button.visible, "主动戒指零耐久后手机入口仍然存在")

	assert(not PlayerState.has_special_effect("memory") and not PlayerState.has_special_effect("prayer"), "记忆/祈祷多人效果被擅自启用")
	print("EQUIPMENT_SPECIAL_PHASE2_PASS：主动戒指、魔血125候选、虹魔9%候选、零耐久与单机边界正常")
	get_tree().quit(0)
