extends Node

## Shop sell page performance + frozen-contract evidence test.
##
## Runs identically on the pre-optimization tree and the optimized tree:
## diagnostics that only exist after optimization are probed via has_method()
## so the same scene produces comparable profile JSON on both sides.
##
## Outputs (res://outputs/shop_sell_kimi_takeover/):
##   profile_<tag>.json       timing samples + operation counters per scale
##   freeze_quotes_<tag>.json deterministic full quote dictionaries + sha256
## tag comes from env SHOP_PERF_TAG (default "current").

const SCALES := [0, 25, 50, 75, 100]
const WARMUP_ROUNDS := 3
const SAMPLE_ROUNDS := 10
const COLD_ROUNDS := 3
const EQUIPMENT_POOL: Array[String] = ["木剑", "匕首", "布衣(男)", "古铜戒指"]
const CONSUMABLE_POOL: Array[String] = ["太阳水", "金创药(小量)", "魔法药(小量)", "强效太阳水", "魔法药(中量)"]
const OUTPUT_DIR := "res://outputs/shop_sell_kimi_takeover"

var _panel: ShopPanel
var _last_quote_items: Array = []
var _quote_usec := 0
var _bind_usec := 0
var _quote_batch_calls := 0
var _profile := {"scales": {}}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState._shop_pricing_session_nonce = "shop-sell-perf-contract-v1"
	PlayerState.active_profile_id = "shop_sell_perf_profile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var tag := OS.get_environment("SHOP_PERF_TAG")
	if tag.is_empty():
		tag = "current"
	_profile["tag"] = tag
	_profile["engine"] = str(Engine.get_version_info().get("string", ""))
	var probe_panel := ShopPanel.new()
	_profile["features"] = {
		"panel_debug_counters": probe_panel.has_method("debug_operation_counters"),
		"player_quote_debug": PlayerState.has_method("test_shop_quote_debug_snapshot"),
		"sell_structure_signature": probe_panel.has_method("_clear_sell_structure"),
	}
	probe_panel.free()
	_run_freeze_contract()
	for scale: int in SCALES:
		_run_scale(scale)
	_write_json(OUTPUT_DIR.path_join("profile_%s.json" % tag), _profile)
	print("SHOP_SELL_PERFORMANCE_CONTRACT_PASS tag=%s scales=%s" % [tag, str(SCALES)])
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Frozen contract evidence
# ---------------------------------------------------------------------------

