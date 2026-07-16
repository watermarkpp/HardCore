extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(FileAccess.file_exists("res://assets/data/equipment_client_art_sources.json"), "装备客户端美术来源表缺失")
	assert(int(GameData.equipment_client_art.get("schemaVersion", 0)) == 1, "装备美术映射版本错误")
	var mappings: Dictionary = GameData.equipment_client_art.get("runtimeMappings", {})
	assert(mappings.size() == 175, "175件装备客户端映射数量错误")
	assert(GameData.equipment_client_art.get("unresolvedMappings", []).is_empty(), "客户端装备映射仍有未解析条目")
	var missing_stditems: Array = GameData.equipment_client_art.get("missing", [])
	assert(missing_stditems == ["落魄神兵", "辟邪手镯", "黑铁手套"], "Looks缺名隔离清单错误")
	for item_name: String in mappings.keys():
		var art: Dictionary = mappings[item_name]
		var expected_confidence := "B" if item_name in missing_stditems else "A"
		assert(art.get("mappingConfidence", "") == expected_confidence, "逐件Looks来源可信度错误：%s" % item_name)
		for field: String in ["inventoryIcon", "equippedIcon", "groundIcon"]:
			var source: Dictionary = art.get(field, {})
			assert(source.get("confidence", "") == "A", "客户端库索引必须保留A源标记")
			assert(ResourceLoader.exists(str(source.get("path", ""))), "%s %s资源缺失" % [item_name, field])

	var wood := GameData.get_item_record("木剑")
	assert(wood.get("art", {}).get("looks", -1) == 30, "默认客户端美术没有进入运行物品目录")
	assert(GameData.get_item_record("怒斩").get("art", {}).get("looks", -1) == 70, "StdItems Looks没有覆盖旧网页候选")
	var base: Array = [{"name": "测试剑", "category": "武器"}]
	var mapped := GameData.apply_equipment_art_mappings(base, {"runtimeMappings": {"测试剑": {"looks": 30, "inventoryIcon": {"path": "old"}}}})
	var customized := GameData.apply_equipment_customization(mapped, {"overrides": {"测试剑": {"fields": {"art": {"inventoryIcon": {"path": "res://custom.png"}}}}}})
	assert(customized[0].get("art", {}).get("inventoryIcon", {}).get("path", "") == "res://custom.png", "用户配置必须能覆盖默认美术映射")

	print("EQUIPMENT_CLIENT_ART_PASS：客户端三类图像、来源可信度、运行目录与用户覆盖顺序正确")
	get_tree().quit(0)
