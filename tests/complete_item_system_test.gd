extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest: Dictionary = GameData.service_item_catalog
	assert(int(manifest.get("database", {}).get("version", 0)) == 105, "主服务端物品数据库版本错误")
	assert(int(manifest.get("counts", {}).get("allServiceRecords", 0)) == 1349, "主服务端1349条物品没有完整解析")
	assert(int(manifest.get("counts", {}).get("runtimeNonEquipment", 0)) == 538, "非装备运行物品目录数量错误")
	assert(GameData.item_catalog.size() >= 700, "统一运行物品目录未完成扩充")

	var missing_art := PackedStringArray()
	for record_value: Variant in GameData.item_catalog:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var art: Dictionary = record.get("art", {})
		for field: String in ["inventoryIcon", "groundIcon"]:
			var art_record: Variant = art.get(field, {})
			var path := str(art_record.get("path", "")) if art_record is Dictionary else str(art_record)
			if path.is_empty() or not FileAccess.file_exists(path) or not ResourceLoader.exists(path):
				missing_art.append("%s:%s" % [str(record.get("name", "")), field])
	assert(missing_art.is_empty(), "运行物品仍有图标或地面外观缺失：%s" % ",".join(missing_art))
	var shenshui_source_indices := {
		"体力强效神水": 424,
		"魔力强效神水": 422,
		"疾风神水": 420,
		"攻击神水": 425,
		"魔力神水": 423,
		"精神神水": 421,
	}
	for item_name: String in shenshui_source_indices:
		var shenshui := GameData.get_item_record(item_name)
		assert(not shenshui.is_empty(), "神水物品缺失：%s" % item_name)
		var shenshui_art: Dictionary = shenshui.get("art", {})
		for field: String in ["inventoryIcon", "groundIcon"]:
			var icon: Dictionary = shenshui_art.get(field, {})
			var icon_path := str(icon.get("path", ""))
			assert("/fallback/" not in icon_path, "%s仍使用占位图：%s" % [item_name, field])
			assert(int(icon.get("sourceIndex", -1)) == shenshui_source_indices[item_name])
			var texture := load(icon_path) as Texture2D
			assert(texture != null, "%s贴图不能加载：%s" % [item_name, field])
			assert(texture.get_width() > 1 and texture.get_height() > 1, "%s贴图无有效尺寸：%s" % [item_name, field])

	# 疾风药水 has a distinct stable project item identity from 疾风神水, but
	# both deliberately reuse the primary client source index 420. Verify the
	# stable-ID, canonical-name, and legacy alias lookups all converge on the
	# same non-placeholder art record instead of relying on display-name guesses.
	for item_ref: Variant in [910013, "疾风药水", "极速神水"]:
		var speed_potion := GameData.get_item_record(item_ref)
		assert(int(speed_potion.get("itemId", -1)) == 910013, "疾风药水 identity lookup drifted: %s" % item_ref)
		var speed_art: Dictionary = speed_potion.get("art", {})
		for field: String in ["inventoryIcon", "stateIcon", "groundIcon"]:
			var icon: Dictionary = speed_art.get(field, {})
			var icon_path := str(icon.get("path", ""))
			assert("/fallback/" not in icon_path, "疾风药水仍使用占位图：%s" % field)
			assert(int(icon.get("sourceIndex", -1)) == 420, "疾风药水 sourceIndex 漂移：%s" % field)
			assert(str(icon.get("distribution", "")) == "client.classic_raw_complete")
	for service_index: int in [684, 685, 686]:
		var service_variant := GameData.get_item_record({"service_index": service_index})
		assert(not service_variant.is_empty(), "疾风药水 service identity missing: %d" % service_index)
		assert(int(service_variant.get("serviceIndex", -1)) == service_index)
		assert(int(service_variant.get("image", -1)) == 420, "疾风药水 service art drifted: %d" % service_index)
		assert(str(service_variant.get("art", {}).get("inventoryIcon", {}).get("path", "")).ends_with("Items_00420.png"))

	var small_hp := GameData.get_item_record("金创药(小量)")
	assert(int(small_hp.get("restoreHealth", 0)) == 30 and int(small_hp.get("restoreMana", 0)) == 0)
	assert(small_hp.get("art", {}).get("groundIcon", {}).get("distribution", "") == "client.classic_raw_complete")
	var extra_hp := GameData.get_item_record("金创药(特大)")
	assert(extra_hp.get("art", {}).get("groundIcon", {}).get("distribution", "") == "client.mir2opensource_2013_complete")
	var resurrection := GameData.get_item_record("复活卷轴")
	assert(resurrection.get("art", {}).get("groundIcon", {}).get("distribution", "") == "project.category_fallback")
	assert(GameData.get_item_record("回城卷").get("useEffect", "") == "town_teleport")
	assert(GameData.get_item_record("随机传送卷").get("useEffect", "") == "random_teleport")
	assert(GameData.get_item_record("地牢逃脱卷").get("useEffect", "") == "dungeon_escape")
	assert(GameData.get_item_kind("沃玛号角") == "quest_item")

	PlayerState.add_item("金创药(小量)", 2)
	assert(PlayerState.use_inventory_index(0).begins_with("使用"), "血瓶未接入使用链")
	assert(PlayerState.has_item("金创药(小量)", 1), "血瓶单次使用数量错误")
	PlayerState.reset_progress()
	PlayerState.add_item("回城卷")
	assert(PlayerState.use_inventory_index(0).begins_with("使用"), "回城卷未接入使用链")

	print("COMPLETE_ITEM_SYSTEM_PASS: 1349 server records, 538 runtime items, exact/fallback art and potion/scroll rules are connected")
	get_tree().quit(0)