func _run_freeze_contract() -> void:
	PlayerState.inventory = [
		{"name": "木剑", "count": 1, "instance_id": "freeze-inst-0001"},
		{"name": "金创药(小量)", "count": 5},
		{"name": "匕首", "count": 1, "instance_id": "freeze-inst-0002", "durability": 3, "max_durability": 5},
		{"name": "太阳水", "count": 2, "bind": true},
		{},
		{"name": "布衣(男)", "count": 1, "instance_id": "freeze-inst-0003", "enhancement_level": 1},
		{"name": "古铜戒指", "count": 1, "instance_id": "freeze-inst-0004", "weapon_luck": 1},
		{"name": "魔法药(小量)", "count": 1, "random_stats": {"attack": 2}},
	]
	var items := _build_quote_items("general")
	var quotes_a := PlayerState.shop_sell_quotes(items)
	var quotes_b := PlayerState.shop_sell_quotes(items)
	var json_a := JSON.stringify(quotes_a)
	var json_b := JSON.stringify(quotes_b)
	assert(json_a == json_b, "相同输入两次报价的 JSON 必须逐字节一致")
	var probe_record: Dictionary = PlayerState.inventory[0]
	var probe_context := GameData.merchant_context("general")
	var probe_pricing := PricingService.quote_sell(
		GameData.get_item_price_record("木剑"),
		GameData.get_item_record("木剑"),
		probe_record,
		1,
		probe_context
	)
	var freeze := {
		"contract": "ui.shop.sell.v1 + gameplay.pricing.authority.v1 frozen quote dictionaries",
		"quote_count": quotes_a.size(),
		"quotes": quotes_a,
		"quotes_sha256": json_a.sha256_text(),
		"probe_pricing_quote": probe_pricing,
		"probe_pricing_sha256": JSON.stringify(probe_pricing).sha256_text(),
		"probe_merchant_context": probe_context,
	}
	assert(quotes_a.size() == 7, "冻结背包 8 槽 1 空洞必须产出 7 条报价")
	var expected_keys := [
		"instance:freeze-inst-0001", "inventory:1", "instance:freeze-inst-0002",
		"inventory:3", "instance:freeze-inst-0003", "instance:freeze-inst-0004", "inventory:7",
	]
	for key: String in expected_keys:
		assert(quotes_a.has(key), "冻结报价缺少 quote_key %s" % key)
	var required_fields := [
		"contract_id", "quote_key", "quote_id", "sellable", "unit_price", "max_quantity",
		"reason", "requires_confirmation", "risk_flags", "warning",
	]
	for key: String in expected_keys:
		var quote: Dictionary = quotes_a[key]
		for field: String in required_fields:
			assert(quote.has(field), "报价 %s 缺少字段 %s" % [key, field])
	var normal: Dictionary = quotes_a["instance:freeze-inst-0001"]
	assert(bool(normal.get("sellable", false)), "普通木剑必须可售")
	assert(int(normal.get("unit_price", 0)) > 0, "普通木剑必须有正售价")
	assert(not bool(normal.get("requires_confirmation", true)), "普通木剑不得要求确认")
	assert(str(normal.get("quote_id", "")).begins_with("gameplay.pricing.authority.v1:"), "quote_id 必须携带正式 contract 前缀")
	var bound: Dictionary = quotes_a["inventory:3"]
	assert(not bool(bound.get("sellable", true)), "绑定物品必须拒绝出售")
	assert(str(bound.get("reason", "")) == "绑定物品不能出售。", "绑定拒绝文案必须保持")
	var enhanced: Dictionary = quotes_a["instance:freeze-inst-0003"]
	assert(bool(enhanced.get("requires_confirmation", false)), "强化装备必须要求确认")
	assert((enhanced.get("risk_flags", []) as Array).has("enhanced"), "强化装备必须携带 enhanced 风险标记")
	var lucky: Dictionary = quotes_a["instance:freeze-inst-0004"]
	assert((lucky.get("risk_flags", []) as Array).has("lucky"), "幸运装备必须携带 lucky 风险标记")
	for key: String in expected_keys:
		var quote: Dictionary = quotes_a[key]
		if bool(quote.get("sellable", false)):
			assert(str(quote.get("merchant_id", "")) == str(GameData.merchant_context("general").get("merchant_id", "")), "可售报价必须绑定权威 merchant_id")
			assert(str(quote.get("merchant_stock_key", "")) == "general", "可售报价必须绑定 merchant_stock_key")
			assert(quote.has("policy_version") and quote.has("formula_snapshot") and quote.has("price_source"), "可售报价必须携带 policy_version/formula_snapshot/price_source")
	var tag := str(_profile.get("tag", "current"))
	_write_json(OUTPUT_DIR.path_join("freeze_quotes_%s.json" % tag), freeze)
	_profile["freeze_quotes_sha256"] = str(freeze["quotes_sha256"])
	_profile["freeze_quote_count"] = int(freeze["quote_count"])


# ---------------------------------------------------------------------------
# Scale measurements
# ---------------------------------------------------------------------------

func _run_scale(scale: int) -> void:
	_build_scale_inventory(scale)
	_panel = ShopPanel.new()
	add_child(_panel)
	_panel.sell_quotes_requested.connect(_on_sell_quotes_requested)
	_panel.open_for(
		"性能合同商店",
		GameData.merchant_stock("general"),
		GameData.merchant_context("general")
	)
	# Warmup rounds exercise the complete production path before sampling.
	for round_index in WARMUP_ROUNDS:
		_drive_sell_entry()
	# Cold cache: texture cache cleared and sell structure reset each round.
	var cold_samples: Array = []
	var cold_miss_delta: Array = []
	for round_index in COLD_ROUNDS:
		UIItemTextureCache.clear_for_test()
		_reset_sell_structure()
		var miss_before := UIItemTextureCache.sync_miss_count()
		cold_samples.append(_drive_sell_entry())
		cold_miss_delta.append(UIItemTextureCache.sync_miss_count() - miss_before)
	# Warm first entry: textures cached, structure reset -> full rebind path.
	var warm_first: Array = []
	var first_counters: Array = []
	for round_index in SAMPLE_ROUNDS:
		_reset_sell_structure()
		_reset_counters()
		warm_first.append(_drive_sell_entry())
		first_counters.append(_counter_snapshot())
	# Warm repeat: same structure, fresh authoritative quotes -> patch-only path.
	var warm_repeat: Array = []
	var repeat_counters: Array = []
	for round_index in SAMPLE_ROUNDS:
		_reset_counters()
		var result := _drive_quote_refresh_only()
		warm_repeat.append(result)
		repeat_counters.append(_counter_snapshot())
	var scale_report := {
		"occupied": scale,
		"inventory_slots": PlayerState.inventory.size(),
		"cold": _summarize_samples(cold_samples),
		"cold_sync_miss_delta": cold_miss_delta,
		"warm_first": _summarize_samples(warm_first),
		"warm_repeat": _summarize_samples(warm_repeat),
		"first_counters": first_counters[0] if not first_counters.is_empty() else {},
		"repeat_counters": repeat_counters[0] if not repeat_counters.is_empty() else {},
	}
	_assert_operation_gates(scale, scale_report)
	(_profile["scales"] as Dictionary)[str(scale)] = scale_report
	_panel.queue_free()
	_panel = null


