extends Node

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for profession: String in ["战士", "法师", "道士"]:
		PlayerState.profession = profession
		PlayerState.level = 10
		PlayerState.recalculate_stats()
		var expected: int = int({"战士": 83, "法师": 70, "道士": 75}[profession])
		assert(PlayerState.max_inventory_weight() == expected, "%s背包负重公式错误" % profession)

	PlayerState.reset_progress()
	PlayerState.level = 1
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats()
	var stacked := PlayerState.receive("金创药(小量)", 50)
	assert(stacked.success and PlayerState.inventory.size() == 3, "药品未按20上限拆栈")
	assert(PlayerState.inventory_weight() == 50, "药品重量未按count计算")
	assert(not PlayerState.can_receive("金创药(小量)", 1), "超负重预检错误")
	assert(str(PlayerState.last_receive_result.get("message", "")) == "超过负重，无法拾取。", "超负重提示错误")
	var gold_before := PlayerState.gold
	assert(PlayerState.receive("金币", 1).success and PlayerState.gold > gold_before, "货币不应受重量阻断")

	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.gold = 100000
	PlayerState.recalculate_stats()
	var stock: Array = [{"name": "金创药(小量)", "pack_count": 20, "offer_id": "weight_test_potion"}]
	var buy_quotes := PlayerState.shop_buy_quotes(stock)
	assert(buy_quotes.size() == 1 and int(buy_quotes[0].get("pack_count", 0)) == 20, "购买报价未保留实际药品数量")
	var buy_quote: Dictionary = buy_quotes[0]
	var bought := PlayerState.buy_shop_item({
		"stock_index": 0,
		"quote_id": buy_quote.get("quote_id", ""),
		"item_name": buy_quote.get("item_name", ""),
		"stock_key": buy_quote.get("stock_key", ""),
		"merchant_id": buy_quote.get("merchant_id", ""),
		"quantity": 20,
	}, stock)
	assert(bool(bought.get("success", false)) and PlayerState.item_count("金创药(小量)") == 20, "购买packCount未按20瓶直接叠加")
	assert(PlayerState.inventory_weight() == 20, "购买packCount重量未按实际瓶数计算")
	PlayerState.inventory = [{"name": "强效太阳水", "count": 220}]
	var overweight_quotes := PlayerState.shop_buy_quotes(stock)
	var overweight_quote: Dictionary = overweight_quotes[0]
	var overweight_buy := PlayerState.buy_shop_item({
		"stock_index": 0,
		"quote_id": overweight_quote.get("quote_id", ""),
		"item_name": overweight_quote.get("item_name", ""),
		"stock_key": overweight_quote.get("stock_key", ""),
		"merchant_id": overweight_quote.get("merchant_id", ""),
		"quantity": 20,
	}, stock)
	assert(not bool(overweight_buy.get("success", true)), "超负重购买没有被拒绝")
	assert(str(overweight_buy.get("message", "")) == "背包空间不足或者超过最大负重。", "购买失败提示没有说明空间或负重")

	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.receive("神水", 100).success and PlayerState.inventory.size() == 100, "100格边界失败")
	assert(not PlayerState.can_receive("神水"), "101格边界未拒绝")

	PlayerState.reset_progress()
	PlayerState.level = 1
	PlayerState.inventory = [{"name": "强效太阳水", "count": 99}]
	assert(not PlayerState.can_receive("强效太阳水"), "旧超重档允许净增重")
	assert(PlayerState.receive("金币", 1).success, "旧超重档金币应可拾取")
	PlayerState.inventory = [{"name": "强效太阳水", "count": 9223372036854775807}]
	assert(PlayerState.inventory_weight() == 9223372036854775807, "重量计算溢出未饱和")

	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.receive("超负载戒指").success, "双倍负重戒指无法获得")
	var ring_index := 0
	assert(PlayerState.equip_inventory_index(ring_index).begins_with("已装备"), "双倍负重戒指无法装备")
	assert(PlayerState.max_inventory_weight() == 2 * EquipmentRulesScript.max_bag_weight("战士", 50), "双倍负重未进入背包门禁")

	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.receive("金创药(小量)", 1).success, "仓库测试物品获取失败")
	var deposited := PlayerState.deposit_to_warehouse(0, 0)
	assert(deposited.success and PlayerState.inventory.is_empty(), "仓库存入未原子完成")
	var withdrawn := PlayerState.withdraw_from_warehouse(0)
	assert(withdrawn.success and PlayerState.item_count("金创药(小量)") == 1, "仓库取出未接入负重门禁")

	# A failed deposit to a high slot must restore the exact pre-transaction
	# array shape, not a snapshot taken after implicit warehouse expansion.
	PlayerState.warehouse_inventory = []
	var inventory_before_failed_deposit := PlayerState.inventory.duplicate(true)
	var warehouse_before_failed_deposit := PlayerState.warehouse_inventory.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	var failed_deposit := PlayerState.deposit_to_warehouse(0, 12)
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(failed_deposit.get("success", true)), "强制存档失败仍报告仓库存入成功")
	assert(PlayerState.inventory == inventory_before_failed_deposit, "仓库存入失败没有恢复背包")
	assert(PlayerState.warehouse_inventory == warehouse_before_failed_deposit, "仓库存入失败没有恢复仓库结构")
	assert(PlayerState.warehouse_inventory.size() == 0, "仓库存入失败遗留扩容空槽")

	# Absolute inventory slot contract: ordinary mutations leave middle holes;
	# only explicit auto-sort may compact them, and new records fill the first hole.
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.receive("木剑").success)
	assert(PlayerState.receive("太阳水").success)
	assert(PlayerState.receive("回城卷").success)
	var first_before: Dictionary = PlayerState.inventory[0].duplicate(true)
	var tail_before: Dictionary = PlayerState.inventory[2].duplicate(true)
	assert(PlayerState.use_inventory_index(1).begins_with("使用："), "中间消耗品使用失败")
	assert(PlayerState.inventory.size() == 3 and PlayerState.inventory[1].is_empty(), "中间消耗后没有保留绝对空洞")
	assert(PlayerState.inventory[0] == first_before and PlayerState.inventory[2] == tail_before, "中间消耗移动了相邻物品")
	assert(PlayerState.receive("匕首").success, "首洞回填测试物品获取失败")
	assert(str(PlayerState.inventory[1].get("name", "")) == "匕首", "新增物品没有优先填入第一个空槽")
	assert(PlayerState.equip_inventory_index(1).begins_with("已装备"), "中间装备穿戴失败")
	assert(PlayerState.inventory.size() == 3 and PlayerState.inventory[1].is_empty(), "穿戴后原背包槽没有保留空洞")
	assert(PlayerState.inventory[0] == first_before and PlayerState.inventory[2] == tail_before, "穿戴移动了无关背包物品")
	var sort_result := PlayerState.sort_inventory_deterministic()
	assert(sort_result.success and PlayerState.inventory.size() == 2, "显式自动整理没有压缩中间空洞")

	print("INVENTORY_WEIGHT_AUTHORITY_PASS")
	get_tree().quit(0)
