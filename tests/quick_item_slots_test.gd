extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats()

	# 候选过滤：仅 skill_book / consumable / scroll 且 usable != false
	assert(PlayerState.is_quick_item_candidate("太阳水"), "消耗品未通过候选")
	assert(PlayerState.is_quick_item_candidate("回城卷"), "卷轴未通过候选")
	assert(PlayerState.is_quick_item_candidate("基本剑术"), "技能书未通过候选")
	assert(not PlayerState.is_quick_item_candidate("木剑"), "装备不得进入候选")
	assert(not PlayerState.is_quick_item_candidate("金币 1000"), "货币不得进入候选")
	assert(not PlayerState.is_quick_item_candidate("沃玛号角"), "任务材料不得进入候选")
	assert(not PlayerState.is_quick_item_candidate("不存在物品"), "未知物品不得进入候选")
	assert(not PlayerState.is_quick_item_candidate(""), "空名不得进入候选")

	# 绑定校验
	assert(PlayerState.quick_item_slots == ["", "", "", ""], "初始快捷物品槽不是四空槽")
	var bad_index := PlayerState.assign_quick_item_slot(4, "太阳水")
	assert(not bool(bad_index.get("ok", false)), "越界槽位不应绑定成功")
	PlayerState.add_item("太阳水", 2)
	var assigned := PlayerState.assign_quick_item_slot(0, "太阳水")
	assert(bool(assigned.get("ok", false)), "合法绑定失败")
	assert(PlayerState.quick_item_slots[0] == "太阳水", "绑定未写入槽位")
	assert(
		str(assigned.get("change", {}).get("contract_id", ""))
		== PlayerState.QUICK_ITEM_SLOTS_CONTRACT_ID,
		"change 合同 ID 不稳定"
	)
	assert(not bool(PlayerState.assign_quick_item_slot(1, "木剑").get("ok", false)), "非候选物品绑定未被拒绝")
	assert(PlayerState.quick_item_slots[1].is_empty(), "被拒绑定污染了槽位")
	assert(bool(PlayerState.assign_quick_item_slot(0, "").get("ok", false)), "清空槽位失败")
	assert(PlayerState.quick_item_slots[0].is_empty(), "清空槽位未生效")

	# 背包必须确有至少一件；库存耗尽不自动清绑定
	PlayerState.reset_progress(false)
	assert(not bool(PlayerState.assign_quick_item_slot(0, "太阳水").get("ok", false)), "背包无货时不应绑定")
	PlayerState.add_item("金创药(小量)", 1)
	PlayerState.add_item("太阳水", 1)
	assert(bool(PlayerState.assign_quick_item_slot(0, "太阳水").get("ok", false)), "有货时绑定失败")
	var first_use := PlayerState.use_quick_item_slot(0, "太阳水")
	assert(bool(first_use.get("ok", false)), "快捷使用失败：%s" % str(first_use.get("message", "")))
	assert(str(first_use.get("kind", "")) == "consumable", "使用结果未报告消耗品类型")
	assert(PlayerState.item_count("太阳水") == 0, "快捷使用未消耗")
	assert(PlayerState.quick_item_slots[0] == "太阳水", "库存耗尽后绑定被错误清空")
	var depleted := PlayerState.use_quick_item_slot(0, "太阳水")
	assert(not bool(depleted.get("ok", false)), "耗尽后仍应失败")
	assert(str(depleted.get("reason", "")) == "no_inventory", "耗尽失败原因不正确")
	assert(PlayerState.quick_item_slots[0] == "太阳水", "耗尽失败后绑定被错误清空")

	# 每次按绑定名字重新扫描 inventory 索引，绝不复用旧 index
	PlayerState.add_item("太阳水", 1)
	PlayerState.inventory.reverse()
	var rescanned := PlayerState.use_quick_item_slot(0)
	assert(bool(rescanned.get("ok", false)), "库存索引变化后未按名字重新扫描")
	assert(PlayerState.item_count("太阳水") == 0, "按名字重扫后未消耗正确物品")

	# expected 不匹配防误用
	PlayerState.add_item("太阳水", 1)
	assert(bool(PlayerState.assign_quick_item_slot(0, "太阳水").get("ok", false)), "重绑定失败")
	var mismatch := PlayerState.use_quick_item_slot(0, "回城卷")
	assert(not bool(mismatch.get("ok", false)), "expected 不匹配不应放行")
	assert(str(mismatch.get("reason", "")) == "expected_name_mismatch", "mismatch 原因不正确")
	assert(PlayerState.item_count("太阳水") == 1, "mismatch 不应消耗物品")

	# 技能书走单一物品规则：消费一本并学习
	PlayerState.add_item("基本剑术", 1)
	assert(bool(PlayerState.assign_quick_item_slot(1, "基本剑术").get("ok", false)), "技能书绑定失败")
	var book_use := PlayerState.use_quick_item_slot(1, "基本剑术")
	assert(bool(book_use.get("ok", false)), "技能书快捷使用失败：%s" % str(book_use.get("message", "")))
	assert(str(book_use.get("kind", "")) == "skill_book", "技能书类型报告错误")
	assert(PlayerState.item_count("基本剑术") == 0, "技能书未消耗")
	assert(PlayerState.is_skill_learned("基本剑术"), "技能书未学习")

	# v9 持久化 + 旧档缺失/畸形输入迁移
	PlayerState.active_profile_id = "quick_item_slots_test"
	PlayerState.character_name = "快捷物品测试"
	PlayerState.reset_progress(false)
	PlayerState.add_item("太阳水", 3)
	PlayerState.add_item("回城卷", 2)
	PlayerState.assign_quick_item_slot(0, "太阳水")
	PlayerState.assign_quick_item_slot(2, "回城卷")
	PlayerState.save_game()
	var save_path := PlayerState._profile_path(PlayerState.active_profile_id)
	var saved: Dictionary = PlayerState._read_json(save_path)
	assert(int(saved.get("save_version", 0)) == PlayerState.SAVE_VERSION, "SAVE_VERSION 未升级到 v9")
	assert(Array(saved.get("quick_item_slots", [])).size() == 4, "存档缺少 4 格快捷物品绑定")
	assert(saved.get("quick_item_slots", []) == ["太阳水", "", "回城卷", ""], "存档快捷物品绑定错误")
	assert(
		saved.get("equip_cycle_cursor", {}) == {"戒指": "左戒指", "手镯": "左手镯"},
		"存档缺少轮换 cursor 默认"
	)
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	assert(PlayerState.quick_item_slots == ["太阳水", "", "回城卷", ""], "v9 重载丢失快捷物品绑定")

	saved["quick_item_slots"] = ["太阳水", 123, null, "多余"]
	saved["save_version"] = 8
	saved.erase("equip_cycle_cursor")
	assert(PlayerState._write_json_atomic(save_path, saved), "无法写入旧档样本")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	assert(PlayerState.quick_item_slots == ["太阳水", "123", "", ""], "非四格输入未规范化为 4 字符串")
	assert(
		PlayerState.equip_cycle_cursor == {"戒指": "左戒指", "手镯": "左手镯"},
		"旧档缺失轮换 cursor 未安全默认"
	)
	var rewritten: Dictionary = PlayerState._read_json(save_path)
	assert(int(rewritten.get("save_version", 0)) == PlayerState.SAVE_VERSION, "旧档未重写为 v9")
	assert(rewritten.has("quick_item_slots") and rewritten.has("equip_cycle_cursor"), "旧档重写缺少 v9 字段")
	assert(Array(rewritten.get("quick_item_slots", [])).size() == 4, "旧档重写快捷物品槽数错误")

	var absolute_save_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(absolute_save_path)
	if FileAccess.file_exists("%s.bak" % save_path):
		DirAccess.remove_absolute("%s.bak" % absolute_save_path)
	PlayerState.active_profile_id = ""
	print("QUICK_ITEM_SLOTS_PASS")
	get_tree().quit(0)
