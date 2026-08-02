extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterIdentityScript.reset_caches_for_test()
	var rules: Dictionary = GameData.boss_service_rules
	assert(rules.get("identityKey", "") == "monsterId", "Boss规则没有声明稳定monsterId主键")
	assert(rules.get("runtimeRulesByMonsterId", {}).has("56"), "骷髅精灵ID规则缺失")
	assert(rules.get("runtimeRules", {}).has("骷髅精灵"), "旧名称Boss查询兼容入口缺失")
	assert(MonsterIdentityScript.boss_rule({"name": "祖玛教主"}, rules).get("monsterId", -1) == 160, "新Boss旧名称到monsterId兼容入口缺失")

	var player := PlayerCharacter.new()
	player.global_position = Vector2(800, 0)
	add_child(player)
	player.set_physics_process(false)

	var renamed_yeti := EnemyActor.new()
	renamed_yeti.setup({"monsterId": 28, "name": "本地化雪怪", "hp": 36, "attackMin": 7, "attackMax": 10}, player)
	add_child(renamed_yeti)
	renamed_yeti.set_physics_process(false)
	await get_tree().process_frame
	assert(renamed_yeti.monster_id == 28, "EnemyActor没有保存稳定monsterId")
	assert(is_equal_approx(renamed_yeti.move_speed_gu_per_sec, 52.0 / 32.0) and is_equal_approx(renamed_yeti.attack_range_gu, 44.0 / 32.0), "行为没有优先按monsterId解析")
	assert(renamed_yeti.visual.uses_final_art(), "改名怪物没有通过monsterId找到正式动画")
	assert(renamed_yeti.visual.active_resources.get("animation_source", "") == "classic_client_wil", "monsterId动画没有使用客户端原帧")

	var conflicting_name := EnemyActor.new()
	conflicting_name.setup({"monsterId": 28, "name": "食人花", "hp": 36, "attackMin": 7, "attackMax": 10}, player)
	assert(is_equal_approx(conflicting_name.move_speed_gu_per_sec, 52.0 / 32.0), "名称覆盖了monsterId主键行为")
	conflicting_name.free()

	var legacy_flower := EnemyActor.new()
	legacy_flower.setup({"name": "食人花", "hp": 20, "attackMin": 1, "attackMax": 2}, player)
	assert(legacy_flower.monster_id == -1 and legacy_flower.move_speed_gu_per_sec == 0.0 and is_equal_approx(legacy_flower.attack_range_gu, 78.0 / 32.0), "旧名称行为兼容入口失效")
	legacy_flower.free()

	var renamed_boss := EnemyActor.new()
	var boss_data := GameData.get_monster_by_id(56).duplicate(true)
	boss_data["name"] = "本地化骷髅首领"
	renamed_boss.setup(boss_data, player, true)
	add_child(renamed_boss)
	renamed_boss.set_physics_process(false)
	await get_tree().process_frame
	assert(int(renamed_boss.boss_rule.get("monsterId", -1)) == 56, "Boss规则没有优先按monsterId解析")
	assert(is_equal_approx(renamed_boss._attack_interval, 2.0), "改名Boss没有读取ID时序规则")
	assert(renamed_boss.visual.uses_final_art(), "改名Boss没有读取ID动画")

	var legacy_rule := MonsterIdentityScript.boss_rule({"name": "尸王"}, rules)
	assert(int(legacy_rule.get("monsterId", -1)) == 89, "旧名称Boss规则兼容入口失效")

	renamed_yeti.queue_free()
	renamed_boss.queue_free()
	player.queue_free()
	print("MONSTER_ID_CONTRACT_PASS：行为、动画与Boss规则以monsterId优先，名称兼容入口保留")
	get_tree().quit(0)
