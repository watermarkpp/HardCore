extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://assets/data/equipment_stditems_176.json"
	assert(FileAccess.file_exists(path), "锁定StdItems快照缺失")
	var file := FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = JSON.parse_string(file.get_as_text()) if file != null else {}
	assert(int(snapshot.get("recordCount", 0)) == 369, "StdItems快照记录数错误")
	assert(int(snapshot.get("matchedVanillaRecords", 0)) == 172, "StdItems校准覆盖数错误")
	assert(snapshot.get("source", {}).get("sha256", "") == "7978a8164b950a96b47ae15c0414f2925fa2418661dc74a1ac4d0427b1c0372b", "StdItems来源哈希未锁定")
	assert(snapshot.get("missingVanillaRecords", []) == ["落魄神兵", "辟邪手镯", "黑铁手套"], "缺失记录隔离清单错误")
	var matched := 0
	for row: Variant in snapshot.get("records", []):
		if not row is Dictionary:
			continue
		var item := GameData.get_item(str(row.get("Name", "")))
		if item.is_empty():
			continue
		matched += 1
		assert(int(item.get("serviceIndex", -1)) == int(row.get("Idx", -2)), "StdItems Idx校准错误：%s" % row.Name)
		assert(int(item.get("serviceStdMode", -1)) == int(row.get("Stdmode", -2)), "StdMode校准错误：%s" % row.Name)
		assert(int(item.get("serviceShape", -1)) == int(row.get("Shape", -2)), "Shape校准错误：%s" % row.Name)
		assert(int(item.get("serviceLooks", -1)) == int(row.get("Looks", -2)), "Looks校准错误：%s" % row.Name)
		assert(int(item.get("serviceAniCount", -1)) == int(row.get("Anicount", -2)), "AniCount校准错误：%s" % row.Name)
		assert(int(item.get("serviceNeed", -1)) == int(row.get("Need", -2)), "Need校准错误：%s" % row.Name)
		assert(int(item.get("serviceNeedLevel", -1)) == int(row.get("NeedLevel", -2)), "NeedLevel校准错误：%s" % row.Name)
		assert(int(item.get("servicePrice", -1)) == int(row.get("Price", -2)) and int(item.get("price", -1)) == int(row.get("Price", -2)), "Price校准错误：%s" % row.Name)
		var dc: Array = item.get("serviceDC", [])
		var mc: Array = item.get("serviceMC", [])
		var sc: Array = item.get("serviceSC", [])
		var ac: Array = item.get("serviceAC", [])
		var mac: Array = item.get("serviceMAC", [])
		assert(dc.size() == 2 and int(dc[0]) == int(row.get("Dc", 0)) and int(dc[1]) == int(row.get("Dc2", 0)), "DC校准错误：%s" % row.Name)
		assert(mc.size() == 2 and int(mc[0]) == int(row.get("Mc", 0)) and int(mc[1]) == int(row.get("Mc2", 0)), "MC校准错误：%s" % row.Name)
		assert(sc.size() == 2 and int(sc[0]) == int(row.get("Sc", 0)) and int(sc[1]) == int(row.get("Sc2", 0)), "SC校准错误：%s" % row.Name)
		assert(ac.size() == 2 and int(ac[0]) == int(row.get("Ac", 0)) and int(ac[1]) == int(row.get("Ac2", 0)), "AC校准错误：%s" % row.Name)
		assert(mac.size() == 2 and int(mac[0]) == int(row.get("Mac", 0)) and int(mac[1]) == int(row.get("Mac2", 0)), "MAC校准错误：%s" % row.Name)
	assert(matched == 172, "逐件StdItems校准实际运行覆盖数错误")
	for name: String in snapshot.get("missingVanillaRecords", []):
		assert(not GameData.get_item(name).has("serviceShape"), "无可靠StdItems的装备不得伪造校准：%s" % name)

	print("EQUIPMENT_STDITEMS_CALIBRATION_PASS：172件逐项属性、价格、Need、Looks、Shape、AniCount已校准，3件保持隔离")
	get_tree().quit(0)
