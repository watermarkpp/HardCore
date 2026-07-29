extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const TEST_DIRECTORY := "user://equipment_luck_test_profiles"
const TEST_INDEX := "user://equipment_luck_test_index.json"

var _oil_unlucky_roll := 0
var _oil_success_roll := 0


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _on_consumable_requested(item_name: String) -> void:
	if item_name == "祝福油":
		PlayerState.apply_blessing_oil_with_rolls(_oil_unlucky_roll, _oil_success_roll)


func _run() -> void:
	var file := FileAccess.open("res://assets/data/equipment_luck_rules.json", FileAccess.READ)
	assert(file != null, "装备幸运规则来源表缺失")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary and source.get("contractId", "") == "equipment.blessing_luck.v2", "祝福油规则合同错误")
	assert(source.get("sourcePolicy", {}).get("distribution", "") == "source.original_gameofmir.server_suite", "祝福油没有使用server_rules主源")
	assert(int(source.defaults.get("unluckyRate", 0)) == 20, "祝福油失败率来源错误")
	var luck_points: Array = source.defaults.get("luckPoints", [])
	assert(luck_points.size() == 3 and int(luck_points[0]) == 1 and int(luck_points[1]) == 3 and int(luck_points[2]) == 7 and int(source.defaults.get("maxCurse", 0)) == 10, "幸运/诅咒边界错误")
	assert(source.get("probabilityFormula", {}).get("spanFactor", "") == "R=max(1,floor(abs(DCmax-DCmin)/5))", "R边界公式不可审计")
	assert(source.get("compatibility", {}).get("nonWeaponCurseField", "") == "curse" and not bool(source.get("compatibility", {}).get("existingCurseValuesInvented", true)), "非武器curse兼容策略错误")

	var outcome := EquipmentRulesScript.blessing_outcome(2, 0, 2, 12, 1, 0)
	assert(outcome == {"result": "cursed", "luck": 1, "curse": 0}, "祝福油失败没有先降低幸运")
	outcome = EquipmentRulesScript.blessing_outcome(0, 0, 2, 12, 1, 0)
	assert(outcome == {"result": "cursed", "luck": 0, "curse": 1}, "零幸运失败没有增加诅咒")
	outcome = EquipmentRulesScript.blessing_outcome(0, 2, 2, 12, 0, 0)
	assert(outcome == {"result": "improved", "luck": 0, "curse": 1}, "成功路径没有优先消除诅咒")
	outcome = EquipmentRulesScript.blessing_outcome(0, 0, 2, 12, 0, 0)
	assert(outcome == {"result": "improved", "luck": 1, "curse": 0}, "幸运0没有必定提升到1")
	outcome = EquipmentRulesScript.blessing_outcome(1, 0, 2, 12, 0, 1)
	assert(outcome == {"result": "improved", "luck": 2, "curse": 0}, "幸运1—2阶段成功判定错误")
	outcome = EquipmentRulesScript.blessing_outcome(3, 0, 12, 16, 0, 1)
	assert(outcome == {"result": "improved", "luck": 4, "curse": 0}, "命运之刃幸运+3后因R=0边界无法继续")
	outcome = EquipmentRulesScript.blessing_outcome(7, 0, 2, 12, 0, 1)
	assert(outcome.get("result", "") == "ineffective" and int(outcome.get("luck", 0)) == 7, "幸运上限没有保持7")
	outcome = EquipmentRulesScript.blessing_outcome(7, 0, 2, 12, 1, 1)
	assert(outcome == {"result": "cursed", "luck": 6, "curse": 0}, "幸运7没有遵循5%负面分支")
	outcome = EquipmentRulesScript.blessing_outcome(0, 10, 2, 12, 1, 1)
	assert(outcome == {"result": "cursed", "luck": 0, "curse": 10}, "诅咒上限没有保持10")

	var negative_results := 0
	for roll in range(EquipmentRulesScript.BLESSING_UNLUCKY_RATE):
		outcome = EquipmentRulesScript.blessing_outcome(0, 0, 2, 12, roll, 0)
		if outcome.get("result", "") == "cursed":
			negative_results += 1
	assert(negative_results == 1, "0—19恰好一个负面点才是5%")
	assert(EquipmentRulesScript.blessing_span_factor(30, 30) == 1, "等值区间R必须钳为1")
	assert(EquipmentRulesScript.blessing_span_factor(12, 16) == 1, "命运之刃窄区间R必须钳为1")
	assert(EquipmentRulesScript.blessing_span_factor(2, 12) == 2, "普通区间R计算错误")
	assert(EquipmentRulesScript.blessing_span_factor(30, 0) == 6, "反向区间R必须使用绝对跨度")
	assert(EquipmentRulesScript.blessing_success_denominator(0, 12, 16) == 1)
	assert(EquipmentRulesScript.blessing_success_denominator(1, 12, 16) == 7)
	assert(EquipmentRulesScript.blessing_success_denominator(2, 2, 12) == 8)
	assert(EquipmentRulesScript.blessing_success_denominator(3, 12, 16) == 40)
	assert(EquipmentRulesScript.blessing_success_denominator(6, 2, 12) == 80)
	assert(EquipmentRulesScript.blessing_success_denominator(7, 12, 16) == 0)

	assert(EquipmentRulesScript.equipment_luck_contribution({"luck": 2, "curse": 3}) == -1, "非武器基础curse没有抵消luck")
	assert(
		EquipmentRulesScript.equipment_luck_contribution(
			{"luck": 1, "curse": 2},
			{"weapon_luck": 4, "weapon_curse": 1},
			true,
		) == 2,
		"基础与实例幸运/诅咒重复或漏算",
	)

	var neutral_rng := RandomNumberGenerator.new()
	var lucky_rng := RandomNumberGenerator.new()
	var cursed_rng := RandomNumberGenerator.new()
	neutral_rng.seed = 176
	lucky_rng.seed = 176
	cursed_rng.seed = 176
	var neutral_total := 0
	var lucky_total := 0
	var cursed_total := 0
	for index in range(512):
		neutral_total += WarriorCombatMath.roll_attack_power(2, 12, 0, neutral_rng)
		lucky_total += WarriorCombatMath.roll_attack_power(2, 12, 9, lucky_rng)
		cursed_total += WarriorCombatMath.roll_attack_power(2, 12, -9, cursed_rng)
	assert(lucky_total == 12 * 512 and cursed_total == 2 * 512, "幸运9/诅咒9没有稳定命中上下限")
	assert(cursed_total < neutral_total and neutral_total < lucky_total, "固定种子攻击分布顺序错误")

	var old_directory: String = PlayerState.profile_directory
	var old_index: String = PlayerState.profile_index_path
	var old_test_mode: bool = PlayerState.test_mode
	var old_active_profile: String = PlayerState.active_profile_id
	_cleanup_save()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("逍遥扇")
	assert(PlayerState.equip_inventory_index(_inventory_index("逍遥扇")).begins_with("已装备"), "基础幸运武器穿戴失败")
	var base_luck_weapon: Dictionary = PlayerState.equipment["武器"]
	base_luck_weapon["weapon_luck"] = 2
	base_luck_weapon["weapon_curse"] = 1
	PlayerState.recalculate_stats()
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 2, "武器基础luck与实例差值发生重复计算")
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	if not PlayerState.consumable_requested.is_connected(_on_consumable_requested):
		PlayerState.consumable_requested.connect(_on_consumable_requested)
	if not PlayerState.scroll_requested.is_connected(_on_consumable_requested):
		PlayerState.scroll_requested.connect(_on_consumable_requested)
	PlayerState.add_item("祝福油", 3)
	var oil_index := _inventory_index("祝福油")
	assert(PlayerState.use_inventory_index(oil_index) == "需要先装备武器", "未装备武器时祝福油提示错误")
	assert(PlayerState.has_item("祝福油", 3), "未装备武器却消耗了祝福油")
	PlayerState.add_item("命运之刃")
	assert(PlayerState.equip_inventory_index(_inventory_index("命运之刃")).begins_with("已装备"), "祝福油测试武器穿戴失败")
	var weapon: Dictionary = PlayerState.equipment["武器"]
	assert(weapon.has("weapon_luck") and weapon.has("weapon_curse"), "武器实例没有幸运/诅咒字段")
	weapon["weapon_luck"] = 3
	weapon["weapon_curse"] = 0
	PlayerState.recalculate_stats()
	_oil_unlucky_roll = 0
	_oil_success_roll = 1
	assert(PlayerState.use_inventory_index(_inventory_index("祝福油")).begins_with("使用"), "装备武器后祝福油没有正常消耗")
	assert(PlayerState.has_item("祝福油", 2), "祝福油每次应消耗一个")
	assert(int(weapon.get("weapon_luck", 0)) == 4, "命运之刃幸运+3后喝油没有继续提升")

	var ring_item := GameData.get_item("古铜戒指")
	var ring_had_luck := ring_item.has("luck")
	var ring_had_curse := ring_item.has("curse")
	var ring_old_luck: Variant = ring_item.get("luck", null)
	var ring_old_curse: Variant = ring_item.get("curse", null)
	ring_item["luck"] = 2
	ring_item["curse"] = 1
	PlayerState.add_item("古铜戒指")
	assert(PlayerState.equip_inventory_index(_inventory_index("古铜戒指")).begins_with("已装备"), "总幸运测试戒指穿戴失败")
	weapon["weapon_curse"] = 1
	PlayerState.recalculate_stats()
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 4, "总幸运没有按全部装备luck-curse和武器实例差值计算")
	var ring: Dictionary = PlayerState.equipment["左戒指"]
	PlayerState.damage_equipment_durability("左戒指", int(ring.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 3, "零耐久非武器仍贡献luck/curse")
	PlayerState.damage_equipment_durability("武器", int(weapon.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 0 and int(weapon.get("weapon_luck", 0)) == 4, "零耐久未禁用幸运或错误清除实例幸运")
	PlayerState.gold = PlayerState.repair_cost()
	PlayerState.repair_all_equipment()
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 4, "维修后全部装备幸运/诅咒没有恢复参与结算")

	PlayerState.profile_directory = TEST_DIRECTORY
	PlayerState.profile_index_path = TEST_INDEX
	PlayerState.active_profile_id = "blessing_luck_save"
	PlayerState.character_name = "祝福存档测试"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	PlayerState.save_game()
	var saved_file := FileAccess.open(TEST_DIRECTORY + "/blessing_luck_save.json", FileAccess.READ)
	assert(saved_file != null, "祝福/诅咒存档没有写入")
	var saved: Variant = JSON.parse_string(saved_file.get_as_text())
	assert(saved is Dictionary)
	assert(int(saved.get("equipment", {}).get("武器", {}).get("weapon_luck", -1)) == 4)
	assert(int(saved.get("equipment", {}).get("武器", {}).get("weapon_curse", -1)) == 1)
	weapon["weapon_luck"] = 0
	weapon["weapon_curse"] = 0
	PlayerState.load_save()
	weapon = PlayerState.equipment["武器"]
	assert(int(weapon.get("weapon_luck", -1)) == 4 and int(weapon.get("weapon_curse", -1)) == 1, "存档没有恢复武器实例幸运/诅咒")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert("幸运+4" in panel.equipment_label.text, "装备面板没有显示武器幸运")

	if ring_had_luck:
		ring_item["luck"] = ring_old_luck
	else:
		ring_item.erase("luck")
	if ring_had_curse:
		ring_item["curse"] = ring_old_curse
	else:
		ring_item.erase("curse")
	PlayerState.profile_directory = old_directory
	PlayerState.profile_index_path = old_index
	PlayerState.active_profile_id = old_active_profile
	PlayerState.test_mode = old_test_mode
	_cleanup_save()

	print("EQUIPMENT_LUCK_PASS：R边界、三结果、5%负面、总幸运、消耗/存档、零耐久与攻击分布正常")
	get_tree().quit(0)


func _cleanup_save() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var index_path := TEST_INDEX + suffix
		if FileAccess.file_exists(index_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		var directory := DirAccess.open(TEST_DIRECTORY)
		if directory != null:
			for file_name: String in directory.get_files():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		DirAccess.remove_absolute(absolute_directory)
