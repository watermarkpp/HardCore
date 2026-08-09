extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const MASTER_PATH := "res://assets/data/equipment_attribute_master.json"
const FEMALE_ARMOR_EVIDENCE_PATH := "res://assets/data/equipment_female_armor_attribute_evidence.json"
const TASK_CORRECTION_SHA256 := "59FCA9C1F220041E3C6D144FC58AFA6CDE9FC02A785EE7FF8381E9136E5E0DA9"
const ARMOR_PAIRS := [
	[116, 117], [118, 119], [120, 121], [122, 123],
	[124, 125], [126, 127], [128, 129], [130, 131],
	[132, 133], [140, 141], [142, 143], [144, 145],
]

var _equipment_changed_count := 0


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
	assert(master.get("schemaVersion", 0) == 2)
	assert(master.get("evidenceSha256", "") == "CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D")
	assert(master.get("sourceTier", "") == "primary" and master.get("fallbackEvidence", []) == [])
	assert(master.get("sourceKind", "") == "explicit_user_primary_override")
	assert(master.get("blankOverridePolicy", "") == "preserve_existing_value")
	assert(master.get("records", []).size() == 175)
	assert(int(master.get("scope", {}).get("weaponRecords", 0)) == 37)
	assert(int(master.get("scope", {}).get("maleArmorRecords", 0)) == 12)
	assert(int(master.get("scope", {}).get("femaleArmorRecords", 0)) == 12)
	assert(int(master.get("scope", {}).get("workbookOverrideRecords", 0)) == 114)
	assert(int(master.get("scope", {}).get("helmetRecords", 0)) == 12)
	assert(int(master.get("scope", {}).get("necklaceRecords", 0)) == 32)
	assert(int(master.get("scope", {}).get("braceletRecords", 0)) == 31)
	assert(int(master.get("scope", {}).get("ringRecords", 0)) == 39)
	assert(int(master.get("units", {}).get("magicEvasionPercentPerPoint", 0)) == 10)

	var by_id := {}
	var warning_keys: Array[String] = []
	var low_confidence_keys: Array[int] = []
	var review_counts := {}
	var accuracy_count := 0
	var agility_count := 0
	var magic_evasion_count := 0
	var attack_speed_count := 0
	var set_count := 0
	var special_effect_count := 0
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
		if record.has("review"):
			var review_status := str(record.get("review", {}).get("status", ""))
			review_counts[review_status] = int(review_counts.get(review_status, 0)) + 1
			assert(record.get("source", {}).get("sourceKind", "") == "explicit_user_primary_override")
			assert(record.get("source", {}).get("evidenceSha256", "") == "CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D")
			assert(record.get("source", {}).get("recordKey", "").begins_with("修正后装备主表!A"))
			assert(record.get("weightRequirementType", "") == "wear")
			assert(record.get("jobLock", "missing") == null)
			accuracy_count += int(record.has("accuracy"))
			agility_count += int(record.has("agility"))
			magic_evasion_count += int(record.has("magicEvasionPercent"))
			attack_speed_count += int(record.has("attackSpeedTier"))
			set_count += int(record.has("setId"))
			special_effect_count += int(record.has("specialEffectId"))
			if record.has("magicEvasionPercent"):
				assert(int(record.get("magicEvasionPercent", -1)) == int(record.get("magicEvasionPoints", -1)) * 10)
				assert(int(record.get("magicEvasionPercentPerPoint", 0)) == 10)
		for warning: Dictionary in record.get("warnings", []):
			var warning_code := str(warning.get("warningCode", ""))
			assert(not bool(warning.get("isError", true)), "主表warning不得作为error")
			if warning_code == "legacy_reverse_range":
				assert(warning.get("runtimeBehavior", "") == EquipmentRulesScript.LEGACY_ROLL_POLICY)
				warning_keys.append("%d:%s" % [item_id, warning.get("field", "")])
			elif warning_code == "low_confidence_user_override":
				low_confidence_keys.append(item_id)
				assert(warning.get("reviewStatus", "") == "低置信待确认")
				assert(warning.get("evidenceGrade", "") == "C")
			else:
				assert(false, "未知主表warning：%s" % warning_code)
	assert(warning_keys == [
		"88:dc", "111:dc", "112:dc", "112:mc", "112:sc",
		"156:dc", "157:mc", "158:sc", "161:dc", "162:mc",
		"164:dc", "202:dc", "244:sc",
	])
	assert(low_confidence_keys == [196])
	assert(review_counts == {
		"已确认": 57,
		"已修正": 51,
		"低置信待确认": 1,
		"特殊机制确认": 3,
		"已补齐特效": 2,
	})
	assert(accuracy_count == 9)
	assert(agility_count == 4)
	assert(magic_evasion_count == 2)
	assert(attack_speed_count == 2)
	assert(set_count == 17)
	assert(special_effect_count == 28)

	for armor_id: int in [116, 118, 120, 122, 128, 140, 124, 130, 142, 126, 132, 144]:
		var armor: Dictionary = by_id.get(armor_id, {})
		assert(armor.get("genderRestriction", "") == "male")
		assert(armor.get("weightRequirementType", "") == "wear")
		assert(EquipmentRulesScript.required_gender(armor) == "男")
	for pair: Array in ARMOR_PAIRS:
		var male: Dictionary = by_id.get(int(pair[0]), {})
		var female: Dictionary = by_id.get(int(pair[1]), {})
		assert(female.get("genderRestriction", "") == "female")
		assert(EquipmentRulesScript.required_gender(female) == "女")
		assert(female.get("source", {}).get("sourceKind", "") == "explicit_user_task_correction")
		assert(female.get("source", {}).get("evidenceSha256", "") == TASK_CORRECTION_SHA256)
		assert(female.get("source", {}).get("fallbackEvidence", []) == [])
		assert(int(female.get("source", {}).get("pairedPrimaryItemId", -1)) == int(pair[0]))
		assert(female.get("source", {}).get("auxiliarySearchEvidence", {}).get("result", "") == "no_eligible_auxiliary")
		assert(bool(female.get("source", {}).get("auxiliarySearchEvidence", {}).get("crystalServerDataExcluded", false)))
		for field: String in [
			"category", "jobAffinity", "jobLock", "requirementType",
			"requirementValue", "legacyNeed", "legacyNeedLevel",
			"weightRequirementType", "weightRequirementValue", "weight",
			"durability", "rollPolicy", "stats", "warnings",
		]:
			assert(female.get(field) == male.get(field), "%d/%d字段%s未保持成对primary值" % [int(pair[0]), int(pair[1]), field])
	_run_armor_gender_gate_table(by_id)
	_assert_production_gender_gate_precedes_visual_resolution()
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
	assert(by_id[159].get("magicEvasionPercent", 0) == 20)
	assert(by_id[159].get("magicEvasionPoints", 0) == 2)
	assert(by_id[164].get("magicEvasionPercent", 0) == 10)
	assert(by_id[164].get("magicEvasionPoints", 0) == 1)
	assert(by_id[221].get("attackSpeedTier", 0) == 2)
	assert(by_id[222].get("attackSpeedTier", 0) == 1)
	assert(by_id[169].get("requirementType", "") == "max_mc")
	assert(by_id[169].get("requirementValue", 0) == 25)
	assert(by_id[169].get("accuracy", 0) == 1)
	assert(by_id[160].get("agility", 0) == 3)
	assert(by_id[225].get("jobAffinity", "") == "general")
	assert(by_id[225].get("jobAffinityLabel", "") == "通用（祈祷套装）")
	assert(by_id[225].get("setId", "") == "prayer_set")
	assert(by_id[225].get("specialEffectId", "") == "prayer_pet_rebellion")
	assert(by_id[196].get("review", {}).get("status", "") == "低置信待确认")
	var evidence := _load_json(FEMALE_ARMOR_EVIDENCE_PATH)
	assert(evidence.get("authorization", {}).get("evidenceSha256", "") == TASK_CORRECTION_SHA256)
	assert(evidence.get("preCorrectionInputs", {}).get("sourcePriorityPolicy", {}).get("eligibleAuxiliarySources", ["unexpected"]) == [])
	assert(evidence.get("records", {}).size() == 12)
	print("EQUIPMENT_ATTRIBUTE_MASTER_PASS：175条唯一主表、12对盔甲性别门禁、114条工作簿覆盖正常")
	get_tree().quit(0)


