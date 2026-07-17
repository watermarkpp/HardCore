extends Node

const BATCH_PATH := "res://assets/data/equipment_reference_batches.json"


func _ready() -> void:
	_run.call_deferred()


func _read_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "缺少数据文件：%s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "JSON格式错误：%s" % path)
	return parsed


func _run() -> void:
	var manifest := _read_json(BATCH_PATH)
	assert(int(manifest.get("schemaVersion", 0)) == 2, "装备参考批次版本错误")
	assert(int(manifest.get("referenceRecordCount", 0)) == 808, "808条参考装备总数错误")
	assert(int(manifest.get("runtimeEquipmentCount", 0)) == 175, "现有运行装备必须保持175件")
	assert(int(manifest.get("enabledReferenceCalibrationCount", 0)) == 2, "主源首批只能校准两条既有男战士装备")
	assert(int(manifest.get("newRuntimeEquipmentCount", -1)) == 0, "首批不得新增808参考装备")
	assert(int(manifest.get("remainingQuarantinedReferenceCount", 0)) == 806, "其余参考装备没有保持隔离")
	assert(GameData.items.size() == 175, "批次清单不得改变运行装备总量")
	assert(int(GameData.item_catalog_counts().get("equipment", 0)) == 175, "统一目录不得混入参考装备")

	var batches: Array = manifest.get("batches", [])
	assert(batches.size() == 1, "当前只能存在一个已验收参考批次")
	var batch: Dictionary = batches[0]
	assert(batch.get("batchId", "") == "equipment-reference-primary-gap-001", "参考批次稳定ID错误")
	assert(batch.get("status", "") == "enabled_existing_record_calibration", "参考批次状态错误")
	assert(batch.get("scope", "") == "当前男性战士", "批次越出男性战士范围")
	assert(batch.get("serverSource", {}).get("distribution", "") == "server.crystal.cjlaaa", "Shape缺口没有使用主服务端源")
	assert(batch.get("serverSource", {}).get("tier", "") == "primary", "服务端主源层级错误")
	assert(int(batch.get("serverSource", {}).get("databaseVersion", 0)) == 105, "服务端数据库版本错误")
	assert(batch.get("clientSource", {}).get("distribution", "") == "client.classic_raw_complete", "动态穿戴没有使用经典主客户端")

	var service_records: Array = GameData.service_item_catalog.get("serviceEquipmentReference", [])
	assert(service_records.size() == 808, "运行加载后的参考层数量错误")
	for reference: Variant in service_records:
		assert(reference is Dictionary and reference.get("kind", "") == "equipment_reference", "参考层记录被改成运行装备")
		assert(not reference.has("enabled"), "参考记录不得通过enabled字段绕过批次清单")

	var mappings: Dictionary = GameData.warrior_wear_art.get("runtimeMappings", {})
	assert(mappings.size() == 26, "男战士映射必须保持24条基线加2条主源校准")
	for record_value: Variant in batch.get("records", []):
		assert(record_value is Dictionary, "批次记录格式错误")
		var record: Dictionary = record_value
		assert(bool(record.get("resourceExact", false)), "批次存在未精确验证的客户端资源")
		var service_record: Dictionary = {}
		for candidate: Variant in service_records:
			if candidate is Dictionary and int(candidate.get("serviceIndex", -1)) == int(record.get("serviceReferenceIndex", -2)):
				service_record = candidate
				break
		assert(not service_record.is_empty(), "主服务端参考记录缺失：%s" % record.get("name", ""))
		assert(service_record.get("name", "") == record.get("name", ""), "服务端索引与名称不一致")
		assert(int(service_record.get("serviceType", -1)) == int(record.get("serviceType", -2)), "服务端装备类型不一致")
		assert(int(service_record.get("shape", -1)) == int(record.get("serviceShape", -2)), "服务端Shape不一致")
		assert(int(service_record.get("image", -1)) == int(record.get("serviceImage", -2)), "服务端Looks/Image不一致")
		assert(bool(service_record.get("artExact", false)), "服务端同索引图像未精确解析")
		assert(service_record.get("source", {}).get("distribution", "") == "server.crystal.cjlaaa", "逐件记录不是主服务端来源")

		var item := GameData.get_item(str(record.get("name", "")))
		assert(int(item.get("itemId", -1)) == int(record.get("stableItemId", -2)), "稳定item_id不一致")
		var appearance_kind := str(record.get("appearanceKind", ""))
		var appearance: Dictionary = mappings.get(record.get("name", ""), {}).get(appearance_kind, {})
		assert(int(appearance.get("shape", -1)) == int(record.get("serviceShape", -2)), "运行Shape没有使用主源记录")
		assert(int(appearance.get("feature", -1)) == int(record.get("runtimeFeature", -2)), "运行feature转换错误")
		assert(appearance.get("mappingSource", "").contains("server.crystal.cjlaaa"), "运行映射没有保留主源追溯")
		assert(appearance.get("clientSource", "") == record.get("clientLibrary", ""), "客户端动态图集来源错误")
		for action_name: String in record.get("actions", []):
			var action: Dictionary = appearance.get("actions", {}).get(action_name, {})
			assert(action.get("missingFrames", []).is_empty(), "%s/%s存在缺帧" % [record.get("name", ""), action_name])
			assert(ResourceLoader.exists(str(action.get("path", ""))), "%s/%s动态图集缺失" % [record.get("name", ""), action_name])

	var rejected_names := {}
	for rejected: Variant in GameData.warrior_wear_art.get("rejectedMappings", []):
		if rejected is Dictionary:
			rejected_names[str(rejected.get("name", ""))] = str(rejected.get("reason", ""))
	assert(rejected_names.has("鹤嘴锄") and "超出" in rejected_names["鹤嘴锄"], "越界鹤嘴锄不得强行启用")
	assert(rejected_names.has("罗刹") and rejected_names.has("落魄神兵") and rejected_names.has("天魔神甲"), "缺少Shape的男战士装备必须保持拒绝")
	assert(rejected_names.get("圣战宝甲", "").contains("女性角色"), "女性装备必须保持在当前范围外")
	assert(not mappings.has("圣战宝甲"), "女性装备不得进入男战士运行映射")

	print("EQUIPMENT_REFERENCE_BATCH_PASS：主源两条既有男战士装备完成校准，其余806条参考装备保持隔离")
	get_tree().quit(0)
