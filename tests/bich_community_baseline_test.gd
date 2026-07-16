extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(not GameData.bich_community_baseline.is_empty(), "比奇社区基准未加载")
	var summary: Dictionary = GameData.bich_community_baseline.get("summary", {})
	assert(int(summary.get("monsterOverrides", 0)) >= 20, "社区怪物覆盖不足")
	assert(int(summary.get("spawnGroups", 0)) == 25, "D001—D003刷新组数量异常")
	assert(int(summary.get("runtimeDropMonsters", 0)) == 10, "社区运行掉落怪物数量异常")
	assert(int(summary.get("runtimeDropSlots", 0)) <= 50, "社区运行掉落槽过多")
	for name: String in ["稻草人", "半兽人", "骷髅", "骷髅精灵", "尸王"]:
		var monster: Dictionary = GameData.get_monster(name)
		assert(not monster.is_empty(), "缺少社区怪物：%s" % name)
		assert(int(monster.get("attackIntervalMs", 0)) > 0, "%s未接入社区攻击间隔" % name)
		assert(not str(monster.get("communitySource", "")).is_empty(), "%s缺少社区来源" % name)
	var player := PlayerCharacter.new()
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster("稻草人"), player, false)
	assert(is_equal_approx(enemy._attack_interval, 2.5), "普通怪没有使用社区攻击间隔")
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster("尸王"), player, true)
	assert(is_equal_approx(boss._attack_interval, 2.8), "尸王社区时序与Boss规则没有一致接入")
	for name: String in ["稻草人", "钉耙猫", "多钩猫", "半兽人", "半兽战士", "森林雪人", "食人花", "毒蜘蛛", "骷髅精灵", "尸王"]:
		var calibrated: Array = GameData.get_calibrated_drops(int(GameData.get_monster(name).get("monsterId", 0)), name)
		assert(not calibrated.is_empty() and calibrated.size() <= 6, "%s校准掉落槽数量异常" % name)
		var aggregate_chance := 0.0
		for drop: Dictionary in calibrated:
			assert(not GameData.get_item_record(str(drop.get("name", ""))).is_empty(), "%s掉落物未进入物品目录" % name)
			aggregate_chance += 1.0 / maxi(1, int(drop.get("denominator", 1)))
		assert(aggregate_chance <= (1.35 if name in ["骷髅精灵", "尸王"] else 0.25), "%s总掉落概率过高" % name)
	player.free()
	enemy.free()
	boss.free()
	print("BICH_COMMUNITY_BASELINE_PASS：社区怪物时序、来源、刷新画像和Boss覆盖正常")
	get_tree().quit(0)
