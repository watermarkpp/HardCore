extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const MonsterUnitAdapterScript := preload("res://scripts/monster_unit_adapter.gd")

const EXPECTED := {
	36: {"name": "半兽战士", "attack_ms": 2000, "move_ms": 1500, "move_speed": 40.0, "ai": 0},
	38: {"name": "半兽勇士", "attack_ms": 1500, "move_ms": 1500, "move_speed": 40.0, "ai": 0},
	60: {"name": "粪虫", "attack_ms": 2500, "move_ms": 1800, "move_speed": 32.0, "ai": 7},
	62: {"name": "暗黑战士", "attack_ms": 2500, "move_ms": 900, "move_speed": 52.0, "ai": 8},
	64: {"name": "沃玛战士", "attack_ms": 2000, "move_ms": 1000, "move_speed": 48.0, "ai": 0},
	66: {"name": "沃玛勇士", "attack_ms": 2000, "move_ms": 1000, "move_speed": 48.0, "ai": 0},
	68: {"name": "沃玛战将", "attack_ms": 2000, "move_ms": 1000, "move_speed": 48.0, "ai": 0},
	70: {"name": "火焰沃玛", "attack_ms": 1700, "move_ms": 800, "move_speed": 46.0, "ai": 10},
	73: {"name": "沃玛卫士", "attack_ms": 1500, "move_ms": 800, "move_speed": 46.0, "ai": 0},
	92: {"name": "红蛇", "attack_ms": 2500, "move_ms": 1200, "move_speed": 44.0, "ai": 0},
	94: {"name": "虎蛇", "attack_ms": 2500, "move_ms": 1200, "move_speed": 44.0, "ai": 0},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterIdentityScript.reset_caches_for_test()
	var manifest: Dictionary = GameData.bich_common_art
	var by_id: Dictionary = manifest.get("runtimeMappingsByMonsterId", {})
	assert(manifest.get("identityKey", "") == "monsterId", "比奇路线怪动画清单未声明monsterId主键")

	var player := PlayerCharacter.new()
	player.global_position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)

	for monster_id: int in EXPECTED:
		var expected: Dictionary = EXPECTED[monster_id]
		var mapping_name := str(by_id.get(str(monster_id), ""))
		var mapping: Dictionary = manifest.get("runtimeMappings", {}).get(mapping_name, {})
		assert(not mapping.is_empty(), "monsterId=%d 客户端动画映射缺失" % monster_id)
		assert(mapping.get("name", "") == expected.name, "monsterId=%d 绑定到错误怪物" % monster_id)
		assert(mapping.get("mappingConfidence", "") == "B", "%s 名称到外观证据未保持B级" % expected.name)
		for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
			var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
			assert(not action.is_empty() and action.get("missingFrames", []).is_empty(), "%s %s 动作不完整" % [expected.name, action_name])

		var profile := MonsterIdentityScript.behavior_profile({"monsterId": monster_id, "name": "冲突旧名称"})
		assert(int(profile.get("timing", {}).get("attackIntervalMs", 0)) == int(expected.attack_ms), "%s 攻击间隔未按monsterId解析" % expected.name)
		assert(int(profile.get("timing", {}).get("moveIntervalMs", 0)) == int(expected.move_ms), "%s 服务端移动间隔未保留" % expected.name)
		var projection := MonsterUnitAdapterScript.runtime_projection_gu(profile, 0.0, 0.0, 0.0)
		var expected_move_speed_gu := float(expected.move_speed) if monster_id == 70 else float(expected.move_speed) / 32.0
		assert(is_equal_approx(float(projection.get("move_speed_gu_per_sec", 0.0)), expected_move_speed_gu), "%s 移动投影未按monsterId解析" % expected.name)
		assert(int(profile.get("serviceBehavior", {}).get("aiCode", -1)) == int(expected.ai), "%s AI码未按monsterId解析" % expected.name)
		var appearance_profile_id := str(MonsterIdentityScript.appearance_profile(monster_id).get("appearance_profile_id", ""))
		assert(not appearance_profile_id.is_empty(), "%s canonical外观档案缺失" % expected.name)
		assert(MonsterIdentityScript.animation_lookup_name({"monsterId": monster_id, "name": "冲突旧名称"}) == appearance_profile_id, "%s 外观档案未按monsterId解析" % expected.name)

	var renamed_data := GameData.get_monster_by_id(36).duplicate(true)
	renamed_data["name"] = "本地化半兽战士"
	var renamed := EnemyActor.new()
	renamed.setup(renamed_data, player, false)
	add_child(renamed)
	renamed.set_physics_process(false)
	await get_tree().process_frame
	assert(renamed.monster_id == 36 and renamed.visual.uses_final_art(), "改名怪物未通过monsterId读取正式动画")
	assert(is_equal_approx(renamed._attack_interval, 2.0) and renamed.service_move_interval_ms == 1500, "EnemyActor未应用monsterId时序")
	assert(is_equal_approx(renamed.move_speed_gu_per_sec, 40.0 / 32.0) and renamed.service_ai_code == 0, "EnemyActor未应用monsterId移动/AI档案")

	var name_only := EnemyActor.new()
	name_only.setup({"name": "沃玛护卫", "hp": 100, "attackMin": 1, "attackMax": 2}, player, false)
	assert(name_only.monster_id == -1 and bool(name_only.get_meta("canonical_rejected", false)), "旧名称入口必须保持ID-only fail-closed")

	name_only.free()
	renamed.queue_free()
	player.queue_free()
	print("BICH_ROUTE_MONSTER_PASS：11类路线怪以monsterId绑定五动作、攻击移动时序与AI证据，旧名称入口保持fail-closed")
	get_tree().quit(0)
