extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(FileAccess.file_exists("res://assets/data/warrior_wear_sources.json"), "战士穿戴来源表缺失")
	var manifest: Dictionary = GameData.warrior_wear_art
	assert(int(manifest.get("schemaVersion", 0)) == 2, "战士穿戴映射版本错误")
	assert(manifest.get("sourcePolicy", {}).get("distributionId", "") == "client.classic_raw_complete", "战士穿戴必须使用主客户端资料")
	assert(manifest.get("formulaEvidence", {}).get("confidence", "") == "A", "Shape×2+性别及600帧公式必须保留A源")
	assert(manifest.get("primaryGapShapeSource", {}).get("distributionId", "") == "server.crystal.cjlaaa", "缺口Shape必须来自服务端数据主源")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(mappings.size() == 26, "男性战士映射应在既有24条上只补两条主源兼容记录")
	assert(manifest.get("rejectedMappings", []).size() == 5, "其余缺源、越界和女性条目必须显式保留")
	var accepted_baseline_features := {
		"木剑": 0, "匕首": 2, "乌木剑": 0, "青铜剑": 4, "短剑": 6,
		"铁剑": 4, "青铜斧": 8, "八荒": 10, "凌风": 16, "破魂": 24,
		"斩马刀": 18, "修罗": 28, "凝霜": 30, "炼狱": 32, "井中月": 38,
		"裁决之杖": 48, "屠龙": 58, "命运之刃": 48, "赤血魔剑": 50,
		"祈祷之刃": 26, "布衣(男)": 2, "轻型盔甲(男)": 4,
		"重盔甲(男)": 6, "战神盔甲(男)": 6,
	}
	for item_name: String in accepted_baseline_features:
		var art: Dictionary = mappings.get(item_name, {})
		var appearance: Dictionary = art.get("weaponAppearance", art.get("dressAppearance", {}))
		assert(int(appearance.get("feature", -1)) == int(accepted_baseline_features[item_name]), "主工作树已验收映射发生变化：%s" % item_name)
	var pickaxe_rejected := false
	var female_armor_rejected := false
	for value: Variant in manifest.get("rejectedMappings", []):
		if value is Dictionary and value.get("name", "") == "鹤嘴锄" and "超出" in str(value.get("reason", "")):
			pickaxe_rejected = true
		if value is Dictionary and value.get("name", "") == "圣战宝甲" and "女性角色" in str(value.get("reason", "")):
			female_armor_rejected = true
	assert(pickaxe_rejected, "越出经典Weapon.wil容量的鹤嘴锄候选不得强行接入")
	assert(female_armor_rejected and not mappings.has("圣战宝甲"), "女性盔甲不得进入当前运行映射")
	assert(int(mappings.get("怒斩", {}).get("weaponAppearance", {}).get("feature", -1)) == 54, "怒斩主源Shape没有补入男战士映射")
	assert(int(mappings.get("中型盔甲(男)", {}).get("dressAppearance", {}).get("feature", -1)) == 4, "中型男甲主源Shape没有补入男战士映射")

	var dagger: Dictionary = mappings.get("匕首", {}).get("weaponAppearance", {})
	assert(int(dagger.get("shape", -1)) == 1 and int(dagger.get("feature", -1)) == 2, "武器Shape到feature转换错误")
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = dagger.get("actions", {}).get(action_name, {})
		assert(action.get("confidence", "") == "A" and action.get("missingFrames", []).is_empty(), "匕首%s客户端帧不完整" % action_name)
		assert(ResourceLoader.exists(str(action.get("path", ""))), "匕首%s图集缺失" % action_name)

	var purgatory := GameData.get_item("炼狱")
	var heavy := GameData.get_item("重盔甲(男)")
	assert(int(purgatory.get("art", {}).get("weaponAppearance", {}).get("feature", -1)) == 32, "炼狱穿戴映射未进入运行目录")
	assert(int(heavy.get("art", {}).get("dressAppearance", {}).get("feature", -1)) == 6, "重盔甲穿戴映射未进入运行目录")
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
	assert(weapon.visible and weapon.texture.resource_path.ends_with("weapon_032_idle.png"), "炼狱动态武器图没有生效")
	assert(not visual.get_node("WeaponAccent").visible and not visual.get_node("ArmorAccent").visible, "客户端穿戴图生效时不应叠加占位强调层")
	assert(weapon.region_rect.size == Vector2(192, 224), "武器独立画布必须容纳长武器攻击像素")
	var body_actor_origin := body.position + Vector2(ArtSpec.WARRIOR_SOURCE_FOOT_ANCHOR)
	var weapon_actor_origin := weapon.position + Vector2(68, 112)
	assert(body_actor_origin == weapon_actor_origin, "武器与人物必须共享经典角色原点")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) < 25, "零耐久装备不得恢复属性")

	print("WARRIOR_WEAR_MAPPING_PASS：保留24条既有男战士基线、主源补两条、越界/缺源/女性隔离正确")
	get_tree().quit(0)
