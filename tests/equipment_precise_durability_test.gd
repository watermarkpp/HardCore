extends Node


func _ready() -> void:
	_run.call_deferred()


func _instance(name: String, current_raw := 10000, maximum_raw := 10000) -> Dictionary:
	return {
		"name": name,
		"count": 1,
		"instance_id": "durability-test-%s" % name,
		"durability_raw": current_raw,
		"max_durability_raw": maximum_raw,
		"durability": int(ceil(float(current_raw) / 1000.0)) if current_raw > 0 else 0,
		"max_durability": int(ceil(float(maximum_raw) / 1000.0)),
	}


func _equip_all(current_raw := 10000) -> void:
	PlayerState.equipment = PlayerState._empty_equipment()
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		PlayerState.equipment[slot] = _instance("木剑", current_raw, 10000)


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		var value: Variant = PlayerState.inventory[index]
		if value is Dictionary and str((value as Dictionary).get("name", "")) == item_name:
			return index
	return -1


func _test_oil_transaction(item_name: String, expected_full_repair: bool) -> void:
	PlayerState.reset_progress(false)
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(0).begins_with("已装备"))
	PlayerState.add_item(item_name)
	var weapon: Dictionary = PlayerState.equipment["武器"]
	weapon["durability_raw"] = 3998
	weapon["max_durability_raw"] = 4000
	PlayerState._sync_durability_compatibility_fields(weapon)
	assert(int(weapon.durability) == 4 and int(weapon.max_durability) == 4)
	var oil_count_before := PlayerState.item_count(item_name)
	var inventory_before := PlayerState.inventory.duplicate(true)
	var equipment_before := PlayerState.equipment.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	var failed := PlayerState.use_inventory_index(_inventory_index(item_name))
	PlayerState._test_force_atomic_write_failure = false
	assert("失败" in failed, "%s存档失败没有向调用方报告" % item_name)
	assert(PlayerState.inventory == inventory_before, "%s存档失败仍消耗物品" % item_name)
	assert(PlayerState.equipment == equipment_before, "%s存档失败仍修改raw耐久" % item_name)
	var success := PlayerState.use_inventory_index(_inventory_index(item_name))
	assert(success.begins_with("武器已"), "%s在3998/4000 raw时被display字段错误阻断" % item_name)
	assert(PlayerState.item_count(item_name) == oil_count_before - 1, "%s成功后没有且仅有一次消费" % item_name)
	weapon = PlayerState.equipment["武器"]
	assert(int(weapon.durability_raw) == int(weapon.max_durability_raw))
	if expected_full_repair:
		assert(int(weapon.max_durability_raw) == 4000, "战神油错误降低最大耐久")


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var equipment_signals := [0]
	var profile_signals := [0]
	PlayerState.equipment_changed.connect(func() -> void: equipment_signals[0] += 1)
	PlayerState.profile_changed.connect(func() -> void: profile_signals[0] += 1)
	_test_oil_transaction("修复油", false)
	_test_oil_transaction("战神油", true)
	PlayerState.reset_progress(false)

	var weapon := _instance("木剑", 5000, 10000)
	PlayerState.equipment["武器"] = weapon
	var unchanged := int(weapon.durability_raw)
	assert(not PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": false, "damage": 10, "weapon_roll": 0}
	).applied, "未确认命中错误损耗武器")
	assert(not PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 0, "weapon_roll": 0}
	).applied, "零伤害错误损耗武器")
	assert(not PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 10, "damage_type": "magic", "weapon_roll": 0}
	).applied, "魔法伤害错误损耗武器")
	assert(int(weapon.durability_raw) == unchanged, "miss/empty/magic改变了raw耐久")

	var equipment_before: int = equipment_signals[0]
	var profile_before: int = profile_signals[0]
	var commits_before: int = PlayerState.durability_event_commit_count
	var minimum_loss := PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 10, "weapon_roll": 0, "weapon_strong": 0}
	)
	assert(minimum_loss.applied and minimum_loss.raw_loss == 2)
	assert(int(weapon.durability_raw) == unchanged - 2, "Random(5)+2下界未按raw扣除")
	assert(equipment_signals[0] == equipment_before + 1, "单事件重复发送equipment_changed")
	assert(profile_signals[0] == profile_before + 1, "单事件重复发送profile_changed")
	assert(PlayerState.durability_event_commit_count == commits_before + 1, "单事件没有且仅有一次存档提交")
	var raw_before_failed_save := int(weapon.durability_raw)
	PlayerState._test_force_atomic_write_failure = true
	var failed_save := PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage_type": "physical", "damage": 1, "weapon_roll": 0}
	)
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(failed_save.applied) and bool(failed_save.get("rolled_back", false)), "耐久存档失败未回滚")
	assert(
		int(PlayerState.equipment["武器"].durability_raw) == raw_before_failed_save,
		"耐久存档失败仍改变了raw耐久"
	)
	weapon = PlayerState.equipment["武器"]

	weapon.durability_raw = 5000
	PlayerState._sync_durability_compatibility_fields(weapon)
	var maximum_loss := PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 10, "weapon_roll": 4, "weapon_strong": 1}
	)
	assert(maximum_loss.raw_loss == 5 and int(weapon.durability_raw) == 4995, "武器Strong未从2..6 raw损耗中精确扣减")

	weapon.durability_raw = 1001
	weapon.max_durability_raw = 2000
	PlayerState._sync_durability_compatibility_fields(weapon)
	assert(int(weapon.durability) == 2)
	PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 1, "weapon_roll": 0}
	)
	assert(int(weapon.durability_raw) == 999 and int(weapon.durability) == 1, "跨1000 raw边界没有同步display兼容字段")
	var roundtrip := PlayerState.migrate_equipment_slots(PlayerState.equipment.duplicate(true))
	assert(int(roundtrip["武器"].durability_raw) == 999 and int(roundtrip["武器"].durability) == 1, "raw存档往返不精确")
	var migrated := PlayerState.migrate_equipment_slots({
		"武器": {"name": "木剑", "durability": 7, "max_durability": 8, "instance_id": "legacy"},
	})
	assert(int(migrated["武器"].durability_raw) == 7000)
	assert(int(migrated["武器"].max_durability_raw) == 8000, "旧display存档没有一次迁移到raw")

	_equip_all()
	var slot_rolls := {}
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		slot_rolls[slot] = 1
	slot_rolls["衣服"] = 0
	slot_rolls["项链"] = 0
	slot_rolls["圣物"] = 0
	slot_rolls["徽章"] = 0
	var incoming := PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK,
		{"damage": 12, "causes_struck": true, "armor_roll": 0, "slot_rolls": slot_rolls}
	)
	assert(incoming.applied and incoming.raw_loss == 5)
	assert(int(PlayerState.equipment["衣服"].durability_raw) == 9990, "衣服未执行必损+独立1/8二次损耗")
	assert(int(PlayerState.equipment["项链"].durability_raw) == 9995, "其他装备独立1/8损耗错误")
	assert(int(PlayerState.equipment["圣物"].durability_raw) == 9995 and int(PlayerState.equipment["徽章"].durability_raw) == 9995, "项目圣物/徽章扩展策略未接入")
	assert(int(PlayerState.equipment["武器"].durability_raw) == 10000, "未命中1/8的槽位被错误损耗")

	_equip_all()
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		slot_rolls[slot] = 1
	var poisoned := PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK,
		{"damage": 12, "causes_struck": true, "armor_roll": 0, "slot_rolls": slot_rolls, "red_poison": true}
	)
	assert(poisoned.raw_loss == 6 and int(PlayerState.equipment["衣服"].durability_raw) == 9994, "红毒1.2倍raw损耗错误")

	PlayerState.reset_progress(false)
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(0).begins_with("已装备"))
	weapon = PlayerState.equipment["武器"]
	var instance_id := str(weapon.instance_id)
	weapon.durability_raw = 2
	PlayerState._sync_durability_compatibility_fields(weapon)
	PlayerState.apply_durability_event(
		PlayerState.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT,
		{"confirmed_hit": true, "damage": 1, "weapon_roll": 0}
	)
	assert(str(PlayerState.equipment["武器"].instance_id) == instance_id and int(weapon.durability_raw) == 0, "零耐久装备实例未保留")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == 5, "raw零耐久装备仍提供属性")

	weapon.durability_raw = 1000
	weapon.max_durability_raw = 10000
	PlayerState._sync_durability_compatibility_fields(weapon)
	PlayerState.apply_weapon_repair_oil(false)
	assert(int(weapon.max_durability_raw) == 9700, "普通修复油最大耐久损耗不是missing/30")
	assert(int(weapon.durability_raw) == 6000, "普通修复油未精确恢复5000 raw")
	PlayerState.apply_weapon_repair_oil(true)
	assert(int(weapon.durability_raw) == int(weapon.max_durability_raw), "战神油未恢复到完整raw最大耐久")

	print("EQUIPMENT_PRECISE_DURABILITY_PASS: raw wear, migration, poison, batching and repair oils")
	get_tree().quit(0)
