extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://assets/data/equipment_reference_batches.json"
	assert(FileAccess.file_exists(path), "808条参考装备缺少分批启用清单")
	var file := FileAccess.open(path, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text()) if file != null else {}
	assert(int(manifest.get("referenceRecordCount", 0)) == 808, "参考装备总数错误")
	assert(int(manifest.get("enabledRecordCount", 0)) == 3, "首批只能启用三条四证齐全记录")
	assert(int(manifest.get("remainingQuarantinedCount", 0)) == 805, "未启用参考装备没有保持隔离")
	var batches: Array = manifest.get("batches", [])
	assert(batches.size() == 1 and batches[0].get("batchId", "") == "equipment-reference-001-stditems-wear", "首批稳定ID错误")
	var records: Array = batches[0].get("records", [])
	assert(records.size() == 3, "首批记录数错误")
	for record: Variant in records:
		assert(record is Dictionary and bool(record.get("resourceExact", false)), "首批存在非精确客户端资源")
		var item := GameData.get_item(str(record.get("name", "")))
		assert(not item.is_empty(), "首批装备没有进入运行目录")
		assert(int(item.get("serviceIndex", -1)) == int(record.get("stdItemsIndex", -2)), "首批StdItems逐件索引不一致")
		assert(int(item.get("serviceLooks", -1)) == int(record.get("looks", -2)), "首批Looks没有逐件校准")
		assert(int(item.get("serviceShape", -1)) == int(record.get("shape", -2)), "首批Shape没有逐件校准")
		var appearance: Dictionary = item.get("art", {}).get("weaponAppearance", item.get("art", {}).get("dressAppearance", {}))
		for gender: String in record.get("wearFeatures", {}):
			var variant: Dictionary = appearance.get("genderVariants", {}).get(gender, {})
			assert(int(variant.get("feature", -1)) == int(record.wearFeatures[gender]), "首批穿戴feature错误：%s/%s" % [record.name, gender])
			for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
				var action: Dictionary = variant.get("actions", {}).get(action_name, {})
				assert(action.get("missingFrames", []).is_empty(), "首批穿戴帧缺失：%s/%s/%s" % [record.name, gender, action_name])
				assert(ResourceLoader.exists(str(action.get("path", ""))), "首批穿戴图集缺失：%s/%s/%s" % [record.name, gender, action_name])

	print("EQUIPMENT_REFERENCE_BATCH_PASS：808条参考装备首批3条四证齐全，其余805条保持隔离")
	get_tree().quit(0)