func _assert_operation_gates(scale: int, report: Dictionary) -> void:
	if scale <= 0:
		return
	var first: Dictionary = report.get("first_counters", {})
	var repeat: Dictionary = report.get("repeat_counters", {})
	# Per-instance safety fingerprint contract: exactly one authoritative quote
	# batch per sell entry, in both builds.
	assert(int(first.get("quote_batch_count", -1)) == 1, "一次进入出售页只允许一个报价批次")
	# Batch-local static input reuse (post-optimization diagnostics).
	if PlayerState.has_method("test_shop_quote_debug_snapshot"):
		var unique_names := _unique_item_name_count()
		assert(int(first.get("merchant_context_lookups", -1)) == 1, "同一商人同一批次 merchant context 解析必须为 1")
		assert(int(first.get("catalog_lookups", -1)) == unique_names, "同批次每唯一物品名 catalog 查询最多 1 次")
		assert(int(first.get("price_record_lookups", -1)) == unique_names, "同批次每唯一物品名 price record 查询最多 1 次")
		assert(int(first.get("base_price_lookups", -1)) == unique_names, "同批次每唯一物品名 adjusted base price 最多 1 次")
		assert(int(first.get("pricing_quote_calls", -1)) == scale, "每个背包实例必须恰好一次正式报价")
	# Panel-side structure gates (post-optimization diagnostics).
	if _panel_has_debug_counters():
		assert(int(first.get("sell_structure_bind_count", -1)) == 1, "首次进入出售页结构绑定必须恰好 1 次")
		assert(int(repeat.get("sell_structure_bind_count", -1)) == 0, "相同结构重复报价不得再次结构绑定")
		assert(int(repeat.get("goods_card_creation_count", -1)) == 0, "相同结构重复报价不得创建新卡")
		assert(int(repeat.get("sell_catalog_lookup_count", -1)) == 0, "相同结构重复报价不得重复静态 catalog 查询")
		assert(int(repeat.get("sell_texture_lookup_count", -1)) == 0, "相同结构重复报价不得重复图标查询")
		assert(int(repeat.get("goods_card_visibility_change_count", -1)) == 0, "相同结构重复报价不得产生全量显隐切换")
		assert(int(repeat.get("sell_quote_patch_count", -1)) == 1, "相同结构重复报价必须恰好一次报价 patch")


# ---------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------

func _drive_sell_entry() -> Dictionary:
	# Production-equivalent: tab click -> panel request -> signal -> authority
	# -> synchronous set_sell_quotes inside the same call stack.
	var started := Time.get_ticks_usec()
	_panel._set_trade_mode("sell")
	var total_usec := Time.get_ticks_usec() - started
	return {
		"total_usec": total_usec,
		"quote_usec": _quote_usec,
		"bind_usec": _bind_usec,
		"cards_created": _panel._goods_card_creation_count,
		"content_updates": _panel._goods_card_content_update_count,
	}


func _drive_quote_refresh_only() -> Dictionary:
	# Fresh authoritative quotes for an unchanged inventory structure.
	_quote_batch_calls += 1
	var quote_started := Time.get_ticks_usec()
	var quotes := PlayerState.shop_sell_quotes(_last_quote_items)
	var quote_usec := Time.get_ticks_usec() - quote_started
	var bind_started := Time.get_ticks_usec()
	_panel.set_sell_quotes(quotes)
	var bind_usec := Time.get_ticks_usec() - bind_started
	return {
		"total_usec": quote_usec + bind_usec,
		"quote_usec": quote_usec,
		"bind_usec": bind_usec,
		"cards_created": _panel._goods_card_creation_count,
		"content_updates": _panel._goods_card_content_update_count,
	}