func _run_armor_gender_gate_table(by_id: Dictionary) -> void:
	var visual_resolution_count := 0
	if not PlayerState.equipment_changed.is_connected(_on_equipment_changed):
		PlayerState.equipment_changed.connect(_on_equipment_changed)
	PlayerState.test_mode = true
	for pair: Array in ARMOR_PAIRS:
		for case: Array in [[int(pair[0]), "男", "女"], [int(pair[1]), "女", "男"]]:
			var item: Dictionary = by_id.get(int(case[0]), {})
			assert(EquipmentRulesScript.requirement_error(item, 99, {
				"attack_max": 999,
				"magic_max": 999,
				"tao_max": 999,
			}).is_empty(), "%d在满足条件后仍不可穿" % int(case[0]))
			assert(int(item.get("weight", 0)) <= EquipmentRulesScript.max_wear_weight("战士", 99))
			_prepare_actor_for_armor(str(case[1]))
			PlayerState.add_item(str(item.get("name", "")))
			var correct_index := _inventory_index(str(item.get("name", "")))
			var correct_signal_count := _equipment_changed_count
			assert(PlayerState.equip_inventory_index(correct_index).begins_with("已装备"), "%d应允许正确性别穿戴" % int(case[0]))
			assert(_equipment_changed_count == correct_signal_count + 1, "%d正确穿戴后必须触发外观刷新信号" % int(case[0]))
			visual_resolution_count += 1
			_prepare_actor_for_armor(str(case[2]))
			PlayerState.add_item(str(item.get("name", "")))
			var wrong_index := _inventory_index(str(item.get("name", "")))
			var wrong_signal_count := _equipment_changed_count
			assert(PlayerState.equip_inventory_index(wrong_index) == "该装备仅限%s性角色" % str(case[1]), "%d必须拒绝错误性别" % int(case[0]))
			assert(_equipment_changed_count == wrong_signal_count, "%d错误性别必须在外观刷新信号前拒绝" % int(case[0]))
	assert(visual_resolution_count == 24, "24件男女甲都必须在正确性别门禁后进入外观解析")


