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
	for map_id: int in RegionContent.FENGMO_MAPS.keys():
		var source: Dictionary = RegionContent.FENGMO_MAPS[map_id]
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("spawns", []).size() + content.get("bosses", []).size() == int(source.get("spawn_count", 0)), "封魔地图%d配置怪物数不符" % map_id)
		assert(content.get("portals", []).size() == source.get("targets", []).size(), "封魔地图%d门点数不符" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "封魔地图%d运行时怪物数不符" % map_id)
	var final_content := RegionContent.get_map_content(3038)
	var final_bosses: Array = final_content.get("bosses", [])
	assert(final_bosses.size() == 3, "封魔殿应有虹魔三Boss")
	assert(str(final_bosses[0].get("name", "")) == "虹魔猪卫" and str(final_bosses[1].get("name", "")) == "虹魔蝎卫" and str(final_bosses[2].get("name", "")) == "虹魔教主", "封魔殿Boss编组错误")
	for boss: Variant in final_bosses:
		assert(float(boss.get("respawn_seconds", 0.0)) == 10800.0, "虹魔Boss刷新候选值失效")
	assert(not GameData.get_drops_for_boss(191).is_empty() and not GameData.get_drops_for_boss(193).is_empty(), "虹魔蝎卫或虹魔教主掉落未接入")
	var tree := EnemyActor.new()
	tree.setup(GameData.get_monster("千年树妖"), game.player, true)
	assert(tree.move_speed_gu_per_sec == 0.0 and tree.attack_range_gu >= 230.0 / 32.0, "千年树妖固定远程行为失效")
	tree.free()
	var leader := EnemyActor.new()
	leader.setup(GameData.get_monster("虹魔教主"), game.player, true)
	leader.current_hp = 1000
	var before_heal := leader.current_hp
	leader.apply_life_steal(90)
	assert(leader.life_steal_ratio > 0.0 and leader.current_hp > before_heal, "虹魔教主近战吸血行为失效")
	leader.free()
	var mengzhong := RegionContent.get_map_content(478)
	var has_fengmo_portal := false
	for portal: Variant in mengzhong.get("portals", []):
		if portal is Dictionary and int(portal.get("target_map_id", 0)) == 3013:
			has_fengmo_portal = true
	assert(has_fengmo_portal, "盟重省没有接入封魔谷入口")
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() + RegionContent.ZUMA_MAPS.size() + RegionContent.UNKNOWN_DARK_MAPS.size() + RegionContent.FENGMO_MAPS.size() == 90, "固定区域地图总数应为90")
	print("FENGMO_AREA_PASS：封魔15图、千年树妖、虹魔三Boss、吸血行为和10800秒刷新正常")
	get_tree().quit(0)