func _on_sell_quotes_requested(items: Array) -> void:
	_last_quote_items = items
	_quote_batch_calls += 1
	var quote_started := Time.get_ticks_usec()
	var quotes := PlayerState.shop_sell_quotes(items)
	_quote_usec = Time.get_ticks_usec() - quote_started
	var bind_started := Time.get_ticks_usec()
	_panel.set_sell_quotes(quotes)
	_bind_usec = Time.get_ticks_usec() - bind_started


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _build_scale_inventory(scale: int) -> void:
	var inventory: Array = []
	var occupied := 0
	var slot := 0
	while occupied < scale:
		if slot > 0 and slot % 7 == 3:
			inventory.append({})
			slot += 1
			continue
		var record := {"count": 1}
		var pick := occupied % 10
		if pick < 6:
			var equipment_name: String = EQUIPMENT_POOL[occupied % EQUIPMENT_POOL.size()]
			record["name"] = equipment_name
			record["instance_id"] = "perf-inst-%04d" % occupied
			if occupied % 5 == 1:
				record["durability"] = 2 + (occupied % 3)
				record["max_durability"] = 5
			if occupied % 11 == 5:
				record["random_stats"] = {"attack": occupied % 3}
		else:
			record["name"] = CONSUMABLE_POOL[occupied % CONSUMABLE_POOL.size()]
			record["count"] = 2 + (occupied % 4)
		if occupied % 13 == 12:
			record["bind"] = true
		inventory.append(record)
		occupied += 1
		slot += 1
	PlayerState.inventory = inventory


func _build_quote_items(stock_key: String) -> Array:
	var context := GameData.merchant_context(stock_key)
	var merchant_id := str(context.get("merchant_id", ""))
	var items: Array = []
	for inventory_index in range(PlayerState.inventory.size()):
		var raw: Variant = PlayerState.inventory[inventory_index]
		if not raw is Dictionary or (raw as Dictionary).is_empty():
			continue
		var record: Dictionary = raw
		var instance_id := str(record.get("instance_id", ""))
		items.append({
			"quote_key": "instance:%s" % instance_id if not instance_id.is_empty() else "inventory:%d" % inventory_index,
			"inventory_index": inventory_index,
			"instance_id": instance_id,
			"item_name": str(record.get("name", "")),
			"count": int(record.get("count", 1)),
			"merchant_id": merchant_id,
			"merchant_stock_key": stock_key,
		})
	return items


func _reset_sell_structure() -> void:
	if _panel.has_method("_clear_sell_structure"):
		_panel._clear_sell_structure()
	else:
		_panel._clear_goods_cards()
		_panel._sell_quotes.clear()


func _reset_counters() -> void:
	_quote_batch_calls = 0
	if PlayerState.has_method("test_shop_quote_debug_reset"):
		PlayerState.test_shop_quote_debug_reset()
	if _panel_has_debug_counters():
		_panel.debug_reset_operation_counters()


func _counter_snapshot() -> Dictionary:
	var snapshot := {"quote_batch_count": _quote_batch_calls}
	if PlayerState.has_method("test_shop_quote_debug_snapshot"):
		snapshot.merge(PlayerState.test_shop_quote_debug_snapshot(), true)
	if _panel_has_debug_counters():
		snapshot.merge(_panel.debug_operation_counters(), true)
	return snapshot


func _panel_has_debug_counters() -> bool:
	return _panel != null and _panel.has_method("debug_operation_counters")


func _panel_has_structure_signature() -> bool:
	return _panel != null and _panel.has_method("_clear_sell_structure")


func _unique_item_name_count() -> int:
	var names := {}
	for raw: Variant in PlayerState.inventory:
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			names[str((raw as Dictionary).get("name", ""))] = true
	return names.size()


func _summarize_samples(samples: Array) -> Dictionary:
	var totals: Array = []
	var quotes: Array = []
	var binds: Array = []
	for sample: Variant in samples:
		var entry: Dictionary = sample
		totals.append(int(entry.get("total_usec", 0)))
		quotes.append(int(entry.get("quote_usec", 0)))
		binds.append(int(entry.get("bind_usec", 0)))
	var last: Dictionary = samples[-1] if not samples.is_empty() else {}
	return {
		"rounds": samples.size(),
		"total": _stats(totals),
		"quote": _stats(quotes),
		"bind": _stats(binds),
		"cards_created": int(last.get("cards_created", 0)),
		"content_updates": int(last.get("content_updates", 0)),
	}


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"median_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2]) / 1000.0
	var p95_index := mini(sorted.size() - 1, maxi(0, ceili(sorted.size() * 0.95) - 1))
	return {
		"median_ms": median,
		"p95_ms": float(sorted[p95_index]) / 1000.0,
		"max_ms": float(sorted[sorted.size() - 1]) / 1000.0,
	}


func _write_json(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "无法写入性能证据 %s" % path)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
