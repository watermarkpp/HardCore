extends Node

const RUNTIME_SPAWN_PATH := "res://assets/data/runtime/region_spawn_runtime_catalog.json"
const ANIMATION_PATH := "res://assets/data/runtime/monster_animation_catalog.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var spawn_catalog := _load_json(RUNTIME_SPAWN_PATH)
	var summary: Dictionary = spawn_catalog.get("summary", {})
	var respawn_statuses: Dictionary = summary.get("respawnStatusCounts", {})
	var primary_source: Dictionary = spawn_catalog.get("sources", {}).get("primaryServerRespawns", {})
	assert(spawn_catalog.get("identityKey", "") == "monsterId", "区域刷新目录未使用稳定 monsterId")
	assert(int(summary.get("entryCount", 0)) == 743, "区域刷新条目数量发生非预期变化")
	assert(int(summary.get("resolvedMonsterIdCount", 0)) == 743, "区域刷新仍存在名称专属条目")
	assert(int(summary.get("unresolvedMonsterIdCount", -1)) == 0, "区域刷新存在未解析 monsterId")

	var tomb_content := RegionContent.get_map_content(217)
	assert(int(respawn_statuses.get("primary_server_mirdb", 0)) == 193, "Primary Server.MirDB respawn rows were not integrated")
	assert(int(respawn_statuses.get("single_player_normal_fallback", 0)) == 503, "Fallback respawn classification changed without review")
	assert(int(primary_source.get("mapCount", 0)) == 389, "Primary Server.MirDB map scan is incomplete")
	assert(int(primary_source.get("respawnRowCount", 0)) == 5600, "Primary Server.MirDB respawn scan is incomplete")
	for spawn: Dictionary in tomb_content.get("spawns", []):
		assert(int(spawn.get("monsterId", -1)) >= 0, "古墓刷新点缺少 monsterId")
		assert(not str(spawn.get("spawnGroupId", "")).is_empty(), "古墓刷新点缺少稳定 spawnGroupId")
		assert(float(spawn.get("respawn_seconds", 0.0)) >= 180.0, "古墓仍在使用秒杀式原型复活周期")
		assert(not spawn.get("respawnEvidence", {}).is_empty(), "古墓刷新周期缺少证据状态")

	var wooma_content := RegionContent.get_map_content(315)
	var wooma_bosses: Array = wooma_content.get("bosses", [])
	assert(wooma_bosses.size() == 2, "沃玛教主地图 Boss 刷新组数量异常")
	assert(int(wooma_bosses[1].get("monsterId", -1)) == 76, "沃玛教主刷新仍依赖名称")
	assert(is_equal_approx(float(wooma_bosses[1].get("respawn_seconds", 0.0)), 7200.0), "沃玛教主真实复活周期丢失")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game._rng.seed = 20260717
	game.player.global_position = Vector2(5000, 5000)

	var zuma_data := GameData.get_monster_by_id(160)
	var zuma: EnemyActor = game._spawn_enemy(
		zuma_data,
		Vector2(900, 0),
		true,
		10800.0,
		{"spawn_group_id": "test:zuma", "spawn_slot_id": "test:zuma:0"}
	)
	zuma.set_physics_process(false)
	game._on_boss_summon_requested(zuma, [153, 156, 150, 159], 8, 3)
	await get_tree().process_frame
	var summoned: Array[EnemyActor] = []
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and str(value.get_meta("summoner_spawn_slot", "")) == "test:zuma:0":
			summoned.append(value)
	assert(summoned.size() == 3, "祖玛教主召唤没有执行 maxActive 上限")
	for enemy: EnemyActor in summoned:
		assert(enemy.monster_id in [153, 156, 150, 159], "Boss 召唤没有按稳定 monsterId 解析")
		assert(not bool(enemy.get_meta("respawn_enabled", true)), "Boss 临时召唤物错误进入区域复活队列")

	var wooma_data := GameData.get_monster_by_id(76)
	var wooma: EnemyActor = game._spawn_enemy(
		wooma_data,
		Vector2(-900, 0),
		true,
		7200.0,
		{"spawn_group_id": "test:wooma", "spawn_slot_id": "test:wooma:0"}
	)
	wooma.set_physics_process(false)
	var original_position := wooma.global_position
	assert(wooma.request_surrounded_relocation(5), "沃玛教主没有发出受困瞬移请求")
	assert(wooma.global_position != original_position, "地图落点服务没有处理 Boss 瞬移信号")
	assert(
		not WorldSpatialRules.point_inside_safe_zones_ground_gu(
			game._canonical_world_to_fractional_tile(wooma.global_position),
			game._active_safe_zones,
		),
		"Boss 瞬移进入安全区"
	)
	assert(
		not WorldSpatialRules.environment_blocks_actor(game.background, wooma.global_position, wooma.collision_radius_px),
		"Boss 瞬移进入地图阻挡"
	)

	var respawn_data := GameData.get_monster_by_id(18)
	var respawn_context := {
		"spawn_group_id": "test:respawn",
		"spawn_slot_id": "test:respawn:0",
		"respawn_evidence": {"status": "test"},
		"respawn_base_seconds": 0.05,
		"respawn_random_seconds": 0.0,
	}
	await game._respawn_later(
		respawn_data,
		Vector2(1200, 0),
		false,
		0.05,
		game._zone_generation,
		respawn_context
	)
	assert(game._spawn_slot_is_alive("test:respawn:0", game._zone_generation), "独立刷新槽位没有按周期复活")
	var respawn_actor := _enemy_by_slot("test:respawn:0")
	assert(respawn_actor != null and respawn_actor.monster_id == 18, "复活槽位没有保留 monsterId")

	var animation := _load_json(ANIMATION_PATH)
	var animation_summary: Dictionary = animation.get("summary", {})
	assert(int(animation_summary.get("total", -1)) == 214, "怪物动画目录没有覆盖全部214个稳定 monsterId")
	assert(int(animation_summary.get("formal", -1)) == 214, "完整客户端美术接入后仍有怪物缺少正式动画")
	assert(int(animation_summary.get("missing", -1)) == 0, "完整客户端美术接入后动画目录仍登记缺失")

	print("MONSTER_WORLD_INTEGRATION_PASS: 743个刷新条目已monsterId化，分钟级复活、Boss召唤与瞬移落点接通，214个怪物均为正式动画")
	get_tree().quit(0)


func _enemy_by_slot(slot_id: String) -> EnemyActor:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and str(value.get_meta("spawn_slot_id", "")) == slot_id:
			return value
	return null


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "JSON 加载失败: %s" % path)
	return parsed
