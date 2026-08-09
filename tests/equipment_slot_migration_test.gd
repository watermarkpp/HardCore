extends Node


func _ready() -> void:
	_run.call_deferred()


func _find_inventory_instance(instance_id: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("instance_id", "")) == instance_id:
			return index
	return -1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.EQUIPMENT_SLOTS == ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"], "1.76八装备槽顺序错误")

	PlayerState.add_item("古铜戒指", 3)
	var first_id := str(PlayerState.inventory[0].get("instance_id", ""))
	var second_id := str(PlayerState.inventory[1].get("instance_id", ""))
	var third_id := str(PlayerState.inventory[2].get("instance_id", ""))
	var attack_before := int(PlayerState.computed_stats.get("attack_max", 0))
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(first_id)).begins_with("已装备"), "第一枚戒指穿戴失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == first_id and PlayerState.equipment["右戒指"].is_empty(), "第一枚戒指没有进入左槽")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(second_id)).begins_with("已装备"), "第二枚戒指穿戴失败")
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == second_id, "第二枚戒指没有进入右槽")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == attack_before + 2, "双戒指属性没有分别计入")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(third_id)).begins_with("已装备"), "第三枚戒指替换失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == third_id, "双槽已满时没有确定性替换左戒指")
	assert(_find_inventory_instance(first_id) >= 0 and str(PlayerState.equipment["右戒指"].get("instance_id", "")) == second_id, "被替换戒指或右戒指实例丢失")

	PlayerState.add_item("铁手镯", 2)
	var bracelet_a := str(PlayerState.inventory[-2].get("instance_id", ""))
	var bracelet_b := str(PlayerState.inventory[-1].get("instance_id", ""))
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_a)).begins_with("已装备"), "左手镯穿戴失败")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_b)).begins_with("已装备"), "右手镯穿戴失败")
	assert(str(PlayerState.equipment["左手镯"].get("instance_id", "")) == bracelet_a, "左手镯槽错误")
	assert(str(PlayerState.equipment["右手镯"].get("instance_id", "")) == bracelet_b, "右手镯槽错误")

	PlayerState.equipment["左戒指"]["durability"] = 1
	PlayerState.equipment["右戒指"]["durability"] = 2
	var dual_repair_cost := PlayerState.repair_cost()
	assert(dual_repair_cost > 0, "双戒指耐久没有进入修理价格")
	PlayerState.gold = dual_repair_cost
	assert(PlayerState.repair_all_equipment().begins_with("全部装备维修完成"), "双槽装备修理失败")
	assert(PlayerState.gold == 0, "双槽修理扣费错误")

	var right_id := str(PlayerState.equipment["右戒指"].get("instance_id", ""))
	assert(PlayerState.unequip_slot("右戒指").begins_with("已卸下"), "指定右戒指槽卸下失败")
	assert(PlayerState.equipment["右戒指"].is_empty() and _find_inventory_instance(right_id) >= 0, "右戒指卸下后实例丢失")

	var legacy_bracelet := {"name": "铁手镯", "durability": 2, "max_durability": 4, "instance_id": "legacy_bracelet"}
	var legacy_ring := {"name": "古铜戒指", "durability": 3, "max_durability": 5, "instance_id": "legacy_ring"}
	var migrated := PlayerState.migrate_equipment_slots({"武器": "木剑", "手镯": legacy_bracelet, "戒指": legacy_ring})
	assert(migrated.size() == 8 and not migrated.has("手镯") and not migrated.has("戒指"), "旧存档没有迁移为八槽结构")
	assert(str(migrated["左手镯"].get("instance_id", "")) == "legacy_bracelet" and migrated["右手镯"].is_empty(), "旧手镯实例迁移错误")
	assert(str(migrated["左戒指"].get("instance_id", "")) == "legacy_ring" and migrated["右戒指"].is_empty(), "旧戒指实例迁移错误")
	assert(str(migrated["武器"].get("name", "")) == "木剑", "旧字符串装备兼容迁移失败")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert(panel.equipment_slot_picker.item_count == 8, "装备面板没有提供八槽选择")
	assert("左手镯" in panel.equipment_label.text and "右戒指" in panel.equipment_label.text, "装备面板没有显示左右槽")

	# ---- 左右重复装备槽自动轮换 cursor ----
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("古铜戒指", 3)
	var cycle_a := str(PlayerState.inventory[0].get("instance_id", ""))
	var cycle_b := str(PlayerState.inventory[1].get("instance_id", ""))
	var cycle_c := str(PlayerState.inventory[2].get("instance_id", ""))
	assert(
		PlayerState.equip_cycle_cursor == {"戒指": "左戒指", "手镯": "左手镯"},
		"初始轮换目标不是左戒指/左手镯"
	)
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_a)).begins_with("已装备"), "轮换第一枚戒指穿戴失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == cycle_a, "轮换第一枚戒指未进左戒指")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "右戒指", "第一枚成功后未切换到右戒指")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_b)).begins_with("已装备"), "轮换第二枚戒指穿戴失败")
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == cycle_b, "轮换第二枚戒指未进右戒指")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "第二枚成功后未切回左戒指")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_c)).begins_with("已装备"), "第三枚戒指未替换左戒指")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == cycle_c, "第三枚戒指未替换左戒指")
	assert(_find_inventory_instance(cycle_a) >= 0, "被替换的左戒指实例丢失")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "右戒指", "左槽替换后未切换到右戒指")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_a)).begins_with("已装备"), "双击被换下的左戒指穿戴失败")
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == cycle_a, "被换下的左戒指未替换右戒指")
	assert(_find_inventory_instance(cycle_b) >= 0, "被替换的右戒指实例丢失")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "右槽替换后未切回左戒指")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_b)).begins_with("已装备"), "再双击被换下的右戒指穿戴失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == cycle_b, "被换下的右戒指未替换左戒指")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "右戒指", "左槽替换后未切回右戒指")

	# 手镯独立维护轮换 cursor
	PlayerState.add_item("铁手镯", 3)
	var bracelet_x := str(PlayerState.inventory[-3].get("instance_id", ""))
	var bracelet_y := str(PlayerState.inventory[-2].get("instance_id", ""))
	var bracelet_z := str(PlayerState.inventory[-1].get("instance_id", ""))
	assert(PlayerState.equip_cycle_cursor["手镯"] == "左手镯", "手镯初始轮换目标不是左手镯")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_x)).begins_with("已装备"), "手镯第一件穿戴失败")
	assert(str(PlayerState.equipment["左手镯"].get("instance_id", "")) == bracelet_x, "手镯第一件未进左手镯")
	assert(PlayerState.equip_cycle_cursor["手镯"] == "右手镯", "手镯第一件成功后未切换")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_y)).begins_with("已装备"), "手镯第二件穿戴失败")
	assert(str(PlayerState.equipment["右手镯"].get("instance_id", "")) == bracelet_y, "手镯第二件未进右手镯")
	assert(PlayerState.equip_cycle_cursor["手镯"] == "左手镯", "手镯双槽满后下一目标应为左手镯")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_z)).begins_with("已装备"), "手镯第三件未替换左手镯")
	assert(str(PlayerState.equipment["左手镯"].get("instance_id", "")) == bracelet_z, "手镯第三件未替换左手镯")
	assert(PlayerState.equip_cycle_cursor["手镯"] == "右手镯", "手镯替换后未切换")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "右戒指", "手镯轮换不得推进戒指 cursor")

	# explicit preferred_slot 精确装备且不推进 cursor
	var explicit_ring_index := _find_inventory_instance(cycle_c)
	assert(explicit_ring_index >= 0, "轮换测试缺少待精确装备的戒指实例")
	var ring_cursor_before := str(PlayerState.equip_cycle_cursor["戒指"])
	assert(PlayerState.equip_inventory_index(explicit_ring_index, "左戒指").begins_with("已装备"), "preferred_slot 精确装备失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == cycle_c, "preferred_slot 未精确进左戒指")
	assert(str(PlayerState.equip_cycle_cursor["戒指"]) == ring_cursor_before, "preferred_slot 不得推进轮换 cursor")

	# 职业/等级/重量类失败不推进 cursor，且实例保持完整
	PlayerState.add_item("法神戒指")
	var fashen_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "法神戒指":
			fashen_index = index
			break
	assert(fashen_index >= 0, "法神戒指未进入背包")
	var failed_result := PlayerState.equip_inventory_index(fashen_index)
	assert(not failed_result.begins_with("已装备"), "法神戒指不应装备成功")
	assert(str(PlayerState.equip_cycle_cursor["戒指"]) == ring_cursor_before, "装备失败不得推进戒指 cursor")
	assert(PlayerState.equip_cycle_cursor["手镯"] == "右手镯", "装备失败不得推进手镯 cursor")
	assert(str(PlayerState.inventory[fashen_index].get("instance_id", "")) != "", "装备失败后实例不应丢失")

	# 失败后的下一次自动装备仍严格按 cursor：当前戒指 cursor=右 → 替换右戒指
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(cycle_b)).begins_with("已装备"), "失败后自动装备未按 cursor 执行")
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == cycle_b, "失败后自动装备未进右戒指")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "失败后自动装备成功后未推进 cursor")

	# 轮换 cursor 持久化，旧档缺失时安全默认
	PlayerState.active_profile_id = "equipment_slot_cycle_persistence_test"
	PlayerState.character_name = "双槽轮换测试"
	PlayerState.save_game()
	var cycle_save_path := PlayerState._profile_path(PlayerState.active_profile_id)
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "戒指 cursor 未持久化")
	assert(PlayerState.equip_cycle_cursor["手镯"] == "右手镯", "手镯 cursor 未持久化")
	var cycle_saved: Dictionary = PlayerState._read_json(cycle_save_path)
	cycle_saved["save_version"] = 8
	cycle_saved.erase("equip_cycle_cursor")
	assert(PlayerState._write_json_atomic(cycle_save_path, cycle_saved), "无法写入旧档样本")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	assert(PlayerState.equip_cycle_cursor == {"戒指": "左戒指", "手镯": "左手镯"}, "旧档缺失轮换 cursor 未安全默认")
	var absolute_cycle_path := ProjectSettings.globalize_path(cycle_save_path)
	if FileAccess.file_exists(cycle_save_path):
		DirAccess.remove_absolute(absolute_cycle_path)
	if FileAccess.file_exists("%s.bak" % cycle_save_path):
		DirAccess.remove_absolute("%s.bak" % absolute_cycle_path)
	PlayerState.active_profile_id = ""

	# 回归：双槽满后手动卸下右槽，cursor 按本次实际装备的槽推进到另一侧
	PlayerState.unequip_slot("右戒指")
	assert(PlayerState.equipment["右戒指"].is_empty(), "回归前置右戒指未卸下")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "回归前置戒指 cursor 应为左戒指")
	var refilled_right_id := str(PlayerState.inventory[-1].get("instance_id", ""))
	assert(
		PlayerState.equip_inventory_index(_find_inventory_instance(refilled_right_id)).begins_with("已装备"),
		"空右槽自动装备失败"
	)
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == refilled_right_id, "空槽自动装备未进右戒指")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "左戒指", "实际装备右槽后 cursor 未推进到左戒指")
	var next_auto_id := str(PlayerState.inventory[0].get("instance_id", ""))
	assert(not next_auto_id.is_empty(), "回归缺少可自动装备的戒指实例")
	assert(
		PlayerState.equip_inventory_index(_find_inventory_instance(next_auto_id)).begins_with("已装备"),
		"满双槽后自动装备失败"
	)
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == next_auto_id, "再下一件未替换左戒指（连续右）")
	assert(PlayerState.equip_cycle_cursor["戒指"] == "右戒指", "左槽替换后 cursor 未推进")

	print("EQUIPMENT_SLOT_MIGRATION_PASS：双手镯、双戒指、确定性替换、属性修理、指定卸下、v02迁移和自动轮换cursor正常")
	get_tree().quit(0)
