extends Node

var _game: Node
var _hud: GameHUD


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.inventory = [
		{"name": "金创药(小量)", "count": 3},
		{"name": "魔法药(小量)", "count": 2},
	]
	PlayerState.gold = 7
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_hud = _game.hud
	assert(_hud.inventory_panel == null and _hud.skill_panel == null)
	var state_before_prewarm := {
		"inventory": PlayerState.inventory.duplicate(true),
		"equipment": PlayerState.equipment.duplicate(true),
		"warehouse": PlayerState.warehouse_inventory.duplicate(true),
		"quests": PlayerState.quest_states.duplicate(true),
	}
	await _hud.prewarm_all_panels(_game._system_menu_panel)
	assert(_hud.all_panels_are_prewarmed(), "all reusable modal profiles did not settle")
	for panel in [
		_hud.inventory_panel, _hud.shop_panel, _hud.skill_panel,
		_hud.quest_panel, _hud.map_panel, _hud.warehouse_panel,
		_hud.death_revival_panel, _game._system_menu_panel,
	]:
		assert(is_instance_valid(panel) and not panel.visible)
	assert(PlayerState.inventory == state_before_prewarm.inventory)
	assert(PlayerState.equipment == state_before_prewarm.equipment)
	assert(PlayerState.warehouse_inventory == state_before_prewarm.warehouse)
	assert(PlayerState.quest_states == state_before_prewarm.quests)
	var inventory_instance_id := _hud.inventory_panel.get_instance_id()
	var skill_instance_id := _hud.skill_panel.get_instance_id()
	await _hud.prewarm_all_panels(_game._system_menu_panel)
	assert(_hud.inventory_panel.get_instance_id() == inventory_instance_id)
	assert(_hud.skill_panel.get_instance_id() == skill_instance_id)
	_hud._toggle_inventory()
	assert(_hud.inventory_panel.visible)
	assert(_hud.inventory_panel.get_instance_id() == inventory_instance_id)
	_hud._toggle_inventory()
	_hud._toggle_skill_book()
	assert(_hud.skill_panel.visible)
	assert(_hud.skill_panel.get_instance_id() == skill_instance_id)
	_hud._toggle_skill_book()
	_hud._ensure_shop_panel()

	# Quote goes HUD -> GameRoot -> PlayerState authority -> HUD. Its price is a
	# deterministic 50% derivation of the existing runtime catalog price.
	var quote_item := _quote_request(0)
	_hud.shop_sell_quotes_requested.emit([quote_item])
	var quote: Dictionary = _hud.shop_panel._sell_quotes.get(
		"inventory:0", {}
	)
	assert(bool(quote.get("sellable", false)), "authority did not quote item")
	var runtime_price := int(
		GameData.get_item_record("金创药(小量)").get("price", 0)
	)
	assert(int(quote.get("unit_price", 0)) == maxi(1, floori(runtime_price / 2.0)))

	var sell_request := quote_item.duplicate(true)
	sell_request["quote_id"] = str(quote.get("quote_id", ""))
	sell_request["amount"] = 1
	var gold_before := PlayerState.gold
	_hud.shop_sell_requested.emit(sell_request)
	assert(int(PlayerState.inventory[0].get("count", 0)) == 2)
	assert(PlayerState.gold == gold_before + int(quote.get("unit_price", 0)))

	# A once-used/stale quote, an excessive quantity, and a now-missing item all
	# fail closed without changing inventory or gold.
	var snapshot_after_sale := PlayerState.inventory.duplicate(true)
	var gold_after_sale := PlayerState.gold
	_hud.shop_sell_requested.emit(sell_request)
	assert(PlayerState.inventory == snapshot_after_sale and PlayerState.gold == gold_after_sale)

	var fresh_quote_item := _quote_request(0)
	_hud.shop_sell_quotes_requested.emit([fresh_quote_item])
	var fresh_quote: Dictionary = _hud.shop_panel._sell_quotes.get(
		"inventory:0", {}
	)
	var excessive := fresh_quote_item.duplicate(true)
	excessive["quote_id"] = str(fresh_quote.get("quote_id", ""))
	excessive["amount"] = int(fresh_quote.get("max_quantity", 0)) + 1
	_hud.shop_sell_requested.emit(excessive)
	assert(PlayerState.inventory == snapshot_after_sale and PlayerState.gold == gold_after_sale)

	var missing_request := fresh_quote_item.duplicate(true)
	missing_request["quote_id"] = str(fresh_quote.get("quote_id", ""))
	missing_request["amount"] = 1
	PlayerState.inventory = []
	_hud.shop_sell_requested.emit(missing_request)
	assert(PlayerState.inventory.is_empty() and PlayerState.gold == gold_after_sale)

	# A non-stackable equipment instance with implicit count=1 must receive a
	# server-authoritative price and sell as one whole item.
	PlayerState.add_item("木剑")
	assert(PlayerState.inventory.size() == 1 and str(PlayerState.inventory[0].get("instance_id", "")) != "")
	var equipment_quote_item := _quote_request(0)
	_hud.shop_sell_quotes_requested.emit([equipment_quote_item])
	var equipment_key := str(equipment_quote_item.get("quote_key", ""))
	var equipment_quote: Dictionary = _hud.shop_panel._sell_quotes.get(equipment_key, {})
	assert(bool(equipment_quote.get("sellable", false)), "数量1的装备没有获得可出售报价")
	assert(int(equipment_quote.get("max_quantity", 0)) == 1, "非堆叠装备的最大出售数量不是1")
	assert(int(equipment_quote.get("unit_price", 0)) == 25, "木剑没有使用服务端价格50的半价出售规则")
	var equipment_sell_request := equipment_quote_item.duplicate(true)
	equipment_sell_request["quote_id"] = str(equipment_quote.get("quote_id", ""))
	equipment_sell_request["amount"] = 1
	var equipment_gold_before := PlayerState.gold
	_hud.shop_sell_requested.emit(equipment_sell_request)
	assert(PlayerState.inventory.is_empty(), "数量1的装备出售后没有从背包移除")
	assert(PlayerState.gold == equipment_gold_before + 25, "数量1的装备出售金币错误")

	# Quest abandon and warehouse sort traverse the same HUD-only-forwarding
	# path and mutate only PlayerState's authoritative containers.
	PlayerState.quest_states = {
		"bich_field_hunt": {"status": "active", "progress": {"鸡": 1}},
	}
	_hud.quest_abandon_requested.emit("bich_field_hunt")
	assert(not PlayerState.quest_states.has("bich_field_hunt"))

	PlayerState.warehouse_inventory = [
		{"name": "C", "count": 1},
		{},
		{"name": "A", "count": 1},
		{"name": "B", "count": 1},
	]
	_hud.warehouse_sort_requested.emit()
	assert(PlayerState.warehouse_inventory.size() == 3)
	assert(str(PlayerState.warehouse_inventory[0].get("name", "")) == "A")
	assert(str(PlayerState.warehouse_inventory[1].get("name", "")) == "B")
	assert(str(PlayerState.warehouse_inventory[2].get("name", "")) == "C")

	print(
		"HUD_AUTHORITY_INTEGRATION_PASS: quote/sell, stale-over-missing "
		+ "guards, quest abandon, and warehouse sort"
	)
	get_tree().quit(0)


func _quote_request(inventory_index: int) -> Dictionary:
	var record: Dictionary = PlayerState.inventory[inventory_index]
	var instance_id := str(record.get("instance_id", ""))
	return {
		"quote_key": "instance:%s" % instance_id if not instance_id.is_empty() else "inventory:%d" % inventory_index,
		"inventory_index": inventory_index,
		"instance_id": instance_id,
		"item_name": str(record.get("name", "")),
		"count": int(record.get("count", 1)),
	}
