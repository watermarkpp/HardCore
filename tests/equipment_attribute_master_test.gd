extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const MASTER_PATH := "res://assets/data/equipment_attribute_master.json"


func _ready() -> void:
	_run.call_deferred()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "无法读取%s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "%s不是有效JSON" % path)
	return parsed


func _run() -> void:
	var master := _load_json(MASTER_PATH)
	assert(master.get("contractId", "") == EquipmentRulesScript.ATTRIBUTE_MASTER_CONTRACT_ID)
	assert(master.get("distribution", "") == EquipmentRulesScript.ATTRIBUTE_MASTER_DISTRIBUTION)
	assert(master.get("evidenceSha256", "") == "8C87CD85F4E5FAF00E8D9F85E4394F021EB5EA26AC74CB453CC370BA10452F98")
	assert(master.get("sourceTier", "") == "primary" and master.get("fallbackEvidence", []) == [])
	assert(master.get("records", []).size() == 49)
	assert(int(master.get("scope", {}).get("weaponRecords", 0)) == 37)
	assert(int(master.get("scope", {}).get("maleArmorRecords", 0)) == 12)

	var by_id := {}
	var warning_keys: Array[String] = []
	for value: Variant in master.get("records", []):
		assert(value is Dictionary)
		var record: Dictionary = value
		var item_id := int(record.get("itemId", -1))
		assert(not by_id.has(item_id), "主表ID重复：%d" % item_id)
		by_id[item_id] = record
		assert(record.has("jobLock") and record.get("jobLock", "missing") == null, "%d默认职业锁必须为null" % item_id)
		assert(record.get("rollPolicy", "") == EquipmentRulesScript.LEGACY_ROLL_POLICY)
		assert(record.get("source", {}).get("contractId", "") == EquipmentRulesScript.ATTRIBUTE_MASTER_CONTRACT_ID)
		assert(record.get("source", {}).get("distribution", "") == EquipmentRulesScript.ATTRIBUTE_MASTER_DISTRIBUTION)
		for warning: Dictionary in record.get("warnings", []):
			assert(warning.get("warningCode", "") == "legacy_reverse_range")
			assert(warning.get("runtimeBehavior", "") == EquipmentRulesScript.LEGACY_ROLL_POLICY)
			assert(not bool(warning.get("isError", true)), "反向区间只能是warning")
			warning_keys.append("%d:%s" % [item_id, warning.get("field", "")])
	assert(warning_keys == ["88:dc", "111:dc", "112:dc", "112:mc", "112:sc"])

	for armor_id: int in [116, 118, 120, 122, 128, 140, 124, 130, 142, 126, 132, 144]:
		var armor: Dictionary = by_id.get(armor_id, {})
		assert(armor.get("genderRestriction", "") == "male")
		assert(armor.get("weightRequirementType", "") == "wear")
		assert(EquipmentRulesScript.required_gender(armor) == "男")
	for weapon_id: int in range(80, 116):
		var weapon: Dictionary = by_id.get(weapon_id, {})
		assert(weapon.get("weightRequirementType", "") == "hand")
		assert(EquipmentRulesScript.required_gender(weapon).is_empty())
	assert(by_id.has(223) and by_id[223].get("weightRequirementType", "") == "hand")

	assert(EquipmentRulesScript.requirement_for(by_id[103]).get("type", -1) == EquipmentRulesScript.NEED_MAGIC)
	assert(EquipmentRulesScript.requirement_for(by_id[103]).get("value", -1) == 27)
	assert(EquipmentRulesScript.requirement_for(by_id[104]).get("type", -1) == EquipmentRulesScript.NEED_TAO)
	assert(EquipmentRulesScript.requirement_for(by_id[104]).get("value", -1) == 25)
	assert(EquipmentRulesScript.requirement_for(by_id[113]).get("type", -1) == EquipmentRulesScript.NEED_ATTACK)
	assert(EquipmentRulesScript.requirement_for(by_id[114]).get("type", -1) == EquipmentRulesScript.NEED_MAGIC)
	assert(EquipmentRulesScript.requirement_for(by_id[130]).get("value", -1) == 28)
	assert(EquipmentRulesScript.requirement_for(by_id[132]).get("value", -1) == 27)
	assert(EquipmentRulesScript.effective_profession(by_id[103]) == "通用", "jobAffinity不得成为职业硬锁")
	assert(EquipmentRulesScript.effective_profession({"jobAffinity": "wizard", "jobLock": "warrior"}) == "战士")
	assert(EquipmentRulesScript.weight_requirement_for(by_id[112]) == {
		"type": "hand",
		"value": 22,
		"source": EquipmentRulesScript.ATTRIBUTE_MASTER_DISTRIBUTION,
	})

	assert(EquipmentRulesScript.legacy_range_warning("dc", 30, 0).get("warningCode", "") == "legacy_reverse_range")
	assert(EquipmentRulesScript.legacy_range_warning("dc", 0, 30).is_empty())

	var lost_soul: Dictionary = by_id[111]
	assert(lost_soul.get("stats", {}).get("dc", {}).get("min", -1) == 30)
	assert(lost_soul.get("stats", {}).get("dc", {}).get("max", -1) == 0)
	assert(lost_soul.get("contentLayer", "") == "classic_legendary")
	assert(lost_soul.get("historicalStatus", "") == "official_existence_unverified")
	print("EQUIPMENT_ATTRIBUTE_MASTER_PASS：49条主表、需求/性别/重量、职业锁和反向区间策略正常")
	get_tree().quit(0)
