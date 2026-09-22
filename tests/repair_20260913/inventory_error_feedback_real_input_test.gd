extends Node

## Equipment rejection real-input acceptance (R1 error channel).
## Every case drives the real touch path (bag tap -> equipment slot tap), no
## direct activation calls: requirement failures (level/attack/magic/tao),
## profession/gender mismatch, wrong slot, bag-full unequip, stale instance
## and save-failure rollback must surface the center error channel while the
## equipment state, bag state, selection and detail stay intact.

const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")

var failures: Array[String] = []
var hud: GameHUD
var panel: InventoryPanel


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func settle() -> void:
	for _index in range(4):
		await get_tree().process_frame


func send_touch(point: Vector2, down: bool, pointer := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_viewport().get_final_transform() * point
	event.index = pointer
	event.pressed = down
	get_viewport().push_input(event)


func center_of(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func point_for(index: int) -> Vector2:
	var button := panel._bag_cells[index].get_child(0) as Control
	return center_of(button)


func tap_bag(index: int) -> void:
	var point := point_for(index)
	send_touch(point, true)
	send_touch(point, false)
	await settle()


func tap_slot(slot: String) -> void:
	var point := center_of(panel.equipment_buttons[slot] as Control)
	send_touch(point, true)
	send_touch(point, false)
	await settle()


func catalog_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value: Variant in GameData.item_catalog:
		if value is Dictionary and not (value as Dictionary).is_empty():
			out.append(value)
	return out


func find_requirement_fixture(type_id: int) -> Dictionary:
	for item in catalog_items():
		if str(item.get("kind", "")) != "equipment":
			continue
		var profession := str(EquipmentRulesScript.effective_profession(item))
		if not profession in ["", "通用", "战士"]:
			continue
		if str(EquipmentRulesScript.required_gender(item)) == "女":
			continue
		var requirement := EquipmentRulesScript.requirement_for(item)
		if int(requirement.get("type", -1)) != type_id or int(requirement.get("value", 0)) <= 0:
			continue
		if str(item.get("name", "")).is_empty():
			continue
		return item
	return {}


func find_gender_fixture() -> Dictionary:
	for item in catalog_items():
		if str(item.get("kind", "")) != "equipment":
			continue
		if str(EquipmentRulesScript.required_gender(item)) != "女":
			continue
		return item
	return {}


func reset_fixture_state() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState.inventory = []
	PlayerState.equipment = {}
	PlayerState.recalculate_stats(false)
	# Deterministic requirement baseline: the requirement authority reads
	# computed_stats, so the test pins the combat stats it needs.
	PlayerState.computed_stats["attack_max"] = 0
	PlayerState.computed_stats["magic_max"] = 0
	PlayerState.computed_stats["tao_max"] = 0
	if panel != null:
		panel._ui_dismiss_selection()


func place_in_bag(item_name: String) -> void:
	# Direct instance creation mirrors the real drop/bag flow without coupling
	# the fixture to pickup-weight rules (heavy weapons are legal in the bag).
	var record := GameData.get_item(item_name)
	expect(not record.is_empty(), "fixture record exists: " + item_name)
	if record.is_empty():
		return
	var instance := PlayerState._make_item_instance(item_name, record)
	expect(not instance.is_empty(), "fixture instance created: " + item_name)
	if instance.is_empty():
		return
	PlayerState.inventory.append(instance)


func assert_error(expected: String, label: String) -> void:
	await settle()
	expect(
		hud.error_label.text == expected,
		"%s center error, expected [%s] got [%s]" % [label, expected, hud.error_label.text]
	)


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	reset_fixture_state()
	hud = GameHUD.new()
	add_child(hud)
	await settle()
	hud._toggle_inventory()
	panel = hud.inventory_panel
	await settle()
	expect(panel != null and panel.visible, "inventory panel open")
	expect(hud.error_label != null, "HUD error channel present")

	# --- 1. 等级不足 ----------------------------------------------------------
	reset_fixture_state()
	PlayerState.level = 1
	var level_item := GameData.get_item_record({"item_id": 102})
	expect(not level_item.is_empty(), "level fixture 井中月 exists")
	place_in_bag(str(level_item.name))
	panel.refresh()
	await settle()
	await tap_bag(0)
	var expected_level := EquipmentRulesScript.requirement_error(level_item, PlayerState.level, PlayerState.computed_stats)
	expect(not expected_level.is_empty(), "level fixture yields a requirement rejection")
	await tap_slot("武器")
	await assert_error(expected_level, "level short")
	expect((PlayerState.equipment.get("武器", {}) as Dictionary).is_empty(), "level short leaves weapon empty")
	expect(panel.selected_inventory_index == 0, "level short keeps the source selected")
	expect(panel.item_detail_presenter.visible, "level short keeps the detail visible")

	# --- 2. 攻击不足 ----------------------------------------------------------
	reset_fixture_state()
	var attack_item := find_requirement_fixture(1)
	expect(not attack_item.is_empty(), "attack requirement fixture exists in catalog")
	if not attack_item.is_empty():
		place_in_bag(str(attack_item.name))
		panel.refresh()
		await settle()
		await tap_bag(0)
		var attack_slots: Array = panel._slots_for_category(str(attack_item.get("category", "")))
		expect(not attack_slots.is_empty(), "attack fixture has an allowed slot")
		var attack_expected := EquipmentRulesScript.requirement_error(attack_item, PlayerState.level, PlayerState.computed_stats)
		await tap_slot(str(attack_slots[0]))
		await assert_error(attack_expected, "attack short")

	# --- 3. 魔法不足 ----------------------------------------------------------
	reset_fixture_state()
	var magic_item := find_requirement_fixture(2)
	expect(not magic_item.is_empty(), "magic requirement fixture exists in catalog")
	if not magic_item.is_empty():
		place_in_bag(str(magic_item.name))
		panel.refresh()
		await settle()
		await tap_bag(0)
		var magic_slots: Array = panel._slots_for_category(str(magic_item.get("category", "")))
		var magic_expected := EquipmentRulesScript.requirement_error(magic_item, PlayerState.level, PlayerState.computed_stats)
		await tap_slot(str(magic_slots[0]))
		await assert_error(magic_expected, "magic short")

	# --- 4. 道术不足 ----------------------------------------------------------
	reset_fixture_state()
	var tao_item := find_requirement_fixture(3)
	expect(not tao_item.is_empty(), "tao requirement fixture exists in catalog")
	if not tao_item.is_empty():
		place_in_bag(str(tao_item.name))
		panel.refresh()
		await settle()
		await tap_bag(0)
		var tao_slots: Array = panel._slots_for_category(str(tao_item.get("category", "")))
		var tao_expected := EquipmentRulesScript.requirement_error(tao_item, PlayerState.level, PlayerState.computed_stats)
		await tap_slot(str(tao_slots[0]))
		await assert_error(tao_expected, "tao short")

	# --- 5. 职业不符 ----------------------------------------------------------
	reset_fixture_state()
	# The formal catalog keeps every equipment record job-unlocked (经典通用
	# 规则), so the profession gate is exercised with a test-only catalog
	# record through the real authority path; the record is removed again.
	var profession_item := {
		"name": "测试法师限定法袍",
		"kind": "equipment",
		"category": "盔甲",
		"jobLock": "wizard",
		"weight": 10,
		"maxDurability": 10,
		"requirementType": "level",
		"requirementValue": 1,
	}
	GameData.items.append(profession_item)
	GameData._build_indexes()
	place_in_bag("测试法师限定法袍")
	panel.refresh()
	await settle()
	await tap_bag(0)
	var profession_expected := "%s只能由%s装备" % [
		"测试法师限定法袍",
		str(EquipmentRulesScript.effective_profession(GameData.get_item("测试法师限定法袍"))),
	]
	await tap_slot("衣服")
	await assert_error(profession_expected, "profession mismatch")
	expect((PlayerState.equipment.get("衣服", {}) as Dictionary).is_empty(), "profession mismatch leaves slot empty")
	GameData.items.erase(profession_item)
	GameData._build_indexes()

	# --- 6. 性别不符 ----------------------------------------------------------
	reset_fixture_state()
	var gender_item := find_gender_fixture()
	expect(not gender_item.is_empty(), "gender fixture exists in catalog")
	if not gender_item.is_empty():
		place_in_bag(str(gender_item.name))
		panel.refresh()
		await settle()
		await tap_bag(0)
		var gender_slots: Array = panel._slots_for_category(str(gender_item.get("category", "")))
		if gender_slots.is_empty():
			expect(gender_slots.size() > 0, "gender fixture has an allowed slot")
		else:
			var gender_expected := "该装备仅限%s性角色" % str(EquipmentRulesScript.required_gender(gender_item))
			await tap_slot(str(gender_slots[0]))
			await assert_error(gender_expected, "gender mismatch")

	# --- 7. 错误装备槽（不再静默） ---------------------------------------------
	reset_fixture_state()
	place_in_bag("木剑")
	panel.refresh()
	await settle()
	await tap_bag(0)
	expect(panel.selected_inventory_index == 0, "wrong-slot case has the weapon selected")
	await tap_slot("衣服")
	await assert_error("%s不能装备到%s位置。" % ["木剑", "衣服"], "wrong slot")
	expect(panel.selected_inventory_index == 0, "wrong slot keeps selection")
	expect(panel.item_detail_presenter.visible, "wrong slot keeps detail")

	# --- 8. 背包已满卸装失败 ---------------------------------------------------
	reset_fixture_state()
	var old_weapon := GameData.get_item_record({"item_id": 99})
	PlayerState.equipment["武器"] = PlayerState._make_item_instance(str(old_weapon.name), old_weapon, 99301)
	for _index in range(InventoryPanel.BAG_CAPACITY):
		PlayerState.add_item("木剑", 1)
	expect(PlayerState.inventory.size() >= InventoryPanel.BAG_CAPACITY, "bag is full for unequip case")
	panel.refresh()
	await settle()
	await tap_slot("武器")
	expect(panel.selected_equipment_slot == "武器", "equipped weapon selected for unequip")
	await tap_bag(0)
	await assert_error("背包已满，没有空位可以卸下装备。", "bag full unequip")
	expect(not (PlayerState.equipment.get("武器", {}) as Dictionary).is_empty(), "weapon still equipped")

	# --- 9. stale instance ------------------------------------------------------
	reset_fixture_state()
	var new_weapon := GameData.get_item_record({"item_id": 102})
	PlayerState.inventory = [PlayerState._make_item_instance(str(new_weapon.name), new_weapon, 102301)]
	panel.refresh()
	await settle()
	await tap_bag(0)
	# The instance changes after the selection exists and WITHOUT a panel
	# refresh (a concurrent mutation): the tap still carries the stale
	# instance id, which the authority must reject with the center error.
	PlayerState.inventory = [PlayerState._make_item_instance(str(new_weapon.name), new_weapon, 102302)]
	await tap_slot("武器")
	await assert_error("所选装备已变化", "stale instance")
	expect((PlayerState.equipment.get("武器", {}) as Dictionary).is_empty(), "stale instance leaves weapon empty")

	# --- 10. 存档失败回滚 -------------------------------------------------------
	reset_fixture_state()
	PlayerState.inventory = [PlayerState._make_item_instance(str(new_weapon.name), new_weapon, 102303)]
	panel.refresh()
	await settle()
	var previous_flag := PlayerState._test_force_atomic_write_failure
	PlayerState._test_force_atomic_write_failure = true
	await tap_bag(0)
	await tap_slot("武器")
	await assert_error("装备存档失败，装备和背包均未改变", "save failure")
	expect((PlayerState.equipment.get("武器", {}) as Dictionary).is_empty(), "save failure rolls back equipment")
	expect(PlayerState.inventory.size() == 1 and not (PlayerState.inventory[0] as Dictionary).is_empty(), "save failure keeps the bag item")
	expect(panel.selected_inventory_index == 0, "save failure keeps the source selected")
	PlayerState._test_force_atomic_write_failure = previous_flag

	hud.queue_free()
	await settle()
	for message in failures:
		push_error(message)
	print("EQUIPMENT_ERROR_FEEDBACK_REAL_INPUT_%s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
