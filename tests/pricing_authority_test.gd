extends Node

const PricingServiceScript := preload("res://scripts/pricing_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var wood := GameData.get_item_price_record("木剑")
	var potion := GameData.get_item_price_record("金创药(小量)")
	assert(int(wood.get("base_price", 0)) == 50 and str(wood.get("item_key", "")) == "service:221")
	assert(int(potion.get("base_price", 0)) == 40 and str(potion.get("source", {}).get("distribution", "")) == "server.crystal.cjlaaa")
	var candidate_file := FileAccess.open("res://assets/data/equipment_price_candidates_v1.json", FileAccess.READ)
	assert(candidate_file != null, "正式装备缺价候选合同缺失")
	var candidate_contract: Variant = JSON.parse_string(candidate_file.get_as_text())
	assert(candidate_contract is Dictionary and str(candidate_contract.get("contractId", "")) == "gameplay.pricing.equipment_missing_server_price_candidates.v1")
	assert(candidate_contract.get("configuredServerDataFallbackEvidence", []).size() == 4)
	for evidence: Variant in candidate_contract.get("configuredServerDataFallbackEvidence", []):
		assert(evidence is Dictionary and str((evidence as Dictionary).get("status", "")) == "missing", "价格候选没有耗尽配置中的更高优先级来源")
	var expected_candidate_prices := {
		"天魔神甲": 50000,
		"圣战头盔": 35000,
		"圣战项链": 35000,
		"圣战手镯": 35000,
		"圣战戒指": 35000,
	}
	for item_name: String in expected_candidate_prices:
		var candidate_record := GameData.get_item_price_record(item_name)
		assert(int(candidate_record.get("base_price", 0)) == int(expected_candidate_prices[item_name]), "%s缺少已审核价格候选" % item_name)
		assert(str(candidate_record.get("source", {}).get("distribution", "")) == "reference.21cq.classic_176")
	# A cumulative resource patch may add the evidence JSON after the base APK
	# price index already exists. The missing record must repair in place without
	# reloading the full gameplay database.
	GameData.equipment_price_candidates = {}
	GameData._price_by_name.erase("天魔神甲")
	var lazy_candidate := GameData.get_item_price_record("天魔神甲")
	assert(int(lazy_candidate.get("base_price", 0)) == 50000, "late patch price candidate was not indexed lazily")
	assert(str(wood.get("source", {}).get("distribution", "")) == "server.crystal.cjlaaa", "候选价格不得覆盖主数据库已有价格")
	var general_stock := GameData.merchant_stock("general")
	var weapon_stock := GameData.merchant_stock("starter_gear")
	var book_stock := GameData.merchant_stock("books")
	var medicine_stock := GameData.merchant_stock("medicine")
	for weapon_offer: Dictionary in weapon_stock:
		assert(
			not str(weapon_offer.get("name", "")).ends_with("Bow")
			and str(weapon_offer.get("name", "")) not in ["虎牙刀", "暴虎刀", "音速刀"],
			"铁匠货单不应暴露无项目装备主表/贴图支持的私服装备"
		)
	var starter_catalog: Dictionary = GameData.merchant_catalog.get("merchants", {}).get("starter_gear", {})
	var starter_excluded_names := {}
	for excluded: Variant in starter_catalog.get("excludedOffers", []):
		if excluded is Dictionary:
			starter_excluded_names[str(excluded.get("itemName", ""))] = true
	assert(
		starter_excluded_names.keys().size() == 8
			and starter_excluded_names.has("虎牙刀")
			and starter_excluded_names.has("暴虎刀")
			and starter_excluded_names.has("音速刀"),
		"私服装备主源行必须保留在 excludedOffers 审计证据中"
	)
	assert(str(general_stock[0].get("name", "")) == "随机传送卷")
	assert(not general_stock.any(func(entry: Dictionary) -> bool: return str(entry.get("name", "")) in ["蜡烛", "火把", "护身符"]))
	assert(str(weapon_stock[0].get("name", "")) == "木剑")
	assert(str(book_stock[0].get("name", "")) == "基本剑术")
	var expected_book_names := [
		"基本剑术", "攻杀剑术",
		"火球术", "抗拒火环", "诱惑之光", "大火球", "地狱火", "雷电术", "瞬息移动",
		"治愈术", "精神力战法", "施毒术", "灵魂火符", "召唤骷髅",
	]
	var actual_book_names: Array[String] = []
	for book_offer: Dictionary in book_stock:
		actual_book_names.append(str(book_offer.get("name", "")))
		assert(not GameData.get_item_record(str(book_offer.get("name", ""))).is_empty(), "书店常售技能书必须解析到正式物品记录")
	assert(actual_book_names == expected_book_names, "书店必须只出售正式合同锁定的14本常规技能书")
	var book_catalog: Dictionary = GameData.merchant_catalog.get("merchants", {}).get("books", {})
	var catalog_book_names: Array[String] = []
	for book_offer: Variant in book_catalog.get("offers", []):
		assert(book_offer is Dictionary)
		catalog_book_names.append(str((book_offer as Dictionary).get("itemName", "")))
		assert(str((book_offer as Dictionary).get("catalogClassification", "")) == "official_shop_live")
	assert(catalog_book_names == actual_book_names, "GameData books stock必须与生成目录live货单完全一致")
	var expected_advanced_names := [
		"刺杀剑术", "半月弯刀", "野蛮冲撞", "烈火剑法",
		"爆裂火焰", "火墙", "疾光电影", "地狱雷光", "魔法盾", "圣言术", "冰咆哮",
		"隐身术", "集体隐身术", "幽灵盾", "心灵启示", "神圣战甲术", "困魔咒", "群体治疗术", "召唤神兽",
	]
	var expected_private_names := [
		"双龙斩", "捕绳剑", "寒冰掌", "嗜血术", "气功波", "净化术", "迷魂术", "无极真气",
		"绝命剑法", "双刀术", "体迅风", "拔刀术", "风身术", "迁移剑", "烈风击", "捕缚术", "猛毒剑气",
	]
	var advanced_names: Array[String] = []
	var private_names: Array[String] = []
	var unresolved_names: Array[String] = []
	var audited_source_ordinals := {}
	for book_offer: Variant in book_catalog.get("offers", []):
		var live_offer := book_offer as Dictionary
		var live_ordinal := int(live_offer.get("sourceOrdinal", 0))
		assert(live_ordinal == int(live_offer.get("offerIndex", -1)) + 1)
		assert(int(live_offer.get("sourceLine", 0)) == 201 + live_ordinal)
		audited_source_ordinals[live_ordinal] = true
	for excluded: Variant in book_catalog.get("excludedOffers", []):
		assert(excluded is Dictionary)
		var excluded_offer := excluded as Dictionary
		var classification := str(excluded_offer.get("catalogClassification", ""))
		var source_ordinal := int(excluded_offer.get("sourceOrdinal", 0))
		assert(source_ordinal == int(excluded_offer.get("offerIndex", -1)) + 1)
		assert(int(excluded_offer.get("sourceLine", 0)) == 201 + source_ordinal)
		assert(int(excluded_offer.get("serviceIndex", -1)) >= 0)
		assert(str(excluded_offer.get("tradeLine", "")) == str(excluded_offer.get("itemName", "")))
		assert(str(excluded_offer.get("exclusionReason", "")) == classification)
		var evidence: Dictionary = excluded_offer.get("exclusionEvidence", {})
		assert(str(evidence.get("policyId", "")) == "BOOK-SHOP-OFFICIAL-176-1")
		match classification:
			"official_advanced_drop_only":
				advanced_names.append(str(excluded_offer.get("itemName", "")))
				var drop_evidence: Dictionary = evidence.get("dropEvidence", {})
				assert(not str(evidence.get("formalSkillId", "")).is_empty())
				assert(not str(drop_evidence.get("path", "")).is_empty())
				assert(str(drop_evidence.get("sha256", "")).length() == 64)
				assert(int(drop_evidence.get("sourceLine", 0)) > 0)
			"private_extension_excluded":
				private_names.append(str(excluded_offer.get("itemName", "")))
				assert(str(evidence.get("formalSkillMasterMembership", "")) == "missing")
			"unresolved_fail_closed":
				unresolved_names.append(str(excluded_offer.get("itemName", "")))
			_:
				assert(false, "书店排除项出现未知分类: %s" % classification)
		audited_source_ordinals[source_ordinal] = true
	advanced_names.sort()
	private_names.sort()
	expected_advanced_names.sort()
	expected_private_names.sort()
	assert(advanced_names == expected_advanced_names, "19本正式高级技能书必须保持掉落专属、不得进书店")
	assert(private_names == expected_private_names, "17本私服扩展技能书必须明确排除")
	assert(unresolved_names.is_empty(), "本次50条审计没有未决项；未来未知书籍必须fail-closed")
	assert(book_catalog.get("excludedOffers", []).size() == 36)
	assert(audited_source_ordinals.size() == 50 and not audited_source_ordinals.has(0))
	var classification_counts: Dictionary = book_catalog.get("projectOverrides", {}).get("officialBookShopPolicy", {}).get("classificationCounts", {})
	assert(classification_counts.size() == 4)
	assert(int(classification_counts.get("official_shop_live", -1)) == 14)
	assert(int(classification_counts.get("official_advanced_drop_only", -1)) == 19)
	assert(int(classification_counts.get("private_extension_excluded", -1)) == 17)
	assert(int(classification_counts.get("unresolved_fail_closed", -1)) == 0)
	for official_weapon: Dictionary in weapon_stock:
		assert(not GameData.get_item_record(str(official_weapon.get("name", ""))).is_empty(), "正式武器货单必须解析到玩家物品记录")
	var medicine_names := [
		"金疮药(小量)", "魔法药(小量)",
		"金疮药(中量)", "魔法药(中量)",
		"金疮药(大量)", "魔法药(大量)",
	]
	assert(medicine_stock.size() == 12, "药店必须提供六种正式药品各单瓶/20瓶两种报价")
	for medicine_offer: Dictionary in medicine_stock:
		assert(
			str(medicine_offer.get("name", "")) in medicine_names
			and int(medicine_offer.get("pack_count", 0)) in [1, 20],
			"药店混入特大/超级药品或非法包装数量"
		)
	for medicine_name: String in medicine_names:
		assert(medicine_stock.filter(func(entry: Dictionary) -> bool: return str(entry.get("name", "")) == medicine_name).size() == 2)
	for medicine_offer: Dictionary in medicine_stock:
		assert(not GameData.get_item_record(str(medicine_offer.get("name", ""))).is_empty(), "正式药品货单必须解析到玩家物品记录")
	assert(not medicine_stock.any(func(entry: Dictionary) -> bool: return "特大" in str(entry.get("name", "")) or "超级" in str(entry.get("name", ""))))
	assert(str(medicine_stock[0].get("merchant_id", "")) == "merchant.server.crystal.cjlaaa.29")
	var potion_summary := GameData.item_usage_summary("金疮药(小量)")
	assert(int(potion_summary.get("restore_health", 0)) == 30 and int(GameData.item_usage_summary("魔法药(小量)").get("restore_mana", 0)) == 40, "药水详情没有使用主库实际恢复数值")
	for medicine_name: String in medicine_names:
		var delayed_summary := GameData.item_usage_summary(medicine_name, 1)
		assert(str(delayed_summary.get("effect_type", "")) == "delayed_restore", "正式药水必须使用主库持续恢复效果")
		assert(int(delayed_summary.get("tick_amount", 0)) == 5 and is_equal_approx(float(delayed_summary.get("tick_interval_seconds", 0.0)), 0.59), "等级1药水恢复节奏没有遵循主库公式")
	var level_50_summary := GameData.item_usage_summary("金疮药(大量)", 50)
	assert(int(level_50_summary.get("tick_amount", 0)) == 10 and is_equal_approx(float(level_50_summary.get("tick_interval_seconds", 0.0)), 0.2), "等级50药水恢复节奏没有遵循主库公式")
	assert(is_equal_approx(float(level_50_summary.get("recovery_per_second", 0.0)), 50.0) and is_equal_approx(float(level_50_summary.get("duration_seconds", 0.0)), 2.0), "药水每秒恢复/持续时间显示投影错误")
	var level_1_restore := GameData.potion_recovery_profile(1, 30, 0, "delayed_restore")
	var level_50_restore := GameData.potion_recovery_profile(50, 0, 40, "delayed_restore")
	assert(int(level_1_restore.get("tick_amount", 0)) == 5 and is_equal_approx(float(level_1_restore.get("tick_interval_seconds", 0.0)), 0.59), "1级药水持续恢复节奏与玩法公式不一致")
	assert(int(level_50_restore.get("tick_amount", 0)) == 10 and is_equal_approx(float(level_50_restore.get("tick_interval_seconds", 0.0)), 0.2), "50级药水持续恢复节奏与玩法公式不一致")
	assert(is_equal_approx(float(level_50_restore.get("recovery_per_second", 0.0)), 50.0), "药水每秒恢复量计算错误")
	assert(is_equal_approx(float(level_1_restore.get("duration_seconds", 0.0)), 2.95) and is_equal_approx(float(level_50_restore.get("duration_seconds", 0.0)), 0.6), "药水首次立即跳与后续持续时间计算错误")
	assert(str(potion_summary.get("effect_type", "")) == "delayed_restore" and int(potion_summary.get("tick_amount", 0)) > 0, "正式药水被错误投影为即时恢复")
	var bich_content := MapEditorRuntimeBridge.game_content_for_map(4)
	var pharmacist_rows: Array = (bich_content.get("npcs", []) as Array).filter(
		func(entry: Dictionary) -> bool:
			return str(entry.get("npc_id", "")) == "npc.expansion.bich_pharmacist"
	)
	assert(pharmacist_rows.size() == 1 and str((pharmacist_rows[0] as Dictionary).get("stock", "")) == "medicine", "比奇药剂商没有绑定主库药店货单")
	assert(str(general_stock[0].get("merchant_id", "")) == "merchant.server.crystal.cjlaaa.33")
	assert(not bool(GameData.merchant_context("general").get("supports_repair", true)))
	assert(bool(GameData.merchant_context("starter_gear").get("supports_repair", false)))
	assert(GameData.merchant_context("starter_gear").get("types", []) == [1, 14])
	var buy := PricingServiceScript.quote_buy(wood)
	assert(bool(buy.get("valid", false)) and int(buy.get("unit_price", 0)) == 55)
	var full_instance := {"name": "木剑", "durability": 4, "max_durability": 4, "instance_id": "pricing-full"}
	var sell := PricingServiceScript.quote_sell(wood, GameData.get_item_record("木剑"), full_instance)
	assert(bool(sell.get("valid", false)) and int(sell.get("unit_price", 0)) == 28)
	var starter_context := GameData.merchant_context("starter_gear")
	var general_context := GameData.merchant_context("general")
	var book_context := GameData.merchant_context("books")
	var medicine_context := GameData.merchant_context("medicine")
	var accepted_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, starter_context
	)
	var cross_merchant_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, general_context
	)
	var book_merchant_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, book_context
	)
	var medicine_merchant_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, medicine_context
	)
	assert(bool(accepted_sell.get("valid", false)), "主库Types允许的武器没有出售报价")
	assert(bool(cross_merchant_sell.get("valid", false)), "项目统一回收规则没有允许杂货商回收武器")
	assert(bool(book_merchant_sell.get("valid", false)), "项目统一回收规则没有允许书店回收武器")
	assert(bool(medicine_merchant_sell.get("valid", false)), "项目统一回收规则没有允许药剂商回收武器")
	var rated_context := starter_context.duplicate(true)
	rated_context["merchant_id"] = "merchant.test.rate"
	rated_context["merchant_rate_bps"] = 13000
	var rated_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, rated_context
	)
	assert(
		bool(rated_sell.get("valid", false))
		and int(rated_sell.get("unit_price", 0)) == 36,
		"Merchant Rate没有进入出售权威报价"
	)
	var half_instance := full_instance.duplicate(true)
	half_instance["durability"] = 2
	var half_sell := PricingServiceScript.quote_sell(wood, GameData.get_item_record("木剑"), half_instance)
	assert(int(half_sell.get("unit_price", 0)) < int(sell.get("unit_price", 0)))
	var repair := PricingServiceScript.quote_repair(wood, GameData.get_item_record("木剑"), {"durability": 0, "max_durability": 4})
	assert(bool(repair.get("valid", false)) and int(repair.get("total_price", 0)) == 9)
	var blacksmith_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		GameData.merchant_context("starter_gear")
	)
	assert(bool(blacksmith_repair.get("valid", false)) and int(blacksmith_repair.get("total_price", 0)) == 9)
	var clothing := GameData.get_item_price_record("布衣(男)")
	var blacksmith_clothing_repair := PricingServiceScript.quote_repair(
		clothing,
		GameData.get_item_record("布衣(男)"),
		{"durability": 0, "max_durability": 5},
		starter_context
	)
	assert(
		bool(blacksmith_clothing_repair.get("valid", false)),
		"铁匠[Types]=[1,14]仅是交易品类，不得阻止衣服维修"
	)
	var grocery_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		GameData.merchant_context("general")
	)
	assert(not bool(grocery_repair.get("valid", true)))
	var forged_repair_context := starter_context.duplicate(true)
	forged_repair_context["merchant_id"] = "merchant.test.forged"
	forged_repair_context["types"] = [1, 2, 4, 5, 6, 7]
	var forged_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		forged_repair_context
	)
	assert(not bool(forged_repair.get("valid", true)), "非权威铁匠不得伪造全装备维修权限")
	var partial_repair := PricingServiceScript.quote_repair_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		1,
		GameData.merchant_context("starter_gear")
	)
	var larger_partial_repair := PricingServiceScript.quote_repair_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		2,
		GameData.merchant_context("starter_gear")
	)
	var raw_repair := PricingServiceScript.quote_repair_raw_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 4, "max_durability": 4, "durability_raw": 3998, "max_durability_raw": 4000},
		2
	)
	assert(
		raw_repair.valid
		and int(raw_repair.formula_snapshot.repair_amount_raw) == 2
		and int(raw_repair.formula_snapshot.target_durability_raw) == 4000,
		"不足1显示点的raw耐久没有进入维修报价"
	)
	assert(bool(partial_repair.get("valid", false)) and int(partial_repair.get("total_price", 0)) >= 1)
	assert(int(larger_partial_repair.get("total_price", 0)) >= int(partial_repair.get("total_price", 0)))
	assert(int(blacksmith_repair.get("total_price", 0)) >= int(larger_partial_repair.get("total_price", 0)))
	assert(int(partial_repair.get("formula_snapshot", {}).get("repair_amount", 0)) == 1)
	assert(int(partial_repair.get("formula_snapshot", {}).get("target_durability", 0)) == 1)
	assert(bool(partial_repair.get("formula_snapshot", {}).get("preserve_maximum_durability", false)))

	var custom := PricingServiceScript.policy()
	custom["policyVersion"] = "test.multiplier"
	custom["modifiers"]["globalBps"] = 13000
	custom["modifiers"]["categoryBps"] = {"武器": 7000}
	custom["modifiers"]["itemBps"] = {"service:221": 7000}
	assert(PricingServiceScript.adjusted_database_price(wood, custom) == 32)
	var forge := PricingServiceScript.estimate_forge_materials(
		[{"item_name": "木剑", "quantity": 2}], {"木剑": wood}, custom
	)
	assert(bool(forge.get("valid", false)) and int(forge.get("total_value", 0)) == 64)

	var stock := [{"name": "木剑", "description": "主库定价测试"}]
	PlayerState.gold = 100
	var quotes := PlayerState.shop_buy_quotes(stock)
	assert(quotes.size() == 1 and int(quotes[0].get("unit_price", 0)) == 55)
	var request := {"stock_index": 0, "quote_id": quotes[0].get("quote_id", ""), "quantity": 1}
	var buy_result := PlayerState.buy_shop_item(request, stock)
	assert(bool(buy_result.get("success", false)) and PlayerState.gold == 45 and PlayerState.has_item("木剑"))
	var inventory_after := PlayerState.inventory.duplicate(true)
	var replay := PlayerState.buy_shop_item(request, stock)
	assert(not bool(replay.get("success", false)) and PlayerState.gold == 45 and PlayerState.inventory == inventory_after)
	var tampered := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": "tampered", "quantity": 1}, stock)
	assert(not bool(tampered.get("success", false)) and PlayerState.gold == 45 and PlayerState.inventory == inventory_after)
	PlayerState.gold = 1
	var poor_quotes := PlayerState.shop_buy_quotes(stock)
	var poor_before := PlayerState.inventory.duplicate(true)
	var poor := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": poor_quotes[0].get("quote_id", ""), "quantity": 1}, stock)
	assert(not bool(poor.get("success", false)) and PlayerState.gold == 1 and PlayerState.inventory == poor_before)
	PlayerState.gold = 100
	var renewed_quotes := PlayerState.shop_buy_quotes(stock)
	assert(str(renewed_quotes[0].get("quote_id", "")) != str(quotes[0].get("quote_id", "")))
	var second_buy := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": renewed_quotes[0].get("quote_id", ""), "quantity": 1}, stock)
	assert(bool(second_buy.get("success", false)) and PlayerState.item_count("木剑") == 2)

	var pack_stock := [{"name": "随机传送卷", "pack_count": 20}]
	PlayerState.gold = 100000
	var pack_quotes := PlayerState.shop_buy_quotes(pack_stock)
	assert(int(pack_quotes[0].get("quantity", 0)) == 20)
	assert(int(pack_quotes[0].get("total_price", 0)) == int(pack_quotes[0].get("unit_price", 0)) * 20)

	print("PRICING_AUTHORITY_PASS：主库价格、倍率、买卖事务、维修与锻造估值正常")
	get_tree().quit(0)
