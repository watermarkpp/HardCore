extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(FileAccess.file_exists("res://assets/data/warrior_wear_sources.json"), "战士穿戴来源表缺失")
	var manifest: Dictionary = GameData.warrior_wear_art
	assert(int(manifest.get("schemaVersion", 0)) == 2, "战士穿戴映射版本错误")
	assert(manifest.get("sourcePolicy", {}).get("distributionId", "") == "client.classic_raw_complete", "战士穿戴必须使用主客户端资料")
	assert(manifest.get("formulaEvidence", {}).get("confidence", "") == "A", "Shape×2+性别及600帧公式必须保留A源")
	var mappings: Dictionary = manifest.get("runtimeMappings", {})
	assert(mappings.size() == 24, "男性战士武器/衣服首批映射数量错误")
	assert(manifest.get("rejectedMappings", []).size() == 7, "不兼容或缺失Shape必须显式保留")
	var pickaxe_rejected := false
	for value: Variant in manifest.get("rejectedMappings", []):
		if value is Dictionary and value.get("name", "") == "鹤嘴锄" and "超出" in str(value.get("reason", "")):
			pickaxe_rejected = true
	assert(pickaxe_rejected, "越出经典Weapon.wil容量的鹤嘴锄候选不得强行接入")

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

	print("WARRIOR_WEAR_MAPPING_PASS：Shape证据、越界拒绝、五动作图集、零耐久外观与属性边界正确")
	get_tree().quit(0)
