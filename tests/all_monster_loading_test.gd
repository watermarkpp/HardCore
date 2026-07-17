extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const MONSTERS_PATH := "res://assets/data/vanilla_176/monsters.json"
const RUNTIME_PATH := "res://assets/data/service_monster_runtime_catalog.json"
const ANIMATION_PATH := "res://assets/data/runtime/monster_animation_catalog.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var monsters := _load_json(MONSTERS_PATH)
	var runtime := _load_json(RUNTIME_PATH)
	var animations := _load_json(ANIMATION_PATH)
	var records: Array = monsters.get("records", [])
	var runtime_by_id: Dictionary = runtime.get("runtimeByMonsterId", {})
	var summary: Dictionary = runtime.get("summary", {})

	assert(runtime.get("identityKey", "") == "monsterId", "全量怪物运行时目录未声明稳定 monsterId 主键")
	assert(runtime.get("runtimeMode", "") == "single_player", "怪物目录没有声明单机运行模式")
	assert(
		runtime.get("sources", {}).get("primaryServiceRules", {}).get("distribution", "")
		== "source.original_gameofmir.server_suite",
		"怪物目录没有遵守主服务树规则优先级"
	)
	assert(records.size() == 214, "项目怪物基表数量发生非预期变化")
	assert(runtime_by_id.size() == records.size(), "并非全部项目怪物都有运行时条目")
	assert(int(summary.get("exactServiceName", -1)) == 142, "主服务端精确名称匹配数量发生非预期变化")
	assert(int(summary.get("baseNameFallback", -1)) == 15, "主服务端基础名兼容匹配数量发生非预期变化")
	assert(int(summary.get("unresolvedProjectFallback", -1)) == 57, "显式项目回退数量发生非预期变化")

	var seen_ids: Dictionary = {}
	for value: Variant in records:
		assert(value is Dictionary, "怪物基表包含非字典记录")
		var monster: Dictionary = value
		var monster_id := int(monster.get("monsterId", -1))
		var key := str(monster_id)
		assert(monster_id >= 0 and not seen_ids.has(key), "怪物基表 monsterId 缺失或重复: %s" % key)
		seen_ids[key] = true
		assert(runtime_by_id.has(key), "monsterId=%d 缺少全量运行时条目" % monster_id)

		var entry := MonsterIdentityScript.service_runtime_entry(monster)
		var profile := MonsterIdentityScript.behavior_profile(monster)
		var timing: Dictionary = profile.get("timing", {})
		var service: Dictionary = profile.get("serviceBehavior", {})
		assert(int(entry.get("monsterId", -1)) == monster_id, "monsterId=%d 被解析到错误运行时条目" % monster_id)
		assert(int(timing.get("attackIntervalMs", 0)) > 0, "monsterId=%d 缺少攻击周期" % monster_id)
		assert(timing.has("moveIntervalMs") and int(timing.get("moveIntervalMs", -1)) >= 0, "monsterId=%d 缺少移动周期" % monster_id)
		assert(int(service.get("aiCode", -1)) >= 0, "monsterId=%d 缺少可加载 AI 编号" % monster_id)
		assert(int(service.get("viewRange", 0)) > 0, "monsterId=%d 缺少服务视野或显式回退" % monster_id)
		assert(not str(service.get("resolutionStatus", "")).is_empty(), "monsterId=%d 缺少证据状态" % monster_id)

	var poison_spider: Dictionary = MonsterIdentityScript.behavior_profile({"monsterId": 18, "name": "冲突旧名称"})
	assert(int(poison_spider.get("serviceBehavior", {}).get("aiCode", -1)) == 4, "毒蜘蛛没有按 monsterId 加载服务端 AI=4")
	assert(int(poison_spider.get("timing", {}).get("attackIntervalMs", 0)) == 2500, "毒蜘蛛攻击周期未加载")
	assert(int(poison_spider.get("timing", {}).get("moveIntervalMs", 0)) == 900, "毒蜘蛛移动周期未加载")

	var touch_dragon: Dictionary = MonsterIdentityScript.behavior_profile({"monsterId": 124, "name": "冲突旧名称"})
	assert(int(touch_dragon.get("serviceBehavior", {}).get("aiCode", -1)) == 14, "触龙神没有按 monsterId 加载服务端 AI=14")
	assert(is_equal_approx(float(touch_dragon.get("runtimeProjection", {}).get("moveSpeed", -1.0)), 0.0), "显式触龙神机制没有覆盖通用目录")

	for fixed_area_id: int in [180, 195]:
		var fixed_area: Dictionary = MonsterIdentityScript.behavior_profile({"monsterId": fixed_area_id, "name": "冲突旧名称"})
		assert(bool(fixed_area.get("movement", {}).get("stationary", false)), "固定单位没有按monsterId禁用移动")
		assert(int(fixed_area.get("areaAttack", {}).get("rangeTiles", 0)) == 16, "固定单位没有按monsterId加载全屏攻击")

	var unresolved: Dictionary = MonsterIdentityScript.service_runtime_entry({"monsterId": 31})
	assert(unresolved.get("resolutionStatus", "") == "unresolved_project_fallback", "未对齐怪物没有保持显式回退状态")
	assert(unresolved.get("behaviorProfile", {}).get("serviceBehavior", {}).get("confidence", "") == "C", "未对齐怪物回退证据等级错误")

	var first_monster: Dictionary = records[0]
	var legacy_entry := MonsterIdentityScript.service_runtime_entry({"name": first_monster.get("name", "")})
	assert(int(legacy_entry.get("monsterId", -1)) == int(first_monster.get("monsterId", -1)), "旧名称全量兼容入口失效")
	var conflicting := MonsterIdentityScript.service_runtime_entry({
		"monsterId": 18,
		"name": records[1].get("name", ""),
	})
	assert(int(conflicting.get("monsterId", -1)) == 18, "旧名称覆盖了稳定 monsterId 主键")

	var player := PlayerCharacter.new()
	var runtime_enemy := EnemyActor.new()
	runtime_enemy.setup({
		"monsterId": 18,
		"name": "运行时改名毒蜘蛛",
		"hp": 42,
		"attackMin": 6,
		"attackMax": 9,
	}, player)
	assert(runtime_enemy.service_ai_code == 4, "EnemyActor 没有消费全量目录中的 AI 编号")
	assert(runtime_enemy.service_move_interval_ms == 900, "EnemyActor 没有消费全量目录中的移动周期")
	assert(is_equal_approx(runtime_enemy._attack_interval, 2.5), "EnemyActor 没有消费全量目录中的攻击周期")
	runtime_enemy.free()
	player.free()

	var animation_summary: Dictionary = animations.get("summary", {})
	assert(int(animation_summary.get("total", -1)) == records.size(), "动画目录没有覆盖全部稳定 monsterId")
	assert(
		int(animation_summary.get("formal", 0))
		+ int(animation_summary.get("provisional", 0))
		+ int(animation_summary.get("missing", 0))
		== records.size(),
		"动画完成度分级没有覆盖全部怪物"
	)
	assert(int(animation_summary.get("formal", 0)) == records.size(), "214个怪物尚未全部完成正式五动作绑定")
	assert(int(animation_summary.get("missing", -1)) == 0, "动画目录仍有缺失登记")

	print(
		(
			"ALL_MONSTER_LOADING_PASS: total=%d service_exact=%d service_base=%d "
			+ "explicit_fallback=%d animation_formal=%d animation_missing=%d"
		) % [
			records.size(),
			int(summary.get("exactServiceName", 0)),
			int(summary.get("baseNameFallback", 0)),
			int(summary.get("unresolvedProjectFallback", 0)),
			int(animation_summary.get("formal", 0)),
			int(animation_summary.get("missing", 0)),
		]
	)
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "缺少测试数据文件: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "JSON 解析失败: %s" % path)
	return parsed
