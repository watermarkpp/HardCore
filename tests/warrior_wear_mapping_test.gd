extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(FileAccess.file_exists("res://assets/data/warrior_wear_sources.json"), "战士穿戴来源表缺失")
	var manifest: Dictionary = GameData.warrior_wear_art
	assert(int(manifest.get("schemaVersion", 0)) == 3, "动态穿戴映射版本错误")
	assert(manifest.get("sourcePolicy", {}).get("distributionId", "") == "client.classic_raw_complete", "战士穿戴必须使用主客户端资料")
	assert(manifest.get("formulaEvidence", {}).get("confidence", "") == "A", "Shape×2+性别及600帧公式必须保留A源")
	assert(manifest.get("shapeSource", {}).get("commit", "").begins_with("3952c536"), "Shape必须来自锁定的1.76 StdItems提交")
	assert(manifest.get("coverage", {}).get("professions", []).size() == 3, "动态穿戴必须覆盖三个职业")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(mappings.size() == 60, "全职业武器/衣服映射数量错误")
	assert(manifest.get("rejectedMappings", []).size() == 1, "缺失StdItems的装备必须显式保留")
	var lost_weapon_rejected := false
	for value: Variant in manifest.get("rejectedMappings", []):
		if value is Dictionary and value.get("name", "") == "落魄神兵" and "无同名" in str(value.get("reason", "")):
			lost_weapon_rejected = true
	assert(lost_weapon_rejected, "落魄神兵在可靠StdItems缺失时必须继续隔离")
	assert(int(mappings.get("鹤嘴锄", {}).get("weaponAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 38, "鹤嘴锄可靠Shape没有补齐")
	assert(int(mappings.get("罗刹", {}).get("weaponAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 14, "罗刹可靠Shape没有补齐")
	assert(int(mappings.get("怒斩", {}).get("weaponAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 64, "怒斩可靠Shape没有补齐")
	assert(int(mappings.get("中型盔甲(男)", {}).get("dressAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 4, "中型男甲可靠Shape没有补齐")
	assert(int(mappings.get("天魔神甲", {}).get("dressAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 12, "天魔神甲可靠Shape没有补齐")
	assert(int(mappings.get("圣战宝甲", {}).get("dressAppearance", {}).get("genderVariants", {}).get("女", {}).get("feature", -1)) == 13, "圣战宝甲必须按StdMode=11接到女性资源")

	var dagger: Dictionary = mappings.get("匕首", {}).get("weaponAppearance", {}).get("genderVariants", {}).get("女", {})
	assert(int(dagger.get("feature", -1)) == 13, "女性武器Shape到feature转换错误")
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = dagger.get("actions", {}).get(action_name, {})
		assert(action.get("confidence", "") == "A" and action.get("missingFrames", []).is_empty(), "匕首%s客户端帧不完整" % action_name)
		assert(ResourceLoader.exists(str(action.get("path", ""))), "匕首%s图集缺失" % action_name)

	var purgatory := GameData.get_item("炼狱")
	var heavy := GameData.get_item("重盔甲(男)")
	assert(int(purgatory.get("art", {}).get("weaponAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 22, "炼狱穿戴映射未进入运行目录")
	assert(int(heavy.get("art", {}).get("dressAppearance", {}).get("genderVariants", {}).get("男", {}).get("feature", -1)) == 6, "重盔甲穿戴映射未进入运行目录")
	var fury := GameData.get_item("怒斩")
	assert(int(fury.get("serviceShape", -1)) == 32 and int(fury.get("serviceLooks", -1)) == 70, "StdItems Shape/Looks校准未进入运行目录")
	assert(int(fury.get("serviceNeed", -1)) == 1 and int(fury.get("serviceNeedLevel", -1)) == 46, "StdItems Need校准未进入运行目录")
	assert(int(fury.get("attackMin", -1)) == 12 and int(fury.get("attackMax", -1)) == 26 and int(fury.get("price", -1)) == 35000, "StdItems属性/价格校准未进入运行目录")
	var customized := GameData.apply_equipment_customization([purgatory], {"overrides": {"炼狱": {"fields": {"art": {"inventoryIcon": {"path": "res://custom_icon.png"}}}}}})
	assert(customized[0].get("art", {}).has("weaponAppearance"), "只覆盖图标时不得误删动态武器映射")
	assert(customized[0].get("art", {}).get("inventoryIcon", {}).get("path", "") == "res://custom_icon.png", "用户图标覆盖优先级错误")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var visual: Node2D = game.player.get_node("PlayerVisual")
	PlayerState.equipment["武器"] = {"name": "炼狱", "durability": 0, "max_durability": 28}
	PlayerState.equipment["衣服"] = {"name": "重盔甲(男)", "durability": 0, "max_durability": 22}
	PlayerState.recalculate_stats()
	PlayerState.equipment_changed.emit()
	visual._process(0.01)
	var body: Sprite2D = visual.get_node("BodySprite")
	var weapon: Sprite2D = visual.get_node("ClientWeaponLayer")
	assert(body.texture.resource_path.ends_with("dress_006_idle.png"), "重盔甲动态人物图没有生效")
	assert(weapon.visible and weapon.texture.resource_path.ends_with("weapon_022_idle.png"), "炼狱动态武器图没有生效")
	assert(not visual.get_node("WeaponAccent").visible and not visual.get_node("ArmorAccent").visible, "客户端穿戴图生效时不应叠加占位强调层")
	assert(weapon.region_rect.size == Vector2(224, 240), "男女武器独立画布必须容纳长武器攻击像素")
	var body_actor_origin := body.position + Vector2(ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	var weapon_actor_origin := weapon.position + Vector2(80, 120)
	assert(body_actor_origin == weapon_actor_origin, "武器与人物必须共享经典角色原点")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) < 25, "零耐久装备不得恢复属性")

	PlayerState.gender = "女"
	PlayerState.select_profession("法师")
	PlayerState.equipment["武器"] = {"name": "魔杖", "durability": 15, "max_durability": 15}
	PlayerState.equipment["衣服"] = {"name": "魔法长袍(女)", "durability": 12, "max_durability": 12}
	PlayerState.equipment_changed.emit()
	visual.refresh_profession()
	visual._process(0.01)
	assert(visual.visible, "女性法师穿戴动态图层没有启用")
	assert(body.texture.resource_path.ends_with("dress_009_idle.png"), "女性法师衣服没有选择女性feature")
	assert(weapon.texture.resource_path.ends_with("weapon_025_idle.png"), "女性法师武器没有选择女性feature")

	PlayerState.gender = "男"
	PlayerState.select_profession("道士")
	PlayerState.equipment["武器"] = {"name": "银蛇", "durability": 24, "max_durability": 24}
	PlayerState.equipment["衣服"] = {"name": "灵魂战衣(男)", "durability": 20, "max_durability": 20}
	PlayerState.equipment_changed.emit()
	visual.refresh_profession()
	visual._process(0.01)
	assert(visual.visible, "男性道士穿戴动态图层没有启用")
	assert(body.texture.resource_path.ends_with("dress_010_idle.png"), "男性道士衣服动态资源错误")
	assert(weapon.texture.resource_path.ends_with("weapon_018_idle.png"), "男性道士武器动态资源错误")

	print("WARRIOR_WEAR_MAPPING_PASS：StdItems校准、男女三职业五动作图集、拒绝隔离与零耐久边界正确")
	get_tree().quit(0)