func _prepare_actor_for_armor(actor_gender: String) -> void:
	PlayerState.reset_progress()
	PlayerState.level = 99
	PlayerState.profession = "战士"
	PlayerState.gender = actor_gender
	PlayerState.recalculate_stats()
	PlayerState.computed_stats["attack_max"] = 999
	PlayerState.computed_stats["magic_max"] = 999
	PlayerState.computed_stats["tao_max"] = 999


func _inventory_index(item_name: String) -> int:
	for index: int in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _on_equipment_changed() -> void:
	_equipment_changed_count += 1


func _assert_production_gender_gate_precedes_visual_resolution() -> void:
	var player_state_file := FileAccess.open("res://scripts/player_state.gd", FileAccess.READ)
	assert(player_state_file != null)
	var player_state_source := player_state_file.get_as_text()
	var equip_start := player_state_source.find("func equip_inventory_index")
	var gender_guard := player_state_source.find("var required_gender := EquipmentRulesScript.required_gender(item)", equip_start)
	var mismatch_return := player_state_source.find("return \"该装备仅限%s性角色\"", gender_guard)
	var equipment_changed_emit := player_state_source.find("equipment_changed.emit()", mismatch_return)
	assert(equip_start >= 0 and gender_guard > equip_start)
	assert(mismatch_return > gender_guard and equipment_changed_emit > mismatch_return)
	var player_visual_file := FileAccess.open("res://scripts/player_visual.gd", FileAccess.READ)
	assert(player_visual_file != null)
	var player_visual_source := player_visual_file.get_as_text()
	assert(player_visual_source.find("PlayerState.equipment_changed.connect(_refresh_equipment_visuals)") >= 0)
