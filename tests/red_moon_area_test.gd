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
	for map_id: int in RegionContent.RED_MOON_MAPS.keys():
		var source: Dictionary = RegionContent.RED_MOON_MAPS[map_id]
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("spawns", []).size() + content.get("bosses", []).size() == int(source.get("spawn_count", 0)), "赤月地图%d配置怪物数不符" % map_id)
		assert(content.get("portals", []).size() == source.get("targets", []).size(), "赤月地图%d门点数不符" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "赤月地图%d运行时怪物数不符" % map_id)
	var white_gate := RegionContent.get_map_content(2863)
	assert(white_gate.get("npcs", []).size() == 4, "白日门商店或导师不完整")
	var choice := RegionContent.get_map_content(2941)
	assert(choice.get("npcs", []).size() == 1 and str(choice.npcs[0].get("name", "")) == "抉择之地商人", "抉择之地商人未接入")
	var altar := RegionContent.get_map_content(2944)
	assert(altar.get("bosses", []).size() == 2 and str(altar.bosses[0].get("name", "")) == "双头血魔" and str(altar.bosses[1].get("name", "")) == "双头金刚", "恶魔祭坛双Boss编组错误")
	var lair := RegionContent.get_map_content(2945)
	assert(lair.get("bosses", []).size() == 1 and str(lair.bosses[0].get("name", "")) == "赤月恶魔", "赤月魔穴Boss编组错误")
	for boss_map: Dictionary in [altar, lair]:
		for boss: Variant in boss_map.get("bosses", []):
			assert(float(boss.get("respawn_seconds", 0.0)) == 21600.0, "赤月Boss刷新候选值失效")
	assert(not GameData.get_drops_for_boss(162).is_empty() and not GameData.get_drops_for_boss(163).is_empty() and not GameData.get_drops_for_boss(180).is_empty(), "赤月三Boss掉落未接入")
	var moon_spider := EnemyActor.new()
	moon_spider.setup(GameData.get_monster("月魔蜘蛛"), game.player, false)
	assert(moon_spider.control_on_hit_seconds >= 1.2, "月魔蜘蛛麻痹能力失效")
	moon_spider.free()
	var illusion_spider := EnemyActor.new()
	illusion_spider.setup(GameData.get_monster("幻影蜘蛛"), game.player, false)
	assert(
		illusion_spider.stationary
		and illusion_spider.move_speed_gu_per_sec == 0.0
		and illusion_spider.attack_range_gu == 0.0
		and bool(illusion_spider.summon_rule.get("enabled", false)),
		"幻影蜘蛛固定召唤行为失效",
	)
	illusion_spider.free()
	var demon := EnemyActor.new()
	demon.setup(GameData.get_monster("赤月恶魔"), game.player, true)
	assert(demon.move_speed_gu_per_sec == 0.0 and demon.attack_range_gu >= 250.0 / 32.0, "赤月恶魔固定范围攻击失效")
	demon.free()
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() + RegionContent.ZUMA_MAPS.size() + RegionContent.UNKNOWN_DARK_MAPS.size() + RegionContent.FENGMO_MAPS.size() + RegionContent.RED_MOON_MAPS.size() == 103, "固定区域地图总数应为103")
	print("RED_MOON_AREA_PASS：白日门赤月13图、蜘蛛行为、祭坛双Boss和赤月恶魔正常")
	get_tree().quit(0)
