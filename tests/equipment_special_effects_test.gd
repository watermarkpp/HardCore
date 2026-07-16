extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _equip_only(item_name: String) -> Dictionary:
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.gold = 1000
	PlayerState.recalculate_stats()
	PlayerState.add_item(item_name)
	assert(PlayerState.equip_inventory_index(_inventory_index(item_name)).begins_with("已装备"), "%s穿戴失败" % item_name)
	return PlayerState.equipment["左戒指"]


func _run() -> void:
	var file := FileAccess.open("res://assets/data/equipment_special_rules.json", FileAccess.READ)
	assert(file != null, "特殊装备规则来源表缺失")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary and source.runtimeEffects.size() == 8, "八项特殊效果来源表错误")
	assert(source.registeredOnly.is_empty() and source.deferredSets.size() == 9, "主动戒指或延期套装边界记录错误")
	assert(int(source.rules.get("revivalCooldownMs", 0)) == 60000 and float(source.rules.get("magicShieldMpPerDamage", 0)) == 1.5, "复活/护身服务端常量错误")

	var teleport := EquipmentRulesScript.special_effect_for(GameData.get_item("传送戒指"))
	assert(teleport.get("id", "") == "teleport" and bool(teleport.get("runtime", false)), "传送戒指手机交互没有登记完成")
	assert(EquipmentRulesScript.paralysis_succeeds(0, 0) and not EquipmentRulesScript.paralysis_succeeds(0, 1), "麻痹戒指基础1/5判定错误")

	PlayerState.test_mode = true
	var overload := _equip_only("超负载戒指")
	var normal_wear := EquipmentRulesScript.max_wear_weight("战士", 50)
	assert(PlayerState.has_special_effect("double_weight"), "超负载戒指没有注册运行效果")
	assert(int(PlayerState.computed_stats.get("max_wear_weight", 0)) == normal_wear * 2, "超负载戒指没有翻倍穿戴负重")
	PlayerState.damage_equipment_durability("左戒指", int(overload.get("max_durability", 1)))
	assert(not PlayerState.has_special_effect("double_weight") and int(PlayerState.computed_stats.get("max_wear_weight", 0)) == normal_wear, "零耐久超负载戒指仍然生效")

	var stealth_ring := _equip_only("隐身戒指")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: PlayerCharacter = game.player
	assert(player.is_stealthed(), "隐身戒指没有让怪物识别为隐身")
	PlayerState.damage_equipment_durability("左戒指", int(stealth_ring.get("max_durability", 1)))
	assert(not player.is_stealthed(), "零耐久隐身戒指仍然生效")

	var shield_ring := _equip_only("护身戒指")
	player.current_hp = 100
	player.current_mp = 100
	player.take_damage(20)
	assert(player.current_hp == 100 and player.current_mp < 100, "护身戒指没有按1.5倍魔法值抵伤")
	PlayerState.damage_equipment_durability("左戒指", int(shield_ring.get("max_durability", 1)))
	var hp_before := player.current_hp
	player.take_damage(20)
	assert(player.current_hp < hp_before, "零耐久护身戒指仍在抵伤")

	var revival_ring := _equip_only("复活戒指")
	player.current_hp = player.max_hp
	var gold_before := PlayerState.gold
	var dura_before := int(revival_ring.get("durability", 0))
	player.take_damage(999999)
	assert(player.current_hp == player.max_hp and PlayerState.gold == gold_before, "复活戒指首次触发没有原地满血复活")
	assert(int(revival_ring.get("durability", 0)) == dura_before - 1, "复活触发没有损耗戒指耐久")
	player.take_damage(999999)
	assert(PlayerState.gold < gold_before, "复活戒指60秒冷却没有阻止连续触发")
	assert(int(revival_ring.get("durability", 0)) == dura_before - 1, "冷却中的复活戒指被再次损耗")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert("60秒复活" in panel.equipment_label.text, "装备面板没有显示特殊效果状态")

	print("EQUIPMENT_SPECIAL_EFFECTS_PASS：五项首批效果、零耐久撤销、复活冷却、护身抵伤和未实现边界正常")
	get_tree().quit(0)
