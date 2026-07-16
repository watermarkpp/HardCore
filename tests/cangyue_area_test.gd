extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in RegionContent.CANGYUE_MAPS.keys():
		var source: Dictionary = RegionContent.CANGYUE_MAPS[map_id]
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("spawns", []).size() + content.get("bosses", []).size() == int(source.get("spawn_count", 0)), "苍月地图%d配置怪物数不符" % map_id)
		assert(content.get("portals", []).size() == source.get("targets", []).size(), "苍月地图%d门点数不符" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "苍月地图%d运行时怪物数不符" % map_id)
	var island := RegionContent.get_map_content(3165)
	assert(island.get("npcs", []).size() == 4 and island.get("portals", []).size() == 5, "苍月岛NPC、三洞或重装入口不完整")
	var corpse_depth := RegionContent.get_map_content(3197)
	assert(corpse_depth.get("bosses", []).size() == 1 and str(corpse_depth.bosses[0].get("name", "")) == "恶灵尸王", "尸魔洞三层精英未接入")
	var bone_depth := RegionContent.get_map_content(3220)
	assert(str(bone_depth.bosses[0].get("name", "")) == "黄泉教主" and float(bone_depth.bosses[0].get("respawn_seconds", 0.0)) == 10800.0, "黄泉教主或刷新候选值失效")
	var cow_hall := RegionContent.get_map_content(3252)
	assert(str(cow_hall.bosses[0].get("name", "")) == "牛魔王" and float(cow_hall.bosses[0].get("respawn_seconds", 0.0)) == 21600.0, "牛魔王或刷新候选值失效")
	assert(not GameData.get_drops_for_boss(208).is_empty() and not GameData.get_drops_for_boss(224).is_empty(), "黄泉教主或牛魔王掉落未接入")
	var archer := EnemyActor.new()
	archer.setup(GameData.get_monster("骷髅弓箭手"), game.player, false)
	assert(archer.attack_range >= 200.0, "骷髅弓箭手远程行为失效")
	archer.free()
	var mage := EnemyActor.new()
	mage.setup(GameData.get_monster("牛魔法师"), game.player, false)
	assert(mage.attack_range >= 200.0, "牛魔法师远程行为失效")
	mage.free()
	var priest := EnemyActor.new()
	priest.setup(GameData.get_monster("牛魔祭司"), game.player, false)
	assert(priest.attack_range >= 170.0 and priest.life_steal_ratio > 0.0, "牛魔祭司恢复行为失效")
	priest.free()
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() + RegionContent.ZUMA_MAPS.size() + RegionContent.UNKNOWN_DARK_MAPS.size() + RegionContent.FENGMO_MAPS.size() + RegionContent.RED_MOON_MAPS.size() + RegionContent.CANGYUE_MAPS.size() == 120, "固定区域地图总数应为120")
	print("CANGYUE_AREA_PASS：苍月17图、尸魔/骨魔/牛魔链、远程怪、黄泉教主和牛魔王正常")
	get_tree().quit(0)
